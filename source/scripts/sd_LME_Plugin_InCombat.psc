Scriptname sd_LME_Plugin_InCombat extends sd_LME_ConditionPlugin

string Function GetPluginId()
    return "lme.combat.incombat"
EndFunction
string Function GetLabel()
    return "In Combat"
EndFunction
string Function GetParamLabel()
    return ""
EndFunction
int Function GetParamMin()
    return 0
EndFunction
int Function GetParamMax()
    return 0
EndFunction
int Function GetParamDefault()
    return 0
EndFunction

bool Function check(Actor target, int param)
    if target == None
        return false
    endif
    return target.IsInCombat()
EndFunction
