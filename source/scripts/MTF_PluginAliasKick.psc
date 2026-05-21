Scriptname MTF_PluginAliasKick extends ReferenceAlias
{Receives MTF_PluginKick mod events on behalf of the owning Quest and
 forwards them to the plugin's `_tryRegister`. Solves the Papyrus
 "function differs since save" quirk that drops queued OnUpdate
 resumptions after a .pex rebuild mid-save — Quest scripts CAN'T
 RegisterForModEvent (the native is on Alias/AMF, not Form/Quest), so
 each plugin quest hosts a single ReferenceAlias filled with PlayerRef
 with this script attached.

 Mod events dispatch FRESH function calls, not queued resumptions, so
 even when OnUpdate's pending tick is dropped on load, the next kick
 from MainQuest's slow-tick will land here and re-arm registration.}

Event OnInit()
    RegisterForModEvent("MTF_PluginKick", "OnPluginKick")
EndEvent

Event OnPlayerLoadGame()
    ; Defensive: re-register on every load to survive the same
    ; "function differs" quirk affecting this script's own queued
    ; OnInit resumption. The alias is filled with PlayerRef so this
    ; event always fires for us on load.
    RegisterForModEvent("MTF_PluginKick", "OnPluginKick")
EndEvent

Function OnPluginKick()
    ; Function (not Event) — Caprica forbids non-native scripts from
    ; defining new events. SKSE's mod-event dispatcher accepts either.
    ; Zero args matches MainQuest's ModEvent.Create+Send with no pushes.
    MTF_Plugin owner = GetOwningQuest() as MTF_Plugin
    if owner != None
        owner._tryRegister()
    endif
EndFunction
