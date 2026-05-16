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
    if p == None
        return
    endif
    p._onHit(cls)
EndEvent

; ── Subject-hotkey forwarding ────────────────────────────────────────────────
; ReferenceAlias scripts can RegisterForKey; the host Quest (MTF_MainQuest)
; can't. We hold the registration here and forward OnKeyDown into the host.

MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

Function RefreshSubjectHotkey()
{Re-bind the player's RegisterForKey to the host's GetSubjectHotkey().
 Called by OnInit (via alias OnPlayerLoadGame), by MCM on hotkey change,
 and by the version migration block.}
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int wanted = h.GetSubjectHotkey()
    int prev   = StorageUtil.GetIntValue(h, "mtf.subject.hotkey.registered", -1)
    if prev >= 0 && prev != wanted
        UnregisterForKey(prev)
    endif
    if wanted >= 0
        RegisterForKey(wanted)
    endif
    StorageUtil.SetIntValue(h, "mtf.subject.hotkey.registered", wanted)
EndFunction

Event OnPlayerLoadGame()
    RefreshSubjectHotkey()
EndEvent

Event OnInit()
    RefreshSubjectHotkey()
EndEvent

Event OnKeyDown(int keyCode)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int wanted = h.GetSubjectHotkey()
    if wanted < 0 || keyCode != wanted
        return
    endif
    h._hotkeyAddCrosshairTarget()
EndEvent
