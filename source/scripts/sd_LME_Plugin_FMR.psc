Scriptname sd_LME_Plugin_FMR extends sd_LME_Plugin
{Conditions backed by Fertility Mode Reloaded. Soft-master: lookup at
 runtime; if FMR isn't loaded the plugin skips registration entirely.

 Conditions:
   0  pregnancy  — faction rank in 1..100 (belly stage)
   1  ovulation  — faction rank == 118}

Faction Property FMR_PregnancyFaction Auto Hidden

string Function GetPluginId()
    return "lme.fmr"
EndFunction
string Function GetPluginLabel()
    return "FMR (Fertility Mode)"
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

int Function GetConditionCount()
    return 2
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "pregnancy"
    elseif idx == 1
        return "ovulation"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "Pregnancy"
    elseif idx == 1
        return "Ovulation"
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx == 0
        return "Min belly stage (1-100)"
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    if idx == 0
        return 1
    endif
    return 0
EndFunction

int Function GetConditionParamMax(int idx)
    if idx == 0
        return 100
    endif
    return 0
EndFunction

int Function GetConditionParamDefault(int idx)
    if idx == 0
        return 1
    endif
    return 0
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None || FMR_PregnancyFaction == None
        return false
    endif
    int rank = target.GetFactionRank(FMR_PregnancyFaction)
    if idx == 0
        return rank >= param && rank <= 100
    elseif idx == 1
        return rank == 118
    endif
    return false
EndFunction
