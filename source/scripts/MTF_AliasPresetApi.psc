Scriptname MTF_AliasPresetApi extends ReferenceAlias
{Receives MTF_ApplyPreset / MTF_RemovePreset / MTF_RemoveAllPresets mod
 events from external mods and forwards them into MTF_MainQuest's
 Api* dispatch functions. Quest scripts can't RegisterForModEvent
 (the native is on Alias/AMF, not Form/Quest), so the listener lives
 here on a ReferenceAlias filled with PlayerRef.

 Caprica forbids non-native scripts from declaring new Event types, so the
 callback handlers are plain Functions. SKSE's mod-event dispatcher accepts
 either Event or Function as the callback name.

 Same defensive re-register pattern as MTF_AliasSkyrimNet: queued OnInit
 resumptions can be dropped after a .pex rebuild mid-save, so we
 re-register on OnPlayerLoadGame too.}

Event OnInit()
    _registerAll()
EndEvent

Event OnPlayerLoadGame()
    _registerAll()
EndEvent

Function _registerAll()
    RegisterForModEvent("MTF_ApplyPreset",      "OnApplyPresetEvent")
    RegisterForModEvent("MTF_RemovePreset",     "OnRemovePresetEvent")
    RegisterForModEvent("MTF_RemoveAllPresets", "OnRemoveAllPresetsEvent")
EndFunction

Function OnApplyPresetEvent(string strArg, float numArg, Form sender)
    ; strArg = preset internal name; sender = target Actor (or None → player)
    MTF_MainQuest host = GetOwningQuest() as MTF_MainQuest
    if host == None
        return
    endif
    Actor target = sender as Actor
    host.ApiApplyPreset(target, strArg)
EndFunction

Function OnRemovePresetEvent(string strArg, float numArg, Form sender)
    MTF_MainQuest host = GetOwningQuest() as MTF_MainQuest
    if host == None
        return
    endif
    Actor target = sender as Actor
    host.ApiRemovePreset(target, strArg)
EndFunction

Function OnRemoveAllPresetsEvent(string strArg, float numArg, Form sender)
    MTF_MainQuest host = GetOwningQuest() as MTF_MainQuest
    if host == None
        return
    endif
    Actor target = sender as Actor
    host.ApiRemoveAllPresets(target)
EndFunction
