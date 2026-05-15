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
    return 6
EndFunction

string Function _slotLabel(int idx)
    if idx == 0
        return "Default"
    endif
    return "Condition " + idx
endFunction

string Function _condTypeLabel(string pid)
    if pid == "" || MainQuest == None
        return "Not set"
    endif
    sd_LME_ConditionPlugin p = MainQuest.FindPlugin(pid)
    if p == None
        return "Unknown (" + pid + ")"
    endif
    return p.GetLabel()
endFunction

event OnConfigInit()
    ModName = "LewdMarks Effects"
    Pages = new String[2]
    Pages[0] = "General"
    Pages[1] = "Conditions"
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
        MainQuest.condIncreaseExposure = new int[8]
        MainQuest.condManaSiphonPct    = new int[8]

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
    if CurrentVersion < 5
        ; v0.0.4: add Mana Siphon side-effect array.
        ; Allocate unconditionally — None-check on array properties is unreliable
        ; (silent cast errors), and any prior allocation is by definition empty/unused.
        MainQuest.condManaSiphonPct  = new int[8]
        MainQuest.condCarryWeightPct = new int[8]
        MainQuest.condSneakPct       = new int[8]
    endif
    if CurrentVersion < 6
        ; v0.0.5: Pheromone Aura
        MainQuest.condPheromoneAura = new int[8]
        MainQuest.pheromoneRadius    = 1500.0
        MainQuest.pheromoneMaxTargets = 32
    endif
endEvent

; ── Page rendering ────────────────────────────────────────────────────────────
event OnPageReset(string page)
    _ensureMainQuest()
    if page == "General"
        drawGeneralPage()
    elseIf page == "Conditions"
        drawConditionsPage()
    endif
endEvent

function drawGeneralPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("General")
    AddToggleOptionST("GEN_MOD_ACTIVE",      "Enable",                MainQuest.ModActive)
    AddSliderOptionST("GEN_UPDATE_INTERVAL", "Update interval (sec)", MainQuest.updateInterval, "{1}")
    AddToggleOptionST("GEN_USE_SLAVETATS",   "Use SlaveTats textures", MainQuest.useSlaveTats)
    AddToggleOptionST("GEN_DEBUG_MODE",      "Debug mode",             MainQuest.DebugMode)
    AddSliderOptionST("GEN_PHEROMONE_RADIUS","Pheromone radius",       MainQuest.pheromoneRadius, "{0}")
    AddHeaderOption("Registered plugins (" + MainQuest.pluginCount + ")")
    int i = 0
    while i < MainQuest.pluginCount
        sd_LME_ConditionPlugin p = MainQuest.GetPluginAt(i)
        if p != None
            AddTextOption(p.GetLabel(), p.GetPluginId(), OPTION_FLAG_DISABLED)
        endif
        i += 1
    endwhile
endFunction

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
        string pid = MainQuest.condPluginId[idx]
        sd_LME_ConditionPlugin p = None
        if pid != ""
            p = MainQuest.FindPlugin(pid)
        endif

        AddMenuOptionST("COND_SELECTOR", "Configure slot", _slotLabel(selectedCondition))
        AddMenuOptionST("SLOT_COND_TYPE", "Condition type", _condTypeLabel(pid))
        AddHeaderOption("Condition " + idx)

        if p != None
            string paramLabel = p.GetParamLabel()
            if paramLabel != ""
                AddSliderOptionST("SLOT_COND_PARAM", paramLabel, MainQuest.condParam[idx])
            else
                AddTextOption(p.GetLabel(), "(no parameter)", OPTION_FLAG_DISABLED)
            endif
        endif

        AddSliderOptionST("SLOT_TEXTURE_NUM", "Texture (0 = Default)", MainQuest.condTextureNum[idx])
        AddToggleOptionST("SLOT_USE_GLOW",    "Use glow",               MainQuest.condUseGlow[idx])
    endif

    AddHeaderOption("Side Effects")
    AddSliderOptionST("SLOT_INCREASE_EXPOSURE", "Arousal exposure per hour", MainQuest.condIncreaseExposure[idx])
    AddSliderOptionST("SLOT_PHEROMONE_AURA",    "Pheromone aura per hour",   MainQuest.condPheromoneAura[idx])
    AddSliderOptionST("SLOT_MANA_SIPHON",        "Mana siphon",         MainQuest.condManaSiphonPct[idx],  "{0}%")
    AddSliderOptionST("SLOT_CARRY_WEIGHT_PEN",   "Carry weight penalty", MainQuest.condCarryWeightPct[idx], "{0}%")
    AddSliderOptionST("SLOT_SNEAK_PEN",          "Sneak penalty",        MainQuest.condSneakPct[idx],       "{0}%")

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

state GEN_PHEROMONE_RADIUS
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.pheromoneRadius)
        SetSliderDialogDefaultValue(1500)
        SetSliderDialogRange(100, 6000)
        SetSliderDialogInterval(50)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.pheromoneRadius = value
        SetSliderOptionValueST(value, "{0}")
    endEvent
    event OnDefaultST()
        MainQuest.pheromoneRadius = 1500.0
        SetSliderOptionValueST(1500.0, "{0}")
    endEvent
    event OnHighlightST()
        SetInfoText("Maximum distance (game units, ~70 = 1m) at which the Pheromone Aura affects NPCs. Default 1500 (~22m). Max 6000 matches high-process actor range.")
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
        SetInfoText("Base NiOverride overlay slot. Two consecutive slots are used: this slot (halo) and slot+1 (mark). Avoid conflicts with other overlay mods.")
    endEvent
endState

state SLOT_COND_TYPE
    event OnMenuOpenST()
        ; Index 0 = "Not set"; indices 1..N map to MainQuest.GetPluginAt(i-1).
        ; OnMenuAcceptST re-derives the mapping live (no cached array — Papyrus
        ; script-level vars don't survive the dialog open→accept gap reliably).
        int total = 1 + MainQuest.pluginCount
        if total > 10
            total = 10
        endif
        string[] opts = _newOpts(total)
        opts[0] = "Not set"
        int curIdx = 0
        string curPid = MainQuest.condPluginId[selectedCondition]
        int i = 0
        while i < MainQuest.pluginCount && (i + 1) < total
            sd_LME_ConditionPlugin p = MainQuest.GetPluginAt(i)
            if p != None
                opts[i + 1] = p.GetLabel()
                if p.GetPluginId() == curPid
                    curIdx = i + 1
                endif
            else
                opts[i + 1] = "(missing)"
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
        string newPid = ""
        if index > 0
            sd_LME_ConditionPlugin p = MainQuest.GetPluginAt(index - 1)
            if p != None
                newPid = p.GetPluginId()
            endif
        endif
        MainQuest.condPluginId[slot] = newPid
        if newPid == ""
            MainQuest.condParam[slot] = 0
        else
            sd_LME_ConditionPlugin p = MainQuest.FindPlugin(newPid)
            if p != None
                MainQuest.condParam[slot] = p.GetParamDefault()
            endif
        endif
        SetMenuOptionValueST(_condTypeLabel(newPid))
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
        sd_LME_ConditionPlugin p = MainQuest.FindPlugin(MainQuest.condPluginId[selectedCondition])
        if p == None
            return
        endif
        SetSliderDialogStartValue(MainQuest.condParam[selectedCondition])
        SetSliderDialogDefaultValue(p.GetParamDefault())
        SetSliderDialogRange(p.GetParamMin(), p.GetParamMax())
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condParam[selectedCondition] = value as int
        SetSliderOptionValueST(value as int)
    endEvent
    event OnDefaultST()
        sd_LME_ConditionPlugin p = MainQuest.FindPlugin(MainQuest.condPluginId[selectedCondition])
        int defVal = 0
        if p != None
            defVal = p.GetParamDefault()
        endif
        MainQuest.condParam[selectedCondition] = defVal
        SetSliderOptionValueST(defVal)
    endEvent
    event OnHighlightST()
        sd_LME_ConditionPlugin p = MainQuest.FindPlugin(MainQuest.condPluginId[selectedCondition])
        if p != None
            SetInfoText(p.GetParamLabel())
        else
            SetInfoText("Threshold value for the selected condition.")
        endif
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

state SLOT_MANA_SIPHON
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condManaSiphonPct[selectedCondition])
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condManaSiphonPct[selectedCondition] = value as int
        SetSliderOptionValueST(value as int, "{0}%")
    endEvent
    event OnDefaultST()
        MainQuest.condManaSiphonPct[selectedCondition] = 0
        SetSliderOptionValueST(0, "{0}%")
    endEvent
    event OnHighlightST()
        SetInfoText("Drain this percentage of your current Magicka regeneration rate (including enchantments) while this slot is active. Recomputes every update tick so gear/buff changes apply immediately. 0 = disabled.")
    endEvent
endState

state SLOT_PHEROMONE_AURA
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condPheromoneAura[selectedCondition])
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condPheromoneAura[selectedCondition] = value as int
        SetSliderOptionValueST(value as int)
    endEvent
    event OnDefaultST()
        MainQuest.condPheromoneAura[selectedCondition] = 0
        SetSliderOptionValueST(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Increase arousal exposure on each nearby NPC by this amount every game hour while this slot is active. Radius is set on the General page. 0 = disabled.")
    endEvent
endState

state SLOT_CARRY_WEIGHT_PEN
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condCarryWeightPct[selectedCondition])
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condCarryWeightPct[selectedCondition] = value as int
        SetSliderOptionValueST(value as int, "{0}%")
    endEvent
    event OnDefaultST()
        MainQuest.condCarryWeightPct[selectedCondition] = 0
        SetSliderOptionValueST(0, "{0}%")
    endEvent
    event OnHighlightST()
        SetInfoText("Reduce your current Carry Weight by this percentage while this slot is active. Recomputes every update tick.")
    endEvent
endState

state SLOT_SNEAK_PEN
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condSneakPct[selectedCondition])
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condSneakPct[selectedCondition] = value as int
        SetSliderOptionValueST(value as int, "{0}%")
    endEvent
    event OnDefaultST()
        MainQuest.condSneakPct[selectedCondition] = 0
        SetSliderOptionValueST(0, "{0}%")
    endEvent
    event OnHighlightST()
        SetInfoText("Reduce your current Sneak skill by this percentage while this slot is active. Recomputes every update tick.")
    endEvent
endState

state SLOT_INCREASE_EXPOSURE
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.condIncreaseExposure[selectedCondition])
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condIncreaseExposure[selectedCondition] = value as int
        SetSliderOptionValueST(value as int)
    endEvent
    event OnDefaultST()
        MainQuest.condIncreaseExposure[selectedCondition] = 0
        SetSliderOptionValueST(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Passively increase arousal exposure by this amount every game hour while this slot is active. 0 = disabled.")
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
