Scriptname sd_LME_Plugin_Base extends sd_LME_Plugin
{Built-in conditions and effects that depend only on vanilla Skyrim
 + PO3 PapyrusExtender.

 Conditions (idx → id):
   0  magicka               — Above Magicka %
   1  magicka.below         — Below Magicka %
   2  stamina               — Above Stamina %
   3  stamina.below         — Below Stamina %
   4  combat.in             — In Combat
   5  combat.alerted        — Enemies Alerted (combat state 1 or 2)
   6  combat.hostile        — Hostile Nearby
   7  combat.hit            — On Combat Hit (any source)
   8  combat.hit.blunt      — On Combat Hit (mace/warhammer/fist)
   9  combat.hit.bladed     — On Combat Hit (sword/dagger/axe)
   10 combat.hit.ranged     — On Combat Hit (bow/crossbow)
   11 combat.hit.magic.fire — On Combat Hit (fire spell)
   12 combat.hit.magic.frost— On Combat Hit (frost spell)
   13 combat.hit.magic.shock— On Combat Hit (shock spell)

 Effects (idx → id):
   0  drain.magickaRate     — drain `param`% of current MagickaRateMult
   1  drain.carryWeight     — drain `param`% of current CarryWeight
   2  drain.sneak           — drain `param`% of current Sneak
   3  burst.magicka         — one-shot: subtract `param`% of current Magicka on switch
   4  burst.stamina         — one-shot: subtract `param`% of current Stamina on switch
   5  drain.speedMult       — drain `param`% of current SpeedMult (movement)
   6  drain.staminaRate     — drain `param`% of current StaminaRateMult (regen)
   7  drain.attackDamageMult— drain `param`% of current AttackDamageMult (outgoing)
   8  drain.damageResist    — drain `param`% of current DamageResist (armor)
   9  burst.stagger         — one-shot: play stagger animation on switch (no param)
   10 state.alertNearby     — one-shot: nearby hostile actors within `param`m engage

 Hit detection is event-driven: sd_LME_HitListener (a ReferenceAlias on
 LME_MainQuest forced to the player) calls _onHit(classIdx) on every hit.
 Each class has its own counter; combat.hit.* conditions consume one
 counter increment per check and roll the slot's chance%. The result
 stays "armed" for HIT_VISIBLE_SECONDS so the mark is visible briefly.}

float Property _appliedMana       = 0.0 Auto Hidden
float Property _appliedCarry      = 0.0 Auto Hidden
float Property _appliedSneak      = 0.0 Auto Hidden
float Property _appliedSpeed      = 0.0 Auto Hidden
float Property _appliedStamRate   = 0.0 Auto Hidden
float Property _appliedAtkDmg     = 0.0 Auto Hidden
float Property _appliedDmgResist  = 0.0 Auto Hidden

; Hit-class counter storage uses PapyrusUtil StorageUtil (see MainQuest).
; Auto Hidden array properties added post-release do not get attached to
; existing script instances — even on a "fresh new game" if any prior save
; touched the quest, indexed-property and whole-array writes silently no-op.
; StorageUtil persists in the cosave and sidesteps the OnInit-once trap.

float Function HIT_VISIBLE_SECONDS() global
    return 8.0
EndFunction

string Function GetPluginId()
    return "lme.base"
EndFunction
string Function GetPluginLabel()
    return "Base"
EndFunction

sd_LME_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "LewdMarksEffects.esp") as sd_LME_MainQuest
EndFunction

; Called by sd_LME_HitListener on each player OnHit event.
Function _onHit(int classIdx)
    sd_LME_MainQuest h = _host()
    if h == None
        return
    endif
    h.IncHitCount(classIdx)
EndFunction

; ── Conditions ────────────────────────────────────────────────────────────────

int Function GetConditionCount()
    return 14
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "magicka"
    elseif idx == 1
        return "magicka.below"
    elseif idx == 2
        return "stamina"
    elseif idx == 3
        return "stamina.below"
    elseif idx == 4
        return "combat.in"
    elseif idx == 5
        return "combat.alerted"
    elseif idx == 6
        return "combat.hostile"
    elseif idx == 7
        return "combat.hit"
    elseif idx == 8
        return "combat.hit.blunt"
    elseif idx == 9
        return "combat.hit.bladed"
    elseif idx == 10
        return "combat.hit.ranged"
    elseif idx == 11
        return "combat.hit.magic.fire"
    elseif idx == 12
        return "combat.hit.magic.frost"
    elseif idx == 13
        return "combat.hit.magic.shock"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "Above Magicka %"
    elseif idx == 1
        return "Below Magicka %"
    elseif idx == 2
        return "Above Stamina %"
    elseif idx == 3
        return "Below Stamina %"
    elseif idx == 4
        return "In Combat"
    elseif idx == 5
        return "Enemies Alerted"
    elseif idx == 6
        return "Hostile Nearby"
    elseif idx == 7
        return "On Hit (Any)"
    elseif idx == 8
        return "On Hit (Blunt: mace/warhammer/fist)"
    elseif idx == 9
        return "On Hit (Bladed)"
    elseif idx == 10
        return "On Hit (Ranged)"
    elseif idx == 11
        return "On Hit (Fire)"
    elseif idx == 12
        return "On Hit (Frost)"
    elseif idx == 13
        return "On Hit (Shock)"
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx <= 3
        return "Magicka/Stamina % threshold"
    elseif idx == 5 || idx == 6
        return "Scan radius (meters)"
    elseif idx >= 7 && idx <= 13
        return "Chance % per hit"
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    if idx == 5 || idx == 6
        return 1
    elseif idx >= 7 && idx <= 13
        return 1
    endif
    return 0
EndFunction

int Function GetConditionParamMax(int idx)
    return 100
EndFunction

int Function GetConditionParamDefault(int idx)
    if idx == 0 || idx == 2
        return 50
    elseif idx == 1 || idx == 3
        return 30
    elseif idx == 5
        return 40
    elseif idx == 6
        return 25
    elseif idx >= 7 && idx <= 13
        return 25
    endif
    return 0
EndFunction

float Function _avPercent(Actor target, string av)
    float maxV = target.GetActorValueMax(av)
    if maxV <= 0.0
        return -1.0
    endif
    return (target.GetActorValue(av) / maxV) * 100.0
EndFunction

int Function _hitClassFor(int idx)
    ; 7=ANY 8=BLUNT 9=BLADED 10=RANGED 11=FIRE 12=FROST 13=SHOCK
    if idx == 7
        return 0
    elseif idx == 8
        return 1
    elseif idx == 9
        return 2
    elseif idx == 10
        return 3
    elseif idx == 11
        return 4
    elseif idx == 12
        return 5
    elseif idx == 13
        return 6
    endif
    return -1
EndFunction

bool Function _checkHit(int classIdx, int param)
    sd_LME_MainQuest h = _host()
    if h == None
        return false
    endif
    float now = Utility.GetCurrentRealTime()
    int cnt = h.GetHitCount(classIdx)
    int rolled = h.GetHitRolled(classIdx)
    if cnt > rolled
        h.SetHitRolled(classIdx, cnt)
        if Utility.RandomInt(1, 100) <= param
            h.SetHitArmedRT(classIdx, now + HIT_VISIBLE_SECONDS())
        endif
    endif
    return now < h.GetHitArmedRT(classIdx)
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None
        return false
    endif
    if idx == 0
        float p = _avPercent(target, "Magicka")
        return p >= 0.0 && p >= param as float
    elseif idx == 1
        float p = _avPercent(target, "Magicka")
        return p >= 0.0 && p <= param as float
    elseif idx == 2
        float p = _avPercent(target, "Stamina")
        return p >= 0.0 && p >= param as float
    elseif idx == 3
        float p = _avPercent(target, "Stamina")
        return p >= 0.0 && p <= param as float
    elseif idx == 4
        return target.IsInCombat()
    elseif idx == 5
        return _scanNearbyCombat(target, param)
    elseif idx == 6
        return _scanNearbyHostile(target, param)
    elseif idx >= 7 && idx <= 13
        int c = _hitClassFor(idx)
        if c < 0
            return false
        endif
        return _checkHit(c, param)
    endif
    return false
EndFunction

bool Function _scanNearbyCombat(Actor target, int paramMeters)
    float radius = (paramMeters as float) * 70.0
    if radius <= 0.0
        return false
    endif
    Actor[] nearby = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if nearby == None
        return false
    endif
    int i = 0
    while i < nearby.Length
        Actor a = nearby[i]
        if a != None && a != target && !a.IsDead()
            if a.GetCombatState() > 0
                if a.GetDistance(target) <= radius
                    return true
                endif
            endif
        endif
        i += 1
    endwhile
    return false
EndFunction

bool Function _scanNearbyHostile(Actor target, int paramMeters)
    float radius = (paramMeters as float) * 70.0
    if radius <= 0.0
        return false
    endif
    Actor[] nearby = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if nearby == None
        return false
    endif
    int i = 0
    while i < nearby.Length
        Actor a = nearby[i]
        if a != None && a != target && !a.IsDead()
            if a.IsHostileToActor(target)
                if a.GetDistance(target) <= radius
                    return true
                endif
            endif
        endif
        i += 1
    endwhile
    return false
EndFunction

; ── Effects ───────────────────────────────────────────────────────────────────

int Function GetEffectCount()
    return 11
EndFunction

string Function GetEffectId(int idx)
    if idx == 0
        return "drain.magickaRate"
    elseif idx == 1
        return "drain.carryWeight"
    elseif idx == 2
        return "drain.sneak"
    elseif idx == 3
        return "burst.magicka"
    elseif idx == 4
        return "burst.stamina"
    elseif idx == 5
        return "drain.speedMult"
    elseif idx == 6
        return "drain.staminaRate"
    elseif idx == 7
        return "drain.attackDamageMult"
    elseif idx == 8
        return "drain.damageResist"
    elseif idx == 9
        return "burst.stagger"
    elseif idx == 10
        return "state.alertNearby"
    endif
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    if idx == 0
        return "Mana Siphon"
    elseif idx == 1
        return "Carry Weight Penalty"
    elseif idx == 2
        return "Sneak Penalty"
    elseif idx == 3
        return "[!] Magicka Burst"
    elseif idx == 4
        return "[!] Stamina Burst"
    elseif idx == 5
        return "Movement Speed Penalty"
    elseif idx == 6
        return "Stamina Regen Penalty"
    elseif idx == 7
        return "Attack Damage Penalty"
    elseif idx == 8
        return "Armor Penalty"
    elseif idx == 9
        return "[!] Stagger"
    elseif idx == 10
        return "[!] Blow Sneak Cover"
    endif
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    if idx == 0
        return "Drain % of current MagickaRateMult"
    elseif idx == 1
        return "Drain % of current CarryWeight"
    elseif idx == 2
        return "Drain % of current Sneak"
    elseif idx == 3
        return "Burst drain % of current Magicka"
    elseif idx == 4
        return "Burst drain % of current Stamina"
    elseif idx == 5
        return "Drain % of current SpeedMult"
    elseif idx == 6
        return "Drain % of current StaminaRateMult"
    elseif idx == 7
        return "Drain % of current AttackDamageMult"
    elseif idx == 8
        return "Drain % of current DamageResist (armor)"
    elseif idx == 9
        return ""
    elseif idx == 10
        return "Alert radius (meters)"
    endif
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    if idx == 10
        return 1
    endif
    return 0
EndFunction
int Function GetEffectParamMax(int idx)
    return 100
EndFunction
int Function GetEffectParamDefault(int idx)
    if idx == 3 || idx == 4
        return 50
    elseif idx == 9
        return 0
    elseif idx == 10
        return 25
    endif
    return 25
EndFunction

bool Function _isDrain(int idx)
    return idx <= 2 || (idx >= 5 && idx <= 8)
EndFunction

string Function _avNameFor(int idx)
    if idx == 0
        return "MagickaRateMult"
    elseif idx == 1
        return "CarryWeight"
    elseif idx == 2
        return "Sneak"
    elseif idx == 5
        return "SpeedMult"
    elseif idx == 6
        return "StaminaRateMult"
    elseif idx == 7
        return "AttackDamageMult"
    elseif idx == 8
        return "DamageResist"
    endif
    return ""
EndFunction

float Function _getApplied(int idx)
    if idx == 0
        return _appliedMana
    elseif idx == 1
        return _appliedCarry
    elseif idx == 2
        return _appliedSneak
    elseif idx == 5
        return _appliedSpeed
    elseif idx == 6
        return _appliedStamRate
    elseif idx == 7
        return _appliedAtkDmg
    elseif idx == 8
        return _appliedDmgResist
    endif
    return 0.0
EndFunction

Function _setApplied(int idx, float v)
    if idx == 0
        _appliedMana = v
    elseif idx == 1
        _appliedCarry = v
    elseif idx == 2
        _appliedSneak = v
    elseif idx == 5
        _appliedSpeed = v
    elseif idx == 6
        _appliedStamRate = v
    elseif idx == 7
        _appliedAtkDmg = v
    elseif idx == 8
        _appliedDmgResist = v
    endif
EndFunction

Function _recompute(int idx, Actor target, int param)
    string av = _avNameFor(idx)
    if av == "" || target == None
        return
    endif
    float prev = _getApplied(idx)
    if prev != 0.0
        target.ModActorValue(av, prev)
    endif
    if param <= 0
        _setApplied(idx, 0.0)
        return
    endif
    float current = target.GetActorValue(av)
    if current <= 0.0
        _setApplied(idx, 0.0)
        return
    endif
    float amt = current * param / 100.0
    target.ModActorValue(av, -amt)
    _setApplied(idx, amt)
EndFunction

Function _burstDrain(string av, Actor target, int param)
    if target == None || param <= 0
        return
    endif
    float current = target.GetActorValue(av)
    if current <= 0.0
        return
    endif
    float amt = current * param / 100.0
    target.DamageActorValue(av, amt)
EndFunction

Function _alertNearby(Actor target, int paramMeters)
    if target == None || paramMeters <= 0
        return
    endif
    float radius = (paramMeters as float) * 70.0
    Actor[] nearby = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if nearby == None
        return
    endif
    int i = 0
    while i < nearby.Length
        Actor a = nearby[i]
        if a != None && a != target && !a.IsDead()
            if a.IsHostileToActor(target)
                if a.GetDistance(target) <= radius
                    a.StartCombat(target)
                endif
            endif
        endif
        i += 1
    endwhile
EndFunction

Function onActivate(int idx, Actor target, int param)
    if _isDrain(idx)
        _recompute(idx, target, param)
    elseif idx == 3
        _burstDrain("Magicka", target, param)
    elseif idx == 4
        _burstDrain("Stamina", target, param)
    elseif idx == 9
        if target != None
            Debug.SendAnimationEvent(target, "staggerStart")
        endif
    elseif idx == 10
        _alertNearby(target, param)
    endif
EndFunction

Function onDeactivate(int idx, Actor target, int param)
    if _isDrain(idx)
        _recompute(idx, target, 0)
    endif
EndFunction

Function onTick(int idx, Actor target, int param)
    if _isDrain(idx)
        _recompute(idx, target, param)
    endif
EndFunction
