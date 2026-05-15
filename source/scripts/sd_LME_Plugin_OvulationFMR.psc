Scriptname sd_LME_Plugin_OvulationFMR extends sd_LME_ConditionPlugin

Faction Property FMR_PregnancyFaction Auto

string Function GetPluginId()
    return "lme.ovulation.fmr"
EndFunction
string Function GetLabel()
    return "Ovulation (FMR)"
EndFunction
string Function GetParamLabel()
    return ""    ; no parameter
EndFunction

bool Function check(Actor target, int param)
    if FMR_PregnancyFaction == None
        return false
    endif
    return target.GetFactionRank(FMR_PregnancyFaction) == 118
EndFunction
