Scriptname sd_LME_Plugin_SLA extends sd_LME_ConditionPlugin
{Conditions backed by SexLab Aroused. Soft-master: lookup at runtime;
 if SLA isn't loaded the plugin skips registration entirely.

 Items:
   0  arousal  — SLA exposure >= threshold}

slaFrameWorkScr Property SLAFramework Auto Hidden

string Function GetPluginId()
    return "lme.sla"
EndFunction
string Function GetPluginLabel()
    return "SLA (SexLab Aroused)"
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
    return 1
EndFunction

string Function GetItemId(int idx)
    if idx == 0
        return "arousal"
    endif
    return ""
EndFunction

string Function GetItemLabel(int idx)
    if idx == 0
        return "Arousal"
    endif
    return ""
EndFunction

string Function GetItemParamLabel(int idx)
    if idx == 0
        return "Arousal threshold"
    endif
    return ""
EndFunction

int Function GetItemParamMin(int idx)
    return 0
EndFunction

int Function GetItemParamMax(int idx)
    return 100
EndFunction

int Function GetItemParamDefault(int idx)
    if idx == 0
        return 80
    endif
    return 0
EndFunction

bool Function checkItem(int idx, Actor target, int param)
    if target == None || SLAFramework == None
        return false
    endif
    if idx == 0
        return SLAFramework.GetActorArousal(target) >= param
    endif
    return false
EndFunction
