Scriptname sd_LME_Plugin_OvulationFMR extends sd_LME_ConditionPlugin
{Soft dependency on Fertility Mode.esm — looked up at runtime so the
 master can be dropped from LewdMarksEffects.esp. If FMR isn't loaded,
 the plugin silently skips registration.}

Faction Property FMR_PregnancyFaction Auto Hidden

string Function GetPluginId()
    return "lme.ovulation.fmr"
EndFunction
string Function GetLabel()
    return "Ovulation (FMR)"
EndFunction
string Function GetParamLabel()
    return ""    ; no parameter
EndFunction

bool Function _resolveDeps()
    if FMR_PregnancyFaction != None
        return true
    endif
    FMR_PregnancyFaction = Game.GetFormFromFile(0x02666B, "Fertility Mode.esm") as Faction
    return FMR_PregnancyFaction != None
EndFunction

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        return
    endif
    sd_LME_MainQuest host = Game.GetFormFromFile(0x803, "LewdMarksEffects.esp") as sd_LME_MainQuest
    if host == None || host.registeredPlugins == None
        RegisterForSingleUpdate(1.0)
        return
    endif
    host.RegisterPlugin(self)
    _registered = true
EndFunction

bool Function check(Actor target, int param)
    if FMR_PregnancyFaction == None
        return false
    endif
    return target.GetFactionRank(FMR_PregnancyFaction) == 118
EndFunction
