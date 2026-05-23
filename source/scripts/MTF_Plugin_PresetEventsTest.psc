Scriptname MTF_Plugin_PresetEventsTest extends MTF_Plugin
{Test/verification plugin for the MTF preset event API.

 The API itself (MTF_ApplyPreset / MTF_RemovePreset / MTF_RemoveAllPresets
 inbound, MTF_ApplyPresetResult / MTF_RemovePresetResult /
 MTF_RemoveAllPresetsResult outbound) lives in the main mod — see the
 PRESET EVENT API section at the bottom of MTF_MainQuest.psc.

 This plugin contributes nothing to the framework's MCM (zero conditions,
 zero effects, zero settings) — it exists purely so a tester can verify
 the API without depending on SkyrimNet or any third-party integration.
 The actual test surface is a self-cast spell shipped in this ESP whose
 ActiveMagicEffect (MTF_TestPresetApi_Effect) opens a UIListMenu and
 fires the corresponding mod event.

 Listens for the OUTBOUND result events too and forwards them to
 Debug.Notification, so the tester sees in-game toast confirmation that
 the round-trip worked. The notification listener registration goes on
 MTF_AliasPresetEventsTest (a ReferenceAlias filled with PlayerRef);
 Quest scripts can't RegisterForModEvent.}

; ── Identity ────────────────────────────────────────────────────────────────
string Function GetPluginId()
    return "mtf.presetEventsTest"
EndFunction

string Function GetPluginLabel()
    return "Preset Event API Test"
EndFunction

; ── No conditions, effects, or settings ─────────────────────────────────────
int Function GetConditionCount()
    return 0
EndFunction

int Function GetEffectCount()
    return 0
EndFunction

int Function GetSettingCount()
    return 0
EndFunction

; ── Outbound-result handler (invoked by MTF_AliasPresetEventsTest) ──────────
; Surface API confirmations as in-game toasts so the tester sees evidence
; the round-trip worked. The strArg/numArg shape comes from MainQuest's
; _apiEmit* helpers.

Function HandleApplyResult(string strArg, float numArg, Form sender)
    ; strArg = "<presetName>|<rc>"
    int pipe = StringUtil.Find(strArg, "|")
    string nm = strArg
    string rcStr = ""
    if pipe >= 0
        nm    = StringUtil.Substring(strArg, 0, pipe)
        rcStr = StringUtil.Substring(strArg, pipe + 1, 0)
    endif
    Debug.Notification("MTF.api: ApplyResult '" + nm + "' rc=" + rcStr)
EndFunction

Function HandleRemoveResult(string strArg, float numArg, Form sender)
    ; strArg = "<presetName>|<status>"
    int pipe = StringUtil.Find(strArg, "|")
    string nm = strArg
    string st = ""
    if pipe >= 0
        nm = StringUtil.Substring(strArg, 0, pipe)
        st = StringUtil.Substring(strArg, pipe + 1, 0)
    endif
    Debug.Notification("MTF.api: RemoveResult '" + nm + "' " + st)
EndFunction

Function HandleRemoveAllResult(string strArg, float numArg, Form sender)
    ; strArg = "<count>"
    Debug.Notification("MTF.api: RemoveAllResult count=" + strArg)
EndFunction
