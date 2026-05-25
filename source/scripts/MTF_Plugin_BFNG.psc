Scriptname MTF_Plugin_BFNG extends MTF_Plugin
{Conditions and effects backed by Beeing Female NG (crajjjj fork; SE/AE).
 Soft-master: lookup at runtime; if BFNG isn't loaded the plugin skips
 registration entirely.

 Metadata loaded from mtf.bfng.json by the base class.

 Conditions:
   0  pregnancy     — IsPregnant AND GetStatePercentage >= param (1..100)
   1  ovulation     — GetFemaleState == 1 (Ovulating)
   2  cycle.phase   — GetFemaleState matches param (0..3 dropdown:
                      follicular / ovulating / luteal / menstruating)
   3  baby.health   — pregnant AND GetBabyHealth >= param
   4  num.births    — GetNumBirth >= param

 Effects:
   0  trigger.ovulation  — one-shot: ChangeState(target, 1). No-op if
                            already pregnant (BFNG cycle is suspended
                            during gestation).

 BFNG's FWController quest (FormID 0x182A on BeeingFemale.esm) is the
 single dependency.}

FWController Property BFController Auto Hidden

string Function GetPluginId()
    return "mtf.bfng"
EndFunction

bool Function _resolveDeps()
    if BFController != None
        return true
    endif
    BFController = Game.GetFormFromFile(0x182A, "BeeingFemale.esm") as FWController
    return BFController != None
EndFunction

; _tryRegister + _host lifted to MTF_Plugin base class. _resolveDeps above is
; the only thing this plugin customises.

; ── Behaviour (stays in Papyrus — can't be data) ────────────────────────────
bool Function checkCondition(Actor target, int param, string cid)
    if target == None || BFController == None
        return false
    endif
    if cid == "pregnancy"
        ; pregnancy: actor must be pregnant AND belly stage >= param.
        if !BFController.IsPregnant(target)
            return false
        endif
        ; GetStatePercentage during pregnancy returns 0..100 belly progress.
        ; param=1 = "any belly stage" (default), param=100 = "near term".
        float pct = BFController.GetStatePercentage(target)
        int stage = pct as int
        if stage < 1
            stage = 1
        elseif stage > 100
            stage = 100
        endif
        return stage >= param
    elseif cid == "ovulation"
        ; ovulation: cycle phase == 1 (Ovulating).
        return BFController.GetFemaleState(target) == 1
    elseif cid == "cycle.phase"
        ; cycle.phase: phase enum matches the picked option.
        return BFController.GetFemaleState(target) == param
    elseif cid == "baby.health"
        ; baby.health: only meaningful while pregnant.
        if !BFController.IsPregnant(target)
            return false
        endif
        return (BFController.GetBabyHealth(target) as int) >= param
    elseif cid == "num.births"
        return BFController.GetNumBirth(target) >= param
    endif
    return false
EndFunction

Function onActivate(Actor target, int param, int param2, string eid)
    if eid != "trigger.ovulation" || target == None || BFController == None
        return
    endif
    ; Don't override a pregnancy — same guard FMR uses. Forcing ovulation
    ; while pregnant would silently no-op on BFNG's side anyway (cycle is
    ; suspended during gestation), but explicit is better.
    if BFController.IsPregnant(target)
        return
    endif
    if BFController.GetFemaleState(target) == 1
        ; Already ovulating.
        return
    endif
    BFController.ChangeState(target, 1)
EndFunction
