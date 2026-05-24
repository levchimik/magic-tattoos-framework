Scriptname MTF_Plugin_FMR extends MTF_Plugin
{Conditions and effects backed by Fertility Mode (original or Reloaded).
 Soft-master: lookup at runtime; if Fertility Mode isn't loaded the plugin
 skips registration. Reads the _JSW_BB_Storage script directly so it works
 on both the original Fertility Mode and FMR — the FMR pregnancy faction
 (0x02666B) doesn't exist in the original mod.

 Conditions:
   0  pregnancy  — belly stage (1..100), computed from
                    (GameTime - LastConception) / PregnancyDuration
   1  ovulation  — LastOvulation in (0, EggLife] AND not pregnant.
                    FMR doesn't clear LastOvulation on conception, so the raw
                    flag stays true through early pregnancy; gate on
                    LastConception == 0 to match FMR's own "isOvulating &&
                    !isPregnant" MCM semantics.

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
        ; Deps not yet loaded (Fertility Mode may not be active, or its forms
        ; aren't resolvable yet). Re-arm; without this the bail is silent and
        ; nothing ever retries — we'd stay unregistered for the session.
        RegisterForSingleUpdate(2.0)
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

string Function GetConditionDescription(int idx)
    if idx == 0
        return "Triggers when the actor is pregnant and at least {param1}% through her pregnancy."
    elseif idx == 1
        return "Triggers while the actor is in her fertile window (recently ovulated, egg still viable)."
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
    string who = "(none)"
    if target != None
        who = target.GetDisplayName()
    endif
    int i = _trackedIndex(target)
    if i < 0
        Debug.Trace("[mtf.fmr] cond idx=" + idx + " who=" + who + " NOT_TRACKED i=" + i)
        return false
    endif
    if idx == 0
        if FMR_Storage.LastConception == None || FMR_PregnancyDuration == None
            Debug.Trace("[mtf.fmr] pregnancy who=" + who + " i=" + i + " deps_missing LastConception=" + (FMR_Storage.LastConception != None) + " PregDur=" + (FMR_PregnancyDuration != None))
            return false
        endif
        float conceived = FMR_Storage.LastConception[i]
        if conceived <= 0.0
            Debug.Trace("[mtf.fmr] pregnancy who=" + who + " i=" + i + " NOT_PREGNANT LastConception=" + conceived)
            return false
        endif
        float duration = FMR_PregnancyDuration.GetValue()
        if duration <= 0.0
            Debug.Trace("[mtf.fmr] pregnancy who=" + who + " i=" + i + " PregDur<=0 (" + duration + ")")
            return false
        endif
        float elapsed = Utility.GetCurrentGameTime() - conceived
        if elapsed < 0.0
            Debug.Trace("[mtf.fmr] pregnancy who=" + who + " i=" + i + " NEG_ELAPSED (" + elapsed + ")")
            return false
        endif
        int stage = ((elapsed / duration) * 100.0) as int
        if stage < 1
            stage = 1
        elseif stage > 100
            stage = 100
        endif
        bool result = stage >= param
        Debug.Trace("[mtf.fmr] pregnancy who=" + who + " i=" + i + " LastConception=" + conceived + " elapsed=" + elapsed + " dur=" + duration + " stage=" + stage + " param=" + param + " -> " + result)
        return result
    elseif idx == 1
        if FMR_Storage.LastOvulation == None || FMR_EggLife == None
            Debug.Trace("[mtf.fmr] ovulation who=" + who + " i=" + i + " deps_missing LastOvulation=" + (FMR_Storage.LastOvulation != None) + " EggLife=" + (FMR_EggLife != None))
            return false
        endif
        ; Pregnancy gate: FMR's natural-conception path doesn't clear LastOvulation
        ; (HandlerQuestAliasScript.psc:1129) — the egg only ages out later. Without
        ; this gate, freshly-pregnant actors show as "ovulating" until then. Mirrors
        ; FMR's own MCM filter logic (isOvulating && !isPregnant).
        float conceived = 0.0
        if FMR_Storage.LastConception != None
            conceived = FMR_Storage.LastConception[i]
        endif
        float ov = FMR_Storage.LastOvulation[i]
        float eggLife = FMR_EggLife.GetValue()
        bool result = conceived <= 0.0 && ov > 0.0 && ov <= eggLife
        Debug.Trace("[mtf.fmr] ovulation who=" + who + " i=" + i + " LastOvulation=" + ov + " EggLife=" + eggLife + " LastConception=" + conceived + " -> " + result)
        return result
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

string Function GetEffectDescription(int idx)
    if idx == 0
        return "Burst — forces the actor to start ovulating (does nothing if she is already pregnant)."
    endif
    return ""
EndFunction

Function onActivate(int idx, Actor target, int param, int param2)
    string who = "(none)"
    if target != None
        who = target.GetDisplayName()
    endif
    Debug.Trace("[mtf.fmr] effect.activate idx=" + idx + " who=" + who + " param=" + param + " param2=" + param2)
    if idx != 0
        Debug.Trace("[mtf.fmr] effect.activate bail: idx!=0")
        return
    endif
    if target == None
        Debug.Trace("[mtf.fmr] effect.activate bail: target==None")
        return
    endif
    if FMR_Storage == None
        Debug.Trace("[mtf.fmr] effect.activate bail: FMR_Storage==None")
        return
    endif
    int i = _trackedIndex(target)
    if i < 0
        Debug.Trace("[mtf.fmr] effect.activate bail: NOT_TRACKED i=" + i + " trackedActorsLen=" + FMR_Storage.TrackedActors.Length)
        return
    endif
    ; NOTE: `if FMR_Storage.LastOvulation == None` was bailing here even though
    ; checkCondition reads LastOvulation[i] successfully at the same moment
    ; (project_papyrus_array_none_cast_noise memory note — `== None` on Auto
    ; array properties is unreliable). Drop the guard and dump .Length instead
    ; so we can distinguish a true-None from the comparison quirk.
    int ovLen = -1
    int lcLen = -1
    if FMR_Storage.LastOvulation
        ovLen = FMR_Storage.LastOvulation.Length
    endif
    if FMR_Storage.LastConception
        lcLen = FMR_Storage.LastConception.Length
    endif
    Debug.Trace("[mtf.fmr] effect.activate i=" + i + " ovLen=" + ovLen + " lcLen=" + lcLen)
    ; Don't interrupt an in-progress pregnancy. Indexed read is safe; if the
    ; array were truly None the indexed access would Papyrus-error and abort.
    float conceived = FMR_Storage.LastConception[i]
    if conceived > 0.0
        Debug.Trace("[mtf.fmr] effect.activate bail: ALREADY_PREGNANT LastConception=" + conceived)
        return
    endif
    float ovBefore = FMR_Storage.LastOvulation[i]
    if ovBefore > 0.0
        Debug.Trace("[mtf.fmr] effect.activate bail: ALREADY_OVULATING LastOvulation=" + ovBefore)
        return
    endif
    Debug.Trace("[mtf.fmr] effect.activate writing LastOvulation[" + i + "] = 0.001 (was " + ovBefore + ")")
    FMR_Storage.LastOvulation[i] = 0.001
    ; Read-back to confirm the indexed write actually stuck. Papyrus array
    ; indexed-writes through a remote script's property can silently hit a
    ; transient copy (project_papyrus_property_array_writes memory note).
    float ovAfter = FMR_Storage.LastOvulation[i]
    Debug.Trace("[mtf.fmr] effect.activate readback LastOvulation[" + i + "] = " + ovAfter + " (write " + (ovAfter > 0.0) + ")")
EndFunction
