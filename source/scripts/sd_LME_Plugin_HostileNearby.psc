Scriptname sd_LME_Plugin_HostileNearby extends sd_LME_ConditionPlugin
{Triggers when any actor hostile to the target is within radius,
 regardless of combat state. Catches "danger nearby" before combat starts
 and after combat ends if a hostile is still loaded.}

string Function GetPluginId()
    return "lme.combat.hostile"
EndFunction
string Function GetLabel()
    return "Hostile Nearby"
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
    return 25
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
