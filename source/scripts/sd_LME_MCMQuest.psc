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
    return 3
EndFunction

string Function _slotLabel(int idx)
    if idx == 0
        return "Default"
    endif
    return "Condition " + idx
endFunction

string Function _condTypeLabel(int idx)
    if idx == 1
        return "Arousal"
    elseif idx == 2
        return "Pregnancy (FMR)"
    elseif idx == 3
        return "Magicka"
    elseif idx == 4
        return "Magic Effects"
    elseif idx == 5
        return "Ovulation (FMR)"
    endif
    return "Not set"
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
endFunction

event OnVersionUpdate(int Version)
    if MainQuest == None
        return
    endif
    if CurrentVersion < 1
        MainQuest.condType             = new int[8]
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

        MainQuest.ModActive          = false
        MainQuest.updateInterval     = 2.0
        MainQuest.OverlaySlot        = 2
        MainQuest.CurrentOverlaySlot = 2

        ; Default slot (index 0) — base appearance, no glow
        MainQuest.condTextureNum[0] = 3
        MainQuest.condMarkAlpha[0]  = 100
        MainQuest.condMarkTint[0]   = 16777215
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
    if CurrentVersion < 3
        ; Backfill tint/emissive for slot 0 (was missed in v1 init)
        if MainQuest.condMarkTint != None && MainQuest.condMarkTint[0] == 0
            MainQuest.condMarkTint[0] = 16777215
        endif
        if MainQuest.condMarkEmissive != None && MainQuest.condMarkEmissive[0] == 0
            MainQuest.condMarkEmissive[0] = 16777215
        endif
        MainQuest.setRedraw()
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
        AddMenuOptionST("COND_SELECTOR", "Configure slot", _slotLabel(selectedCondition))
        AddMenuOptionST("SLOT_COND_TYPE", "Condition type", _condTypeLabel(MainQuest.condType[idx]))
        AddHeaderOption("Condition " + idx)

        int cType = MainQuest.condType[idx]
        if cType == 1
            AddSliderOptionST("SLOT_COND_PARAM", "Arousal threshold",      MainQuest.condParam[idx])
        elseIf cType == 2
            AddSliderOptionST("SLOT_COND_PARAM", "Min belly stage (1-100)", MainQuest.condParam[idx])
        elseIf cType == 3
            AddSliderOptionST("SLOT_COND_PARAM", "Magicka % threshold",    MainQuest.condParam[idx])
        elseIf cType == 5
            AddTextOption("Ovulation phase", "Active when FMR rank = 118", OPTION_FLAG_DISABLED)
        elseIf cType == 4
            int fxCount = 0
            if MainQuest.cond_magicfx_effects != None
                fxCount = MainQuest.cond_magicfx_effects.Length
            endif
            AddTextOption("Configured effects", fxCount as string, OPTION_FLAG_DISABLED)
        endif

        AddSliderOptionST("SLOT_TEXTURE_NUM", "Texture (0 = Default)", MainQuest.condTextureNum[idx])
        AddToggleOptionST("SLOT_USE_GLOW",    "Use glow",               MainQuest.condUseGlow[idx])
    endif

    AddHeaderOption("Side Effects")
    AddSliderOptionST("SLOT_INCREASE_EXPOSURE", "Arousal exposure per hour", MainQuest.condIncreaseExposure[idx])

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
        string[] opts = new string[6]
        opts[0] = "Not set"
        opts[1] = "Arousal"
        opts[2] = "Pregnancy (FMR)"
        opts[3] = "Magicka"
        opts[4] = "Magic Effects"
        opts[5] = "Ovulation (FMR)"
        int curType = 0
        if MainQuest != None
            curType = MainQuest.condType[selectedCondition]
        endif
        SetMenuDialogStartIndex(curType)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index < 0
            return
        endif
        int idx = selectedCondition
        if MainQuest != None
            MainQuest.condType[idx] = index
            if index == 1
                MainQuest.condParam[idx] = 70
            elseIf index == 2
                MainQuest.condParam[idx] = 1
            elseIf index == 3
                MainQuest.condParam[idx] = 100
            else
                MainQuest.condParam[idx] = 0
            endif
        endif
        SetMenuOptionValueST(_condTypeLabel(index))
        ForcePageReset()
    endEvent
    event OnDefaultST()
        if MainQuest != None
            MainQuest.condType[selectedCondition]  = 0
            MainQuest.condParam[selectedCondition] = 0
        endif
        SetMenuOptionValueST(_condTypeLabel(0))
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Which condition must be satisfied for this slot to activate.")
    endEvent
endState

state SLOT_COND_PARAM
    event OnSliderOpenST()
        int idx = selectedCondition
        int cType = MainQuest.condType[idx]
        SetSliderDialogStartValue(MainQuest.condParam[idx])
        SetSliderDialogInterval(1)
        if cType == 1
            SetSliderDialogDefaultValue(70)
            SetSliderDialogRange(0, 100)
        elseIf cType == 2
            SetSliderDialogDefaultValue(1)
            SetSliderDialogRange(1, 100)
        elseIf cType == 3
            SetSliderDialogDefaultValue(100)
            SetSliderDialogRange(1, 100)
        endif
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.condParam[selectedCondition] = value as int
        SetSliderOptionValueST(value as int)
    endEvent
    event OnDefaultST()
        int cType = MainQuest.condType[selectedCondition]
        int defVal = 0
        if cType == 1
            defVal = 70
        elseIf cType == 2
            defVal = 1
        elseIf cType == 3
            defVal = 100
        endif
        MainQuest.condParam[selectedCondition] = defVal
        SetSliderOptionValueST(defVal)
    endEvent
    event OnHighlightST()
        int cType = MainQuest.condType[selectedCondition]
        if cType == 1
            SetInfoText("Arousal must be at or above this value (0-100).")
        elseIf cType == 2
            SetInfoText("Belly stage must be at or above this value. 1 = any pregnancy, 50 = mid-term, 100 = full term. Rank range 1-100 is pregnancy only; recovery (101-115) and cycle phases (116-119) are not checked.")
        elseIf cType == 3
            SetInfoText("Magicka must be at or above this percentage of maximum (1-100%).")
        elseIf cType == 5
            SetInfoText("No threshold — active only during the ovulation cycle phase (FMR rank 118).")
        else
            SetInfoText("Threshold value for the selected condition type.")
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
            SetColorDialogDefaultColor(0)
        endif
    endEvent
    event OnColorAcceptST(int color)
        MainQuest.condMarkTint[selectedCondition] = color
        SetColorOptionValueST(color)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        int defVal = 0
        if selectedCondition > 0
            defVal = 16777215
        endif
        MainQuest.condMarkTint[selectedCondition] = defVal
        SetColorOptionValueST(defVal)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color applied to the mark texture.")
    endEvent
endState

state SLOT_MARK_EMISSIVE
    event OnColorOpenST()
        SetColorDialogStartColor(MainQuest.condMarkEmissive[selectedCondition])
        if selectedCondition > 0
            SetColorDialogDefaultColor(16777215)
        else
            SetColorDialogDefaultColor(0)
        endif
    endEvent
    event OnColorAcceptST(int color)
        MainQuest.condMarkEmissive[selectedCondition] = color
        SetColorOptionValueST(color)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        int defVal = 0
        if selectedCondition > 0
            defVal = 16777215
        endif
        MainQuest.condMarkEmissive[selectedCondition] = defVal
        SetColorOptionValueST(defVal)
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
function toggleTextureSet(bool useST)
    if useST
        MainQuest.texturePathNormal = texturePathNormalST
        MainQuest.texturePathGlow   = texturePathGlowST
    else
        MainQuest.texturePathNormal = texturePathNormalRM
        MainQuest.texturePathGlow   = texturePathGlowRM
    endif
endFunction
