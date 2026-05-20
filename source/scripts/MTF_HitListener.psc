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
    _registerLifecycleEvents()
    _ensureApplyTattooSpell()
    _cleanupLegacySpells()
    _autoEnableTestBranch()
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
            MTFPulse.ClearActorFade(p, host.OverlaySlot)
            MTFPulse.ClearActorAt(p, host.OverlaySlot)
        endif
        host.setRedraw()
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
    _autoEnableTestBranch()
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

Function _autoEnableTestBranch()
{Test-branch convenience: ensure Enable+Debug are ON every save load AND
 force the host into checkingAroused state so the OnUpdate loop fires.
 Without the GotoState the slow-tick rotation never runs — ModActive is
 just a flag; the state machine is what drives the loop. Revert before
 shipping.}
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    if !h.ModActive
        h.ModActive = true
    endif
    if !h.DebugMode
        h.DebugMode = true
    endif
    h.setRedraw()
    ; Force OnBeginState to re-fire (which calls RegisterForSingleUpdate).
    ; State persists across save/load, but RegisterForSingleUpdate TIMERS do
    ; not. If we don't cycle, GotoState("checkingAroused") is a no-op when
    ; the quest is already in that state — and OnUpdate then never re-fires
    ; after a save/load, breaking _tickSlotEffects (slowTime, detectAll,
    ; cloak refreshes all rely on this).
    if h.GetState() == "checkingAroused"
        h.GotoState("")
    endif
    h.GotoState("checkingAroused")
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

