scriptname MTF_MCMQuest extends SKI_ConfigBase

import Debug

; ── Runtime ───────────────────────────────────────────────────────────────────
int selectedCondition = 0

MTF_MainQuest Property MainQuest Auto

; ── Versioning ────────────────────────────────────────────────────────────────
int Function GetVersion()
    return 23
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
    Pages[1] = "Preset editor"
    Pages[2] = "Subjects"
    Pages[3] = "Plugins"
    Pages[4] = "Menu Options"
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
    ; single fresh-init wipe. v0.0.29 bumped to ml=19 so the Pages array gets
    ; rewritten (Presets folded into General). Anyone upgrading from an older
    ; pre-release (ml<19) gets all arrays reallocated and all defaults
    ; applied. Once we ship, the next migration must be a non-destructive
    ; ml<20 block added below this one.
    int ml = MainQuest._migrationLevel
    if ml >= 36
        return
    endif
    ; v0.1.3 refactor (ml=36): Flash on Hit moved from sibling-to-Pulse
    ; (per-slot `mtf.cond.flash.*` StorageUtil keys + dedicated MCM block)
    ; to an effect-framework binding (mtf.base:flash.onhit at effect[N]
    ; with extras keyed by `mtf.fx.<slot>.<effectIdx>.ex.<field>`). The
    ; old per-slot keys still sit in cosaves but nothing reads them
    ; anymore — they'll naturally age out. New saves never touch them.
    if ml >= 35 || ml >= 34
        MainQuest._migrationLevel = 36
        return
    endif
    ; v0.1.2 (ml=34): non-destructive. The "Conditions" page was renamed to
    ; "Preset editor" — rewrite the Pages array so existing saves pick up
    ; the new label. (Pages doesn't auto-refresh on script update; same
    ; reason the older ml=19 defensive block exists below.)
    if ml >= 33
        Pages = new String[5]
        Pages[0] = "General"
        Pages[1] = "Preset editor"
        Pages[2] = "Subjects"
        Pages[3] = "Plugins"
        Pages[4] = "Menu Options"
        MainQuest._migrationLevel = 34
        return
    endif
    ; v0.0.33 (ml=33): non-destructive. Two things:
    ;   1. Back out any legacy per-quest applied magnitudes on Plugin_Base
    ;      (mana/carry/sneak/speed/staminaRate/atkDmg/dmgResist/spellCost)
    ;      now that they live in StorageUtil keyed on the actor. If we
    ;      didn't, the next _recompute would stack a fresh delta on top of
    ;      the legacy delta — the player would see the drain double.
    ;   2. Defensive scratch-buffer allocation (Auto property attach trap
    ;      protection — these are new in v0.0.33).
    if ml >= 20
        MTF_Plugin basePlug = MainQuest.FindPlugin("mtf.base")
        if basePlug != None
            (basePlug as MTF_Plugin_Base)._migrateLegacyApplied(MainQuest.PlayerRef)
        endif
        ; Lazy-allocate the scratch arrays via the host helper. If they
        ; were declared but never attached, this is a no-op and the
        ; runtime falls back to per-call allocation in _loadPresetToScratch.
        MainQuest._ensureScratchArrays()
        MainQuest._migrationLevel = 33
        return
    endif
    ; v0.0.32 (ml=20): pulse rate/depth used to be Auto arrays here; they're
    ; now StorageUtil-backed, no allocation needed.
    if ml >= 19
        MainQuest._migrationLevel = 20
        return
    endif

    ; Pages: 5-page layout (also set by OnConfigInit; redundant here for the
    ; sake of upgraders whose Pages array predates the current shape).
    Pages = new String[5]
    Pages[0] = "General"
    Pages[1] = "Preset editor"
    Pages[2] = "Subjects"
    Pages[3] = "Plugins"
    Pages[4] = "Menu Options"

    ; Make sure every state array is allocated at the CURRENT
    ; MAX_EFFECTS_PER_SLOT size. Previously this block hardcoded
    ; `new string[32]` for the effect arrays (8 slots × 4 effects), which
    ; silently shrank them after EnsureArrays correctly sized them — the
    ; next EnsureArrays call then hit the 128-element ceiling trying to
    ; migrate 32 → 128 inside one VM tick and the loop never settled.
    MainQuest.EnsureArrays()

    MainQuest.ModActive          = false
    MainQuest.updateInterval     = 0.1
    MainQuest.OverlaySlot        = 2
    MainQuest.CurrentOverlaySlot = 2

    ; Default slot (idx 0): leave empty so the player sees no tattoo until
    ; they explicitly pick one in MCM. Loading visual catalogs is still
    ; required so the per-slot pickers can populate when opened.
    MainQuest.LoadVisualCatalogs()
    MainQuest.condPackId[0]  = ""
    MainQuest.condEntryId[0] = ""

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

    MainQuest._migrationLevel = 36
endEvent

; ── Page rendering ────────────────────────────────────────────────────────────
event OnPageReset(string page)
    _ensureMainQuest()
    if page == "General"
        drawGeneralPage()
    elseIf page == "Preset editor"
        drawPresetEditorPage()
    elseif page == "Subjects"
        drawSubjectsPage()
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

    ; Single-column engine/global settings. Preset management (Save / Pick /
    ; Delete) lives on the Preset editor page next to the per-preset content
    ; it operates on.
    AddHeaderOption("General")
    AddToggleOptionST("GEN_MOD_ACTIVE",      "Enable",                MainQuest.ModActive)
    AddSliderOptionST("GEN_UPDATE_INTERVAL", "Update interval (sec)", MainQuest.updateInterval, "{2}")
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

function drawPresetEditorPage()
    SetCursorFillMode(TOP_TO_BOTTOM)

    ; Defensive: EnsureArrays now lazy-allocates post-release arrays even
    ; when _arraysReady is true, but call it here explicitly so any stale
    ; instance gets patched before we read any of them.
    MainQuest.EnsureArrays()

    int idx = selectedCondition

    ; ── LEFT COLUMN: preset management + transition + visual config ─────────
    ; Preset header groups file lifecycle (Editing status + Save / Save as /
    ; Load / Delete / New). Transition has its own header (preset-wide
    ; animation timing, distinct from file management). Visuals/Layers/Pulse
    ; below the live-preview hint are per-slot (driven by the slot picker on
    ; the right).
    _refreshPresetNames()
    AddHeaderOption("Preset")
    AddTextOptionST("PRESET_EDITING_STATUS", "Editing", _editingLabel(), OPTION_FLAG_DISABLED)
    int saveFlag = OPTION_FLAG_NONE
    if _editingPresetName == ""
        saveFlag = OPTION_FLAG_DISABLED
    endif
    AddTextOptionST("PRESET_SAVE",     "Save",          "", saveFlag)
    AddInputOptionST("PRESET_SAVE_AS", "Save as...",    "(type a name)")
    AddMenuOptionST("PRESET_PICK",     "Load preset",   "")
    AddMenuOptionST("PRESET_DEL",      "Delete preset", "")
    AddMenuOptionST("PRESET_NEW",      "New preset",    "")

    AddHeaderOption("Transition")
    AddSliderOptionST("PRESET_TRANSITION_DUR", "Duration", MainQuest.GetTransitionDuration(), "{1} s")

    ; Per-preset fade on death (v0.1.4). One menu picks "Off" or one of the
    ; three modes; Duration is greyed out when Off. We use a single 4-entry
    ; menu instead of a separate toggle + mode menu to stay under the SkyUI
    ; engine's 127-named-state limit (the script is already at the ceiling).
    AddHeaderOption("Fade on death")
    AddMenuOptionST("PRESET_FADE_MODE",     "Mode",     _fadeModeMenuLabel(MainQuest.GetFadeOnDeathEnabled(), MainQuest.GetFadeOnDeathMode()))
    int fadeFlag = OPTION_FLAG_NONE
    if !MainQuest.GetFadeOnDeathEnabled()
        fadeFlag = OPTION_FLAG_DISABLED
    endif
    AddSliderOptionST("PRESET_FADE_DURATION", "Duration", MainQuest.GetFadeOnDeathDurationMs() / 1000.0, "{1} s", fadeFlag)

    AddHeaderOption("Visuals")
    AddMenuOptionST("SLOT_PACK_PICK",     "Visual pack", _slotPackLabel(idx))
    AddMenuOptionST("SLOT_VISUAL_ENTRY",  "Texture",     _slotEntryLabel(idx))

    ; Determine layer count from the resolved (slot or inherited) entry.
    ; When the slot's pack resolves to "(no texture)" (sentinel "<none>" or,
    ; for Default with no packs installed, ""), hide all layer sliders —
    ; there's nothing to tint. Otherwise default to MAX_LAYERS so the user
    ; can pre-tweak even before an entry resolves.
    string resPack  = MainQuest.ResolveSlotPackId(idx)
    string resEntry = MainQuest.ResolveSlotEntryId(idx)
    int layerN = MTF_MainQuest.MAX_LAYERS_PER_SLOT()
    if resPack == "" || resPack == "<none>"
        layerN = 0
    elseif resEntry != ""
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

    ; ── Pulse (animated emissive) ───────────────────────────────────────
    ; Only meaningful when the slot has emissive layers to modulate.
    ; Shown unconditionally so users can dial it in even with pack="<none>"
    ; (effects-only mode shows no overlay, so pulse is a no-op there).
    AddHeaderOption("Pulse")
    AddSliderOptionST("SLOT_PULSE_RATE",  "Rate",  MainQuest.GetCondPulseRate(idx), "{2} Hz")
    AddSliderOptionST("SLOT_PULSE_DEPTH", "Depth", MainQuest.GetCondPulseDepth(idx), "{0}%")
    AddSliderOptionST("SLOT_PULSE_PAUSE", "Pause", MainQuest.GetCondPulsePause(idx), "{1} s")
    AddMenuOptionST("SLOT_PULSE_WAVEFORM", "Waveform", _waveformLabel(MainQuest.GetCondWaveform(idx)))

    ; ── RIGHT COLUMN: slot picker + condition definition + cooldown + effects ──
    SetCursorPosition(1)

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
            string param2Label = p.GetConditionParam2Label(itemIdx)
            if param2Label != ""
                AddSliderOptionST("SLOT_COND_PARAM2", param2Label, MainQuest.GetCondParam2(idx), p.GetConditionParam2Format(itemIdx))
            endif
        endif

        int cdMin = MainQuest.cooldownMin[idx]
        AddHeaderOption("Cooldown")
        AddMenuOptionST("SLOT_CD_MODE",     "Mode",    _cooldownModeLabel(MainQuest.cooldownMode[idx]))
        AddSliderOptionST("SLOT_CD_HOURS",   "Hours",   cdMin / 60)
        AddSliderOptionST("SLOT_CD_MINUTES", "Minutes", cdMin % 60)
    endif

    AddHeaderOption("Effects")
    ; Progressive disclosure: row N is shown only after row N-1 has a key
    ; set. Row 0 is always visible. The trailing visible row is always the
    ; first "Not set" slot, so the user sees exactly one selector beyond
    ; their last bound effect. Clearing a row in the middle is handled by
    ; CompactEffectsAfter (see _acceptEffectType) so no row stays orphaned
    ; out of view.
    ;
    ; Storage cap (MAX_EFFECTS_PER_SLOT) is larger than the MCM cap below
    ; — JSON-authored presets can hold up to that many effects. Hidden
    ; effects beyond row 4 still dispatch at runtime; we surface a count
    ; so the user knows they're there (clear a visible row to promote one
    ; into view via the compact-shift).
    _drawEffectRow(idx, 0, "SLOT_EFFECT_1_TYPE", "SLOT_EFFECT_1_PARAM", "SLOT_EFFECT_1_P2", \
                   "SLOT_EFFECT_1_EX1", "SLOT_EFFECT_1_EX2", "SLOT_EFFECT_1_EX3")
    if MainQuest.GetSlotEffectKey(idx, 0) != ""
        _drawEffectRow(idx, 1, "SLOT_EFFECT_2_TYPE", "SLOT_EFFECT_2_PARAM", "SLOT_EFFECT_2_P2", \
                       "SLOT_EFFECT_2_EX1", "SLOT_EFFECT_2_EX2", "SLOT_EFFECT_2_EX3")
        if MainQuest.GetSlotEffectKey(idx, 1) != ""
            _drawEffectRow(idx, 2, "SLOT_EFFECT_3_TYPE", "SLOT_EFFECT_3_PARAM", "SLOT_EFFECT_3_P2", \
                           "SLOT_EFFECT_3_EX1", "SLOT_EFFECT_3_EX2", "SLOT_EFFECT_3_EX3")
            if MainQuest.GetSlotEffectKey(idx, 2) != ""
                _drawEffectRow(idx, 3, "SLOT_EFFECT_4_TYPE", "SLOT_EFFECT_4_PARAM", "SLOT_EFFECT_4_P2", \
                               "SLOT_EFFECT_4_EX1", "SLOT_EFFECT_4_EX2", "SLOT_EFFECT_4_EX3")
            endif
        endif
    endif
    ; Count bound effects beyond the MCM cap and surface a hint when any
    ; exist. They're dispatched but invisible in the editor; clearing a
    ; visible row promotes one of them into view via CompactEffectsAfter.
    int hidden = 0
    int hi = MTF_MainQuest.MAX_EFFECTS_PER_SLOT_MCM()
    int storageMax = MTF_MainQuest.MAX_EFFECTS_PER_SLOT()
    while hi < storageMax
        if MainQuest.GetSlotEffectKey(idx, hi) != ""
            hidden += 1
        endif
        hi += 1
    endwhile
    if hidden > 0
        AddTextOption("  (+" + hidden + " more — not editable here)", "", OPTION_FLAG_DISABLED)
    endif
endFunction

string Function _waveformLabel(string name)
    if name == ""
        return "Cosine (built-in)"
    endif
    return name
EndFunction

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
        SetSliderDialogDefaultValue(0.1)
        SetSliderDialogRange(0.1, 45.0)
        SetSliderDialogInterval(0.1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.updateInterval = value
        SetSliderOptionValueST(value, "{2}")
    endEvent
    event OnDefaultST()
        MainQuest.updateInterval = 0.1
        SetSliderOptionValueST(0.1, "{2}")
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
        string curKey = MainQuest.condPluginId[selectedCondition]
        MainQuest.BuildVisibleConditionMenu(curKey)
        string[] keys   = MainQuest.menuKeys
        string[] labels = MainQuest.menuLabels
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
            opts[i + 1] = labels[i]
            if keys[i] == curKey
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
            string[] keys = MainQuest.menuKeys
            int n = MainQuest.menuCount
            if (index - 1) < n && keys != None
                newKey = keys[index - 1]
            endif
        endif
        MainQuest.SetCondPluginId(slot, newKey)
        if newKey == ""
            MainQuest.SetCondParam(slot, 0)
            MainQuest.SetCondParam2(slot, 0)
        else
            MTF_Plugin p = MainQuest.ResolvePluginByKey(newKey)
            int itemIdx = -1
            if p != None
                itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(newKey))
            endif
            if itemIdx >= 0
                MainQuest.SetCondParam(slot, p.GetConditionParamDefault(itemIdx))
                MainQuest.SetCondParam2(slot, p.GetConditionParam2Default(itemIdx))
            else
                MainQuest.SetCondParam(slot, 0)
                MainQuest.SetCondParam2(slot, 0)
            endif
        endif
        SetMenuOptionValueST(_condTypeLabel(newKey))
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPluginId(selectedCondition, "")
        MainQuest.SetCondParam(selectedCondition, 0)
        MainQuest.SetCondParam2(selectedCondition, 0)
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

state SLOT_COND_PARAM2
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
        SetSliderDialogStartValue(MainQuest.GetCondParam2(selectedCondition))
        SetSliderDialogDefaultValue(p.GetConditionParam2Default(itemIdx))
        SetSliderDialogRange(p.GetConditionParam2Min(itemIdx), p.GetConditionParam2Max(itemIdx))
        SetSliderDialogInterval(p.GetConditionParam2Step(itemIdx))
    endEvent
    event OnSliderAcceptST(float value)
        string key = MainQuest.condPluginId[selectedCondition]
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        string fmt = "{0}"
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                fmt = p.GetConditionParam2Format(itemIdx)
            endif
        endif
        MainQuest.SetCondParam2(selectedCondition, value as int)
        SetSliderOptionValueST(value as int, fmt)
    endEvent
    event OnDefaultST()
        string key = MainQuest.condPluginId[selectedCondition]
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        int defVal = 0
        string fmt = "{0}"
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                defVal = p.GetConditionParam2Default(itemIdx)
                fmt = p.GetConditionParam2Format(itemIdx)
            endif
        endif
        MainQuest.SetCondParam2(selectedCondition, defVal)
        SetSliderOptionValueST(defVal, fmt)
    endEvent
    event OnHighlightST()
        string key = MainQuest.condPluginId[selectedCondition]
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                SetInfoText(p.GetConditionParam2Label(itemIdx))
                return
            endif
        endif
        SetInfoText("Second parameter for the selected condition.")
    endEvent
endState

; ── Per-slot entry picker (texture choice within the active visual pack) ────
string Function _slotEntryLabel(int slot)
    ; When the slot is in "(no texture)" mode (resolved at the pack level)
    ; the entry row is informational only.
    string resPack = MainQuest.ResolveSlotPackId(slot)
    if resPack == "<none>" || resPack == ""
        return "—"
    endif
    string entryId = MainQuest.condEntryId[slot]
    if entryId == ""
        if slot == 0
            return "(not set)"
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
    if pid == "<none>"
        return "(no texture)"
    endif
    if pid == ""
        if slot == 0
            if MainQuest.GetVisualPackCount() == 0
                return "(no packs found)"
            endif
            return "(no texture)"
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
        ; Options layout: [(inherit Default) if slot>0], (no texture), packs...
        int total = n + 1   ; +1 for "(no texture)"
        if allowInherit
            total += 1
        endif
        string[] opts = _newOpts(total)
        int sel = 0
        int writeIdx = 0
        string curPack = MainQuest.condPackId[selectedCondition]
        if allowInherit
            opts[writeIdx] = "(inherit Default)"
            if curPack == ""
                sel = writeIdx
            endif
            writeIdx += 1
        endif
        opts[writeIdx] = "(no texture)"
        if curPack == "<none>" || (selectedCondition == 0 && curPack == "")
            sel = writeIdx
        endif
        writeIdx += 1
        int i = 0
        while i < n
            opts[writeIdx] = MainQuest.GetVisualPackLabelAt(i)
            if MainQuest.GetVisualPackIdAt(i) == curPack
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
        int cursor = 0
        string newPack = ""
        bool resolved = false
        if allowInherit
            if index == cursor
                newPack = ""
                resolved = true
            endif
            cursor += 1
        endif
        if !resolved && index == cursor
            ; "(no texture)" — for slot 0 we just clear (no inheritance possible);
            ; for 1-7 we store the explicit sentinel.
            if selectedCondition == 0
                newPack = ""
            else
                newPack = "<none>"
            endif
            resolved = true
        endif
        cursor += 1
        if !resolved
            int packIdx = index - cursor
            if packIdx >= 0 && packIdx < MainQuest.GetVisualPackCount()
                newPack = MainQuest.GetVisualPackIdAt(packIdx)
            endif
        endif
        ; Switching packs invalidates the entry pick — reset to first entry
        ; of the new pack (or clear if inheriting / no-texture).
        if newPack != MainQuest.condPackId[selectedCondition]
            MainQuest.condPackId[selectedCondition] = newPack
            if newPack == "" || newPack == "<none>"
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
        ; Default for every slot is "no tattoo" — leave pack + entry empty.
        ; User must pick a pack explicitly to enable a visual.
        MainQuest.condPackId[selectedCondition]  = ""
        MainQuest.condEntryId[selectedCondition] = ""
        SetMenuOptionValueST(_slotPackLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnHighlightST()
        if selectedCondition == 0
            SetInfoText("Visual pack used by the Default slot. Pick (no texture) for effects-only operation with no overlay. Packs are JSON files under Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/.")
        else
            SetInfoText("Visual pack for this condition slot. (inherit Default) falls back to the Default slot's pack + texture; (no texture) renders nothing and runs effects only.")
        endif
    endEvent
endState

state SLOT_VISUAL_ENTRY
    event OnMenuOpenST()
        string pid = MainQuest.ResolveSlotPackId(selectedCondition)
        ; If the slot is in "(no texture)" / no-pack mode, the entry picker
        ; is a no-op — render a single read-only label.
        if pid == "" || pid == "<none>"
            string[] na = new string[1]
            na[0] = "—"
            SetMenuDialogStartIndex(0)
            SetMenuDialogDefaultIndex(0)
            SetMenuDialogOptions(na)
            return
        endif
        int n = MainQuest.GetPackEntryCount(pid)
        ; Condition slots get a leading "(inherit Default)" option at index 0
        ; ONLY when they also inherit the pack — picking a different pack means
        ; the slot has its own (pack, entry) and entry inheritance is moot.
        bool allowInherit = (selectedCondition > 0) && (MainQuest.condPackId[selectedCondition] == "")
        int total = n
        if allowInherit
            total += 1
        endif
        if total <= 0
            string[] empty = new string[1]
            empty[0] = "(no entries)"
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
            if MainQuest.condEntryId[selectedCondition] == ""
                sel = 0
            endif
            writeIdx = 1
        endif
        int i = 0
        while i < n
            opts[writeIdx] = MainQuest.GetPackEntryLabelAt(pid, i)
            if MainQuest.GetPackEntryIdAt(pid, i) == MainQuest.condEntryId[selectedCondition]
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
        if pid == "" || pid == "<none>"
            ; No-pack mode — picker is informational; ignore selection.
            return
        endif
        bool allowInherit = (selectedCondition > 0) && (MainQuest.condPackId[selectedCondition] == "")
        if index < 0
            return
        endif
        if allowInherit && index == 0
            MainQuest.condEntryId[selectedCondition] = ""
        else
            int entryIdx = index
            if allowInherit
                entryIdx -= 1
            endif
            if entryIdx >= 0 && entryIdx < MainQuest.GetPackEntryCount(pid)
                MainQuest.condEntryId[selectedCondition] = MainQuest.GetPackEntryIdAt(pid, entryIdx)
            endif
        endif
        SetMenuOptionValueST(_slotEntryLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnDefaultST()
        ; Default for every slot is "no entry" — same as the pack picker;
        ; user picks explicitly. Slot 0 was the odd one out previously.
        MainQuest.condEntryId[selectedCondition] = ""
        SetMenuOptionValueST(_slotEntryLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnHighlightST()
        if selectedCondition == 0
            SetInfoText("Texture used by the Default slot. To run effects-only with no overlay, set Visual pack to (no texture).")
        else
            SetInfoText("Texture used by this condition slot. (inherit Default) falls back to Default's pick. To disable the overlay entirely, set Visual pack to (no texture).")
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

; ── Per-slot pulse (animated emissive) ──────────────────────────────────────
; Modulates each layer's emissive intensity as base * (1 + depth% * sin(2π·rate·t)).
; Rate is in cycles per second; 0 disables pulse for the slot.

state SLOT_PULSE_RATE
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetCondPulseRate(selectedCondition))
        SetSliderDialogDefaultValue(0.0)
        SetSliderDialogRange(0.0, 5.0)
        SetSliderDialogInterval(0.05)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetCondPulseRate(selectedCondition, value)
        SetSliderOptionValueST(value, "{2} Hz")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPulseRate(selectedCondition, 0.0)
        SetSliderOptionValueST(0.0, "{2} Hz")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Pulse cycles per second. 0 disables the animation.")
    endEvent
endState

state SLOT_PULSE_DEPTH
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetCondPulseDepth(selectedCondition))
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(5)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetCondPulseDepth(selectedCondition, value as int)
        SetSliderOptionValueST(value as int, "{0}%")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPulseDepth(selectedCondition, 0)
        SetSliderOptionValueST(0, "{0}%")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("How far the glow dims from peak. 0% = no pulse, 100% = full off at the trough. Emission strength is the peak.")
    endEvent
endState

state SLOT_PULSE_PAUSE
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetCondPulsePause(selectedCondition))
        SetSliderDialogDefaultValue(0.0)
        SetSliderDialogRange(0.0, 10.0)
        SetSliderDialogInterval(0.1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetCondPulsePause(selectedCondition, value)
        SetSliderOptionValueST(value, "{1} s")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPulsePause(selectedCondition, 0.0)
        SetSliderOptionValueST(0.0, "{1} s")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Seconds of hold at the trough (dim) between pulse cycles. 0 = continuous.")
    endEvent
endState

; ── Preset-wide settings (rendered above the slot picker) ────────────────────

state PRESET_TRANSITION_DUR
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetTransitionDuration())
        SetSliderDialogDefaultValue(1.0)
        SetSliderDialogRange(0.0, 10.0)
        SetSliderDialogInterval(0.1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetTransitionDuration(value)
        SetSliderOptionValueST(value, "{1} s")
    endEvent
    event OnDefaultST()
        MainQuest.SetTransitionDuration(1.0)
        SetSliderOptionValueST(1.0, "{1} s")
    endEvent
    event OnHighlightST()
        SetInfoText("Seconds to cross-fade tattoo visuals (alpha, tint, emissive color, emission strength) when the active tier changes. 0 = snap instantly. Saved with the preset.")
    endEvent
endState

; ── Fade on death (v0.1.4) ──────────────────────────────────────────────
; Mode menu carries the on/off toggle as item 0 ("Off"); items 1-3 each
; pick a mode AND enable fade. Duration slider greys out when "Off".
; Combined into 2 states (not 3) to stay under the 127 named-state limit.

state PRESET_FADE_MODE
    event OnMenuOpenST()
        ; "Off" + 3 modes. SkyUI's "None" sentinel bug means we never put
        ; the literal string "None" in this array — use "Off" instead.
        string[] opts = Utility.CreateStringArray(4, "")
        opts[0] = "Off"
        opts[1] = "Overlay (full disappear)"
        opts[2] = "Emissive (dim glow only)"
        opts[3] = "Inverted (dip then recover)"
        int cur = 0
        if MainQuest.GetFadeOnDeathEnabled()
            cur = MainQuest.GetFadeOnDeathMode() + 1
            if cur < 1 || cur > 3
                cur = 1
            endif
        endif
        SetMenuDialogStartIndex(cur)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index <= 0
            MainQuest.SetFadeOnDeathEnabled(false)
        else
            MainQuest.SetFadeOnDeathMode(index - 1)
            MainQuest.SetFadeOnDeathEnabled(true)
        endif
        SetMenuOptionValueST(_fadeModeMenuLabel(MainQuest.GetFadeOnDeathEnabled(), MainQuest.GetFadeOnDeathMode()))
        ; Repaint the page so the Duration slider's disabled flag tracks
        ; the new enabled state.
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetFadeOnDeathEnabled(false)
        SetMenuOptionValueST(_fadeModeMenuLabel(false, 0))
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Fade the tattoo when the actor dies. One-shot animation, then the entry stops animating.\n* Off: no fade on death.\n* Overlay: alpha to 0, tattoo disappears.\n* Emissive: emission strength to 0, art stays but stops glowing.\n* Inverted: dip to 0 then recover — a final flicker.\nSaved with the preset.")
    endEvent
endState

state PRESET_FADE_DURATION
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetFadeOnDeathDurationMs() / 1000.0)
        SetSliderDialogDefaultValue(2.0)
        SetSliderDialogRange(0.1, 10.0)
        SetSliderDialogInterval(0.1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetFadeOnDeathDurationMs((value * 1000.0) as int)
        SetSliderOptionValueST(value, "{1} s")
    endEvent
    event OnDefaultST()
        MainQuest.SetFadeOnDeathDurationMs(2000)
        SetSliderOptionValueST(2.0, "{1} s")
    endEvent
    event OnHighlightST()
        SetInfoText("Full duration of the fade animation in seconds. For Inverted mode the dip and recovery each take half of this. Saved with the preset.")
    endEvent
endState

string Function _fadeModeMenuLabel(bool enabled, int mode)
    if !enabled
        return "Off"
    elseif mode == 1
        return "Emissive"
    elseif mode == 2
        return "Inverted"
    endif
    return "Overlay"
EndFunction

state SLOT_PULSE_WAVEFORM
    event OnMenuOpenST()
        string[] files = MainQuest.ListWaveforms()
        int fileCount = MainQuest.ListWaveformsCount()
        ; Size the option array EXACTLY to the count we have. Padding with
        ; duplicate labels (a prior approach to dodge the SkyUI "None"
        ; sentinel quirk) ends up showing 27 phantom rows in the dropdown.
        int total = fileCount + 1
        string[] opts = Utility.CreateStringArray(total, "")
        opts[0] = "Cosine (built-in)"
        int i = 0
        while i < fileCount
            opts[i + 1] = files[i]
            i += 1
        endwhile

        ; Pre-select the currently saved waveform.
        string cur = MainQuest.GetCondWaveform(selectedCondition)
        int startIdx = 0
        if cur != ""
            int k = 1
            while k < total && opts[k] != cur
                k += 1
            endwhile
            if k < total
                startIdx = k
            endif
        endif
        SetMenuDialogStartIndex(startIdx)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        string[] files = MainQuest.ListWaveforms()
        int fileCount = MainQuest.ListWaveformsCount()
        string chosen = ""
        if index >= 1 && (index - 1) < fileCount
            chosen = files[index - 1]
        endif
        MainQuest.SetCondWaveform(selectedCondition, chosen)
        SetMenuOptionValueST(_waveformLabel(chosen))
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondWaveform(selectedCondition, "")
        SetMenuOptionValueST(_waveformLabel(""))
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Curve shape for one pulse cycle. Built-in cosine is the default; JSON files under MagicTattoosFramework/waveforms/ are listed here.")
    endEvent
endState

; ── Per-slot effect list (4 effects × 2 controls each + optional extras) ───

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

Function _drawEffectRow(int slot, int effectIdx, string typeStateId, string paramStateId, string param2StateId, string extra1StateId, string extra2StateId, string extra3StateId)
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
        if p.GetEffectParamMenuOptionCount(itemIdx) > 0
            ; Menu-style: render current value's label.
            AddMenuOptionST(paramStateId, "  " + paramLabel, \
                _menuLabelForParam(p, itemIdx, MainQuest.GetSlotEffectParam(slot, effectIdx)))
        else
            AddSliderOptionST(paramStateId, "  " + paramLabel, MainQuest.GetSlotEffectParam(slot, effectIdx))
        endif
    endif
    string param2Label = p.GetEffectParam2Label(itemIdx)
    if param2Label != ""
        if p.GetEffectParam2MenuOptionCount(itemIdx) > 0
            AddMenuOptionST(param2StateId, "  " + param2Label, \
                _menuLabelForParam2(p, itemIdx, MainQuest.GetSlotEffectParam2(slot, effectIdx)))
        else
            AddSliderOptionST(param2StateId, "  " + param2Label, MainQuest.GetSlotEffectParam2(slot, effectIdx), p.GetEffectParam2Format(itemIdx))
        endif
    endif
    ; v0.1.3 extras — up to 3 plugin-declared extra fields per effect row.
    ; State IDs are pre-allocated (12 total = 4 rows × 3); the state block
    ; resolves its field name + spec at runtime by querying the plugin's
    ; count + typed getters with the field index it owns.
    string[] extraIds = new string[3]
    extraIds[0] = extra1StateId
    extraIds[1] = extra2StateId
    extraIds[2] = extra3StateId
    int xN = p.GetEffectExtraFieldCount(itemIdx)
    if xN > 3
        xN = 3
    endif
    int xi = 0
    while xi < xN
        string xname  = p.GetEffectExtraFieldName(itemIdx, xi)
        string xlabel = p.GetEffectExtraFieldLabel(itemIdx, xi)
        if xname != "" && xlabel != ""
            int xval = MainQuest.GetSlotEffectExtra(slot, effectIdx, xname) as int
            if p.GetEffectExtraFieldMenuOptionCount(itemIdx, xi) > 0
                AddMenuOptionST(extraIds[xi], "  " + xlabel, \
                    _menuLabelForExtra(p, itemIdx, xi, xval))
            else
                AddSliderOptionST(extraIds[xi], "  " + xlabel, xval)
            endif
        endif
        xi += 1
    endwhile
EndFunction

Function _openEffectTypeMenu(int effectIdx)
    string curKey = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    ; Build the menu cache ONCE on the host (single plugin walk inside),
    ; then snapshot the cache locally so the build loop is pure-local —
    ; no per-effect cross-script calls.
    MainQuest.BuildVisibleEffectMenu(curKey)
    string[] keys   = MainQuest.menuKeys
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
        ; Read from the menu cache populated by _openEffectTypeMenu in the
        ; preceding open event. Avoids re-walking plugins for an O(N)
        ; cross-script lookup per pick.
        string[] keys = MainQuest.menuKeys
        int n = MainQuest.menuCount
        if (index - 1) < n && keys != None
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
    ; Progressive-disclosure UI: if the user just CLEARED this row, shift
    ; any subsequent configured rows up so nothing stays orphaned beyond
    ; the trailing "Not set" slot.
    if newKey == ""
        MainQuest.CompactEffectsAfter(selectedCondition, effectIdx)
    endif
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
    int menuCnt = 0
    int itemIdx = -1
    if p != None
        itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            defVal = p.GetEffectParamDefault(itemIdx)
            menuCnt = p.GetEffectParamMenuOptionCount(itemIdx)
        endif
    endif
    MainQuest.SetSlotEffect(selectedCondition, effectIdx, key, defVal)
    if menuCnt > 0 && p != None && itemIdx >= 0
        SetMenuOptionValueST(_menuLabelForParam(p, itemIdx, defVal))
    else
        SetSliderOptionValueST(defVal)
    endif
EndFunction

; ── Menu-style param helpers (v0.1.3) ───────────────────────────────────────
; Plugin script (extends Quest) indexed array writes silently no-op on this
; VM, AND StringUtil.Split returns arrays whose .Length sometimes reads as
; 0 mid-loop. So the dropdown API exposes count + per-index getters for
; value AND label separately — no array round-trips, no split parsing.
; These helpers walk the options one at a time and return the label for
; the stored int value, falling back to "Custom: N" when the value isn't
; in the curated preset list.
string Function _menuLabelForParam(MTF_Plugin p, int itemIdx, int curVal)
    int n = p.GetEffectParamMenuOptionCount(itemIdx)
    int i = 0
    while i < n
        if p.GetEffectParamMenuOptionValue(itemIdx, i) == curVal
            return p.GetEffectParamMenuOptionLabel(itemIdx, i)
        endif
        i += 1
    endwhile
    return "Custom: " + curVal
EndFunction

string Function _menuLabelForParam2(MTF_Plugin p, int itemIdx, int curVal)
    int n = p.GetEffectParam2MenuOptionCount(itemIdx)
    int i = 0
    while i < n
        if p.GetEffectParam2MenuOptionValue(itemIdx, i) == curVal
            return p.GetEffectParam2MenuOptionLabel(itemIdx, i)
        endif
        i += 1
    endwhile
    return "Custom: " + curVal
EndFunction

Function _openEffectParamMenu(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetEffectParamMenuOptionCount(itemIdx)
    if n <= 0
        return
    endif
    int curVal     = MainQuest.GetSlotEffectParam(selectedCondition, effectIdx)
    int defaultVal = p.GetEffectParamDefault(itemIdx)
    ; Allocate via _newOpts (literal-return-in-state-block pattern that the
    ; VM accepts here) and populate by querying the plugin one option at a
    ; time. We avoid the plugin returning a populated string[] entirely —
    ; Quest-script indexed array writes silently no-op on this VM.
    string[] labels = _newOpts(n)
    int curSel = 0
    int defaultSel = 0
    int i = 0
    while i < n
        int   v = p.GetEffectParamMenuOptionValue(itemIdx, i)
        string label = p.GetEffectParamMenuOptionLabel(itemIdx, i)
        labels[i] = label
        if v == curVal
            curSel = i
        endif
        if v == defaultVal
            defaultSel = i
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(curSel)
    SetMenuDialogDefaultIndex(defaultSel)
    SetMenuDialogOptions(labels)
EndFunction

Function _acceptEffectParamMenu(int effectIdx, int index)
    if index < 0
        return
    endif
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetEffectParamMenuOptionCount(itemIdx)
    if index >= n
        return
    endif
    int newVal = p.GetEffectParamMenuOptionValue(itemIdx, index)
    string label = p.GetEffectParamMenuOptionLabel(itemIdx, index)
    MainQuest.SetSlotEffect(selectedCondition, effectIdx, key, newVal)
    SetMenuOptionValueST(label)
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
    int menuCnt = 0
    int itemIdx = -1
    if p != None
        itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            defVal = p.GetEffectParam2Default(itemIdx)
            fmt = p.GetEffectParam2Format(itemIdx)
            menuCnt = p.GetEffectParam2MenuOptionCount(itemIdx)
        endif
    endif
    MainQuest.SetSlotEffectParam2(selectedCondition, effectIdx, defVal)
    if menuCnt > 0 && p != None && itemIdx >= 0
        SetMenuOptionValueST(_menuLabelForParam2(p, itemIdx, defVal))
    else
        SetSliderOptionValueST(defVal, fmt)
    endif
EndFunction

Function _openEffectParam2Menu(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetEffectParam2MenuOptionCount(itemIdx)
    if n <= 0
        return
    endif
    int curVal     = MainQuest.GetSlotEffectParam2(selectedCondition, effectIdx)
    int defaultVal = p.GetEffectParam2Default(itemIdx)
    string[] labels = _newOpts(n)
    int curSel = 0
    int defaultSel = 0
    int i = 0
    while i < n
        int   v = p.GetEffectParam2MenuOptionValue(itemIdx, i)
        string label = p.GetEffectParam2MenuOptionLabel(itemIdx, i)
        labels[i] = label
        if v == curVal
            curSel = i
        endif
        if v == defaultVal
            defaultSel = i
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(curSel)
    SetMenuDialogDefaultIndex(defaultSel)
    SetMenuDialogOptions(labels)
EndFunction

Function _acceptEffectParam2Menu(int effectIdx, int index)
    if index < 0
        return
    endif
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetEffectParam2MenuOptionCount(itemIdx)
    if index >= n
        return
    endif
    int newVal = p.GetEffectParam2MenuOptionValue(itemIdx, index)
    string label = p.GetEffectParam2MenuOptionLabel(itemIdx, index)
    MainQuest.SetSlotEffectParam2(selectedCondition, effectIdx, newVal)
    SetMenuOptionValueST(label)
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
    event OnMenuOpenST()
        _openEffectParamMenu(0)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(0, index)
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
    event OnMenuOpenST()
        _openEffectParamMenu(1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(1, index)
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
    event OnMenuOpenST()
        _openEffectParamMenu(2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(2, index)
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
    event OnMenuOpenST()
        _openEffectParamMenu(3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(3, index)
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
    event OnMenuOpenST()
        _openEffectParam2Menu(0)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParam2Menu(0, index)
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
    event OnMenuOpenST()
        _openEffectParam2Menu(1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParam2Menu(1, index)
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
    event OnMenuOpenST()
        _openEffectParam2Menu(2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParam2Menu(2, index)
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
    event OnMenuOpenST()
        _openEffectParam2Menu(3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParam2Menu(3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam2(3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam2(3)
    endEvent
endState

; ── Per-effect "extras" states (v0.1.3) ─────────────────────────────────────
; Up to 3 plugin-declared extra slider fields per effect row. The state ID
; encodes (effectRow ∈ 0..3, extraSlot ∈ 0..2); the field name, label, and
; min/max/step/default come from the bound plugin's
; GetEffectExtraFieldName / Label / Min / Max / Step / Default getters,
; indexed by extraSlot. If the plugin declares fewer than 3 fields
; (GetEffectExtraFieldCount returns < extraSlot+1), the unused state slots
; simply never appear (AddSliderOptionST is not called in _drawEffectRow).

string Function _getEffectExtraFieldName(int effectIdx, int extraSlot)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    if key == ""
        return ""
    endif
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return ""
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return ""
    endif
    int n = p.GetEffectExtraFieldCount(itemIdx)
    if extraSlot < 0 || extraSlot >= n
        return ""
    endif
    return p.GetEffectExtraFieldName(itemIdx, extraSlot)
EndFunction

Function _openEffectExtra(int effectIdx, int extraSlot)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetEffectExtraFieldCount(itemIdx)
    if extraSlot < 0 || extraSlot >= n
        return
    endif
    string fieldName = p.GetEffectExtraFieldName(itemIdx, extraSlot)
    if fieldName == ""
        return
    endif
    float startVal = MainQuest.GetSlotEffectExtra(selectedCondition, effectIdx, fieldName)
    SetSliderDialogStartValue(startVal)
    SetSliderDialogRange(p.GetEffectExtraFieldMin(itemIdx, extraSlot) as float, \
                         p.GetEffectExtraFieldMax(itemIdx, extraSlot) as float)
    SetSliderDialogInterval(p.GetEffectExtraFieldStep(itemIdx, extraSlot) as float)
    SetSliderDialogDefaultValue(p.GetEffectExtraFieldDefault(itemIdx, extraSlot) as float)
EndFunction

Function _acceptEffectExtra(int effectIdx, int extraSlot, float value)
    string fieldName = _getEffectExtraFieldName(effectIdx, extraSlot)
    if fieldName == ""
        return
    endif
    MainQuest.SetSlotEffectExtra(selectedCondition, effectIdx, fieldName, value)
    SetSliderOptionValueST(value as int)
EndFunction

; ── Extras dropdown variant (mirrors _open/_acceptEffectParamMenu) ──────────
; Mounted on the same SLOT_EFFECT_n_EXm state as the slider; SkyUI picks
; which event fires based on whether _drawEffectRow registered Add*Slider* or
; Add*Menu*. Branch is per-render so the same state can swap modes mid-row
; (e.g. when a new effect is bound that uses dropdowns instead of sliders).
string Function _menuLabelForExtra(MTF_Plugin p, int itemIdx, int fieldIdx, int curVal)
    int n = p.GetEffectExtraFieldMenuOptionCount(itemIdx, fieldIdx)
    int i = 0
    while i < n
        if p.GetEffectExtraFieldMenuOptionValue(itemIdx, fieldIdx, i) == curVal
            return p.GetEffectExtraFieldMenuOptionLabel(itemIdx, fieldIdx, i)
        endif
        i += 1
    endwhile
    return "Custom: " + curVal
EndFunction

Function _openEffectExtraMenu(int effectIdx, int extraSlot)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetEffectExtraFieldCount(itemIdx)
    if extraSlot < 0 || extraSlot >= n
        return
    endif
    string fieldName = p.GetEffectExtraFieldName(itemIdx, extraSlot)
    if fieldName == ""
        return
    endif
    int mn = p.GetEffectExtraFieldMenuOptionCount(itemIdx, extraSlot)
    if mn <= 0
        return
    endif
    int curVal     = MainQuest.GetSlotEffectExtra(selectedCondition, effectIdx, fieldName) as int
    int defaultVal = p.GetEffectExtraFieldDefault(itemIdx, extraSlot)
    string[] labels = _newOpts(mn)
    int curSel = 0
    int defaultSel = 0
    int i = 0
    while i < mn
        int v = p.GetEffectExtraFieldMenuOptionValue(itemIdx, extraSlot, i)
        labels[i] = p.GetEffectExtraFieldMenuOptionLabel(itemIdx, extraSlot, i)
        if v == curVal
            curSel = i
        endif
        if v == defaultVal
            defaultSel = i
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(curSel)
    SetMenuDialogDefaultIndex(defaultSel)
    SetMenuDialogOptions(labels)
EndFunction

Function _acceptEffectExtraMenu(int effectIdx, int extraSlot, int index)
    if index < 0
        return
    endif
    string fieldName = _getEffectExtraFieldName(effectIdx, extraSlot)
    if fieldName == ""
        return
    endif
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int mn = p.GetEffectExtraFieldMenuOptionCount(itemIdx, extraSlot)
    if index >= mn
        return
    endif
    int newVal = p.GetEffectExtraFieldMenuOptionValue(itemIdx, extraSlot, index)
    string label = p.GetEffectExtraFieldMenuOptionLabel(itemIdx, extraSlot, index)
    MainQuest.SetSlotEffectExtra(selectedCondition, effectIdx, fieldName, newVal as float)
    SetMenuOptionValueST(label)
EndFunction

Function _defaultEffectExtra(int effectIdx, int extraSlot)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetEffectExtraFieldCount(itemIdx)
    if extraSlot < 0 || extraSlot >= n
        return
    endif
    string fieldName = p.GetEffectExtraFieldName(itemIdx, extraSlot)
    if fieldName == ""
        return
    endif
    float defVal = p.GetEffectExtraFieldDefault(itemIdx, extraSlot) as float
    MainQuest.SetSlotEffectExtra(selectedCondition, effectIdx, fieldName, defVal)
    ; Match how _drawEffectRow registered this widget — Set*Slider* won't take
    ; on a menu-mode control and vice versa.
    if p.GetEffectExtraFieldMenuOptionCount(itemIdx, extraSlot) > 0
        SetMenuOptionValueST(_menuLabelForExtra(p, itemIdx, extraSlot, defVal as int))
    else
        SetSliderOptionValueST(defVal as int)
    endif
EndFunction

Function _highlightEffectExtra(int effectIdx, int extraSlot)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        SetInfoText("Effect extra parameter.")
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        SetInfoText("Effect extra parameter.")
        return
    endif
    int n = p.GetEffectExtraFieldCount(itemIdx)
    if extraSlot < 0 || extraSlot >= n
        SetInfoText("Effect extra parameter.")
        return
    endif
    SetInfoText(p.GetEffectExtraFieldLabel(itemIdx, extraSlot))
EndFunction

state SLOT_EFFECT_1_EX1
    event OnSliderOpenST()
        _openEffectExtra(0, 0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(0, 0, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(0, 0)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(0, 0, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(0, 0)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(0, 0)
    endEvent
endState

state SLOT_EFFECT_1_EX2
    event OnSliderOpenST()
        _openEffectExtra(0, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(0, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(0, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(0, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(0, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(0, 1)
    endEvent
endState

state SLOT_EFFECT_1_EX3
    event OnSliderOpenST()
        _openEffectExtra(0, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(0, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(0, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(0, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(0, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(0, 2)
    endEvent
endState

state SLOT_EFFECT_2_EX1
    event OnSliderOpenST()
        _openEffectExtra(1, 0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(1, 0, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(1, 0)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(1, 0, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(1, 0)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(1, 0)
    endEvent
endState

state SLOT_EFFECT_2_EX2
    event OnSliderOpenST()
        _openEffectExtra(1, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(1, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(1, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(1, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(1, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(1, 1)
    endEvent
endState

state SLOT_EFFECT_2_EX3
    event OnSliderOpenST()
        _openEffectExtra(1, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(1, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(1, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(1, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(1, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(1, 2)
    endEvent
endState

state SLOT_EFFECT_3_EX1
    event OnSliderOpenST()
        _openEffectExtra(2, 0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(2, 0, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(2, 0)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(2, 0, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(2, 0)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(2, 0)
    endEvent
endState

state SLOT_EFFECT_3_EX2
    event OnSliderOpenST()
        _openEffectExtra(2, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(2, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(2, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(2, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(2, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(2, 1)
    endEvent
endState

state SLOT_EFFECT_3_EX3
    event OnSliderOpenST()
        _openEffectExtra(2, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(2, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(2, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(2, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(2, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(2, 2)
    endEvent
endState

state SLOT_EFFECT_4_EX1
    event OnSliderOpenST()
        _openEffectExtra(3, 0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(3, 0, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(3, 0)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(3, 0, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(3, 0)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(3, 0)
    endEvent
endState

state SLOT_EFFECT_4_EX2
    event OnSliderOpenST()
        _openEffectExtra(3, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(3, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(3, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(3, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(3, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(3, 1)
    endEvent
endState

state SLOT_EFFECT_4_EX3
    event OnSliderOpenST()
        _openEffectExtra(3, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectExtra(3, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectExtraMenu(3, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectExtraMenu(3, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectExtra(3, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectExtra(3, 2)
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
{Returns a fresh string[] sized n (or 1 if n<=1).
 Previously a literal-size dispatcher with 100+ elseif branches — that
 silently returned length-0 arrays on this VM build once the chain
 crossed ~40 branches (the same VM bug that breaks sub-function
 trampolining). With 60+ registered effects we trip the threshold and
 every Effect/Condition dropdown ends up empty.

 SKSE's Utility.CreateStringArray(n, default) handles runtime-sized
 allocation natively — same primitive we use for the per-slot effect
 arrays. Single call, no branches.}
    if n <= 1
        return new string[1]
    endif
    return Utility.CreateStringArray(n, "")
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

; Tracks the preset (if any) the editor is currently editing. Set on
; successful Load and Save-as; cleared by New preset and by deleting the
; same name we were editing. Display version preserves original casing.
string _editingPresetName    = ""
string _editingPresetDisplay = ""

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

string function _editingLabel()
    if _editingPresetName == ""
        return "(unsaved)"
    endif
    return _editingPresetDisplay
endFunction

Function _setEditing(string sanitized, string display)
    _editingPresetName = sanitized
    _editingPresetDisplay = display
EndFunction

Function _clearEditing()
    _editingPresetName = ""
    _editingPresetDisplay = ""
EndFunction

; Returns -1 if no preset with this sanitized filename exists.
int Function _findPresetIndex(string sanitized)
    int i = 0
    while i < _scratchPresetCount
        if _scratchPresetNames[i] == sanitized
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

; Loads the named preset, refreshes editor state, and refreshes the page.
; Returns false on JSON read failure.
bool Function _doLoadPreset(string sanitized)
    if !MainQuest.LoadPreset(sanitized)
        return false
    endif
    string disp = MainQuest.GetPresetDisplayName(sanitized)
    _setEditing(sanitized, disp)
    MainQuest.setRedraw()
    ForcePageReset()
    return true
EndFunction

; "Editing: <name>" status row (disabled). Hover text reflects whether a
; preset is loaded for in-place save.
state PRESET_EDITING_STATUS
    event OnHighlightST()
        if _editingPresetName == ""
            SetInfoText("No preset is loaded for editing. Use Save as... to commit current edits as a new preset, or Load preset to bring in an existing one.")
        else
            SetInfoText("Currently editing '" + _editingPresetDisplay + "'. Click Save to overwrite, or Save as... to fork to a new name.")
        endif
    endEvent
endState

; In-place save: overwrites the currently-loaded preset. Disabled in the
; draw fn when nothing is loaded.
state PRESET_SAVE
    event OnSelectST()
        if _editingPresetName == ""
            return
        endif
        if MainQuest.SavePreset(_editingPresetDisplay)
            Debug.Notification("MTF: saved '" + _editingPresetDisplay + "'")
            ForcePageReset()
        else
            Debug.Notification("MTF: failed to save '" + _editingPresetDisplay + "'")
        endif
    endEvent
    event OnHighlightST()
        if _editingPresetName == ""
            SetInfoText("No preset is loaded. Use Save as... to create one.")
        else
            SetInfoText("Overwrite '" + _editingPresetDisplay + "' on disk with the current editor state.")
        endif
    endEvent
endState

; Save as: always creates a NEW preset. Refuses on filename collision —
; user must either pick a different name or use Save (which overwrites the
; loaded preset by its original name).
state PRESET_SAVE_AS
    event OnInputOpenST()
        SetInputDialogStartText("")
    endEvent
    event OnInputAcceptST(string a_input)
        if a_input == ""
            return
        endif
        string sanitized = MainQuest._sanitizePresetName(a_input)
        if sanitized == ""
            Debug.Notification("MTF: invalid preset name")
            return
        endif
        _refreshPresetNames()
        if _findPresetIndex(sanitized) >= 0
            Debug.Notification("MTF: '" + a_input + "' already exists — use Save, or pick another name")
            return
        endif
        if MainQuest.SavePreset(a_input)
            _setEditing(sanitized, a_input)
            Debug.Notification("MTF: saved as '" + a_input + "'")
            ForcePageReset()
        else
            Debug.Notification("MTF: failed to save '" + a_input + "'")
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Save as a NEW preset (letters/digits/_/-, max 32 chars). Fails on existing names — use Save to overwrite the loaded preset.")
    endEvent
endState

; Load picker — confirm is baked into each menu option label so a single
; click both confirms intent and triggers the load.
state PRESET_PICK
    event OnMenuOpenST()
        _refreshPresetNames()
        if _scratchPresetCount == 0
            string[] empty = new string[1]
            empty[0] = "(no presets)"
            SetMenuDialogOptions(empty)
            SetMenuDialogStartIndex(0)
            SetMenuDialogDefaultIndex(0)
            return
        endif
        int total = _scratchPresetCount + 1
        string[] opts = Utility.CreateStringArray(total, "")
        opts[0] = "Cancel"
        bool hasLoaded = (_editingPresetName != "")
        int i = 0
        while i < _scratchPresetCount
            string disp = MainQuest.GetPresetDisplayName(_scratchPresetNames[i])
            if hasLoaded
                opts[i + 1] = "Discard '" + _editingPresetDisplay + "' and load '" + disp + "'"
            else
                opts[i + 1] = "Load '" + disp + "'"
            endif
            i += 1
        endwhile
        SetMenuDialogOptions(opts)
        SetMenuDialogStartIndex(0)
        SetMenuDialogDefaultIndex(0)
    endEvent
    event OnMenuAcceptST(int a_index)
        if a_index <= 0
            return
        endif
        int idx = a_index - 1
        if idx >= _scratchPresetCount
            return
        endif
        string nm = _scratchPresetNames[idx]
        _selectedPresetIdx = idx
        if _doLoadPreset(nm)
            Debug.Notification("MTF: loaded '" + MainQuest.GetPresetDisplayName(nm) + "'")
        else
            Debug.Notification("MTF: failed to load '" + nm + "'")
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Pick a preset to load it into the editor. Current edits are replaced — Save first to keep them. Spell-applied presets stack above this base and are unaffected.")
    endEvent
endState

; Delete picker — confirm baked into each menu option label. Deleting the
; preset currently being edited clears the Editing status.
state PRESET_DEL
    event OnMenuOpenST()
        _refreshPresetNames()
        if _scratchPresetCount == 0
            string[] empty = new string[1]
            empty[0] = "(no presets to delete)"
            SetMenuDialogOptions(empty)
            SetMenuDialogStartIndex(0)
            SetMenuDialogDefaultIndex(0)
            return
        endif
        int total = _scratchPresetCount + 1
        string[] opts = Utility.CreateStringArray(total, "")
        opts[0] = "Cancel"
        int i = 0
        while i < _scratchPresetCount
            opts[i + 1] = "Delete '" + MainQuest.GetPresetDisplayName(_scratchPresetNames[i]) + "'"
            i += 1
        endwhile
        SetMenuDialogOptions(opts)
        SetMenuDialogStartIndex(0)
        SetMenuDialogDefaultIndex(0)
    endEvent
    event OnMenuAcceptST(int a_index)
        if a_index <= 0
            return
        endif
        int idx = a_index - 1
        if idx >= _scratchPresetCount
            return
        endif
        string nm = _scratchPresetNames[idx]
        string disp = MainQuest.GetPresetDisplayName(nm)
        if MainQuest.DeletePreset(nm)
            Debug.Notification("MTF: deleted '" + disp + "'")
            if nm == _editingPresetName
                _clearEditing()
            endif
            _selectedPresetIdx = -1
            ForcePageReset()
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Permanently delete a preset's JSON file. Editor state and spell-applied presets are unaffected.")
    endEvent
endState

; New preset — clears all slot/layer/effect/cooldown content and resets
; transition duration to 1.0s. Confirm baked into the second menu option.
state PRESET_NEW
    event OnMenuOpenST()
        string[] opts = Utility.CreateStringArray(2, "")
        opts[0] = "Cancel"
        if _editingPresetName == ""
            opts[1] = "Create new empty preset"
        else
            opts[1] = "Discard '" + _editingPresetDisplay + "' and create new"
        endif
        SetMenuDialogOptions(opts)
        SetMenuDialogStartIndex(0)
        SetMenuDialogDefaultIndex(0)
    endEvent
    event OnMenuAcceptST(int a_index)
        if a_index != 1
            return
        endif
        MainQuest.ResetEditor()
        _clearEditing()
        ForcePageReset()
        Debug.Notification("MTF: new empty preset")
    endEvent
    event OnHighlightST()
        SetInfoText("Clear all slot definitions, layers, effects, and transition duration to defaults. Use Save as... to commit the new preset to disk.")
    endEvent
endState

; ═════════════════════════════════════════════════════════════════════════════
; SUBJECTS PAGE (v0.0.33)
; ═════════════════════════════════════════════════════════════════════════════
; Header: hotkey, default-preset dropdown.
; Body:   paginated list of tracked actors. Each row is ONE menu option;
;         clicking opens a combined picker [<preset1>, ..., <presetN>, —,
;         Remove subject, Cancel]. The "—" item is a separator and isn't
;         selectable in practice — picking it falls through as Cancel.
; Footer: clear-all + counter.

int Function SUBJECTS_PAGE_SIZE() global
    return 16
EndFunction

int _subjectsPage = 0
int _currentSubjectAbsIdx = -1   ; absolute idx into the tracked list

Function _refreshSubjectPresets()
{Subjects originally cached its own preset list (_scratchPresetNames / _scratchPresetCount),
 but `MainQuest.ListPresets()` returns None when called from inside this script's
 state event handlers (Papyrus cross-script array-return quirk; same call works
 fine from drawGeneralPage). Workaround: delegate to General's _refreshPresetNames
 and use its _scratchPresetNames / _scratchPresetCount, which are populated from
 the same source but via a code path that doesn't hit the bug.}
    _refreshPresetNames()
EndFunction

function drawSubjectsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    int total = MainQuest.GetTrackedCount()
    int pageSize = SUBJECTS_PAGE_SIZE()
    int maxPage = 0
    if total > 0
        maxPage = (total - 1) / pageSize
    endif
    if _subjectsPage > maxPage
        _subjectsPage = maxPage
    endif
    if _subjectsPage < 0
        _subjectsPage = 0
    endif

    ; ── Left column: header + tracked actor rows (read-only) ───────────────
    ; Tattoo application is spell-only now. This page is for inspection +
    ; cleanup; clicking a row offers Remove only.
    AddHeaderOption("Subjects (" + total + ")")
    AddTextOption("Apply tattoos via the Apply Tattoo spell on the target.", "", OPTION_FLAG_DISABLED)

    int firstFlag = OPTION_FLAG_NONE
    int lastFlag  = OPTION_FLAG_NONE
    if _subjectsPage == 0
        firstFlag = OPTION_FLAG_DISABLED
    endif
    if _subjectsPage >= maxPage
        lastFlag = OPTION_FLAG_DISABLED
    endif
    AddTextOptionST("SUBJ_PAGE_PREV", "  ← Previous page", "(page " + (_subjectsPage + 1) + " of " + (maxPage + 1) + ")", firstFlag)
    AddTextOptionST("SUBJ_PAGE_NEXT", "  Next page →", "", lastFlag)

    int rowStart = _subjectsPage * pageSize
    int r = 0
    while r < pageSize
        int absIdx = rowStart + r
        if absIdx >= total
            AddEmptyOption()
        else
            Actor a = MainQuest.GetTrackedAt(absIdx)
            string label
            string val
            if a == None
                label = "<stale subject>"
                val = "[click: remove]"
            else
                string nm = a.GetDisplayName()
                if nm == ""
                    nm = "Actor 0x" + a.GetFormID()
                endif
                int pCount = MainQuest.GetActorPresetCount(a)
                string summary = ""
                int pi = 0
                while pi < pCount && pi < 3
                    string nm2 = MainQuest.GetActorPresetAt(a, pi)
                    if pi > 0
                        summary += ", "
                    endif
                    summary += MainQuest.GetPresetDisplayName(nm2)
                    pi += 1
                endwhile
                if pCount > 3
                    summary += ", +" + (pCount - 3)
                endif
                if pCount == 0
                    summary = "(none)"
                endif
                label = nm
                val = "[" + pCount + "] " + summary
            endif
            AddTextOptionST(_subjectRowStateId(r), label, val)
        endif
        r += 1
    endwhile

    ; ── Right column: bulk + counter info ──────────────────────────────────
    SetCursorPosition(1)
    AddHeaderOption("Bulk")
    int clearFlag = OPTION_FLAG_NONE
    if total == 0
        clearFlag = OPTION_FLAG_DISABLED
    endif
    AddTextOptionST("SUBJ_CLEAR_ALL", "Clear all subjects", "(" + total + ")", clearFlag)
endFunction

string Function _subjectRowStateId(int row)
    return "SUBJ_ROW_" + row
EndFunction

int Function _subjectRowIdxFromState(string st)
    if StringUtil.Find(st, "SUBJ_ROW_") != 0
        return -1
    endif
    string tail = StringUtil.Substring(st, 9, StringUtil.GetLength(st) - 9)
    return tail as int
EndFunction

Function _subjectRowSelect()
    int row = _subjectRowIdxFromState(GetState())
    if row < 0
        return
    endif
    int abs = _subjectsPage * SUBJECTS_PAGE_SIZE() + row
    if abs >= MainQuest.GetTrackedCount()
        return
    endif
    _currentSubjectAbsIdx = abs
    ; Multi-preset apply/remove lives on the spell now. This page only
    ; offers full-subject removal as a cleanup option.
    string[] opts = Utility.CreateStringArray(2)
    opts[0] = "Remove subject"
    opts[1] = "Cancel"
    SetMenuDialogOptions(opts)
    SetMenuDialogDefaultIndex(1)
EndFunction

Function _subjectRowAccept(int index)
    if _currentSubjectAbsIdx < 0
        return
    endif
    Actor a = MainQuest.GetTrackedAt(_currentSubjectAbsIdx)
    if index == 0
        if a != None
            MainQuest.RemoveTrackedActor(a)
        else
            StorageUtil.FormListRemoveAt(MainQuest, "mtf.tracked", _currentSubjectAbsIdx)
        endif
        ForcePageReset()
    endif
    _currentSubjectAbsIdx = -1
EndFunction

Function _subjectRowHighlight()
    int row = _subjectRowIdxFromState(GetState())
    int abs = _subjectsPage * SUBJECTS_PAGE_SIZE() + row
    if abs >= MainQuest.GetTrackedCount()
        SetInfoText("")
        return
    endif
    Actor a = MainQuest.GetTrackedAt(abs)
    if a == None
        SetInfoText("Stale subject reference — click to clean up.")
        return
    endif
    int pCount = MainQuest.GetActorPresetCount(a)
    SetInfoText("Click to remove this subject (untracks + clears all overlays). " + pCount + " preset(s) applied. Use the Apply Tattoo spell to add or remove individual presets.")
EndFunction

state SUBJ_PAGE_PREV
    event OnSelectST()
        if _subjectsPage > 0
            _subjectsPage -= 1
            ForcePageReset()
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Previous page of tracked subjects.")
    endEvent
endState

state SUBJ_PAGE_NEXT
    event OnSelectST()
        int total = MainQuest.GetTrackedCount()
        int maxPage = 0
        if total > 0
            maxPage = (total - 1) / SUBJECTS_PAGE_SIZE()
        endif
        if _subjectsPage < maxPage
            _subjectsPage += 1
            ForcePageReset()
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Next page of tracked subjects.")
    endEvent
endState

state SUBJ_CLEAR_ALL
    event OnSelectST()
        if MainQuest.GetTrackedCount() == 0
            return
        endif
        string[] opts = Utility.CreateStringArray(2)
        opts[0] = "Yes, clear all"
        opts[1] = "Cancel"
        SetMenuDialogOptions(opts)
        SetMenuDialogDefaultIndex(1)
    endEvent
    event OnMenuAcceptST(int index)
        if index == 0
            MainQuest.ClearAllTrackedActors()
            ForcePageReset()
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Remove every tracked subject and clear their overlays.")
    endEvent
endState

; ── Per-row states (16 of them) — all delegate to the dispatchers above ─────
state SUBJ_ROW_0
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_1
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_2
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_3
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_4
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_5
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_6
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_7
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_8
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_9
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_10
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_11
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_12
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_13
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_14
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
state SUBJ_ROW_15
    event OnSelectST()
        _subjectRowSelect()
    endEvent
    event OnMenuAcceptST(int index)
        _subjectRowAccept(index)
    endEvent
    event OnHighlightST()
        _subjectRowHighlight()
    endEvent
endState
