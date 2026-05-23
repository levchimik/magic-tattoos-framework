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
    ; Re-run SkyrimNet API registration. SkyrimNet's C++ side resets its
    ; schema/decorator tables every game launch — without this call the
    ; bridge would silently lose its registration after the first session.
    ; _setupBridge ALSO re-seeds the player's StorageUtil bio string (see
    ; the bridge's storage-bypass architecture comment), so the bio is
    ; populated before any tier evaluation fires post-load.
    ; The bridge intentionally has no persistent _bridgeSetup guard so
    ; this re-poke isn't blocked.
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
    MTF_Plugin_SkyrimNet host = GetOwningQuest() as MTF_Plugin_SkyrimNet
    if host != None
        host.HandleTierChange(strArg, numArg, sender)
    else
        ; Kept as a Trace — only fires if the alias is orphaned from its
        ; owning Quest, which would be a deep bug in our ESP wiring.
        Debug.Trace("MTF.SkyrimNet alias: owning quest is None — event dropped")
    endif
EndFunction
