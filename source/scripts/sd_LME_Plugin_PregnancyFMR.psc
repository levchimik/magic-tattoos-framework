Scriptname sd_LME_Plugin_PregnancyFMR extends sd_LME_ConditionPlugin

Faction Property FMR_PregnancyFaction Auto

string Function GetPluginId()
    return "lme.pregnancy.fmr"
EndFunction
string Function GetLabel()
    return "Pregnancy (FMR)"
EndFunction
string Function GetParamLabel()
    return "Min belly stage (1-100)"
EndFunction
int Function GetParamMin()
    return 1
EndFunction
int Function GetParamMax()
    return 100
EndFunction
int Function GetParamDefault()
    return 1
EndFunction

bool Function check(Actor target, int param)
    if FMR_PregnancyFaction == None
        return false
    endif
    int rank = target.GetFactionRank(FMR_PregnancyFaction)
    return rank >= param && rank <= 100
EndFunction
