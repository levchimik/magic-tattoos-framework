Scriptname sd_LME_Plugin_FMR extends sd_LME_Plugin
{Conditions and effects backed by Fertility Mode Reloaded. Soft-master:
 lookup at runtime; if FMR isn't loaded the plugin skips registration.

 Conditions:
   0  pregnancy  — faction rank in 1..100 (belly stage)
   1  ovulation  — faction rank == 118

 Effects:
   0  trigger.ovulation  — one-shot: set faction rank to 118 on switch
                            (no-op if currently pregnant or recovering)}

Faction Property FMR_PregnancyFaction Auto Hidden
_JSW_BB_Storage Property FMR_Storage Auto Hidden

string Function GetPluginId()
    return "lme.fmr"
EndFunction
string Function GetPluginLabel()
    return "FMR (Fertility Mode)"
EndFunction

bool Function _resolveDeps()
    if FMR_PregnancyFaction != None && FMR_Storage != None
        return true
    endif
    if FMR_PregnancyFaction == None
        FMR_PregnancyFaction = Game.GetFormFromFile(0x02666B, "Fertility Mode.esm") as Faction
    endif
    if FMR_Storage == None
        FMR_Storage = Game.GetFormFromFile(0x000D62, "Fertility Mode.esm") as _JSW_BB_Storage
    endif
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
    if idx != 0 || target == None
        return
    endif
    ; Match the MCM "Force Ovulation" path: locate target in Storage.TrackedActors
    ; and set Storage.LastOvulation[index] = 0.001. Setting the faction rank alone
    ; isn't enough — FMR's state machine reads LastOvulation, and the faction rank
    ; is derived from it, not the other way around.
    if FMR_Storage == None
        return
    endif
    if FMR_PregnancyFaction != None
        int rank = target.GetFactionRank(FMR_PregnancyFaction)
        if rank >= 1 && rank <= 115
            ; Pregnant or recovering — do not interrupt FMR's state machine.
            return
        endif
    endif
    int trackedIdx = FMR_Storage.TrackedActors.Find(target as Form)
    if trackedIdx < 0
        return
    endif
    if FMR_Storage.LastOvulation[trackedIdx] > 0.0
        ; Already ovulating.
        return
    endif
    FMR_Storage.LastOvulation[trackedIdx] = 0.001
EndFunction
