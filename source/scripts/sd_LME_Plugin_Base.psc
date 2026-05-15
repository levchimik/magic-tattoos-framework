Scriptname sd_LME_Plugin_Base extends sd_LME_ConditionPlugin
{Built-in conditions that depend only on vanilla Skyrim + PO3 PapyrusExtender.

 Items:
   0  magicka         — Magicka %
   1  combat.in       — In Combat
   2  combat.alerted  — Enemies Alerted (combat state 1 or 2)
   3  combat.hostile  — Hostile Nearby}

string Function GetPluginId()
    return "lme.base"
EndFunction
string Function GetPluginLabel()
    return "Base"
EndFunction

int Function GetItemCount()
    return 4
EndFunction

string Function GetItemId(int idx)
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

string Function GetItemLabel(int idx)
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

string Function GetItemParamLabel(int idx)
    if idx == 0
        return "Magicka % threshold"
    elseif idx == 2
        return "Scan radius (meters)"
    elseif idx == 3
        return "Scan radius (meters)"
    endif
    return ""    ; combat.in has no param
EndFunction

int Function GetItemParamMin(int idx)
    if idx == 0
        return 0
    elseif idx == 2 || idx == 3
        return 1
    endif
    return 0
EndFunction

int Function GetItemParamMax(int idx)
    if idx == 0
        return 100
    elseif idx == 2 || idx == 3
        return 100
    endif
    return 0
EndFunction

int Function GetItemParamDefault(int idx)
    if idx == 0
        return 50
    elseif idx == 2
        return 40
    elseif idx == 3
        return 25
    endif
    return 0
EndFunction

bool Function checkItem(int idx, Actor target, int param)
    if target == None
        return false
    endif
    if idx == 0
        ; magicka %
        float maxMp = target.GetActorValueMax("Magicka")
        if maxMp <= 0.0
            return false
        endif
        return (target.GetActorValue("Magicka") / maxMp) * 100.0 >= param as float
    elseif idx == 1
        ; in combat
        return target.IsInCombat()
    elseif idx == 2
        ; enemies alerted (state 1 OR 2)
        return _scanNearbyCombat(target, param, true)
    elseif idx == 3
        ; hostile nearby
        return _scanNearbyHostile(target, param)
    endif
    return false
EndFunction

bool Function _scanNearbyCombat(Actor target, int paramMeters, bool includeFullCombat)
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
            int cs = a.GetCombatState()
            bool match = false
            if includeFullCombat
                match = (cs > 0)
            else
                match = (cs == 2)
            endif
            if match && a.GetDistance(target) <= radius
                return true
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
