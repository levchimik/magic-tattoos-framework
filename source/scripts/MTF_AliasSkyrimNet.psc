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
    ; Also re-run SkyrimNet API registration. SkyrimNet's C++ side resets
    ; its decorator/schema tables every game launch — without this call
    ; the bridge silently loses its decorator after the first session and
    ; `mtf_active_tattoos(actorUUID)` returns nothing. Owning Quest's
    ; persistent _bridgeSetup guard (if any) would prevent the re-run, so
    ; the bridge plugin script intentionally has no such guard.
    MTF_Plugin_SkyrimNet owner = GetOwningQuest() as MTF_Plugin_SkyrimNet
    if owner != None
        owner._setupBridge()
    endif
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
    Debug.Trace("MTF.SkyrimNet alias: OnMTFTierChanged strArg=" + strArg + " numArg=" + numArg)
    MTF_Plugin_SkyrimNet host = GetOwningQuest() as MTF_Plugin_SkyrimNet
    if host != None
        host.HandleTierChange(strArg, numArg, sender)
    else
        Debug.Trace("MTF.SkyrimNet alias: owning quest is None — event dropped")
    endif
EndFunction
