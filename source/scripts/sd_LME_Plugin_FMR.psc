Scriptname sd_LME_Plugin_FMR extends sd_LME_ConditionPlugin
{Conditions backed by Fertility Mode Reloaded. Soft-master: lookup at runtime;
 if FMR isn't loaded the plugin skips registration entirely.

 Items:
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

int Function GetItemCount()
    return 2
EndFunction

string Function GetItemId(int idx)
    if idx == 0
        return "pregnancy"
    elseif idx == 1
        return "ovulation"
    endif
    return ""
EndFunction

string Function GetItemLabel(int idx)
    if idx == 0
        return "Pregnancy"
    elseif idx == 1
        return "Ovulation"
    endif
    return ""
EndFunction

string Function GetItemParamLabel(int idx)
    if idx == 0
        return "Min belly stage (1-100)"
    endif
    return ""    ; ovulation: no param
EndFunction

int Function GetItemParamMin(int idx)
    if idx == 0
        return 1
    endif
    return 0
EndFunction

int Function GetItemParamMax(int idx)
    if idx == 0
        return 100
    endif
    return 0
EndFunction

int Function GetItemParamDefault(int idx)
    if idx == 0
        return 1
    endif
    return 0
EndFunction

bool Function checkItem(int idx, Actor target, int param)
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
