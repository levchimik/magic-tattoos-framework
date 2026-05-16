Scriptname SKI_ConfigBase extends SKI_QuestBase

int Property OPTION_FLAG_NONE      = 0x00 autoReadOnly
int Property OPTION_FLAG_DISABLED  = 0x04 autoReadOnly
int Property OPTION_FLAG_HIDDEN    = 0x08 autoReadOnly
int Property LEFT_TO_RIGHT         = 0    autoReadOnly
int Property TOP_TO_BOTTOM         = 1    autoReadOnly

string Property ModName auto
string[] Property Pages auto

int Function GetVersion()
    return 0
EndFunction

Event OnConfigInit()
EndEvent

Event OnVersionUpdate(int a_version)
EndEvent

Event OnPageReset(string a_page)
EndEvent

Function SetCursorFillMode(int a_fillMode)
EndFunction

Function SetCursorPosition(int a_position)
EndFunction

int Function AddHeaderOption(string a_text, int a_flags = 0)
    return 0
EndFunction

int Function AddTextOption(string a_text, string a_value, int a_flags = 0)
    return 0
EndFunction

int Function AddToggleOptionST(string a_stateName, string a_text, bool a_checked, int a_flags = 0)
    return 0
EndFunction

int Function AddSliderOptionST(string a_stateName, string a_text, float a_value, string a_formatString = "{0}", int a_flags = 0)
    return 0
EndFunction

int Function AddMenuOptionST(string a_stateName, string a_text, string a_value, int a_flags = 0)
    return 0
EndFunction

int Function AddColorOptionST(string a_stateName, string a_text, int a_color, int a_flags = 0)
    return 0
EndFunction

int Function AddInputOptionST(string a_stateName, string a_text, string a_value, int a_flags = 0)
    return 0
EndFunction

int Function AddTextOptionST(string a_stateName, string a_text, string a_value, int a_flags = 0)
    return 0
EndFunction

Function SetTextOptionValueST(string a_value, bool a_noUpdate = false, string a_stateName = "")
EndFunction

Function SetInputOptionValueST(string a_value, bool a_noUpdate = false, string a_stateName = "")
EndFunction

Function SetInputDialogStartText(string a_text)
EndFunction

Function SetToggleOptionValueST(bool a_checked, bool a_noUpdate = false, string a_stateName = "")
EndFunction

Function SetSliderOptionValueST(float a_value, string a_formatString = "{0}", bool a_noUpdate = false, string a_stateName = "")
EndFunction

Function SetMenuOptionValueST(string a_value, bool a_noUpdate = false, string a_stateName = "")
EndFunction

Function SetColorOptionValueST(int a_color, bool a_noUpdate = false, string a_stateName = "")
EndFunction

Function SetSliderDialogStartValue(float a_value)
EndFunction

Function SetSliderDialogDefaultValue(float a_value)
EndFunction

Function SetSliderDialogRange(float a_min, float a_max)
EndFunction

Function SetSliderDialogInterval(float a_interval)
EndFunction

Function SetMenuDialogStartIndex(int a_index)
EndFunction

Function SetMenuDialogDefaultIndex(int a_index)
EndFunction

Function SetMenuDialogOptions(string[] a_options)
EndFunction

Function SetColorDialogStartColor(int a_color)
EndFunction

Function SetColorDialogDefaultColor(int a_color)
EndFunction

Function SetInfoText(string a_text)
EndFunction

Function ForcePageReset()
EndFunction

; State-tagged event stubs — must exist in empty state so subclasses can override in named states
Event OnHighlightST()
EndEvent

Event OnDefaultST()
EndEvent

Event OnSelectST()
EndEvent

Event OnSliderOpenST()
EndEvent

Event OnSliderAcceptST(float a_value)
EndEvent

Event OnMenuOpenST()
EndEvent

Event OnMenuAcceptST(int a_index)
EndEvent

Event OnColorOpenST()
EndEvent

Event OnColorAcceptST(int a_color)
EndEvent

Event OnInputOpenST()
EndEvent

Event OnInputAcceptST(string a_input)
EndEvent

Event OnHighlightST()
EndEvent
