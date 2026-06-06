Scriptname MTF_HitListener extends ReferenceAlias
{Listens for OnHit events on the player (forced reference) and forwards
 a single weapon/spell class index per hit to MTF_Plugin_Base. The
 base plugin maintains per-class hit counters which the combat.hit.*
 conditions consume on each new hit (one roll per hit, per class).

 Class indices:
   0 ANY      — every hit increments this
   1 BLUNT    — mace, warhammer, unarmed
   2 BLADED   — sword, dagger, axe (1H + 2H battleaxe)
   3 RANGED   — bow, crossbow
   4 FIRE     — spell with MagicDamageFire keyword
   5 FROST    — spell with MagicDamageFrost keyword
   6 SHOCK    — spell with MagicDamageShock keyword

 Staves and unclassified spells/sources increment only ANY.}

Keyword Property _kwWarhammer Auto Hidden
Keyword Property _kwFire Auto Hidden
Keyword Property _kwFrost Auto Hidden
Keyword Property _kwShock Auto Hidden
bool Property _kwResolved = false Auto Hidden

Function _resolveKeywords()
    if _kwResolved
        return
    endif
    _kwWarhammer = Game.GetFormFromFile(0x06D930, "Skyrim.esm") as Keyword
    _kwFire = Game.GetFormFromFile(0x01CEAD, "Skyrim.esm") as Keyword
    _kwFrost = Game.GetFormFromFile(0x01CEAE, "Skyrim.esm") as Keyword
    _kwShock = Game.GetFormFromFile(0x01CEAF, "Skyrim.esm") as Keyword
    _kwResolved = true
EndFunction

int Function _classify(Form akSource)
    Weapon w = akSource as Weapon
    if w != None
        int wt = w.GetWeaponType()
        ; Vanilla GetWeaponType mapping:
        ;   0 HtH  1 OneHSword  2 OneHDagger  3 OneHAxe  4 OneHMace
        ;   5 TwoHSword  6 TwoHAxe(incl. warhammer)  7 Bow  8 Staff  9 Crossbow
        if wt == 0 || wt == 4
            return 1 ; BLUNT
        elseif wt == 6
            if _kwWarhammer != None && w.HasKeyword(_kwWarhammer)
                return 1 ; BLUNT (warhammer)
            endif
            return 2 ; BLADED (battleaxe)
        elseif wt == 1 || wt == 2 || wt == 3 || wt == 5
            return 2 ; BLADED
        elseif wt == 7 || wt == 9
            return 3 ; RANGED
        endif
        return 0 ; staff / unknown — ANY only
    endif
    Spell s = akSource as Spell
    if s != None
        if _kwFire != None && s.HasKeyword(_kwFire)
            return 4 ; FIRE
        endif
        if _kwFrost != None && s.HasKeyword(_kwFrost)
            return 5 ; FROST
        endif
        if _kwShock != None && s.HasKeyword(_kwShock)
            return 6 ; SHOCK
        endif
        return 0 ; non-elemental spell — ANY only
    endif
    ; akSource None — typically unarmed
    return 1 ; BLUNT
EndFunction

Event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked)
    _resolveKeywords()
    int cls = _classify(akSource)
    MTF_Plugin_Base p = Game.GetFormFromFile(0x80D, "MagicTattoosFramework.esp") as MTF_Plugin_Base
    if p != None
        p._onHit(cls)
        ; v0.4 idea #3 — on-hit retaliation. Player-only (this alias only fires
        ; for the player). Reads the player's mtf.onhit.* flags set by the
        ; ragdoll.onhit / damage.*OnHit effects and hits the aggressor back.
        Actor aggr = akAggressor as Actor
        if aggr != None
            p._onHitRetaliate(Game.GetPlayer(), aggr)
        endif
    endif
    ; v0.1.3: flash dispatch on hit lives in the C++ TESHitEvent sink
    ; now (see MTFPulse cpp-plugin/src/hit_sink.cpp). That path covers
    ; the player AND every NPC with a roster entry — this alias-bound
    ; OnHit only fires for the player, so doing flash dispatch here
    ; would double-fire on the player AND miss NPCs entirely. The
    ; combat.hit.* condition counters above stay on this path since
    ; they're Papyrus-only state.
    ;
    ; External Papyrus mods that want to fire CUSTOM tags can still call
    ; MainQuest.DispatchFlashHit("their.tag") — that path is independent
    ; of this listener and goes straight to MTFPulse.TriggerActorFlash.
EndEvent

MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

Event OnPlayerLoadGame()
    ; Arm the post-load grace window BEFORE _rearmSlowTick cycles state
    ; and schedules the first slow tick. Without this, that first eval at
    ; ~0.5s can clear stacked presets whose lock-on-activate cooldown
    ; expired during the load process — tattoo flashes on then vanishes.
    ; See MTF_MainQuest._postLoadFreezeUntilRT.
    MTF_MainQuest hostFreeze = _host()
    if hostFreeze != None
        ; v0.3.9: one-shot mtf.base → themed-module key rewrite. Runs before
        ; the slow-tick re-arms (the 3s freeze below covers it) so the first
        ; eval already sees migrated keys. Version-gated; a no-op after the
        ; first post-split load.
        hostFreeze._migrateModuleSplit()
        ; v0.3.x: 5.0 -> 3.0. The freeze gates the slow-tick redraw that
        ; actually repaints the tattoo on load. The floor is SKEE's async
        ; override-store restore (~1-3s post-load, see KB "SKEE post-load
        ; race"); redrawing before SKEE settles leaves the overlay invisible
        ; until the next tier change. 3.0 sits just above that floor, halving
        ; the visible post-load delay (~5s -> ~3s) without risking the race.
        ; The 0.5s postLoadRedrawNow kick still fires first as a best-effort
        ; early draw for the case where SKEE happens to be ready sooner.
        hostFreeze.ArmPostLoadFreeze(3.0)
    endif

    _registerLifecycleEvents()
    _ensureApplyTattooSpell()
    _cleanupLegacySpells()
    _rearmSlowTick()
    ; Legacy hotkey registration cleanup — older versions kept a key bound
    ; here for the (now-removed) crosshair-add hotkey.
    int prev = StorageUtil.GetIntValue(_host(), "mtf.subject.hotkey.registered", -1)
    if prev >= 0
        UnregisterForKey(prev)
        StorageUtil.UnsetIntValue(_host(), "mtf.subject.hotkey.registered")
    endif

    ; v0.1.4 fade-on-death persistence fix: the C++ pulse_roster Tick writes
    ; alpha / emissive_mult straight to the LIVE shader (via
    ; SetNodeProperty) without touching the persistent NiOverride store.
    ; If the player dies while a fade is playing, the live shader settles
    ; at alpha=0, then the engine serializes that shader state into the
    ; save. On reload, SKEE restores the override store (alpha=normal at
    ; save time) but never re-pushes it to the live shader — and Skyrim
    ; loads the persisted live-shader alpha=0, so the tattoo stays
    ; invisible until something forces a redraw.
    ;
    ; Force one here: clear any stale roster state for the player (the
    ; C++ Roster is in-memory only, but we want fade arming to start
    ; cold), then set forceRedraw on MainQuest so the next slow tick
    ; re-runs drawOverlay → ApplyNodeOverrides → live shader gets the
    ; correct alpha from the override store.
    MTF_MainQuest host = _host()
    if host != None
        Actor p = Game.GetPlayer()
        if p != None
            ; v0.1.17 Phase 3 (multi-area): player MCM-base roster is body-only.
            MTFPulse.ClearActorFade(p, host.OverlaySlot, 0)
            MTFPulse.ClearActorAt(p, host.OverlaySlot, 0)
        endif
        host.setRedraw()
    endif

    ; postLoadRedrawNow now does AddOverlays + setRedraw + C++ pulse
    ; roster repopulation. None of these write to the NiOverride override
    ; store, so the original SKEE-async-restore race no longer applies
    ; (setRedraw is just a flag — the actual draw happens later via the
    ; slow tick once the 5s post-load grace window expires). The roster
    ; repopulation specifically wants to fire as early as possible so
    ; stacked-preset pulse animations resume quickly; 0.5s is "right
    ; after load" UX-wise.
    RegisterForSingleUpdate(0.5)
EndEvent

Event OnUpdate()
{Post-load: re-scan the visual pack catalogs first (so content packs
 installed or removed since last session are picked up automatically —
 the same work as the MCM "Reload visual packs" button), THEN the
 second-chance redraw + C++ pulse roster repopulation. See
 postLoadRedrawNow for details.}
    MTF_MainQuest h = _host()
    if h != None
        ; Rescan BEFORE the redraw so postLoadRedrawNow and the freeze-gated
        ; slow-tick eval see fresh catalog data (GetPackArea /
        ; GetEntryLayerCount lookups resolve against the current pack set).
        ; _visualsLoaded persists in the cosave, so without this the pack
        ; registry stays frozen at the previous session's scan until the
        ; user opens the MCM and clicks "Reload visual packs" by hand.
        ; Gated by the "Rescan packs on load" MCM toggle (default ON).
        if h.GetRescanOnLoad()
            h.ForceReloadVisualCatalogs()
        endif
        h.postLoadRedrawNow()
    endif
EndEvent

; One-time cleanup of MTF spells that older code AddSpell'd onto the player
; before we switched to DoCombatSpellApply. Removes Frost/Lightning/Flame
; Cloak, Slow Time, and Detect All from the player's spell list. Safe to
; run every load — RemoveSpell is a no-op if the spell isn't present.
Function _cleanupLegacySpells()
    Actor p = Game.GetPlayer()
    if p == None
        return
    endif
    int[] ids = new int[4]
    ids[0] = 0x847  ; FlameCloak
    ids[1] = 0x84B  ; FrostCloak
    ids[2] = 0x84F  ; LightningCloak
    ids[3] = 0x843  ; SlowTime
    ; NOTE: 0x841 DetectAll is now intentionally AddSpell'd by the queue drain
    ; because DetectLife archetype only engages via full Cast() (which needs
    ; the caster to know the spell). Removing it here would just have the
    ; next tick re-add it.
    ; NOTE: 0x81A ApplyTattoo is also AddSpell'd by _ensureApplyTattooSpell — keep.
    int i = 0
    while i < ids.Length
        Spell s = Game.GetFormFromFile(ids[i], "MagicTattoosFramework.esp") as Spell
        if s != None && p.HasSpell(s)
            p.RemoveSpell(s)
        endif
        i += 1
    endwhile
EndFunction

Event OnInit()
    _registerLifecycleEvents()
    _ensureApplyTattooSpell()
    _rearmSlowTick()
EndEvent

Function _ensureApplyTattooSpell()
{Idempotent: gives the player MTF_Spell_ApplyTattoo once per save so the
 spell is always available for in-world preset application.}
    Spell s = Game.GetFormFromFile(0x81A, "MagicTattoosFramework.esp") as Spell
    if s == None
        return
    endif
    Actor p = Game.GetPlayer()
    if p != None && !p.HasSpell(s)
        p.AddSpell(s, false)
    endif
EndFunction

Function _rearmSlowTick()
{Re-arm MainQuest's slow-tick state machine after save load / fresh init.
 State persists across save/load but RegisterForSingleUpdate TIMERS do
 NOT — so the OnUpdate loop never re-fires after reload unless we force
 OnBeginState to run again. MainQuest.Rearm() cycles the state ("" →
 checkingAroused) to do exactly that, re-arming the slow tick that drives
 _tickSlotEffects (slowTime, detectAll, cloak refreshes all rely on it).
 Also pokes setRedraw so the next slow tick re-runs drawOverlay.

 v0.2.5 (was _autoEnableTestBranch): dropped the dev-convenience
 auto-toggling of ModActive + DebugMode — those are user-facing MCM
 toggles, not state we should be force-flipping on every load. The
 state-cycle is the load-bearing part and stays.}
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    h.setRedraw()
    h.Rearm()
EndFunction

; ── PO3 PapyrusExtender lifecycle events ────────────────────────────────────
; The PO3 OnActorKilled / OnObjectLoaded / OnObjectUnloaded events fire on
; any ReferenceAlias registered with the global PO3_Events_Alias helpers,
; regardless of which actor the alias is forced onto. We use the player
; alias as a convenient host. Form type 43 = Actor.

int Function FORMTYPE_ACTOR() global
    return 43
EndFunction

Function _registerLifecycleEvents()
    PO3_Events_Alias.RegisterForActorKilled(self)
    PO3_Events_Alias.RegisterForObjectLoaded(self, FORMTYPE_ACTOR())
EndFunction

Event OnActorKilled(Actor akVictim, Actor akKiller)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    h._onTrackedActorKilled(akVictim)
EndEvent

Event OnObjectLoaded(ObjectReference akRef, int aiFormType)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    Actor a = akRef as Actor
    if a == None
        return
    endif
    h._onTrackedActorAttached(a)
EndEvent

Event OnObjectUnloaded(ObjectReference akRef, int aiFormType)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    Actor a = akRef as Actor
    if a == None
        return
    endif
    h._onTrackedActorDetached(a)
EndEvent

