Scriptname MTF_CastListener extends ReferenceAlias
{Listens for spell-cast begin events on the player (forced reference) and
 polls Skyrim's animation variables to track whether a cast is still being
 held. Drives the combat.casting condition + the flash.oncast effect's
 retrigger dispatch.

 Detection design (see KNOWLEDGEBASE "Cast-state detection"):
   - Begin: RegisterForAnimationEvent for BeginCastLeft / BeginCastRight
     gives us a reliable one-shot trigger for cast start.
   - End: instead of pairing each Begin with an end event (SpellRelease,
     CastStop, InterruptCast, …) — which is brittle for concentration
     spells and interrupts — we poll four animvars every 0.1s while in
     casting state:
        bWantCastLeft
        bWantCastRight
        IsCastingDual
        bRitualSpellActive
     When all four are false, the cast has ended for any reason.
   - Re-dispatch flash on every poll tick: flash.oncast effects use the
     C++ pulse roster's retrigger window (default 250ms) to keep the
     additive emissive lane lit while the cast is held; without the
     re-dispatch the lane would decay halfway through a long
     concentration cast.

 Reference implementation: ZAO Active Overlays' zao_onspellleft_script.psc
 — author's own comment notes "CK IsCasting checks ... seem to miss a lot,"
 motivating the animvar-polling approach we mirror here.

 Currently player-only. NPC cast tracking would need per-NPC alias
 provisioning or a C++ sink; deferred.}

bool Property _castingActive = false Auto Hidden

MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

Event OnInit()
    _registerCastEvents()
EndEvent

Event OnPlayerLoadGame()
    ; Re-register on every load — animation event registrations don't
    ; reliably persist across save/load even on Auto Hidden state.
    _registerCastEvents()
    ; Also clear stale casting flag in case the player saved mid-cast and
    ; loaded back outside any cast — the listener won't re-fire OnUpdate
    ; until the next BeginCast*, so without this the flag could stick.
    MTF_MainQuest h = _host()
    if h != None
        Actor p = Game.GetPlayer()
        if p != None
            h._setCasting(p, false)
        endif
    endif
    _castingActive = false
EndEvent

Function _registerCastEvents()
    Actor a = GetReference() as Actor
    if a == None
        return
    endif
    RegisterForAnimationEvent(a, "BeginCastLeft")
    RegisterForAnimationEvent(a, "BeginCastRight")
EndFunction

Event OnAnimationEvent(ObjectReference akSource, String asEventName)
    Actor a = GetReference() as Actor
    if a == None || akSource != a
        return
    endif
    ; BeginCastLeft / BeginCastRight both kick the same logic — start
    ; polling and arm flash. Re-firing while already in casting state is
    ; harmless (DispatchFlashCast is idempotent; OnUpdate stays scheduled).
    if asEventName == "BeginCastLeft" || asEventName == "BeginCastRight"
        if !_castingActive
            _castingActive = true
            MTF_MainQuest h = _host()
            if h != None
                h._setCasting(a, true)
                h.DispatchFlashCast("cast")
            endif
            RegisterForSingleUpdate(0.1)
        endif
    endif
EndEvent

Event OnUpdate()
    Actor a = GetReference() as Actor
    if a == None
        _castingActive = false
        return
    endif
    ; Four-animvar OR — covers single-hand charge/hold, dual-cast, and
    ; ritual spells (Fire Storm, Bound Sword summon, etc.). The Right-hand
    ; check is in here even though we don't have a separate _castingRight
    ; bool because the user asked for one umbrella "is casting" condition.
    bool stillCasting = a.GetAnimationVariableBool("bWantCastLeft")  || \
                        a.GetAnimationVariableBool("bWantCastRight") || \
                        a.GetAnimationVariableBool("IsCastingDual")  || \
                        a.GetAnimationVariableBool("bRitualSpellActive")
    MTF_MainQuest h = _host()
    if stillCasting
        if h != None
            h._setCasting(a, true)
            ; Re-dispatch flash so retrig window stays alive while the
            ; cast is held. Cheap — one MTFPulse call, no scene-side state.
            h.DispatchFlashCast("cast")
        endif
        RegisterForSingleUpdate(0.1)
    else
        _castingActive = false
        if h != None
            h._setCasting(a, false)
        endif
        ; Don't re-schedule — next BeginCast* will rearm. If nothing
        ; happens, we sit idle (no polling cost when not casting).
    endif
EndEvent
