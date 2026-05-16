scriptname MTF_MCMQuest extends SKI_ConfigBase

import Debug

; ── Runtime ───────────────────────────────────────────────────────────────────
int selectedCondition = 0

MTF_MainQuest Property MainQuest Auto

; ── Versioning ────────────────────────────────────────────────────────────────
int Function GetVersion()
    return 18
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
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
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
    ModName = "Magic Tattoos Framework"
    Pages = new String[5]
    Pages[0] = "General"
    Pages[1] = "Conditions"
    Pages[2] = "Plugins"
    Pages[3] = "Menu Options"
    Pages[4] = "Presets"
    _ensureMainQuest()
endEvent

function _ensureMainQuest()
    if MainQuest == None
        Quest q = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as Quest
        MainQuest = q as MTF_MainQuest
    endif
    if MainQuest != None
        MainQuest.EnsureArrays()
    endif
endFunction

event OnVersionUpdate(int Version)
    if MainQuest == None
        return
    endif
    ; SkyUI's CurrentVersion isn't persisting reliably in this install, so
    ; OnVersionUpdate would fire on every page reset and re-run the wipe
    ; below. Guard with a persistent counter on MainQuest (which IS persistent
    ; via StartGameEnabled).
    ;
    ; v0.0.27 collapsed the 11-block pre-release migration ladder into a
    ; single fresh-init wipe. Anyone upgrading from an older pre-release
    ; (ml<18) gets all arrays reallocated and all defaults applied. Once we
    ; ship, the next migration must be a non-destructive ml<19 block added
    ; below this one.
    int ml = MainQuest._migrationLevel
    if ml >= 18
        return
    endif

    ; Pages: 5-page layout (also set by OnConfigInit; redundant here for the
    ; sake of upgraders whose Pages array predates the current shape).
    Pages = new String[5]
    Pages[0] = "General"
    Pages[1] = "Conditions"
    Pages[2] = "Plugins"
    Pages[3] = "Menu Options"
    Pages[4] = "Presets"

    ; Allocate every state array. EnsureArrays handles fresh installs; this
    ; block additionally handles upgraders whose existing script instance
    ; never re-fires OnInit and therefore never allocates new-in-vX arrays.
    MainQuest.condPluginId          = new string[8]
    MainQuest.condParam             = new int[8]
    MainQuest.condPackId            = new string[8]
    MainQuest.condEntryId           = new string[8]
    MainQuest.condLayerTint         = new int[32]
    MainQuest.condLayerEmissive     = new int[32]
    MainQuest.condLayerEmissiveMult = new float[32]
    MainQuest.condLayerAlpha        = new int[32]
    MainQuest.effectKey             = new string[32]
    MainQuest.effectParam           = new int[32]
    MainQuest.effectParam2          = new int[32]
    MainQuest.cooldownMin           = new int[8]
    MainQuest.cooldownMode          = new int[8]
    MainQuest.cooldownUntilGT       = new float[8]
    MainQuest.disabledItems         = new string[64]

    MainQuest.ModActive          = false
    MainQuest.updateInterval     = 2.0
    MainQuest.OverlaySlot        = 2
    MainQuest.CurrentOverlaySlot = 2

    ; Default slot (idx 0): seed with the first available pack + first entry.
    ; No content is bundled with the framework — if no packs are installed,
    ; the slot is left empty and the user can pick later (or run effects-only
    ; via the "(no texture)" entry option).
    MainQuest.LoadVisualCatalogs()
    string defPack = ""
    string defEntry = ""
    if MainQuest.GetVisualPackCount() > 0
        defPack = MainQuest.GetVisualPackIdAt(0)
        if MainQuest.GetPackEntryCount(defPack) > 0
            defEntry = MainQuest.GetPackEntryIdAt(defPack, 0)
        endif
    endif
    MainQuest.condPackId[0]  = defPack
    MainQuest.condEntryId[0] = defEntry

    ; Per-layer defaults: layer 0 = opaque white mark, no glow.
    ;                     layer 1 = warm glow (off by default — emissiveMult=0
    ;                                          on Default, 2.5 on condition slots).
    int s = 0
    while s < 8
        if s > 0
            ; slots 1-7 inherit Default's pack+entry until user overrides
            MainQuest.condPackId[s]  = ""
            MainQuest.condEntryId[s] = ""
        endif

        ; Layer 0 (base mark)
        int li0 = s * 4 + 0
        MainQuest.condLayerTint[li0]         = 16777215   ; white
        MainQuest.condLayerEmissive[li0]     = 16777215
        MainQuest.condLayerEmissiveMult[li0] = 0.0
        MainQuest.condLayerAlpha[li0]        = 100

        ; Layer 1 (glow halo)
        int li1 = s * 4 + 1
        MainQuest.condLayerTint[li1]         = 16777215
        MainQuest.condLayerEmissive[li1]     = 11337843   ; warm amber
        MainQuest.condLayerEmissiveMult[li1] = 0.0
        MainQuest.condLayerAlpha[li1]        = 80
        if s > 0
            MainQuest.condLayerEmissiveMult[li1] = 2.5
        endif

        ; Layers 2-3 fully opaque-transparent so trailing-slot clear is moot
        int Li = 2
        while Li < 4
            int liN = s * 4 + Li
            MainQuest.condLayerTint[liN]         = 16777215
            MainQuest.condLayerEmissive[liN]     = 16777215
            MainQuest.condLayerEmissiveMult[liN] = 0.0
            MainQuest.condLayerAlpha[liN]        = 100
            Li += 1
        endwhile

        s += 1
    endwhile

    MainQuest._migrationLevel = 18
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
    elseif page == "Presets"
        drawPresetsPage()
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
        MTF_Plugin p = MainQuest.GetPluginAt(i)
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
            MTF_Plugin p = MainQuest.GetPluginAt(i)
            if p != None
                int cn = p.GetConditionCount()
                if slot < seen + cn
                    int local = slot - seen
                    _scratchToggleKey   = p.GetPluginId() + ":" + p.GetConditionId(local)
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
        MTF_Plugin p2 = MainQuest.GetPluginAt(j)
        if p2 != None
            int en = p2.GetEffectCount()
            if eslot < seenE + en
                int localE = eslot - seenE
                _scratchToggleKey   = p2.GetPluginId() + ":" + p2.GetEffectId(localE)
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
        MTF_Plugin p = MainQuest.GetPluginAt(i)
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
    AddSliderOptionST("SLOT_OVERLAY_SLOT",   "Overlay slot",          MainQuest.OverlaySlot)
    AddTextOptionST("GEN_RELOAD_VISUALS", "Reload visual packs", "(" + MainQuest.GetVisualPackCount() + " loaded)")
    AddToggleOptionST("GEN_DEBUG_MODE",      "Debug mode",             MainQuest.DebugMode)
endFunction

function drawPluginsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    int settingSlot = 0

    AddHeaderOption("Plugins (" + MainQuest.pluginCount + ", " + MainQuest.GetTotalConditionItemCount() + " conditions, " + MainQuest.GetTotalEffectItemCount() + " effects)")
    int i = 0
    while i < MainQuest.pluginCount
        MTF_Plugin p = MainQuest.GetPluginAt(i)
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
        MTF_Plugin p = MainQuest.GetPluginAt(i)
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
        MTF_Plugin p2 = MainQuest.GetPluginAt(j)
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
    MTF_Plugin p = f as MTF_Plugin
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
    MTF_Plugin p = f as MTF_Plugin
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
    MTF_Plugin p = f as MTF_Plugin
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
    MTF_Plugin p = f as MTF_Plugin
    SetInfoText(p.GetSettingInfo(_scratchItemIdx))
EndFunction

function drawConditionsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)

    int idx = selectedCondition

    ; ── LEFT COLUMN: slot config + cooldown + effects ────────────────────────
    AddMenuOptionST("COND_SELECTOR", "Configure slot", _slotLabel(selectedCondition))

    if idx == 0
        AddHeaderOption("Default slot")
    else
        string key = MainQuest.condPluginId[idx]
        MTF_Plugin p = None
        int itemIdx = -1
        if key != ""
            p = MainQuest.ResolvePluginByKey(key)
            if p != None
                itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            endif
        endif

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

        int cdMin = MainQuest.cooldownMin[idx]
        AddHeaderOption("Cooldown")
        AddMenuOptionST("SLOT_CD_MODE",     "Mode",    _cooldownModeLabel(MainQuest.cooldownMode[idx]))
        AddSliderOptionST("SLOT_CD_HOURS",   "Hours",   cdMin / 60)
        AddSliderOptionST("SLOT_CD_MINUTES", "Minutes", cdMin % 60)
    endif

    AddHeaderOption("Effects")
    _drawEffectRow(idx, 0, "SLOT_EFFECT_1_TYPE", "SLOT_EFFECT_1_PARAM", "SLOT_EFFECT_1_P2")
    _drawEffectRow(idx, 1, "SLOT_EFFECT_2_TYPE", "SLOT_EFFECT_2_PARAM", "SLOT_EFFECT_2_P2")
    _drawEffectRow(idx, 2, "SLOT_EFFECT_3_TYPE", "SLOT_EFFECT_3_PARAM", "SLOT_EFFECT_3_P2")
    _drawEffectRow(idx, 3, "SLOT_EFFECT_4_TYPE", "SLOT_EFFECT_4_PARAM", "SLOT_EFFECT_4_P2")

    ; ── RIGHT COLUMN: Visuals block (pack + texture) then per-layer sliders ──
    SetCursorPosition(1)

    AddHeaderOption("Visuals")
    AddMenuOptionST("SLOT_PACK_PICK",     "Visual pack", _slotPackLabel(idx))
    AddMenuOptionST("SLOT_VISUAL_ENTRY",  "Texture",     _slotEntryLabel(idx))

    ; Determine layer count from the resolved (slot or inherited) entry.
    ; If the slot is in "(no texture)" mode (resolved entry is empty) we hide
    ; layer sliders entirely — there's nothing to tint. If pack/entry are
    ; merely unresolved (no packs installed), show all MAX_LAYERS rows so
    ; the user can still pre-tweak.
    string resPack  = MainQuest.ResolveSlotPackId(idx)
    string resEntry = MainQuest.ResolveSlotEntryId(idx)
    bool noTexture = (MainQuest.condEntryId[idx] == "<none>") || (idx == 0 && MainQuest.condEntryId[0] == "")
    int layerN = MTF_MainQuest.MAX_LAYERS_PER_SLOT()
    if noTexture
        layerN = 0
    elseif resPack != "" && resEntry != ""
        int lc = MainQuest.GetEntryLayerCount(resPack, resEntry)
        if lc > 0 && lc < layerN
            layerN = lc
        endif
    endif
    ; Per-layer visuals always read from the LAYOUT slot (idx), not the
    ; inheritance target — letting a condition slot keep its own colors
    ; even when it inherits pack+entry.
    int L = 0
    while L < layerN
        int li = idx * MTF_MainQuest.MAX_LAYERS_PER_SLOT() + L
        AddHeaderOption("Layer " + L)
        AddColorOptionST("SLOT_L" + L + "_TINT",      "Tint",              MainQuest.condLayerTint[li])
        AddColorOptionST("SLOT_L" + L + "_EMISSIVE",  "Emission color",    MainQuest.condLayerEmissive[li])
        AddSliderOptionST("SLOT_L" + L + "_EM_MULT",  "Emission strength", MainQuest.condLayerEmissiveMult[li], "{1}")
        AddSliderOptionST("SLOT_L" + L + "_ALPHA",    "Opacity",           MainQuest.condLayerAlpha[li], "{0}%")
        L += 1
    endwhile
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

state GEN_RELOAD_VISUALS
    event OnSelectST()
        MainQuest.ForceReloadVisualCatalogs()
        SetTextOptionValueST("(" + MainQuest.GetVisualPackCount() + " loaded)")
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Re-scan Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/ for pack JSONs.")
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
        ; HYPOTHESIS: holding local array references blocks further `new
        ; string[N]` allocations in this state event frame. So allocate
        ; opts FIRST (no locals alive), then do cross-script reads inline
        ; in the loop without snapshotting MainQuest's arrays locally.
        string curKey = MainQuest.condPluginId[selectedCondition]
        MainQuest.BuildVisibleConditionMenu(curKey)
        int n = MainQuest.menuCount
        int sz = n + 1
        if sz > 127
            sz = 127
        endif
        string[] opts = _newOpts(sz)
        opts[0] = "Not set"
        int curIdx = 0
        int i = 0
        while i < n && (i + 1) < sz
            opts[i + 1] = MainQuest.menuLabels[i]
            if MainQuest.menuKeys[i] == curKey
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
        string newKey = ""
        if index > 0
            string curKey = MainQuest.condPluginId[slot]
            MainQuest.BuildVisibleConditionMenu(curKey)
            string[] keys = MainQuest.menuKeys
            int n = MainQuest.menuCount
            if keys != None && (index - 1) < n
                newKey = keys[index - 1]
            endif
        endif
        MainQuest.SetCondPluginId(slot, newKey)
        if newKey == ""
            MainQuest.SetCondParam(slot, 0)
        else
            MTF_Plugin p = MainQuest.ResolvePluginByKey(newKey)
            int itemIdx = -1
            if p != None
                itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(newKey))
            endif
            if itemIdx >= 0
                MainQuest.SetCondParam(slot, p.GetConditionParamDefault(itemIdx))
            else
                MainQuest.SetCondParam(slot, 0)
            endif
        endif
        SetMenuOptionValueST(_condTypeLabel(newKey))
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPluginId(selectedCondition, "")
        MainQuest.SetCondParam(selectedCondition, 0)
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
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
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
        MainQuest.SetCondParam(selectedCondition, value as int)
        SetSliderOptionValueST(value as int)
    endEvent
    event OnDefaultST()
        string key = MainQuest.condPluginId[selectedCondition]
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        int defVal = 0
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                defVal = p.GetConditionParamDefault(itemIdx)
            endif
        endif
        MainQuest.SetCondParam(selectedCondition, defVal)
        SetSliderOptionValueST(defVal)
    endEvent
    event OnHighlightST()
        string key = MainQuest.condPluginId[selectedCondition]
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
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

; ── Per-slot entry picker (texture choice within the active visual pack) ────
string Function _slotEntryLabel(int slot)
    string entryId = MainQuest.condEntryId[slot]
    if entryId == "<none>"
        return "(no texture)"
    endif
    if entryId == ""
        if slot == 0
            return "(no texture)"
        endif
        return "(inherit Default)"
    endif
    string pid = MainQuest.ResolveSlotPackId(slot)
    if pid == ""
        return entryId
    endif
    string lbl = ""
    int n = MainQuest.GetPackEntryCount(pid)
    int i = 0
    while i < n
        if MainQuest.GetPackEntryIdAt(pid, i) == entryId
            lbl = MainQuest.GetPackEntryLabelAt(pid, i)
            i = n
        else
            i += 1
        endif
    endwhile
    if lbl == ""
        return entryId
    endif
    return lbl
EndFunction

string Function _slotPackLabel(int slot)
    string pid = MainQuest.condPackId[slot]
    if pid == ""
        if slot == 0
            if MainQuest.GetVisualPackCount() == 0
                return "(no packs found)"
            endif
            return "(not set)"
        endif
        return "(inherit Default)"
    endif
    int idx = MainQuest.FindVisualPackIndex(pid)
    if idx < 0
        return "Unknown (" + pid + ")"
    endif
    return MainQuest.GetVisualPackLabelAt(idx)
EndFunction

state SLOT_PACK_PICK
    event OnMenuOpenST()
        int n = MainQuest.GetVisualPackCount()
        bool allowInherit = (selectedCondition > 0)
        int total = n
        if allowInherit
            total += 1
        endif
        if total <= 0
            string[] empty = new string[1]
            empty[0] = "(no packs found)"
            SetMenuDialogStartIndex(0)
            SetMenuDialogDefaultIndex(0)
            SetMenuDialogOptions(empty)
            return
        endif
        string[] opts = _newOpts(total)
        int sel = 0
        int writeIdx = 0
        if allowInherit
            opts[0] = "(inherit Default)"
            if MainQuest.condPackId[selectedCondition] == ""
                sel = 0
            endif
            writeIdx = 1
        endif
        int i = 0
        while i < n
            opts[writeIdx] = MainQuest.GetVisualPackLabelAt(i)
            if MainQuest.GetVisualPackIdAt(i) == MainQuest.condPackId[selectedCondition]
                sel = writeIdx
            endif
            writeIdx += 1
            i += 1
        endwhile
        SetMenuDialogStartIndex(sel)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        bool allowInherit = (selectedCondition > 0)
        if index < 0
            return
        endif
        string newPack = ""
        if !(allowInherit && index == 0)
            int packIdx = index
            if allowInherit
                packIdx -= 1
            endif
            if packIdx >= 0 && packIdx < MainQuest.GetVisualPackCount()
                newPack = MainQuest.GetVisualPackIdAt(packIdx)
            endif
        endif
        ; Switching packs invalidates the entry pick — reset to first entry
        ; of the new pack (or "" if inheriting).
        if newPack != MainQuest.condPackId[selectedCondition]
            MainQuest.condPackId[selectedCondition] = newPack
            if newPack == ""
                MainQuest.condEntryId[selectedCondition] = ""
            elseif MainQuest.GetPackEntryCount(newPack) > 0
                MainQuest.condEntryId[selectedCondition] = MainQuest.GetPackEntryIdAt(newPack, 0)
            else
                MainQuest.condEntryId[selectedCondition] = ""
            endif
        endif
        SetMenuOptionValueST(_slotPackLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnDefaultST()
        if selectedCondition == 0
            if MainQuest.GetVisualPackCount() > 0
                MainQuest.condPackId[0] = MainQuest.GetVisualPackIdAt(0)
            else
                MainQuest.condPackId[0] = ""
            endif
        else
            MainQuest.condPackId[selectedCondition] = ""
            MainQuest.condEntryId[selectedCondition] = ""
        endif
        SetMenuOptionValueST(_slotPackLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnHighlightST()
        if selectedCondition == 0
            SetInfoText("Visual pack used by the Default slot. Packs are JSON files under Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/.")
        else
            SetInfoText("Visual pack for this condition slot. (inherit Default) falls back to the Default slot's pack + texture.")
        endif
    endEvent
endState

state SLOT_VISUAL_ENTRY
    event OnMenuOpenST()
        string pid = MainQuest.ResolveSlotPackId(selectedCondition)
        int n = 0
        if pid != ""
            n = MainQuest.GetPackEntryCount(pid)
        endif
        ; Condition slots (1-7) get a leading "(inherit Default)" option ONLY
        ; when they also inherit the pack — picking a different pack means
        ; the slot has its own (pack, entry) and entry inheritance is moot.
        ; All slots get a "(no texture)" option (effects-only, no overlay).
        bool allowInherit = (selectedCondition > 0) && (MainQuest.condPackId[selectedCondition] == "")
        int total = n + 1   ; +1 for "(no texture)"
        if allowInherit
            total += 1
        endif
        string[] opts = _newOpts(total)
        int sel = 0
        int writeIdx = 0
        string curEntry = MainQuest.condEntryId[selectedCondition]
        if allowInherit
            opts[writeIdx] = "(inherit Default)"
            if curEntry == ""
                sel = writeIdx
            endif
            writeIdx += 1
        endif
        ; "(no texture)" — for slot 0 represented as "" (no inherit possible),
        ; for slots 1-7 represented as "<none>" so we can distinguish from inherit.
        opts[writeIdx] = "(no texture)"
        if selectedCondition == 0 && curEntry == ""
            sel = writeIdx
        elseif selectedCondition > 0 && curEntry == "<none>"
            sel = writeIdx
        endif
        writeIdx += 1
        int i = 0
        while i < n
            opts[writeIdx] = MainQuest.GetPackEntryLabelAt(pid, i)
            if MainQuest.GetPackEntryIdAt(pid, i) == curEntry
                sel = writeIdx
            endif
            writeIdx += 1
            i += 1
        endwhile
        SetMenuDialogStartIndex(sel)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        string pid = MainQuest.ResolveSlotPackId(selectedCondition)
        bool allowInherit = (selectedCondition > 0) && (MainQuest.condPackId[selectedCondition] == "")
        if index < 0
            return
        endif
        int cursor = 0
        if allowInherit
            if index == cursor
                MainQuest.condEntryId[selectedCondition] = ""
                SetMenuOptionValueST(_slotEntryLabel(selectedCondition))
                MainQuest.setRedraw()
                ForcePageReset()
                return
            endif
            cursor += 1
        endif
        if index == cursor
            ; "(no texture)" — explicit empty for slot 0, sentinel for 1-7.
            if selectedCondition == 0
                MainQuest.condEntryId[0] = ""
            else
                MainQuest.condEntryId[selectedCondition] = "<none>"
            endif
            SetMenuOptionValueST(_slotEntryLabel(selectedCondition))
            MainQuest.setRedraw()
            ForcePageReset()
            return
        endif
        cursor += 1
        int entryIdx = index - cursor
        if entryIdx >= 0 && pid != "" && entryIdx < MainQuest.GetPackEntryCount(pid)
            MainQuest.condEntryId[selectedCondition] = MainQuest.GetPackEntryIdAt(pid, entryIdx)
        endif
        SetMenuOptionValueST(_slotEntryLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnDefaultST()
        if selectedCondition == 0
            string pid = MainQuest.condPackId[0]
            if pid != "" && MainQuest.GetPackEntryCount(pid) > 0
                MainQuest.condEntryId[0] = MainQuest.GetPackEntryIdAt(pid, 0)
            else
                MainQuest.condEntryId[0] = ""
            endif
        else
            MainQuest.condEntryId[selectedCondition] = ""
        endif
        SetMenuOptionValueST(_slotEntryLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnHighlightST()
        if selectedCondition == 0
            SetInfoText("Texture used by the Default slot. Pick (no texture) for effects-only with no overlay.")
        else
            SetInfoText("Texture used by this condition slot. (inherit Default) falls back to Default's pick; (no texture) renders nothing and runs effects only.")
        endif
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
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
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

Function _drawEffectRow(int slot, int effectIdx, string typeStateId, string paramStateId, string param2StateId)
    AddMenuOptionST(typeStateId, "Effect " + (effectIdx + 1), _effectTypeLabel(effectIdx))
    string key = MainQuest.GetSlotEffectKey(slot, effectIdx)
    if key == ""
        return
    endif
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
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
    string param2Label = p.GetEffectParam2Label(itemIdx)
    if param2Label != ""
        AddSliderOptionST(param2StateId, "  " + param2Label, MainQuest.GetSlotEffectParam2(slot, effectIdx), p.GetEffectParam2Format(itemIdx))
    endif
EndFunction

Function _openEffectTypeMenu(int effectIdx)
    string curKey = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MainQuest.BuildVisibleEffectMenu(curKey)
    string[] keys = MainQuest.menuKeys
    string[] labels = MainQuest.menuLabels
    int n = MainQuest.menuCount
    int sz = n + 1
    if sz > 127
        sz = 127
    endif
    string[] opts = _newOpts(sz)
    opts[0] = "Not set"
    int curSel = 0
    int i = 0
    while i < n && (i + 1) < sz
        opts[i + 1] = labels[i]
        if keys[i] == curKey
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
    int defParam2 = 0
    if index > 0
        ; Rebuild cache fresh in this frame (see SLOT_COND_TYPE.OnMenuAcceptST).
        string curKey = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
        MainQuest.BuildVisibleEffectMenu(curKey)
        string[] keys = MainQuest.menuKeys
        int n = MainQuest.menuCount
        if keys != None && (index - 1) < n
            newKey = keys[index - 1]
        endif
        MTF_Plugin p = MainQuest.ResolvePluginByKey(newKey)
        if p != None
            int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(newKey))
            if itemIdx >= 0
                defParam = p.GetEffectParamDefault(itemIdx)
                defParam2 = p.GetEffectParam2Default(itemIdx)
            endif
        endif
    endif
    MainQuest.SetSlotEffectFull(selectedCondition, effectIdx, newKey, defParam, defParam2)
EndFunction

Function _openEffectParam(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
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
    int step = p.GetEffectParamStep(itemIdx)
    if step < 1
        step = 1
    endif
    SetSliderDialogInterval(step)
EndFunction

Function _acceptEffectParam(int effectIdx, float value)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MainQuest.SetSlotEffect(selectedCondition, effectIdx, key, value as int)
    SetSliderOptionValueST(value as int)
EndFunction

Function _defaultEffectParam(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
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
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p != None
        int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            SetInfoText(p.GetEffectParamLabel(itemIdx))
            return
        endif
    endif
    SetInfoText("Effect parameter.")
EndFunction

; ── Per-effect param2 helpers ───────────────────────────────────────────────
Function _openEffectParam2(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    SetSliderDialogStartValue(MainQuest.GetSlotEffectParam2(selectedCondition, effectIdx))
    SetSliderDialogDefaultValue(p.GetEffectParam2Default(itemIdx))
    SetSliderDialogRange(p.GetEffectParam2Min(itemIdx), p.GetEffectParam2Max(itemIdx))
    int step = p.GetEffectParam2Step(itemIdx)
    if step < 1
        step = 1
    endif
    SetSliderDialogInterval(step)
EndFunction

Function _acceptEffectParam2(int effectIdx, float value)
    MainQuest.SetSlotEffectParam2(selectedCondition, effectIdx, value as int)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    string fmt = "{0}"
    if p != None
        int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            fmt = p.GetEffectParam2Format(itemIdx)
        endif
    endif
    SetSliderOptionValueST(value as int, fmt)
EndFunction

Function _defaultEffectParam2(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    int defVal = 0
    string fmt = "{0}"
    if p != None
        int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            defVal = p.GetEffectParam2Default(itemIdx)
            fmt = p.GetEffectParam2Format(itemIdx)
        endif
    endif
    MainQuest.SetSlotEffectParam2(selectedCondition, effectIdx, defVal)
    SetSliderOptionValueST(defVal, fmt)
EndFunction

Function _highlightEffectParam2(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p != None
        int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            SetInfoText(p.GetEffectParam2Label(itemIdx))
            return
        endif
    endif
    SetInfoText("Secondary effect parameter.")
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

; ── Per-effect param2 states (only shown when effect declares param2) ───────
state SLOT_EFFECT_1_P2
    event OnSliderOpenST()
        _openEffectParam2(0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam2(0, value)
    endEvent
    event OnDefaultST()
        _defaultEffectParam2(0)
    endEvent
    event OnHighlightST()
        _highlightEffectParam2(0)
    endEvent
endState

state SLOT_EFFECT_2_P2
    event OnSliderOpenST()
        _openEffectParam2(1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam2(1, value)
    endEvent
    event OnDefaultST()
        _defaultEffectParam2(1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam2(1)
    endEvent
endState

state SLOT_EFFECT_3_P2
    event OnSliderOpenST()
        _openEffectParam2(2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam2(2, value)
    endEvent
    event OnDefaultST()
        _defaultEffectParam2(2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam2(2)
    endEvent
endState

state SLOT_EFFECT_4_P2
    event OnSliderOpenST()
        _openEffectParam2(3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam2(3, value)
    endEvent
    event OnDefaultST()
        _defaultEffectParam2(3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam2(3)
    endEvent
endState

; ── Per-layer visual states (slot * MAX_LAYERS + layer indexing) ─────────────
; Each layer of the picked entry gets its own Tint/Emissive/EmissiveMult/Alpha.
; State blocks below are mechanical wrappers around 4 helper functions that
; compute the backing-array index from selectedCondition and the layer
; constant baked into each state.

int Function _layerArrIdx(int L)
    return selectedCondition * MTF_MainQuest.MAX_LAYERS_PER_SLOT() + L
EndFunction

Function _openLayerTint(int L)
    SetColorDialogStartColor(MainQuest.condLayerTint[_layerArrIdx(L)])
    SetColorDialogDefaultColor(16777215)
EndFunction
Function _acceptLayerTint(int L, int color)
    MainQuest.condLayerTint[_layerArrIdx(L)] = color
    SetColorOptionValueST(color)
    MainQuest.setRedraw()
EndFunction
Function _defaultLayerTint(int L)
    MainQuest.condLayerTint[_layerArrIdx(L)] = 16777215
    SetColorOptionValueST(16777215)
    MainQuest.setRedraw()
EndFunction

Function _openLayerEmissive(int L)
    SetColorDialogStartColor(MainQuest.condLayerEmissive[_layerArrIdx(L)])
    SetColorDialogDefaultColor(16777215)
EndFunction
Function _acceptLayerEmissive(int L, int color)
    MainQuest.condLayerEmissive[_layerArrIdx(L)] = color
    SetColorOptionValueST(color)
    MainQuest.setRedraw()
EndFunction
Function _defaultLayerEmissive(int L)
    MainQuest.condLayerEmissive[_layerArrIdx(L)] = 16777215
    SetColorOptionValueST(16777215)
    MainQuest.setRedraw()
EndFunction

Function _openLayerEmMult(int L)
    SetSliderDialogStartValue(MainQuest.condLayerEmissiveMult[_layerArrIdx(L)])
    SetSliderDialogDefaultValue(0.0)
    SetSliderDialogRange(0.0, 25.0)
    SetSliderDialogInterval(0.5)
EndFunction
Function _acceptLayerEmMult(int L, float value)
    MainQuest.condLayerEmissiveMult[_layerArrIdx(L)] = value
    SetSliderOptionValueST(value, "{1}")
    MainQuest.setRedraw()
EndFunction
Function _defaultLayerEmMult(int L)
    MainQuest.condLayerEmissiveMult[_layerArrIdx(L)] = 0.0
    SetSliderOptionValueST(0.0, "{1}")
    MainQuest.setRedraw()
EndFunction

Function _openLayerAlpha(int L)
    SetSliderDialogStartValue(MainQuest.condLayerAlpha[_layerArrIdx(L)])
    SetSliderDialogDefaultValue(100)
    SetSliderDialogRange(0, 100)
    SetSliderDialogInterval(1)
EndFunction
Function _acceptLayerAlpha(int L, float value)
    MainQuest.condLayerAlpha[_layerArrIdx(L)] = value as int
    SetSliderOptionValueST(value, "{0}%")
    MainQuest.setRedraw()
EndFunction
Function _defaultLayerAlpha(int L)
    MainQuest.condLayerAlpha[_layerArrIdx(L)] = 100
    SetSliderOptionValueST(100, "{0}%")
    MainQuest.setRedraw()
EndFunction

; ── Layer 0 ──────────────────────────────────────────────────────────────────
state SLOT_L0_TINT
    event OnColorOpenST()
        _openLayerTint(0)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerTint(0, color)
    endEvent
    event OnDefaultST()
        _defaultLayerTint(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for layer 0 (typically the base mark texture).")
    endEvent
endState
state SLOT_L0_EMISSIVE
    event OnColorOpenST()
        _openLayerEmissive(0)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerEmissive(0, color)
    endEvent
    event OnDefaultST()
        _defaultLayerEmissive(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Emission (glow) color for layer 0.")
    endEvent
endState
state SLOT_L0_EM_MULT
    event OnSliderOpenST()
        _openLayerEmMult(0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerEmMult(0, value)
    endEvent
    event OnDefaultST()
        _defaultLayerEmMult(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for layer 0. 0 = no glow.")
    endEvent
endState
state SLOT_L0_ALPHA
    event OnSliderOpenST()
        _openLayerAlpha(0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerAlpha(0, value)
    endEvent
    event OnDefaultST()
        _defaultLayerAlpha(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity for layer 0.")
    endEvent
endState

; ── Layer 1 ──────────────────────────────────────────────────────────────────
state SLOT_L1_TINT
    event OnColorOpenST()
        _openLayerTint(1)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerTint(1, color)
    endEvent
    event OnDefaultST()
        _defaultLayerTint(1)
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for layer 1 (typically the glow layer).")
    endEvent
endState
state SLOT_L1_EMISSIVE
    event OnColorOpenST()
        _openLayerEmissive(1)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerEmissive(1, color)
    endEvent
    event OnDefaultST()
        _defaultLayerEmissive(1)
    endEvent
    event OnHighlightST()
        SetInfoText("Emission (glow) color for layer 1.")
    endEvent
endState
state SLOT_L1_EM_MULT
    event OnSliderOpenST()
        _openLayerEmMult(1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerEmMult(1, value)
    endEvent
    event OnDefaultST()
        _defaultLayerEmMult(1)
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for layer 1. 0 = no glow.")
    endEvent
endState
state SLOT_L1_ALPHA
    event OnSliderOpenST()
        _openLayerAlpha(1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerAlpha(1, value)
    endEvent
    event OnDefaultST()
        _defaultLayerAlpha(1)
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity for layer 1.")
    endEvent
endState

; ── Layer 2 ──────────────────────────────────────────────────────────────────
state SLOT_L2_TINT
    event OnColorOpenST()
        _openLayerTint(2)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerTint(2, color)
    endEvent
    event OnDefaultST()
        _defaultLayerTint(2)
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for layer 2.")
    endEvent
endState
state SLOT_L2_EMISSIVE
    event OnColorOpenST()
        _openLayerEmissive(2)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerEmissive(2, color)
    endEvent
    event OnDefaultST()
        _defaultLayerEmissive(2)
    endEvent
    event OnHighlightST()
        SetInfoText("Emission color for layer 2.")
    endEvent
endState
state SLOT_L2_EM_MULT
    event OnSliderOpenST()
        _openLayerEmMult(2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerEmMult(2, value)
    endEvent
    event OnDefaultST()
        _defaultLayerEmMult(2)
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for layer 2.")
    endEvent
endState
state SLOT_L2_ALPHA
    event OnSliderOpenST()
        _openLayerAlpha(2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerAlpha(2, value)
    endEvent
    event OnDefaultST()
        _defaultLayerAlpha(2)
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity for layer 2.")
    endEvent
endState

; ── Layer 3 ──────────────────────────────────────────────────────────────────
state SLOT_L3_TINT
    event OnColorOpenST()
        _openLayerTint(3)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerTint(3, color)
    endEvent
    event OnDefaultST()
        _defaultLayerTint(3)
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for layer 3.")
    endEvent
endState
state SLOT_L3_EMISSIVE
    event OnColorOpenST()
        _openLayerEmissive(3)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerEmissive(3, color)
    endEvent
    event OnDefaultST()
        _defaultLayerEmissive(3)
    endEvent
    event OnHighlightST()
        SetInfoText("Emission color for layer 3.")
    endEvent
endState
state SLOT_L3_EM_MULT
    event OnSliderOpenST()
        _openLayerEmMult(3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerEmMult(3, value)
    endEvent
    event OnDefaultST()
        _defaultLayerEmMult(3)
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for layer 3.")
    endEvent
endState
state SLOT_L3_ALPHA
    event OnSliderOpenST()
        _openLayerAlpha(3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerAlpha(3, value)
    endEvent
    event OnDefaultST()
        _defaultLayerAlpha(3)
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity for layer 3.")
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
{Returns an array sized n (max 100). Papyrus needs literal array sizes;
 this dispatcher picks the matching literal via a single if-elseif chain.
 Kept monolithic and under 40 branches because (a) trampolining through a
 sub-function caused  to return length-0 arrays on this VM
 build, and (b) chains over ~40 branches do the same.}
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
    elseIf n == 10
        return new string[10]
    elseIf n == 11
        return new string[11]
    elseIf n == 12
        return new string[12]
    elseIf n == 13
        return new string[13]
    elseIf n == 14
        return new string[14]
    elseIf n == 15
        return new string[15]
    elseIf n == 16
        return new string[16]
    elseIf n == 17
        return new string[17]
    elseIf n == 18
        return new string[18]
    elseIf n == 19
        return new string[19]
    elseIf n == 20
        return new string[20]
    elseIf n == 21
        return new string[21]
    elseIf n == 22
        return new string[22]
    elseIf n == 23
        return new string[23]
    elseIf n == 24
        return new string[24]
    elseIf n == 25
        return new string[25]
    elseIf n == 26
        return new string[26]
    elseIf n == 27
        return new string[27]
    elseIf n == 28
        return new string[28]
    elseIf n == 29
        return new string[29]
    elseIf n == 30
        return new string[30]
    elseIf n == 31
        return new string[31]
    elseIf n == 32
        return new string[32]
    elseIf n == 33
        return new string[33]
    elseIf n == 34
        return new string[34]
    elseIf n == 35
        return new string[35]
    elseIf n == 36
        return new string[36]
    elseIf n == 37
        return new string[37]
    elseIf n == 38
        return new string[38]
    elseIf n == 39
        return new string[39]
    elseIf n == 40
        return new string[40]
    elseIf n == 41
        return new string[41]
    elseIf n == 42
        return new string[42]
    elseIf n == 43
        return new string[43]
    elseIf n == 44
        return new string[44]
    elseIf n == 45
        return new string[45]
    elseIf n == 46
        return new string[46]
    elseIf n == 47
        return new string[47]
    elseIf n == 48
        return new string[48]
    elseIf n == 49
        return new string[49]
    elseIf n == 50
        return new string[50]
    elseIf n == 51
        return new string[51]
    elseIf n == 52
        return new string[52]
    elseIf n == 53
        return new string[53]
    elseIf n == 54
        return new string[54]
    elseIf n == 55
        return new string[55]
    elseIf n == 56
        return new string[56]
    elseIf n == 57
        return new string[57]
    elseIf n == 58
        return new string[58]
    elseIf n == 59
        return new string[59]
    elseIf n == 60
        return new string[60]
    elseIf n == 61
        return new string[61]
    elseIf n == 62
        return new string[62]
    elseIf n == 63
        return new string[63]
    elseIf n == 64
        return new string[64]
    elseIf n == 65
        return new string[65]
    elseIf n == 66
        return new string[66]
    elseIf n == 67
        return new string[67]
    elseIf n == 68
        return new string[68]
    elseIf n == 69
        return new string[69]
    elseIf n == 70
        return new string[70]
    elseIf n == 71
        return new string[71]
    elseIf n == 72
        return new string[72]
    elseIf n == 73
        return new string[73]
    elseIf n == 74
        return new string[74]
    elseIf n == 75
        return new string[75]
    elseIf n == 76
        return new string[76]
    elseIf n == 77
        return new string[77]
    elseIf n == 78
        return new string[78]
    elseIf n == 79
        return new string[79]
    elseIf n == 80
        return new string[80]
    elseIf n == 81
        return new string[81]
    elseIf n == 82
        return new string[82]
    elseIf n == 83
        return new string[83]
    elseIf n == 84
        return new string[84]
    elseIf n == 85
        return new string[85]
    elseIf n == 86
        return new string[86]
    elseIf n == 87
        return new string[87]
    elseIf n == 88
        return new string[88]
    elseIf n == 89
        return new string[89]
    elseIf n == 90
        return new string[90]
    elseIf n == 91
        return new string[91]
    elseIf n == 92
        return new string[92]
    elseIf n == 93
        return new string[93]
    elseIf n == 94
        return new string[94]
    elseIf n == 95
        return new string[95]
    elseIf n == 96
        return new string[96]
    elseIf n == 97
        return new string[97]
    elseIf n == 98
        return new string[98]
    elseIf n == 99
        return new string[99]
    elseIf n == 100
        return new string[100]
    elseIf n == 101
        return new string[101]
    elseIf n == 102
        return new string[102]
    elseIf n == 103
        return new string[103]
    elseIf n == 104
        return new string[104]
    elseIf n == 105
        return new string[105]
    elseIf n == 106
        return new string[106]
    elseIf n == 107
        return new string[107]
    elseIf n == 108
        return new string[108]
    elseIf n == 109
        return new string[109]
    elseIf n == 110
        return new string[110]
    elseIf n == 111
        return new string[111]
    elseIf n == 112
        return new string[112]
    elseIf n == 113
        return new string[113]
    elseIf n == 114
        return new string[114]
    elseIf n == 115
        return new string[115]
    elseIf n == 116
        return new string[116]
    elseIf n == 117
        return new string[117]
    elseIf n == 118
        return new string[118]
    elseIf n == 119
        return new string[119]
    elseIf n == 120
        return new string[120]
    elseIf n == 121
        return new string[121]
    elseIf n == 122
        return new string[122]
    elseIf n == 123
        return new string[123]
    elseIf n == 124
        return new string[124]
    elseIf n == 125
        return new string[125]
    elseIf n == 126
        return new string[126]
    elseIf n == 127
        return new string[127]
    endif
    return new string[127]
EndFunction



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

; ── Presets page ─────────────────────────────────────────────────────────────
; A single MenuOption lists the saved presets; the user picks one with the
; dropdown, then clicks Load or Delete. Save creates a new preset from the
; current config. JSON files at
;   Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/<name>.json

string[] _scratchPresetNames
int      _scratchPresetCount = 0
int      _selectedPresetIdx = -1

function _refreshPresetNames()
    _scratchPresetNames = MainQuest.ListPresets()
    _scratchPresetCount = MainQuest.ListPresetsCount()
    if _scratchPresetCount == 0
        _selectedPresetIdx = -1
        return
    endif
    if _selectedPresetIdx < 0 || _selectedPresetIdx >= _scratchPresetCount
        _selectedPresetIdx = 0
    endif
endFunction

string function _currentPresetLabel()
    if _scratchPresetCount == 0 || _selectedPresetIdx < 0 || _selectedPresetIdx >= _scratchPresetCount
        return "(none)"
    endif
    return MainQuest.GetPresetDisplayName(_scratchPresetNames[_selectedPresetIdx])
endFunction

function drawPresetsPage()
    SetCursorFillMode(LEFT_TO_RIGHT)
    _refreshPresetNames()

    AddHeaderOption("Save")
    AddInputOptionST("PRESET_SAVE_AS", "Save current as...", "(type a name)")

    AddHeaderOption("Load / Delete")
    AddMenuOptionST("PRESET_PICK", "Selected preset", _currentPresetLabel())
    int loadFlag = OPTION_FLAG_NONE
    int delFlag  = OPTION_FLAG_NONE
    if _scratchPresetCount == 0 || _selectedPresetIdx < 0
        loadFlag = OPTION_FLAG_DISABLED
        delFlag  = OPTION_FLAG_DISABLED
    endif
    AddTextOptionST("PRESET_LOAD", "Load selected",   "", loadFlag)
    AddTextOptionST("PRESET_DEL",  "Delete selected", "", delFlag)
endFunction

state PRESET_SAVE_AS
    event OnInputOpenST()
        SetInputDialogStartText("")
    endEvent
    event OnInputAcceptST(string a_input)
        if a_input == ""
            return
        endif
        if MainQuest.SavePreset(a_input)
            Debug.Notification("MTF: saved preset '" + a_input + "'")
            ForcePageReset()
        else
            Debug.Notification("MTF: invalid preset name")
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Type a name (letters/digits/_/-, max 32). Saves to Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/<name>.json.")
    endEvent
endState

state PRESET_PICK
    event OnMenuOpenST()
        if _scratchPresetCount == 0
            string[] empty = new string[1]
            empty[0] = "(no presets)"
            SetMenuDialogOptions(empty)
            SetMenuDialogStartIndex(0)
            return
        endif
        string[] disp = new string[64]
        int i = 0
        while i < _scratchPresetCount
            disp[i] = MainQuest.GetPresetDisplayName(_scratchPresetNames[i])
            i += 1
        endwhile
        ; Note: disp has empty strings beyond _scratchPresetCount but SkyUI
        ; ignores trailing empties in the dropdown.
        SetMenuDialogOptions(disp)
        int si = _selectedPresetIdx
        if si < 0
            si = 0
        endif
        SetMenuDialogStartIndex(si)
        SetMenuDialogDefaultIndex(0)
    endEvent
    event OnMenuAcceptST(int a_index)
        if _scratchPresetCount == 0 || a_index < 0 || a_index >= _scratchPresetCount
            return
        endif
        _selectedPresetIdx = a_index
        SetMenuOptionValueST(_currentPresetLabel())
    endEvent
    event OnHighlightST()
        SetInfoText("Pick a preset, then use Load or Delete below.")
    endEvent
endState

state PRESET_LOAD
    event OnSelectST()
        if _selectedPresetIdx < 0 || _selectedPresetIdx >= _scratchPresetCount
            return
        endif
        string nm = _scratchPresetNames[_selectedPresetIdx]
        if MainQuest.LoadPreset(nm)
            Debug.Notification("MTF: loaded preset '" + MainQuest.GetPresetDisplayName(nm) + "'")
            ForcePageReset()
        else
            Debug.Notification("MTF: load failed")
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Apply the selected preset to all slots + plugin settings.")
    endEvent
endState

state PRESET_DEL
    event OnSelectST()
        if _selectedPresetIdx < 0 || _selectedPresetIdx >= _scratchPresetCount
            return
        endif
        string nm = _scratchPresetNames[_selectedPresetIdx]
        if MainQuest.DeletePreset(nm)
            Debug.Notification("MTF: deleted preset '" + MainQuest.GetPresetDisplayName(nm) + "'")
            _selectedPresetIdx = -1
            ForcePageReset()
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Remove the selected preset.")
    endEvent
endState
