Scriptname MTF_AliasSkyrimNet extends ReferenceAlias
{Receives MTF_TierChanged mod events on behalf of the SkyrimNet bridge
 plugin's owning Quest and forwards them via HandleTierChange. Same
 architectural reason as MTF_PluginAliasKick: RegisterForModEvent is on
 Alias/AMF (not Form/Quest), and Caprica forbids non-native scripts from
 declaring new Event types, so mod-event callbacks must be plain
 Functions hosted on a ReferenceAlias.

 The plugin's host alias is filled with PlayerRef, so this event always
 fires for us regardless of cell load state.}

Event OnInit()
    RegisterForModEvent("MTF_TierChanged", "OnMTFTierChanged")
EndEvent

Event OnPlayerLoadGame()
    ; Re-register on every load (same defensive pattern as
    ; MTF_PluginAliasKick) — Papyrus's "function differs since save"
    ; quirk can drop queued OnInit resumptions after a .pex rebuild.
    RegisterForModEvent("MTF_TierChanged", "OnMTFTierChanged")
EndEvent

Function OnMTFTierChanged(string strArg, float numArg, Form sender)
    ; Function (not Event) — Caprica forbids non-native scripts from
    ; defining new Event types. SKSE's mod-event dispatcher accepts
    ; either keyword, so Function is the portable choice.
    ;
    ; Payload shape (matches MTF_MainQuest._emitTierChanged):
    ;   strArg = "<scope>|<presetName>|<prevTier>|<newTier>"
    ;   numArg = newTier as float
    ;   sender = the actor (PlayerRef or NPC)
    MTF_Plugin_SkyrimNet host = GetOwningQuest() as MTF_Plugin_SkyrimNet
    if host != None
        host.HandleTierChange(strArg, numArg, sender)
    endif
EndFunction
