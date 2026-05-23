Scriptname MTF_Plugin_BFNG extends MTF_Plugin
{Conditions and effects backed by Beeing Female NG (crajjjj fork; SE/AE).
 Soft-master: lookup at runtime; if BFNG isn't loaded the plugin skips
 registration entirely.

 Mirrors the surface of MTF_Plugin_FMR (pregnancy + ovulation conditions
 + trigger.ovulation effect) so presets authored against one can be
 retargeted with a key swap. BFNG also gets a couple of native extras
 (cycle.phase dropdown, baby.health threshold) because the API surfaces
 them cleanly.

 Conditions:
   0  pregnancy     — IsPregnant AND belly stage (GetStatePercentage when
                      pregnant) >= param (1..100)
   1  ovulation     — GetFemaleState == 1 (Ovulating)
   2  cycle.phase   — GetFemaleState matches param (0/1/2/3 — dropdown
                      menstrual/follicular/ovulatory/luteal). Useful for
                      a 4-tier tattoo system tied to cycle.
   3  baby.health   — GetBabyHealth >= param (only meaningful while
                      pregnant; mirrors "damage" narratives)
   4  num.births    — GetNumBirth >= param (slow-evolving counter)

 Effects:
   0  trigger.ovulation  — one-shot: ChangeState(target, 1). Does nothing
                            if already pregnant — BFNG's pregnancy state
                            takes precedence.

 BFNG's FWController quest (FormID 0x182A on BeeingFemale.esm) is the
 single dependency. The cycle state enum is documented in the FWController
 stub in `_deps/`.}

FWController Property BFController Auto Hidden

MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

string Function GetPluginId()
    return "mtf.bfng"
EndFunction
string Function GetPluginLabel()
    return "Beeing Female NG"
EndFunction

bool Function _resolveDeps()
    if BFController != None
        return true
    endif
    BFController = Game.GetFormFromFile(0x182A, "BeeingFemale.esm") as FWController
    return BFController != None
EndFunction

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        ; BFNG not loaded — re-arm. Without the re-arm we'd silently stay
        ; unregistered forever (load order or late-init scenarios).
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

; ── Conditions ────────────────────────────────────────────────────────────────

int Function GetConditionCount()
    return 5
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "pregnancy"
    elseif idx == 1
        return "ovulation"
    elseif idx == 2
        return "cycle.phase"
    elseif idx == 3
        return "baby.health"
    elseif idx == 4
        return "num.births"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "Pregnancy"
    elseif idx == 1
        return "Ovulation"
    elseif idx == 2
        return "Cycle Phase"
    elseif idx == 3
        return "Baby Health"
    elseif idx == 4
        return "Birth Count"
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx == 0
        return "Min belly stage (1-100)"
    elseif idx == 1
        return ""
    elseif idx == 2
        return "Phase"
    elseif idx == 3
        return "Min baby health (0-100)"
    elseif idx == 4
        return "Min births"
    endif
    return ""
EndFunction

string Function GetConditionDescription(int idx)
    if idx == 0
        return "Triggers when the actor is pregnant and at least {param1}% through her pregnancy."
    elseif idx == 1
        return "Triggers while the actor is ovulating."
    elseif idx == 2
        return "Triggers when the actor is in the {param1} part of her cycle."
    elseif idx == 3
        return "Triggers while the actor is pregnant and the baby is at least {param1}% healthy."
    elseif idx == 4
        return "Triggers when the actor has given birth at least {param1} time(s) before."
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
    if idx == 0 || idx == 3
        return 100
    elseif idx == 2
        return 3
    elseif idx == 4
        return 20
    endif
    return 0
EndFunction

int Function GetConditionParamDefault(int idx)
    if idx == 0
        return 1
    elseif idx == 2
        return 1
    elseif idx == 3
        return 50
    elseif idx == 4
        return 1
    endif
    return 0
EndFunction

; ── Cycle phase dropdown (cond idx 2) ───────────────────────────────────────

int Function GetConditionParamMenuOptionCount(int idx)
    if idx == 2
        return 4
    endif
    return 0
EndFunction

int Function GetConditionParamMenuOptionValue(int idx, int optionIdx)
    if idx == 2
        return optionIdx
    endif
    return 0
EndFunction

string Function GetConditionParamMenuOptionLabel(int idx, int optionIdx)
    if idx == 2
        if optionIdx == 0
            return "Follicular"
        elseif optionIdx == 1
            return "Ovulating"
        elseif optionIdx == 2
            return "Luteal"
        elseif optionIdx == 3
            return "Menstruating"
        endif
    endif
    return ""
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None || BFController == None
        return false
    endif
    if idx == 0
        ; pregnancy: actor must be tracked + pregnant AND belly stage >= param
        if !BFController.IsPregnant(target)
            return false
        endif
        ; GetStatePercentage during pregnancy returns 0..100 belly progress.
        ; param=1 means "any belly stage" (default), param=100 means "near term".
        float pct = BFController.GetStatePercentage(target)
        int stage = pct as int
        if stage < 1
            stage = 1
        elseif stage > 100
            stage = 100
        endif
        return stage >= param
    elseif idx == 1
        ; ovulation: cycle phase == 1 (Ovulating)
        return BFController.GetFemaleState(target) == 1
    elseif idx == 2
        ; cycle.phase: phase enum matches the picked option
        return BFController.GetFemaleState(target) == param
    elseif idx == 3
        ; baby.health: only meaningful while pregnant
        if !BFController.IsPregnant(target)
            return false
        endif
        return (BFController.GetBabyHealth(target) as int) >= param
    elseif idx == 4
        return BFController.GetNumBirth(target) >= param
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
    if idx != 0 || target == None || BFController == None
        return
    endif
    ; Don't override a pregnancy — same guard FMR uses. Forcing ovulation
    ; while pregnant would silently no-op on BFNG's side anyway (the
    ; cycle is suspended during gestation), but explicit is better.
    if BFController.IsPregnant(target)
        return
    endif
    ; Already ovulating: no-op.
    if BFController.GetFemaleState(target) == 1
        return
    endif
    BFController.ChangeState(target, 1)
EndFunction
