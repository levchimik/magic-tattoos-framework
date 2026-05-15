Scriptname sd_LME_Plugin_Magicka extends sd_LME_ConditionPlugin

string Function GetPluginId()
    return "lme.magicka"
EndFunction
string Function GetLabel()
    return "Magicka %"
EndFunction
string Function GetParamLabel()
    return "Magicka % threshold"
EndFunction
int Function GetParamMin()
    return 0
EndFunction
int Function GetParamMax()
    return 100
EndFunction
int Function GetParamDefault()
    return 50
EndFunction

bool Function check(Actor target, int param)
    float maxMp = target.GetActorValueMax("Magicka")
    if maxMp <= 0.0
        return false
    endif
    return (target.GetActorValue("Magicka") / maxMp) * 100.0 >= param as float
EndFunction
