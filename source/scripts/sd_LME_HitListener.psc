Scriptname sd_LME_HitListener extends ReferenceAlias
{Listens for OnHit events on the player (forced reference) and forwards
 a single weapon/spell class index per hit to sd_LME_Plugin_Base. The
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
    sd_LME_Plugin_Base p = Game.GetFormFromFile(0x80D, "LewdMarksEffects.esp") as sd_LME_Plugin_Base
    if p != None
        p._onHit(cls)
    endif
EndEvent
