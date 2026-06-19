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
   7  pregnancy.stage  — GetFemaleState matches param (dropdown: trimester1/2/3
                         /labor/recovery -> states 4/5/6/7/8)
   5  father.near      — father of the CURRENT pregnancy (FW.ChildFather) is
                         loaded within param metres. Empty unless pregnant; a mere
                         sperm donor (FW.SpermName) does NOT count.
   6  father.near.past — father of an already-born child (FW.BornChildFather)
                         is loaded within param metres

 Effects (eid-keyed; bursts fire in onActivate, sustained set in onActivate
 and restore in onDeactivate):
   trigger.ovulation   burst     ChangeState(t,1). No-op if pregnant/ovulating.
   mark.fecundity      sustained guarantee a multiple pregnancy (setNumBabys),
                                 enforced each game-hour while worn. param1 = babies.
   hex.barren          sustained block conception while worn; prior flag stashed
                                 and restored on removal (setCanBecomePregnant).
   charm.serenity      sustained suppress PMS while worn (setCanBecomePMS).
   purge.contraception burst     SetContraception(t,0.0) — scale-immune.
   gift.fertility      burst     setCanBecomePregnant(t,true).
   induce.pms          burst     setCanBecomePMS(t,true).
   restore.natural     burst     setAutoFlag(t) — clear manual overrides.
   rite.quickening     burst     ActiveSpermImpregnation(t). No-op if pregnant.
   trigger.labor       burst     ChangeState(t,7) only from third trimester (6).
   reset.cycle         burst     ChangeState(t,0). No-op while pregnant.
   end.pregnancy       burst     AbortusBaby(t). No-op if not pregnant.
   ward.womb           sustained heal unborn each game-hour (HealBaby cmd).
   ward.contraception  sustained top up contraception each game-hour (0-100 scale).
   cleanse.sperm       burst     WashOutSperm cmd (param1 = %).
   blight.womb         burst     DamageBaby cmd. No-op if not pregnant.

 The womb/sperm/contraception effects use BFNG's public "BeeingFemale" command
 ModEvent (sender = the actor) rather than direct FWController calls — version-
 resilient and routed through BFNG's own actor validation. See FWSystem.psc
 onBeeingFemaleCommand. BFNG's FWController quest (FormID 0x182A on
 BeeingFemale.esm) is the single dependency.}

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
        ; cycle.phase: phase id matches the picked option. v0.2.9 schema v2 —
        ; param1 carries a string id; map to BFNG's GetFemaleState int.
        string phaseId = _host().GetEvalParamStr()
        int wantPhase = -1
        if phaseId == "follicular"
            wantPhase = 0
        elseif phaseId == "ovulating"
            wantPhase = 1
        elseif phaseId == "luteal"
            wantPhase = 2
        elseif phaseId == "menstruating"
            wantPhase = 3
        endif
        if wantPhase < 0
            return false
        endif
        return BFController.GetFemaleState(target) == wantPhase
    elseif cid == "baby.health"
        ; baby.health: only meaningful while pregnant.
        if !BFController.IsPregnant(target)
            return false
        endif
        return (BFController.GetBabyHealth(target) as int) >= param
    elseif cid == "num.births"
        return BFController.GetNumBirth(target) >= param
    elseif cid == "pregnancy.stage"
        ; pregnancy.stage: discrete GetFemaleState match (4..8). Avoids the
        ; GetStatePercentage path. param1 is a menu string id.
        string stageId = _host().GetEvalParamStr()
        int wantState = -1
        if stageId == "trimester1"
            wantState = 4
        elseif stageId == "trimester2"
            wantState = 5
        elseif stageId == "trimester3"
            wantState = 6
        elseif stageId == "labor"
            wantState = 7
        elseif stageId == "recovery"
            wantState = 8
        endif
        if wantState < 0
            return false
        endif
        return BFController.GetFemaleState(target) == wantState
    elseif cid == "father.near"
        ; father.near: the father of the CURRENT pregnancy is loaded within range.
        ; FW.ChildFather is written at impregnation, so this is empty unless she is
        ; actually pregnant — a mere sperm donor (FW.SpermName) does not count.
        return _anyFormListActorWithin(target, "FW.ChildFather", _radiusUnits(param))
    elseif cid == "father.near.past"
        ; father.near.past: a father of an already-born child is loaded within range.
        return _anyFormListActorWithin(target, "FW.BornChildFather", _radiusUnits(param))
    endif
    return false
EndFunction

float Function _radiusUnits(int radiusM) global
    if radiusM < 1
        radiusM = 1
    endif
    ; ~69.99 game units per metre (matches the SLA plugin's aura conversion).
    return (radiusM as float) * 70.0
EndFunction

bool Function _anyFormListActorWithin(Actor target, string key, float radius)
    int n = StorageUtil.FormListCount(target, key)
    int i = 0
    while i < n
        Actor f = StorageUtil.FormListGet(target, key, i) as Actor
        if f != None && f != target && f.Is3DLoaded() && f.GetDistance(target) <= radius
            return true
        endif
        i += 1
    endwhile
    return false
EndFunction

Function onActivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if target == None || BFController == None
        return
    endif
    if eid == "trigger.ovulation"
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

    elseif eid == "purge.contraception"
        ; Scale-immune: 0.0 = no protection regardless of BFNG's contraception
        ; domain (sidesteps the unresolved unit-scale question).
        BFController.SetContraception(target, 0.0)

    elseif eid == "gift.fertility"
        ; Flag that she *can* conceive — does not force conception. Pair with
        ; rite.quickening to actually impregnate.
        BFController.setCanBecomePregnant(target, true)

    elseif eid == "induce.pms"
        BFController.setCanBecomePMS(target, true)

    elseif eid == "restore.natural"
        ; Clear all manual fertility/PMS overrides back to BFNG auto.
        BFController.setAutoFlag(target)

    elseif eid == "rite.quickening"
        ; Force conception from sperm already present. No-op if already pregnant;
        ; BFNG no-ops on its side too if no relevant sperm. Respects contraception.
        if !BFController.IsPregnant(target)
            BFController.ActiveSpermImpregnation(target, false)
        endif

    elseif eid == "trigger.labor"
        ; Induce birth only from the third trimester (state 6 -> labor 7).
        if BFController.GetFemaleState(target) == 6
            BFController.ChangeState(target, 7)
        endif

    elseif eid == "reset.cycle"
        ; Restart the cycle from follicular. Guard against interrupting a pregnancy.
        if !BFController.IsPregnant(target)
            BFController.ChangeState(target, 0)
        endif

    elseif eid == "end.pregnancy"
        ; Terminate an active pregnancy (miscarriage). Gated on IsPregnant.
        if BFController.IsPregnant(target)
            BFController.AbortusBaby(target)
        endif

    elseif eid == "hex.barren"
        ; Sustained: block conception while worn. Stash the prior flag so a
        ; naturally-infertile actor isn't silently made fertile on removal.
        StorageUtil.SetIntValue(target, _flagStashKey("barren", slot, effectIdx), BFController.canBecomePregnant(target) as int)
        BFController.setCanBecomePregnant(target, false)

    elseif eid == "charm.serenity"
        ; Sustained: suppress PMS while worn. Stash prior flag for restore.
        StorageUtil.SetIntValue(target, _flagStashKey("serenity", slot, effectIdx), BFController.canBecomePMS(target) as int)
        BFController.setCanBecomePMS(target, false)

    elseif eid == "mark.fecundity"
        ; Sustained: enforced each game-hour in onGameTime. Apply once now too so
        ; a fresh conception doesn't wait up to an hour for the first bump.
        _enforceFecundity(target, param)

    elseif eid == "cleanse.sperm"
        ; Wash out param% of sperm currently inside her (default 100).
        _bfCmd(target, "WashOutSperm", param)

    elseif eid == "blight.womb"
        ; Damage the unborn baby by param. No-op if not pregnant.
        if BFController.IsPregnant(target)
            _bfCmd(target, "DamageBaby", param)
        endif

    elseif eid == "ward.womb"
        ; Sustained: heal unborn each game-hour (see onGameTime). Apply once now.
        if BFController.IsPregnant(target)
            _bfCmd(target, "HealBaby", param)
        endif

    elseif eid == "ward.contraception"
        ; Sustained: top up contraception each game-hour (see onGameTime). Apply now.
        _bfCmd(target, "AddContraception", param)
    endif
EndFunction

Function onDeactivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    ; Safe to call even if onActivate never ran: _popFlag defaults to true (BFNG's
    ; natural "can become" state) when no stash exists.
    if target == None || BFController == None
        return
    endif
    if eid == "hex.barren"
        BFController.setCanBecomePregnant(target, _popFlag(target, "barren", slot, effectIdx))
    elseif eid == "charm.serenity"
        BFController.setCanBecomePMS(target, _popFlag(target, "serenity", slot, effectIdx))
    endif
EndFunction

Function onGameTime(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if target == None || BFController == None
        return
    endif
    if eid == "mark.fecundity"
        _enforceFecundity(target, param)
    elseif eid == "ward.womb"
        ; Top up the unborn's health while worn. AddBaby-health is capped at 100
        ; inside BFNG; a no-op when not pregnant.
        if BFController.IsPregnant(target)
            _bfCmd(target, "HealBaby", param)
        endif
    elseif eid == "ward.contraception"
        ; Keep contraception from ever lapsing. AddContraception is additive and
        ; capped at 100 inside BFNG.
        _bfCmd(target, "AddContraception", param)
    endif
EndFunction

; ── helpers ─────────────────────────────────────────────────────────────────
Function _bfCmd(Actor target, string cmd, int amount)
    ; BFNG public command channel: the actor is the ModEvent sender, the command
    ; is the string arg, the amount is the numeric arg. Handled by FWSystem's
    ; onBeeingFemaleCommand (routes through BFNG's actor validation).
    target.SendModEvent("BeeingFemale", cmd, amount as float)
EndFunction
string Function _flagStashKey(string tag, int slot, int eff) global
    return "mtf.bfng." + tag + ".prev." + slot + "." + eff
EndFunction

bool Function _popFlag(Actor target, string tag, int slot, int eff)
    ; Read-and-clear the stashed flag; default true (BFNG's natural state) if absent.
    string key = _flagStashKey(tag, slot, eff)
    bool prev = true
    if StorageUtil.HasIntValue(target, key)
        prev = StorageUtil.GetIntValue(target, key) != 0
        StorageUtil.UnsetIntValue(target, key)
    endif
    return prev
EndFunction

Function _enforceFecundity(Actor target, int wantBabies)
    ; Guarantee a multiple pregnancy: while pregnant, raise the litter to
    ; `wantBabies` if BFNG rolled fewer. Never lowers an existing larger litter.
    if wantBabies < 2
        wantBabies = 2
    endif
    if BFController.IsPregnant(target) && BFController.getNumBabys(target) < wantBabies
        BFController.setNumBabys(target, wantBabies)
    endif
EndFunction
