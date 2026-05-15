scriptname sd_LME_MCMQuest extends SKI_ConfigBase

import Debug

; ── Runtime ───────────────────────────────────────────────────────────────────
int selectedCondition = 0
int lewdMarksLastNumber = 96

string texturePathNormalRM = "actors\\character\\overlays\\lewdmarks\\"
string texturePathGlowRM   = "actors\\character\\overlays\\lewdmarks-glow\\"
string texturePathNormalST = "actors\\character\\slavetats\\lewdmarks\\"
string texturePathGlowST   = "actors\\character\\slavetats\\lewdmarks-glow\\"

sd_LME_MainQuest Property MainQuest Auto

; ── Versioning ────────────────────────────────────────────────────────────────
int Function GetVersion()
    return 14
EndFunction

string Function _slotLabel(int idx)
    if idx == 0
        return "Default"
    endif
    return "Condition " + idx
endFunction

string Function _condTypeLabel(string key)
    if key == "" || MainQuest == None
        return "Not set"
    endif
    sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return "Unknown (" + key + ")"
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return "Unknown (" + key + ")"
    endif
    string pl = p.GetPluginLabel()
    string il = p.GetConditionLabel(itemIdx)
    if pl == ""
        return il
    endif
    return pl + " — " + il
endFunction

event OnConfigInit()
    ModName = "LewdMarks Effects"
    Pages = new String[4]
    Pages[0] = "General"
    Pages[1] = "Conditions"
    Pages[2] = "Plugins"
    Pages[3] = "Menu Options"
    _ensureMainQuest()
endEvent

function _ensureMainQuest()
    if MainQuest == None
        Quest q = Game.GetFormFromFile(0x803, "LewdMarksEffects.esp") as Quest
        MainQuest = q as sd_LME_MainQuest
    endif
    if MainQuest != None
        MainQuest.EnsureArrays()
    endif
endFunction

event OnVersionUpdate(int Version)
    if MainQuest == None
        return
    endif
    if CurrentVersion < 4
        ; Fresh init for v0.0.2 plugin-system schema
        MainQuest.condPluginId         = new string[8]
        MainQuest.condParam            = new int[8]
        MainQuest.condTextureNum       = new int[8]
        MainQuest.condUseGlow          = new bool[8]
        MainQuest.condMarkTint         = new int[8]
        MainQuest.condMarkEmissive     = new int[8]
        MainQuest.condMarkEmissiveMult = new float[8]
        MainQuest.condMarkAlpha        = new int[8]
        MainQuest.condHaloTint         = new int[8]
        MainQuest.condHaloEmissive     = new int[8]
        MainQuest.condHaloEmissiveMult = new float[8]
        MainQuest.condHaloAlpha        = new int[8]

        MainQuest.ModActive          = false
        MainQuest.updateInterval     = 2.0
        MainQuest.OverlaySlot        = 2
        MainQuest.CurrentOverlaySlot = 2

        ; Default slot (index 0)
        MainQuest.condTextureNum[0]   = 3
        MainQuest.condMarkAlpha[0]    = 100
        MainQuest.condMarkTint[0]     = 16777215
        MainQuest.condMarkEmissive[0] = 16777215

        ; Condition slots 1-7 — glow on, warm white defaults
        int i = 1
        while i < 8
            MainQuest.condUseGlow[i]          = true
            MainQuest.condMarkTint[i]         = 16777215
            MainQuest.condMarkAlpha[i]        = 70
            MainQuest.condMarkEmissive[i]     = 16777215
            MainQuest.condMarkEmissiveMult[i] = 2.5
            MainQuest.condHaloTint[i]         = 15231909
            MainQuest.condHaloAlpha[i]        = 100
            MainQuest.condHaloEmissive[i]     = 11337843
            MainQuest.condHaloEmissiveMult[i] = 3.0
            i += 1
        endwhile
    endif
    if CurrentVersion < 7
        ; v0.0.8: condPluginId now stores composite "<pluginId>:<itemId>" keys.
        ; All old single-id values are obsolete — wipe them.
        int slot7 = 0
        while slot7 < 8
            MainQuest.condPluginId[slot7] = ""
            MainQuest.condParam[slot7]    = 0
            slot7 += 1
        endwhile
    endif
    if CurrentVersion < 8
        ; v0.0.9: side effects moved to effect plugins. Allocate the per-slot
        ; effect list (8 slots × 4 effects = 32) and wipe any previously-set
        ; side-effect sliders (their backing arrays no longer exist on MainQuest).
        MainQuest.effectKey   = new string[32]
        MainQuest.effectParam = new int[32]
    endif
    if CurrentVersion < 10
        ; v0.0.10: condition and effect plugins merged. Old plugin IDs
        ; (lme.base.fx, lme.sla.fx) no longer exist — effect keys using
        ; them won't resolve. Wipe all per-slot effect picks. Condition
        ; picks are unchanged (lme.base, lme.fmr, lme.sla survive).
        int fxI = 0
        while fxI < 32
            MainQuest.effectKey[fxI]   = ""
            MainQuest.effectParam[fxI] = 0
            fxI += 1
        endwhile
    endif
    if CurrentVersion < 11
        ; v0.0.11: per-item enable/disable list. Default = all enabled.
        MainQuest.disabledItems = new string[64]
    endif
    if CurrentVersion < 12
        ; v0.0.12: split per-item toggles into their own "Menu Options" page.
        ; OnConfigInit only sets Pages once per MCM registration, so refresh.
        Pages = new String[4]
        Pages[0] = "General"
        Pages[1] = "Conditions"
        Pages[2] = "Plugins"
        Pages[3] = "Menu Options"
    endif
    if CurrentVersion < 13
        ; v0.0.13: per-slot cooldown (minutes, up to 24h).
        MainQuest.cooldownMin     = new int[8]
        MainQuest.cooldownUntilGT = new float[8]
    endif
    if CurrentVersion < 14
        ; v0.0.14: per-slot cooldown mode (0 = after-deactivate, 1 = lock-on-activate).
        MainQuest.cooldownMode = new int[8]
    endif
endEvent

; ── Page rendering ────────────────────────────────────────────────────────────
event OnPageReset(string page)
    _ensureMainQuest()
    if page == "General"
        drawGeneralPage()
    elseIf page == "Conditions"
        drawConditionsPage()
    elseif page == "Plugins"
        drawPluginsPage()
    elseif page == "Menu Options"
        drawMenuOptionsPage()
    endif
endEvent

; ── Settings binding (resolved on demand by walking plugins) ─────────────────
; Slot index `slot` (0..7) maps to the Nth setting found by walking
; registered plugins in order. _bindSetting() returns the owning plugin's
; Form and writes the local item idx into _scratchItemIdx. Re-derivable
; from any context so the slot → plugin mapping always matches between
; render and slider-event time even after save/load.

int _scratchItemIdx

string Function _settingStateId(int slot)
    return "SETTING_" + (slot + 1)
EndFunction

Form Function _bindSetting(int slot)
    int seen = 0
    int i = 0
    while i < MainQuest.pluginCount
        sd_LME_Plugin p = MainQuest.GetPluginAt(i)
        if p != None
            int n = p.GetSettingCount()
            if slot < seen + n
                _scratchItemIdx = slot - seen
                return p as Form
            endif
            seen += n
        endif
        i += 1
    endwhile
    return None
EndFunction

; Toggle pool: 32 TOGGLE_N states, each maps (via _bindToggle) to one
; condition or effect item across all registered plugins, in walk order:
;   for each plugin p, conditions 0..cn-1 then effects 0..en-1.
; Re-derived on demand; nothing cached.

string Function _toggleStateId(int slot)
    return "TOGGLE_" + (slot + 1)
EndFunction

string _scratchToggleKey
string _scratchToggleLabel
string _scratchToggleKind   ; "cond" or "effect"

bool Function _bindToggle(int slot)
{Writes the slot's composite key + label into scratch fields. Returns true if slot resolved.
 Walk order: all conditions across all plugins first, then all effects. The Menu Options
 page draws conditions in the left column and effects in the right, in the same order.}
    int totalConds = MainQuest.GetTotalConditionItemCount()
    if slot < totalConds
        ; condition walk
        int seen = 0
        int i = 0
        while i < MainQuest.pluginCount
            sd_LME_Plugin p = MainQuest.GetPluginAt(i)
            if p != None
                int cn = p.GetConditionCount()
                if slot < seen + cn
                    int local = slot - seen
                    _scratchToggleKey   = p.GetPluginId() + ":" + p.GetConditionId(local)
                    _scratchToggleLabel = p.GetConditionLabel(local)
                    _scratchToggleKind  = "cond"
                    return true
                endif
                seen += cn
            endif
            i += 1
        endwhile
        return false
    endif
    ; effect walk
    int eslot = slot - totalConds
    int seenE = 0
    int j = 0
    while j < MainQuest.pluginCount
        sd_LME_Plugin p2 = MainQuest.GetPluginAt(j)
        if p2 != None
            int en = p2.GetEffectCount()
            if eslot < seenE + en
                int localE = eslot - seenE
                _scratchToggleKey   = p2.GetPluginId() + ":" + p2.GetEffectId(localE)
                _scratchToggleLabel = p2.GetEffectLabel(localE)
                _scratchToggleKind  = "effect"
                return true
            endif
            seenE += en
        endif
        j += 1
    endwhile
    return false
EndFunction

Function _selectToggle(int slot)
    if !_bindToggle(slot)
        return
    endif
    bool now = !MainQuest.IsItemEnabled(_scratchToggleKey)
    MainQuest.SetItemEnabled(_scratchToggleKey, now)
    SetToggleOptionValueST(now)
EndFunction

Function _defaultToggle(int slot)
    if !_bindToggle(slot)
        return
    endif
    MainQuest.SetItemEnabled(_scratchToggleKey, true)
    SetToggleOptionValueST(true)
EndFunction

Function _highlightToggle(int slot)
    if !_bindToggle(slot)
        SetInfoText("")
        return
    endif
    string kindLabel = "condition"
    if _scratchToggleKind == "effect"
        kindLabel = "effect"
    endif
    SetInfoText("Enable this " + kindLabel + " (" + _scratchToggleKey + "). Disabled items are hidden from slot dropdowns.")
EndFunction

Function _setAllItems(bool on)
    int i = 0
    while i < MainQuest.pluginCount
        sd_LME_Plugin p = MainQuest.GetPluginAt(i)
        if p != None
            string pid = p.GetPluginId()
            int cn = p.GetConditionCount()
            int c = 0
            while c < cn
                MainQuest.SetItemEnabled(pid + ":" + p.GetConditionId(c), on)
                c += 1
            endwhile
            int en = p.GetEffectCount()
            int e = 0
            while e < en
                MainQuest.SetItemEnabled(pid + ":" + p.GetEffectId(e), on)
                e += 1
            endwhile
        endif
        i += 1
    endwhile
    ForcePageReset()
EndFunction

state TOGGLE_ALL
    event OnMenuOpenST()
        string[] opts = new string[3]
        opts[0] = "—"
        opts[1] = "Enable all"
        opts[2] = "Disable all"
        SetMenuDialogStartIndex(0)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index == 1
            _setAllItems(true)
        elseif index == 2
            _setAllItems(false)
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Bulk-toggle every condition and effect across all plugins.")
    endEvent
endState

function drawGeneralPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("General")
    AddToggleOptionST("GEN_MOD_ACTIVE",      "Enable",                MainQuest.ModActive)
    AddSliderOptionST("GEN_UPDATE_INTERVAL", "Update interval (sec)", MainQuest.updateInterval, "{1}")
    AddToggleOptionST("GEN_USE_SLAVETATS",   "Use SlaveTats textures", MainQuest.useSlaveTats)
    AddToggleOptionST("GEN_DEBUG_MODE",      "Debug mode",             MainQuest.DebugMode)
endFunction

function drawPluginsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    int settingSlot = 0

    AddHeaderOption("Plugins (" + MainQuest.pluginCount + ", " + MainQuest.GetTotalConditionItemCount() + " conditions, " + MainQuest.GetTotalEffectItemCount() + " effects)")
    int i = 0
    while i < MainQuest.pluginCount
        sd_LME_Plugin p = MainQuest.GetPluginAt(i)
        if p != None
            int cn = p.GetConditionCount()
            int en = p.GetEffectCount()
            AddTextOption(p.GetPluginLabel(), p.GetPluginId() + " (" + cn + "c, " + en + "e)", OPTION_FLAG_DISABLED)
            int sn = p.GetSettingCount()
            int s = 0
            while s < sn && settingSlot < 8
                AddSliderOptionST(_settingStateId(settingSlot), "  " + p.GetSettingLabel(s), p.GetSettingValue(s), p.GetSettingFormat(s))
                settingSlot += 1
                s += 1
            endwhile
        endif
        i += 1
    endwhile
endFunction

function drawMenuOptionsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    ; Row 0 — header left, bulk toggle right
    AddHeaderOption("Visible items")
    SetCursorPosition(1)
    AddMenuOptionST("TOGGLE_ALL", "Bulk toggle", "—")

    ; ── Left column: conditions ──
    SetCursorPosition(2)    ; row 1 col 0
    int toggleSlot = 0
    AddHeaderOption("Conditions")
    int i = 0
    while i < MainQuest.pluginCount
        sd_LME_Plugin p = MainQuest.GetPluginAt(i)
        if p != None
            int cn = p.GetConditionCount()
            if cn > 0
                AddTextOption(p.GetPluginLabel(), "", OPTION_FLAG_DISABLED)
                int c = 0
                while c < cn && toggleSlot < 32
                    string ckey = p.GetPluginId() + ":" + p.GetConditionId(c)
                    AddToggleOptionST(_toggleStateId(toggleSlot), "  " + p.GetConditionLabel(c), MainQuest.IsItemEnabled(ckey))
                    toggleSlot += 1
                    c += 1
                endwhile
            endif
        endif
        i += 1
    endwhile

    ; ── Right column: effects ──
    SetCursorPosition(3)    ; row 1 col 1
    AddHeaderOption("Effects")
    int j = 0
    while j < MainQuest.pluginCount
        sd_LME_Plugin p2 = MainQuest.GetPluginAt(j)
        if p2 != None
            int en = p2.GetEffectCount()
            if en > 0
                AddTextOption(p2.GetPluginLabel(), "", OPTION_FLAG_DISABLED)
                int e = 0
                while e < en && toggleSlot < 32
                    string ekey = p2.GetPluginId() + ":" + p2.GetEffectId(e)
                    AddToggleOptionST(_toggleStateId(toggleSlot), "  " + p2.GetEffectLabel(e), MainQuest.IsItemEnabled(ekey))
                    toggleSlot += 1
                    e += 1
                endwhile
            endif
        endif
        j += 1
    endwhile
endFunction

; ── Setting-slot dispatchers (the 8 SETTING_N state blocks all call these) ──

Function _openSetting(int slot)
    Form f = _bindSetting(slot)
    if f == None
        return
    endif
    sd_LME_Plugin p = f as sd_LME_Plugin
    int idx = _scratchItemIdx
    SetSliderDialogStartValue(p.GetSettingValue(idx))
    SetSliderDialogDefaultValue(p.GetSettingDefault(idx))
    SetSliderDialogRange(p.GetSettingMin(idx), p.GetSettingMax(idx))
    SetSliderDialogInterval(1)
EndFunction

Function _acceptSetting(int slot, float value)
    Form f = _bindSetting(slot)
    if f == None
        return
    endif
    sd_LME_Plugin p = f as sd_LME_Plugin
    int idx = _scratchItemIdx
    int v = value as int
    p.SetSettingValue(idx, v)
    SetSliderOptionValueST(v, p.GetSettingFormat(idx))
EndFunction

Function _defaultSetting(int slot)
    Form f = _bindSetting(slot)
    if f == None
        return
    endif
    sd_LME_Plugin p = f as sd_LME_Plugin
    int idx = _scratchItemIdx
    int defV = p.GetSettingDefault(idx)
    p.SetSettingValue(idx, defV)
    SetSliderOptionValueST(defV, p.GetSettingFormat(idx))
EndFunction

Function _highlightSetting(int slot)
    Form f = _bindSetting(slot)
    if f == None
        SetInfoText("")
        return
    endif
    sd_LME_Plugin p = f as sd_LME_Plugin
    SetInfoText(p.GetSettingInfo(_scratchItemIdx))
EndFunction

function drawConditionsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)

    int idx = selectedCondition

    if idx == 0
        AddMenuOptionST("COND_SELECTOR", "Configure slot", _slotLabel(selectedCondition))
        AddHeaderOption("Default slot")
        AddSliderOptionST("SLOT_OVERLAY_SLOT", "Overlay slot",   MainQuest.OverlaySlot)
        AddSliderOptionST("SLOT_TEXTURE_NUM",  "Texture number", MainQuest.condTextureNum[0])
        AddToggleOptionST("SLOT_USE_GLOW",     "Use glow",       MainQuest.condUseGlow[0])
    else
        string key = MainQuest.condPluginId[idx]
        sd_LME_Plugin p = None
        int itemIdx = -1
        if key != ""
            p = MainQuest.ResolvePluginByKey(key)
            if p != None
                itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            endif
        endif

        AddMenuOptionST("COND_SELECTOR", "Configure slot", _slotLabel(selectedCondition))
        AddMenuOptionST("SLOT_COND_TYPE", "Condition type", _condTypeLabel(key))
        AddHeaderOption("Condition " + idx)

        if p != None && itemIdx >= 0
            string paramLabel = p.GetConditionParamLabel(itemIdx)
            if paramLabel != ""
                AddSliderOptionST("SLOT_COND_PARAM", paramLabel, MainQuest.condParam[idx])
            else
                AddTextOption(p.GetConditionLabel(itemIdx), "(no parameter)", OPTION_FLAG_DISABLED)
            endif
        endif

        AddSliderOptionST("SLOT_TEXTURE_NUM", "Texture (0 = Default)", MainQuest.condTextureNum[idx])
        AddToggleOptionST("SLOT_USE_GLOW",    "Use glow",               MainQuest.condUseGlow[idx])

        int cdMin = MainQuest.cooldownMin[idx]
        AddHeaderOption("Cooldown")
        AddMenuOptionST("SLOT_CD_MODE",     "Mode",    _cooldownModeLabel(MainQuest.cooldownMode[idx]))
        AddSliderOptionST("SLOT_CD_HOURS",   "Hours",   cdMin / 60)
        AddSliderOptionST("SLOT_CD_MINUTES", "Minutes", cdMin % 60)
    endif

    AddHeaderOption("Effects")
    _drawEffectRow(idx, 0, "SLOT_EFFECT_1_TYPE", "SLOT_EFFECT_1_PARAM")
    _drawEffectRow(idx, 1, "SLOT_EFFECT_2_TYPE", "SLOT_EFFECT_2_PARAM")
    _drawEffectRow(idx, 2, "SLOT_EFFECT_3_TYPE", "SLOT_EFFECT_3_PARAM")
    _drawEffectRow(idx, 3, "SLOT_EFFECT_4_TYPE", "SLOT_EFFECT_4_PARAM")

    SetCursorPosition(1)
    AddHeaderOption("Mark colors")
    AddColorOptionST("SLOT_MARK_TINT",          "Tint",              MainQuest.condMarkTint[idx])
    AddColorOptionST("SLOT_MARK_EMISSIVE",       "Emission color",    MainQuest.condMarkEmissive[idx])
    AddSliderOptionST("SLOT_MARK_EMISSIVE_MULT", "Emission strength", MainQuest.condMarkEmissiveMult[idx], "{1}")
    AddSliderOptionST("SLOT_MARK_ALPHA",          "Opacity",          MainQuest.condMarkAlpha[idx], "{0}%")

    AddHeaderOption("Halo colors")
    AddColorOptionST("SLOT_HALO_TINT",          "Tint",              MainQuest.condHaloTint[idx])
    AddColorOptionST("SLOT_HALO_EMISSIVE",       "Emission color",    MainQuest.condHaloEmissive[idx])
    AddSliderOptionST("SLOT_HALO_EMISSIVE_MULT", "Emission strength", MainQuest.condHaloEmissiveMult[idx], "{1}")
    AddSliderOptionST("SLOT_HALO_ALPHA",          "Opacity",          MainQuest.condHaloAlpha[idx], "{0}%")
endFunction

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  GENERAL PAGE STATES                                                    ║
; ╚══════════════════════════════════════════════════════════════════════════╝

state GEN_MOD_ACTIVE
    event OnSelectST()
        bool v = !MainQuest.ModActive
        MainQuest.ModActive = v
        SetToggleOptionValueST(v)
        if v
            MainQuest.setRedraw()
            MainQuest.GotoState("checkingAroused")
        endif
    endEvent
    event OnDefaultST()
        MainQuest.ModActive = false
        SetToggleOptionValueST(false)
    endEvent
    event OnHighlightST()
        SetInfoText("Enable or disable the mod.")
    endEvent
endState

state GEN_UPDATE_INTERVAL
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.updateInterval)
        SetSliderDialogDefaultValue(2.0)
        SetSliderDialogRange(1, 45)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.updateInterval = value
        SetSliderOptionValueST(value, "{1}")
    endEvent
    event OnDefaultST()
        MainQuest.updateInterval = 2.0
        SetSliderOptionValueST(2.0, "{1}")
    endEvent
    event OnHighlightST()
        SetInfoText("How often in seconds the script checks conditions. Lower = more responsive, higher = better performance.")
    endEvent
endState

state GEN_USE_SLAVETATS
    event OnSelectST()
        bool v = !MainQuest.useSlaveTats
        MainQuest.useSlaveTats = v
        SetToggleOptionValueST(v)
        toggleTextureSet(v)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.useSlaveTats = false
        SetToggleOptionValueST(false)
        toggleTextureSet(false)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Use SlaveTats texture paths instead of RaceMenu overlay paths.")
    endEvent
endState

state GEN_DEBUG_MODE
    event OnSelectST()
        bool v = !MainQuest.DebugMode
        MainQuest.DebugMode = v
        SetToggleOptionValueST(v)
    endEvent
    event OnDefaultST()
        MainQuest.DebugMode = false
        SetToggleOptionValueST(false)
    endEvent
    event OnHighlightST()
        SetInfoText("Show a corner-notification toast whenever the active condition tier changes, listing what's being drained. Useful for verifying that conditions and side effects are firing correctly.")
    endEvent
endState

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  CONDITIONS PAGE STATES                                                 ║
; ╚══════════════════════════════════════════════════════════════════════════╝

state COND_SELECTOR
    event OnMenuOpenST()
        string[] opts = new string[8]
        opts[0] = "Default"
        opts[1] = "Condition 1"
        opts[2] = "Condition 2"
        opts[3] = "Condition 3"
        opts[4] = "Condition 4"
        opts[5] = "Condition 5"
        opts[6] = "Condition 6"
        opts[7] = "Condition 7"
        SetMenuDialogStartIndex(selectedCondition)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index < 0
            return
        endif
        selectedCondition = index
        SetMenuOptionValueST(_slotLabel(index))
        ForcePageReset()
    endEvent
    event OnDefaultST()
        selectedCondition = 0
        SetMenuOptionValueST(_slotLabel(0))
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Select which slot to configure. Default is always active as the fallback. Conditions 1-7 are checked in order — first satisfied wins.")
    endEvent
endState

state SLOT_OVERLAY_SLOT
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.OverlaySlot)
        SetSliderDialogDefaultValue(2)
        SetSliderDialogRange(0, 30)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.OverlaySlot = value as int
        SetSliderOptionValueST(value as int)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.OverlaySlot = 2
        SetSliderOptionValueST(2)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Base NiOverride overlay slot. Two consecutive slots are used: this slot (mark) and slot+1 (halo). Avoid conflicts with other overlay mods.")
    endEvent
endState

state SLOT_COND_TYPE
    event OnMenuOpenST()
        ; Flattened visible-only list. Index 0 = "Not set"; the currently-
        ; bound key stays visible even if disabled.
        string curKey = MainQuest.condPluginId[selectedCondition]
        int total = 1 + MainQuest.GetVisibleConditionCount(curKey)
        if total > 10
            total = 10    ; _newOpts dispatcher max
        endif
        string[] opts = _newOpts(total)
        opts[0] = "Not set"
        int curIdx = 0
        int i = 0
        while (i + 1) < total
            string key = MainQuest.GetVisibleConditionKey(i, curKey)
            opts[i + 1] = MainQuest.GetVisibleConditionLabel(i, curKey)
            if key == curKey
                curIdx = i + 1
            endif
            i += 1
        endwhile
        SetMenuDialogStartIndex(curIdx)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index < 0
            return
        endif
        int slot = selectedCondition
        string curKey = MainQuest.condPluginId[slot]
        string newKey = ""
        if index > 0
            newKey = MainQuest.GetVisibleConditionKey(index - 1, curKey)
        endif
        MainQuest.condPluginId[slot] = newKey
        if newKey == ""
            MainQuest.condParam[slot] = 0
        else
            sd_LME_Plugin p = MainQuest.ResolvePluginByKey(newKey)
            int itemIdx = -1
            if p != None
                itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(newKey))
            endif
            if itemIdx >= 0
                MainQuest.condParam[slot] = p.GetConditionParamDefault(itemIdx)
            else
                MainQuest.condParam[slot] = 0
            endif
        endif
        SetMenuOptionValueST(_condTypeLabel(newKey))
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.condPluginId[selectedCondition] = ""
        MainQuest.condParam[selectedCondition]    = 0
        SetMenuOptionValueST(_condTypeLabel(""))
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Which condition must be satisfied for this slot to activate. The list is built from registered plugins.")
    endEvent
endState

state SLOT_COND_PARAM
    event OnSliderOpenST()
        string key = MainQuest.condPluginId[selectedCondition]
        sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p == None
            return
        endif
        int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx < 0
            return
        endif
        SetSliderDialogStartValue(MainQuest.condParam[selectedCondition])
        SetSliderDialogDefaultValue(p.GetConditionParamDefault(itemIdx))
        SetSliderDialogRange(p.GetConditionParamMin(itemIdx), p.GetConditionParamMax(itemIdx))
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condParam[selectedCondition] = value as int
        SetSliderOptionValueST(value as int)
    endEvent
    event OnDefaultST()
        string key = MainQuest.condPluginId[selectedCondition]
        sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
        int defVal = 0
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                defVal = p.GetConditionParamDefault(itemIdx)
            endif
        endif
        MainQuest.condParam[selectedCondition] = defVal
        SetSliderOptionValueST(defVal)
    endEvent
    event OnHighlightST()
        string key = MainQuest.condPluginId[selectedCondition]
        sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                SetInfoText(p.GetConditionParamLabel(itemIdx))
                return
            endif
        endif
        SetInfoText("Threshold value for the selected condition.")
    endEvent
endState

state SLOT_TEXTURE_NUM
    event OnSliderOpenST()
        int idx = selectedCondition
        SetSliderDialogStartValue(MainQuest.condTextureNum[idx])
        SetSliderDialogInterval(1)
        if idx == 0
            SetSliderDialogDefaultValue(3)
            SetSliderDialogRange(1, lewdMarksLastNumber)
        else
            SetSliderDialogDefaultValue(0)
            SetSliderDialogRange(0, lewdMarksLastNumber)
        endif
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condTextureNum[selectedCondition] = value as int
        SetSliderOptionValueST(value as int)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        int defVal = 0
        if selectedCondition == 0
            defVal = 3
        endif
        MainQuest.condTextureNum[selectedCondition] = defVal
        SetSliderOptionValueST(defVal)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        if selectedCondition == 0
            SetInfoText("Base LewdMark texture number (1-96). Condition slots can override this.")
        else
            SetInfoText("Override texture number for this slot. Set 0 to use the Default slot's texture.")
        endif
    endEvent
endState

state SLOT_USE_GLOW
    event OnSelectST()
        bool v = !MainQuest.condUseGlow[selectedCondition]
        MainQuest.condUseGlow[selectedCondition] = v
        SetToggleOptionValueST(v)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        bool defVal = false
        if selectedCondition > 0
            defVal = true
        endif
        MainQuest.condUseGlow[selectedCondition] = defVal
        SetToggleOptionValueST(defVal)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Show glowing texture variant and halo when this slot is active.")
    endEvent
endState

string Function _cooldownModeLabel(int mode)
    if mode == 1
        return "Lock on activate"
    endif
    return "After deactivate"
EndFunction

state SLOT_CD_MODE
    event OnMenuOpenST()
        string[] opts = new string[2]
        opts[0] = "After deactivate"
        opts[1] = "Lock on activate"
        SetMenuDialogStartIndex(MainQuest.cooldownMode[selectedCondition])
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index < 0
            return
        endif
        MainQuest.cooldownMode[selectedCondition] = index
        SetMenuOptionValueST(_cooldownModeLabel(index))
    endEvent
    event OnDefaultST()
        MainQuest.cooldownMode[selectedCondition] = 0
        SetMenuOptionValueST(_cooldownModeLabel(0))
    endEvent
    event OnHighlightST()
        SetInfoText("After deactivate: slot can't reactivate for the cooldown duration. Lock on activate: slot stays active and blocks lower-priority slots for the duration (higher-priority slots can still override).")
    endEvent
endState

Function _setCooldownComponents(int hours, int minutes)
    if hours < 0
        hours = 0
    elseif hours > 24
        hours = 24
    endif
    if minutes < 0
        minutes = 0
    elseif minutes > 59
        minutes = 59
    endif
    int total = hours * 60 + minutes
    if total > 1440
        total = 1440
    endif
    MainQuest.cooldownMin[selectedCondition] = total
EndFunction

state SLOT_CD_HOURS
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.cooldownMin[selectedCondition] / 60)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 24)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        int hours = value as int
        int minutes = MainQuest.cooldownMin[selectedCondition] % 60
        _setCooldownComponents(hours, minutes)
        SetSliderOptionValueST(MainQuest.cooldownMin[selectedCondition] / 60)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        _setCooldownComponents(0, MainQuest.cooldownMin[selectedCondition] % 60)
        SetSliderOptionValueST(0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Hours of cooldown after this slot deactivates. Higher-priority slots can still activate during cooldown.")
    endEvent
endState

state SLOT_CD_MINUTES
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.cooldownMin[selectedCondition] % 60)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 59)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        int minutes = value as int
        int hours = MainQuest.cooldownMin[selectedCondition] / 60
        _setCooldownComponents(hours, minutes)
        SetSliderOptionValueST(MainQuest.cooldownMin[selectedCondition] % 60)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        _setCooldownComponents(MainQuest.cooldownMin[selectedCondition] / 60, 0)
        SetSliderOptionValueST(0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Minutes of cooldown after this slot deactivates (added to hours).")
    endEvent
endState

; ── Per-slot effect list (4 effects × 2 controls each) ──────────────────────

string Function _effectTypeLabel(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    if key == ""
        return "Not set"
    endif
    sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return "Unknown (" + key + ")"
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return "Unknown (" + key + ")"
    endif
    string pl = p.GetPluginLabel()
    string il = p.GetEffectLabel(itemIdx)
    if pl == ""
        return il
    endif
    return pl + " — " + il
EndFunction

Function _drawEffectRow(int slot, int effectIdx, string typeStateId, string paramStateId)
    AddMenuOptionST(typeStateId, "Effect " + (effectIdx + 1), _effectTypeLabel(effectIdx))
    string key = MainQuest.GetSlotEffectKey(slot, effectIdx)
    if key == ""
        return
    endif
    sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    string paramLabel = p.GetEffectParamLabel(itemIdx)
    if paramLabel != ""
        AddSliderOptionST(paramStateId, "  " + paramLabel, MainQuest.GetSlotEffectParam(slot, effectIdx))
    endif
EndFunction

Function _openEffectTypeMenu(int effectIdx)
    string curKey = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    int total = 1 + MainQuest.GetVisibleEffectCount(curKey)
    if total > 10
        total = 10
    endif
    string[] opts = _newOpts(total)
    opts[0] = "Not set"
    int curSel = 0
    int i = 0
    while (i + 1) < total
        string key = MainQuest.GetVisibleEffectKey(i, curKey)
        opts[i + 1] = MainQuest.GetVisibleEffectLabel(i, curKey)
        if key == curKey
            curSel = i + 1
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(curSel)
    SetMenuDialogDefaultIndex(0)
    SetMenuDialogOptions(opts)
EndFunction

Function _acceptEffectType(int effectIdx, int index)
    if index < 0
        return
    endif
    string newKey = ""
    int defParam = 0
    if index > 0
        string curKey = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
        newKey = MainQuest.GetVisibleEffectKey(index - 1, curKey)
        sd_LME_Plugin p = MainQuest.ResolvePluginByKey(newKey)
        if p != None
            int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(newKey))
            if itemIdx >= 0
                defParam = p.GetEffectParamDefault(itemIdx)
            endif
        endif
    endif
    MainQuest.SetSlotEffect(selectedCondition, effectIdx, newKey, defParam)
EndFunction

Function _openEffectParam(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    SetSliderDialogStartValue(MainQuest.GetSlotEffectParam(selectedCondition, effectIdx))
    SetSliderDialogDefaultValue(p.GetEffectParamDefault(itemIdx))
    SetSliderDialogRange(p.GetEffectParamMin(itemIdx), p.GetEffectParamMax(itemIdx))
    SetSliderDialogInterval(1)
EndFunction

Function _acceptEffectParam(int effectIdx, float value)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MainQuest.SetSlotEffect(selectedCondition, effectIdx, key, value as int)
    SetSliderOptionValueST(value as int)
EndFunction

Function _defaultEffectParam(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
    int defVal = 0
    if p != None
        int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            defVal = p.GetEffectParamDefault(itemIdx)
        endif
    endif
    MainQuest.SetSlotEffect(selectedCondition, effectIdx, key, defVal)
    SetSliderOptionValueST(defVal)
EndFunction

Function _highlightEffectParam(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    sd_LME_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p != None
        int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            SetInfoText(p.GetEffectParamLabel(itemIdx))
            return
        endif
    endif
    SetInfoText("Effect parameter.")
EndFunction

state SLOT_EFFECT_1_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(0)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(0, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 0, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins. The effect fires while this slot is the winning tier.")
    endEvent
endState

state SLOT_EFFECT_1_PARAM
    event OnSliderOpenST()
        _openEffectParam(0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(0, value)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(0)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(0)
    endEvent
endState

state SLOT_EFFECT_2_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(1, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 1, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_2_PARAM
    event OnSliderOpenST()
        _openEffectParam(1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(1, value)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(1)
    endEvent
endState

state SLOT_EFFECT_3_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(2, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 2, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_3_PARAM
    event OnSliderOpenST()
        _openEffectParam(2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(2, value)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(2)
    endEvent
endState

state SLOT_EFFECT_4_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(3, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 3, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_4_PARAM
    event OnSliderOpenST()
        _openEffectParam(3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(3, value)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(3)
    endEvent
endState

; ── Visual states (shared across all slots via selectedCondition) ─────────────

state SLOT_MARK_TINT
    event OnColorOpenST()
        SetColorDialogStartColor(MainQuest.condMarkTint[selectedCondition])
        if selectedCondition > 0
            SetColorDialogDefaultColor(16777215)
        else
            SetColorDialogDefaultColor(16777215)
        endif
    endEvent
    event OnColorAcceptST(int color)
        MainQuest.condMarkTint[selectedCondition] = color
        SetColorOptionValueST(color)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.condMarkTint[selectedCondition] = 16777215
        SetColorOptionValueST(16777215)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color applied to the mark texture.")
    endEvent
endState

state SLOT_MARK_EMISSIVE
    event OnColorOpenST()
        SetColorDialogStartColor(MainQuest.condMarkEmissive[selectedCondition])
        SetColorDialogDefaultColor(16777215)
    endEvent
    event OnColorAcceptST(int color)
        MainQuest.condMarkEmissive[selectedCondition] = color
        SetColorOptionValueST(color)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.condMarkEmissive[selectedCondition] = 16777215
        SetColorOptionValueST(16777215)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Emission (glow) color for the mark.")
    endEvent
endState

state SLOT_MARK_EMISSIVE_MULT
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condMarkEmissiveMult[selectedCondition])
        if selectedCondition > 0
            SetSliderDialogDefaultValue(2.5)
        else
            SetSliderDialogDefaultValue(0.0)
        endif
        SetSliderDialogRange(0.0, 25.0)
        SetSliderDialogInterval(0.5)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condMarkEmissiveMult[selectedCondition] = value
        SetSliderOptionValueST(value, "{1}")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        float defVal = 0.0
        if selectedCondition > 0
            defVal = 2.5
        endif
        MainQuest.condMarkEmissiveMult[selectedCondition] = defVal
        SetSliderOptionValueST(defVal, "{1}")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for the mark.")
    endEvent
endState

state SLOT_MARK_ALPHA
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condMarkAlpha[selectedCondition])
        if selectedCondition > 0
            SetSliderDialogDefaultValue(70)
        else
            SetSliderDialogDefaultValue(100)
        endif
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condMarkAlpha[selectedCondition] = value as int
        SetSliderOptionValueST(value, "{0}%")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        int defVal = 100
        if selectedCondition > 0
            defVal = 70
        endif
        MainQuest.condMarkAlpha[selectedCondition] = defVal
        SetSliderOptionValueST(defVal, "{0}%")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity of the mark.")
    endEvent
endState

state SLOT_HALO_TINT
    event OnColorOpenST()
        SetColorDialogStartColor(MainQuest.condHaloTint[selectedCondition])
        if selectedCondition > 0
            SetColorDialogDefaultColor(15231909)
        else
            SetColorDialogDefaultColor(0)
        endif
    endEvent
    event OnColorAcceptST(int color)
        MainQuest.condHaloTint[selectedCondition] = color
        SetColorOptionValueST(color)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        int defVal = 0
        if selectedCondition > 0
            defVal = 15231909
        endif
        MainQuest.condHaloTint[selectedCondition] = defVal
        SetColorOptionValueST(defVal)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for the halo layer.")
    endEvent
endState

state SLOT_HALO_EMISSIVE
    event OnColorOpenST()
        SetColorDialogStartColor(MainQuest.condHaloEmissive[selectedCondition])
        if selectedCondition > 0
            SetColorDialogDefaultColor(11337843)
        else
            SetColorDialogDefaultColor(0)
        endif
    endEvent
    event OnColorAcceptST(int color)
        MainQuest.condHaloEmissive[selectedCondition] = color
        SetColorOptionValueST(color)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        int defVal = 0
        if selectedCondition > 0
            defVal = 11337843
        endif
        MainQuest.condHaloEmissive[selectedCondition] = defVal
        SetColorOptionValueST(defVal)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Emission (glow) color for the halo.")
    endEvent
endState

state SLOT_HALO_EMISSIVE_MULT
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condHaloEmissiveMult[selectedCondition])
        if selectedCondition > 0
            SetSliderDialogDefaultValue(3.0)
        else
            SetSliderDialogDefaultValue(0.0)
        endif
        SetSliderDialogRange(0.0, 25.0)
        SetSliderDialogInterval(0.5)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condHaloEmissiveMult[selectedCondition] = value
        SetSliderOptionValueST(value, "{1}")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        float defVal = 0.0
        if selectedCondition > 0
            defVal = 3.0
        endif
        MainQuest.condHaloEmissiveMult[selectedCondition] = defVal
        SetSliderOptionValueST(defVal, "{1}")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for the halo.")
    endEvent
endState

state SLOT_HALO_ALPHA
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condHaloAlpha[selectedCondition])
        if selectedCondition > 0
            SetSliderDialogDefaultValue(100)
        else
            SetSliderDialogDefaultValue(0)
        endif
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condHaloAlpha[selectedCondition] = value as int
        SetSliderOptionValueST(value, "{0}%")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        int defVal = 0
        if selectedCondition > 0
            defVal = 100
        endif
        MainQuest.condHaloAlpha[selectedCondition] = defVal
        SetSliderOptionValueST(defVal, "{0}%")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity of the halo.")
    endEvent
endState

; ── Plugin-settings slider slots ──────────────────────────────────────────────
state SETTING_1
    event OnSliderOpenST()
        _openSetting(0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptSetting(0, value)
    endEvent
    event OnDefaultST()
        _defaultSetting(0)
    endEvent
    event OnHighlightST()
        _highlightSetting(0)
    endEvent
endState

state SETTING_2
    event OnSliderOpenST()
        _openSetting(1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptSetting(1, value)
    endEvent
    event OnDefaultST()
        _defaultSetting(1)
    endEvent
    event OnHighlightST()
        _highlightSetting(1)
    endEvent
endState

state SETTING_3
    event OnSliderOpenST()
        _openSetting(2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptSetting(2, value)
    endEvent
    event OnDefaultST()
        _defaultSetting(2)
    endEvent
    event OnHighlightST()
        _highlightSetting(2)
    endEvent
endState

state SETTING_4
    event OnSliderOpenST()
        _openSetting(3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptSetting(3, value)
    endEvent
    event OnDefaultST()
        _defaultSetting(3)
    endEvent
    event OnHighlightST()
        _highlightSetting(3)
    endEvent
endState

state SETTING_5
    event OnSliderOpenST()
        _openSetting(4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptSetting(4, value)
    endEvent
    event OnDefaultST()
        _defaultSetting(4)
    endEvent
    event OnHighlightST()
        _highlightSetting(4)
    endEvent
endState

state SETTING_6
    event OnSliderOpenST()
        _openSetting(5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptSetting(5, value)
    endEvent
    event OnDefaultST()
        _defaultSetting(5)
    endEvent
    event OnHighlightST()
        _highlightSetting(5)
    endEvent
endState

state SETTING_7
    event OnSliderOpenST()
        _openSetting(6)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptSetting(6, value)
    endEvent
    event OnDefaultST()
        _defaultSetting(6)
    endEvent
    event OnHighlightST()
        _highlightSetting(6)
    endEvent
endState

state SETTING_8
    event OnSliderOpenST()
        _openSetting(7)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptSetting(7, value)
    endEvent
    event OnDefaultST()
        _defaultSetting(7)
    endEvent
    event OnHighlightST()
        _highlightSetting(7)
    endEvent
endState

; ── Helpers ───────────────────────────────────────────────────────────────────
string[] Function _newOpts(int n)
{Papyrus requires literal array sizes; this dispatcher picks the matching literal.}
    if n <= 1
        return new string[1]
    elseIf n == 2
        return new string[2]
    elseIf n == 3
        return new string[3]
    elseIf n == 4
        return new string[4]
    elseIf n == 5
        return new string[5]
    elseIf n == 6
        return new string[6]
    elseIf n == 7
        return new string[7]
    elseIf n == 8
        return new string[8]
    elseIf n == 9
        return new string[9]
    endif
    return new string[10]
EndFunction

function toggleTextureSet(bool useST)
    if useST
        MainQuest.texturePathNormal = texturePathNormalST
        MainQuest.texturePathGlow   = texturePathGlowST
    else
        MainQuest.texturePathNormal = texturePathNormalRM
        MainQuest.texturePathGlow   = texturePathGlowRM
    endif
endFunction

state TOGGLE_1
    event OnSelectST()
        _selectToggle(0)
    endEvent
    event OnDefaultST()
        _defaultToggle(0)
    endEvent
    event OnHighlightST()
        _highlightToggle(0)
    endEvent
endState
state TOGGLE_2
    event OnSelectST()
        _selectToggle(1)
    endEvent
    event OnDefaultST()
        _defaultToggle(1)
    endEvent
    event OnHighlightST()
        _highlightToggle(1)
    endEvent
endState
state TOGGLE_3
    event OnSelectST()
        _selectToggle(2)
    endEvent
    event OnDefaultST()
        _defaultToggle(2)
    endEvent
    event OnHighlightST()
        _highlightToggle(2)
    endEvent
endState
state TOGGLE_4
    event OnSelectST()
        _selectToggle(3)
    endEvent
    event OnDefaultST()
        _defaultToggle(3)
    endEvent
    event OnHighlightST()
        _highlightToggle(3)
    endEvent
endState
state TOGGLE_5
    event OnSelectST()
        _selectToggle(4)
    endEvent
    event OnDefaultST()
        _defaultToggle(4)
    endEvent
    event OnHighlightST()
        _highlightToggle(4)
    endEvent
endState
state TOGGLE_6
    event OnSelectST()
        _selectToggle(5)
    endEvent
    event OnDefaultST()
        _defaultToggle(5)
    endEvent
    event OnHighlightST()
        _highlightToggle(5)
    endEvent
endState
state TOGGLE_7
    event OnSelectST()
        _selectToggle(6)
    endEvent
    event OnDefaultST()
        _defaultToggle(6)
    endEvent
    event OnHighlightST()
        _highlightToggle(6)
    endEvent
endState
state TOGGLE_8
    event OnSelectST()
        _selectToggle(7)
    endEvent
    event OnDefaultST()
        _defaultToggle(7)
    endEvent
    event OnHighlightST()
        _highlightToggle(7)
    endEvent
endState
state TOGGLE_9
    event OnSelectST()
        _selectToggle(8)
    endEvent
    event OnDefaultST()
        _defaultToggle(8)
    endEvent
    event OnHighlightST()
        _highlightToggle(8)
    endEvent
endState
state TOGGLE_10
    event OnSelectST()
        _selectToggle(9)
    endEvent
    event OnDefaultST()
        _defaultToggle(9)
    endEvent
    event OnHighlightST()
        _highlightToggle(9)
    endEvent
endState
state TOGGLE_11
    event OnSelectST()
        _selectToggle(10)
    endEvent
    event OnDefaultST()
        _defaultToggle(10)
    endEvent
    event OnHighlightST()
        _highlightToggle(10)
    endEvent
endState
state TOGGLE_12
    event OnSelectST()
        _selectToggle(11)
    endEvent
    event OnDefaultST()
        _defaultToggle(11)
    endEvent
    event OnHighlightST()
        _highlightToggle(11)
    endEvent
endState
state TOGGLE_13
    event OnSelectST()
        _selectToggle(12)
    endEvent
    event OnDefaultST()
        _defaultToggle(12)
    endEvent
    event OnHighlightST()
        _highlightToggle(12)
    endEvent
endState
state TOGGLE_14
    event OnSelectST()
        _selectToggle(13)
    endEvent
    event OnDefaultST()
        _defaultToggle(13)
    endEvent
    event OnHighlightST()
        _highlightToggle(13)
    endEvent
endState
state TOGGLE_15
    event OnSelectST()
        _selectToggle(14)
    endEvent
    event OnDefaultST()
        _defaultToggle(14)
    endEvent
    event OnHighlightST()
        _highlightToggle(14)
    endEvent
endState
state TOGGLE_16
    event OnSelectST()
        _selectToggle(15)
    endEvent
    event OnDefaultST()
        _defaultToggle(15)
    endEvent
    event OnHighlightST()
        _highlightToggle(15)
    endEvent
endState
state TOGGLE_17
    event OnSelectST()
        _selectToggle(16)
    endEvent
    event OnDefaultST()
        _defaultToggle(16)
    endEvent
    event OnHighlightST()
        _highlightToggle(16)
    endEvent
endState
state TOGGLE_18
    event OnSelectST()
        _selectToggle(17)
    endEvent
    event OnDefaultST()
        _defaultToggle(17)
    endEvent
    event OnHighlightST()
        _highlightToggle(17)
    endEvent
endState
state TOGGLE_19
    event OnSelectST()
        _selectToggle(18)
    endEvent
    event OnDefaultST()
        _defaultToggle(18)
    endEvent
    event OnHighlightST()
        _highlightToggle(18)
    endEvent
endState
state TOGGLE_20
    event OnSelectST()
        _selectToggle(19)
    endEvent
    event OnDefaultST()
        _defaultToggle(19)
    endEvent
    event OnHighlightST()
        _highlightToggle(19)
    endEvent
endState
state TOGGLE_21
    event OnSelectST()
        _selectToggle(20)
    endEvent
    event OnDefaultST()
        _defaultToggle(20)
    endEvent
    event OnHighlightST()
        _highlightToggle(20)
    endEvent
endState
state TOGGLE_22
    event OnSelectST()
        _selectToggle(21)
    endEvent
    event OnDefaultST()
        _defaultToggle(21)
    endEvent
    event OnHighlightST()
        _highlightToggle(21)
    endEvent
endState
state TOGGLE_23
    event OnSelectST()
        _selectToggle(22)
    endEvent
    event OnDefaultST()
        _defaultToggle(22)
    endEvent
    event OnHighlightST()
        _highlightToggle(22)
    endEvent
endState
state TOGGLE_24
    event OnSelectST()
        _selectToggle(23)
    endEvent
    event OnDefaultST()
        _defaultToggle(23)
    endEvent
    event OnHighlightST()
        _highlightToggle(23)
    endEvent
endState
state TOGGLE_25
    event OnSelectST()
        _selectToggle(24)
    endEvent
    event OnDefaultST()
        _defaultToggle(24)
    endEvent
    event OnHighlightST()
        _highlightToggle(24)
    endEvent
endState
state TOGGLE_26
    event OnSelectST()
        _selectToggle(25)
    endEvent
    event OnDefaultST()
        _defaultToggle(25)
    endEvent
    event OnHighlightST()
        _highlightToggle(25)
    endEvent
endState
state TOGGLE_27
    event OnSelectST()
        _selectToggle(26)
    endEvent
    event OnDefaultST()
        _defaultToggle(26)
    endEvent
    event OnHighlightST()
        _highlightToggle(26)
    endEvent
endState
state TOGGLE_28
    event OnSelectST()
        _selectToggle(27)
    endEvent
    event OnDefaultST()
        _defaultToggle(27)
    endEvent
    event OnHighlightST()
        _highlightToggle(27)
    endEvent
endState
state TOGGLE_29
    event OnSelectST()
        _selectToggle(28)
    endEvent
    event OnDefaultST()
        _defaultToggle(28)
    endEvent
    event OnHighlightST()
        _highlightToggle(28)
    endEvent
endState
state TOGGLE_30
    event OnSelectST()
        _selectToggle(29)
    endEvent
    event OnDefaultST()
        _defaultToggle(29)
    endEvent
    event OnHighlightST()
        _highlightToggle(29)
    endEvent
endState
state TOGGLE_31
    event OnSelectST()
        _selectToggle(30)
    endEvent
    event OnDefaultST()
        _defaultToggle(30)
    endEvent
    event OnHighlightST()
        _highlightToggle(30)
    endEvent
endState
state TOGGLE_32
    event OnSelectST()
        _selectToggle(31)
    endEvent
    event OnDefaultST()
        _defaultToggle(31)
    endEvent
    event OnHighlightST()
        _highlightToggle(31)
    endEvent
endState
