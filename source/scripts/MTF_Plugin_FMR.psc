Scriptname MTF_Plugin_FMR extends MTF_Plugin
{Conditions and effects backed by Fertility Mode (original or Reloaded).
 Soft-master: lookup at runtime; if Fertility Mode isn't loaded the plugin
 skips registration. Reads the _JSW_BB_Storage script directly so it works
 on both the original Fertility Mode and FMR — the FMR pregnancy faction
 (0x02666B) doesn't exist in the original mod.

 Conditions:
   0  pregnancy  — belly stage (1..100), computed from
                    (GameTime - LastConception) / PregnancyDuration
   1  ovulation  — LastOvulation in (0, EggLife]

 Effects:
   0  trigger.ovulation  — one-shot: set LastOvulation[index] = 0.001
                            (no-op if currently pregnant)}

_JSW_BB_Storage Property FMR_Storage Auto Hidden
GlobalVariable Property FMR_EggLife Auto Hidden
GlobalVariable Property FMR_PregnancyDuration Auto Hidden

string Function GetPluginId()
    return "mtf.fmr"
EndFunction
string Function GetPluginLabel()
    return "Fertility Mode (v3 / Reloaded)"
EndFunction

bool Function _resolveDeps()
    if FMR_Storage != None && FMR_EggLife != None && FMR_PregnancyDuration != None
        return true
    endif
    if FMR_Storage == None
        FMR_Storage = Game.GetFormFromFile(0x000D62, "Fertility Mode.esm") as _JSW_BB_Storage
    endif
    if FMR_EggLife == None
        FMR_EggLife = Game.GetFormFromFile(0x0125F1, "Fertility Mode.esm") as GlobalVariable
    endif
    if FMR_PregnancyDuration == None
        FMR_PregnancyDuration = Game.GetFormFromFile(0x000D66, "Fertility Mode.esm") as GlobalVariable
    endif
    return FMR_Storage != None
EndFunction

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        return
    endif
    MTF_MainQuest host = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
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

int Function _trackedIndex(Actor target)
    if target == None || FMR_Storage == None || FMR_Storage.TrackedActors == None
        return -1
    endif
    return FMR_Storage.TrackedActors.Find(target as Form)
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    int i = _trackedIndex(target)
    if i < 0
        return false
    endif
    if idx == 0
        if FMR_Storage.LastConception == None || FMR_PregnancyDuration == None
            return false
        endif
        float conceived = FMR_Storage.LastConception[i]
        if conceived <= 0.0
            return false
        endif
        float duration = FMR_PregnancyDuration.GetValue()
        if duration <= 0.0
            return false
        endif
        float elapsed = Utility.GetCurrentGameTime() - conceived
        if elapsed < 0.0
            return false
        endif
        int stage = ((elapsed / duration) * 100.0) as int
        if stage < 1
            stage = 1
        elseif stage > 100
            stage = 100
        endif
        return stage >= param
    elseif idx == 1
        if FMR_Storage.LastOvulation == None || FMR_EggLife == None
            return false
        endif
        float ov = FMR_Storage.LastOvulation[i]
        return ov > 0.0 && ov <= FMR_EggLife.GetValue()
    endif
    return false
EndFunction

; ── Effects ───────────────────────────────────────────────────────────────────

int Function GetEffectCount()
    return 1
EndFunction

string Function GetEffectId(int idx)
    if idx == 0
        return "trigger.ovulation"
    endif
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    if idx == 0
        return "[!] Trigger Ovulation"
    endif
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    return ""
EndFunction

Function onActivate(int idx, Actor target, int param)
    if idx != 0 || target == None || FMR_Storage == None
        return
    endif
    int i = _trackedIndex(target)
    if i < 0
        return
    endif
    ; Don't interrupt an in-progress pregnancy.
    if FMR_Storage.LastConception != None && FMR_Storage.LastConception[i] > 0.0
        return
    endif
    if FMR_Storage.LastOvulation == None
        return
    endif
    if FMR_Storage.LastOvulation[i] > 0.0
        ; Already ovulating.
        return
    endif
    FMR_Storage.LastOvulation[i] = 0.001
EndFunction
