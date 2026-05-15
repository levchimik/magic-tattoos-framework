Scriptname sd_LME_Plugin_Arousal extends sd_LME_ConditionPlugin

slaFrameWorkScr Property SLAFramework Auto

string Function GetPluginId()
    return "lme.arousal"
EndFunction
string Function GetLabel()
    return "Arousal (SLA)"
EndFunction
string Function GetParamLabel()
    return "Arousal threshold"
EndFunction
int Function GetParamMin()
    return 0
EndFunction
int Function GetParamMax()
    return 100
EndFunction
int Function GetParamDefault()
    return 80
EndFunction

bool Function check(Actor target, int param)
    if SLAFramework == None
        return false
    endif
    return SLAFramework.GetActorArousal(target) >= param
EndFunction
