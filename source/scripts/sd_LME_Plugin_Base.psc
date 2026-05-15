Scriptname sd_LME_Plugin_Base extends sd_LME_Plugin
{Built-in conditions and effects that depend only on vanilla Skyrim
 + PO3 PapyrusExtender.

 Conditions (idx → id):
   0  magicka         — Magicka %
   1  combat.in       — In Combat
   2  combat.alerted  — Enemies Alerted (combat state 1 or 2)
   3  combat.hostile  — Hostile Nearby

 Effects (idx → id):
   0  drain.magickaRate  — drain `param`% of current MagickaRateMult
   1  drain.carryWeight  — drain `param`% of current CarryWeight
   2  drain.sneak        — drain `param`% of current Sneak
   3  burst.magicka      — one-shot: subtract `param`% of current Magicka on switch
   4  burst.stamina      — one-shot: subtract `param`% of current Stamina on switch}

float Property _appliedMana = 0.0 Auto Hidden
float Property _appliedCarry = 0.0 Auto Hidden
float Property _appliedSneak = 0.0 Auto Hidden

string Function GetPluginId()
    return "lme.base"
EndFunction
string Function GetPluginLabel()
    return "Base"
EndFunction

; ── Conditions ────────────────────────────────────────────────────────────────

int Function GetConditionCount()
    return 4
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "magicka"
    elseif idx == 1
        return "combat.in"
    elseif idx == 2
        return "combat.alerted"
    elseif idx == 3
        return "combat.hostile"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "Magicka %"
    elseif idx == 1
        return "In Combat"
    elseif idx == 2
        return "Enemies Alerted"
    elseif idx == 3
        return "Hostile Nearby"
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx == 0
        return "Magicka % threshold"
    elseif idx == 2 || idx == 3
        return "Scan radius (meters)"
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    if idx == 2 || idx == 3
        return 1
    endif
    return 0
EndFunction

int Function GetConditionParamMax(int idx)
    if idx == 0 || idx == 2 || idx == 3
        return 100
    endif
    return 0
EndFunction

int Function GetConditionParamDefault(int idx)
    if idx == 0
        return 50
    elseif idx == 2
        return 40
    elseif idx == 3
        return 25
    endif
    return 0
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None
        return false
    endif
    if idx == 0
        float maxMp = target.GetActorValueMax("Magicka")
        if maxMp <= 0.0
            return false
        endif
        return (target.GetActorValue("Magicka") / maxMp) * 100.0 >= param as float
    elseif idx == 1
        return target.IsInCombat()
    elseif idx == 2
        return _scanNearbyCombat(target, param)
    elseif idx == 3
        return _scanNearbyHostile(target, param)
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
    return 5
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
    endif
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    return 0
EndFunction
int Function GetEffectParamMax(int idx)
    return 100
EndFunction
int Function GetEffectParamDefault(int idx)
    if idx == 3 || idx == 4
        return 50
    endif
    return 25
EndFunction

string Function _avNameFor(int idx)
    if idx == 0
        return "MagickaRateMult"
    elseif idx == 1
        return "CarryWeight"
    elseif idx == 2
        return "Sneak"
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

Function onActivate(int idx, Actor target, int param)
    if idx <= 2
        _recompute(idx, target, param)
    elseif idx == 3
        _burstDrain("Magicka", target, param)
    elseif idx == 4
        _burstDrain("Stamina", target, param)
    endif
EndFunction

Function onDeactivate(int idx, Actor target, int param)
    if idx <= 2
        _recompute(idx, target, 0)
    endif
EndFunction

Function onTick(int idx, Actor target, int param)
    ; Re-apply every tick so continuous drains stay in sync with gear/buff
    ; changes. Burst effects are one-shot (onActivate only) and don't tick.
    if idx <= 2
        _recompute(idx, target, param)
    endif
EndFunction
