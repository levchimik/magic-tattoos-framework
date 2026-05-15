Scriptname sd_LME_Plugin_Arousal extends sd_LME_ConditionPlugin
{Soft dependency on SexLabAroused.esm — looked up at runtime so the
 master can be dropped from LewdMarksEffects.esp. If SLA isn't loaded,
 the plugin silently skips registration.}

slaFrameWorkScr Property SLAFramework Auto Hidden

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

bool Function _resolveDeps()
    if SLAFramework != None
        return true
    endif
    SLAFramework = Game.GetFormFromFile(0x04290F, "SexLabAroused.esm") as slaFrameWorkScr
    return SLAFramework != None
EndFunction

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        ; SLA not loaded — stay dormant.
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
    if SLAFramework == None
        return false
    endif
    return SLAFramework.GetActorArousal(target) >= param
EndFunction
