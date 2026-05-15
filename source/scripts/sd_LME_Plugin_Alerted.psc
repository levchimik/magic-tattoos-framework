Scriptname sd_LME_Plugin_Alerted extends sd_LME_ConditionPlugin
{Triggers when any nearby actor is aware of the target — combat state 1
 (actively fighting) OR state 2 (searching / hunting / lost line of sight).
 Superset of "In Combat": fires both before, during, and just after combat.}

string Function GetPluginId()
    return "lme.combat.alerted"
EndFunction
string Function GetLabel()
    return "Enemies Alerted"
EndFunction
string Function GetParamLabel()
    return "Scan radius (meters)"
EndFunction
int Function GetParamMin()
    return 1
EndFunction
int Function GetParamMax()
    return 100
EndFunction
int Function GetParamDefault()
    return 40
EndFunction

bool Function check(Actor target, int param)
    if target == None
        return false
    endif
    float radius = (param as float) * 70.0
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
