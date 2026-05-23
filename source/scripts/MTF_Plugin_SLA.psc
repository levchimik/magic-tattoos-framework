Scriptname MTF_Plugin_SLA extends MTF_Plugin
{Conditions and effects backed by SexLab Aroused. Soft-master: lookup at
 runtime; if SLA isn't loaded the plugin skips registration entirely.

 All methods used here exist on the canonical slaFrameWorkScr class shared
 by every SLA fork (OSL Aroused, SLO Aroused NG, Aroused Redux), so the
 plugin works regardless of which fork the user has loaded.

 Conditions:
   0  arousal            — SLA exposure >= threshold (param 0..100)
   1  days.since.orgasm  — days since last orgasm >= threshold (param 0..30)
   2  exposure.rate      — per-actor exposure rate >= threshold (param 0..100)
   3  arousal.lock       — IsActorArousalLocked flag matches (param 0 = unlocked, 1 = locked)

 Effects:
   0  arousal.rate       — increase target's SLA exposure by `param` per game-hour
   1  arousal.rate.npc   — increase nearby NPCs' SLA exposure by `param` per game-hour;
                          radius is per-slot `param2` (meters, default 22)
   2  modify.arousal     — one-shot: add `param` exposure on self on switch
   3  set.exposure.rate  — set target's exposure rate to `param` while active,
                          restore previous rate on deactivate
   4  trigger.orgasm     — one-shot: call UpdateActorOrgasmDate (resets the
                          "days since orgasm" timer to 0)

 No plugin-level settings — the aura radius is per-slot (effect param2);
 the per-tick NPC cap is hardcoded to PHEROMONE_MAX_TARGETS (30).}

slaFrameWorkScr Property SLAFramework Auto Hidden

MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

; Maximum NPCs the Pheromone Aura can affect in one game-hour tick.
; Caps the cost in crowds. Not user-tunable.
int Function PHEROMONE_MAX_TARGETS() global
    return 30
EndFunction

string Function GetPluginId()
    return "mtf.sla"
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
        ; Deps not yet loaded (SexLab Aroused may not be active, or its forms
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

; ── Conditions ────────────────────────────────────────────────────────────────

int Function GetConditionCount()
    return 4
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "arousal"
    elseif idx == 1
        return "days.since.orgasm"
    elseif idx == 2
        return "exposure.rate"
    elseif idx == 3
        return "arousal.lock"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "Arousal"
    elseif idx == 1
        return "Days Since Orgasm"
    elseif idx == 2
        return "Exposure Rate"
    elseif idx == 3
        return "Arousal Locked"
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx == 0
        return "Arousal threshold"
    elseif idx == 1
        return "Min days since orgasm"
    elseif idx == 2
        return "Min exposure rate"
    elseif idx == 3
        return "Lock state"
    endif
    return ""
EndFunction

string Function GetConditionDescription(int idx)
    if idx == 0
        return "Triggers when the actor's arousal is at or above {param1}%."
    elseif idx == 1
        return "Triggers when the actor has gone without orgasm for at least {param1} day(s)."
    elseif idx == 2
        return "Triggers when the actor's arousal is climbing at least {param1} per check."
    elseif idx == 3
        return "Triggers when the actor's arousal is {param1}%."
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    return 0
EndFunction

int Function GetConditionParamMax(int idx)
    if idx == 1
        return 30
    elseif idx == 3
        return 1
    endif
    return 100
EndFunction

int Function GetConditionParamDefault(int idx)
    if idx == 0
        return 80
    elseif idx == 1
        return 3
    elseif idx == 2
        return 25
    elseif idx == 3
        return 1
    endif
    return 0
EndFunction

; ── Arousal locked dropdown (cond idx 3) ────────────────────────────────────

int Function GetConditionParamMenuOptionCount(int idx)
    if idx == 3
        return 2
    endif
    return 0
EndFunction

int Function GetConditionParamMenuOptionValue(int idx, int optionIdx)
    if idx == 3
        return optionIdx  ; 0 = Unlocked, 1 = Locked
    endif
    return 0
EndFunction

string Function GetConditionParamMenuOptionLabel(int idx, int optionIdx)
    if idx == 3
        if optionIdx == 0
            return "Unlocked"
        elseif optionIdx == 1
            return "Locked"
        endif
    endif
    return ""
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None || SLAFramework == None
        return false
    endif
    if idx == 0
        return SLAFramework.GetActorArousal(target) >= param
    elseif idx == 1
        ; GetActorDaysSinceLastOrgasm returns float days. Threshold is integer days.
        return SLAFramework.GetActorDaysSinceLastOrgasm(target) >= (param as float)
    elseif idx == 2
        ; ExposureRate is float. Threshold is integer.
        return SLAFramework.GetActorExposureRate(target) >= (param as float)
    elseif idx == 3
        bool locked = SLAFramework.IsActorArousalLocked(target)
        if param == 1
            return locked
        endif
        return !locked
    endif
    return false
EndFunction

; ── Effects ───────────────────────────────────────────────────────────────────

int Function GetEffectCount()
    return 5
EndFunction

string Function GetEffectId(int idx)
    if idx == 0
        return "arousal.rate"
    elseif idx == 1
        return "arousal.rate.npc"
    elseif idx == 2
        return "modify.arousal"
    elseif idx == 3
        return "set.exposure.rate"
    elseif idx == 4
        return "trigger.orgasm"
    endif
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    if idx == 0
        return "Arousal Rate"
    elseif idx == 1
        return "NPC Arousal Rate"
    elseif idx == 2
        return "[!] Modify Arousal"
    elseif idx == 3
        return "Set Exposure Rate"
    elseif idx == 4
        return "[!] Trigger Orgasm"
    endif
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    if idx == 0
        return "Exposure delta on self per game-hour"
    elseif idx == 1
        return "Exposure delta on nearby NPCs per game-hour"
    elseif idx == 2
        return "Burst exposure added to self on switch"
    elseif idx == 3
        return "Exposure rate while active"
    endif
    return ""
EndFunction

string Function GetEffectDescription(int idx)
    if idx == 0
        return "Steadily raises the actor's arousal by {param1}% every in-game hour while active."
    elseif idx == 1
        return "Pheromone aura — steadily raises the arousal of nearby NPCs by {param1}% every in-game hour while active."
    elseif idx == 2
        return "Burst — adds {param1}% to the actor's arousal when the tier activates."
    elseif idx == 3
        return "Sets the actor's arousal-climb speed to {param1} while active, then restores the previous value on deactivate."
    elseif idx == 4
        return "Burst — resets the actor's 'days since orgasm' counter to zero when the tier activates."
    endif
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    return 0
EndFunction

int Function GetEffectParamMax(int idx)
    if idx == 3
        return 200
    endif
    return 100
EndFunction

int Function GetEffectParamDefault(int idx)
    if idx == 2
        return 25
    elseif idx == 3
        return 50
    endif
    return 5
EndFunction

; ── set.exposure.rate state plumbing ────────────────────────────────────────
; We need to restore the previous rate on deactivate. Store the pre-apply
; rate in StorageUtil under a per-actor key keyed on (slot, eff). Following
; the project_papyrus_storage_before_suspend rule: write storage BEFORE the
; suspending SetActorExposureRate call so a concurrent stack hits the
; "rate already applied" early-out.

string Function _rateStashKey(Actor target, int slot, int eff) global
    return "mtf.sla.rate.prev." + slot + "." + eff
EndFunction

Function onActivate(int idx, Actor target, int param, int param2)
    if SLAFramework == None || target == None
        return
    endif
    if idx == 2
        if param <= 0
            return
        endif
        int cur = SLAFramework.GetActorExposure(target)
        if cur < 0
            return
        endif
        SLAFramework.SetActorExposure(target, cur + param)
    elseif idx == 3
        MTF_MainQuest h = _host()
        if h == None
            return
        endif
        int slot = h._getDispatchSlot()
        int eff  = h._getDispatchEffectIdx()
        if slot < 0 || eff < 0
            return
        endif
        string key = _rateStashKey(target, slot, eff)
        ; Stash current rate so onDeactivate can restore it. Write BEFORE
        ; the suspending SetActorExposureRate to avoid a double-apply race.
        float prev = SLAFramework.GetActorExposureRate(target)
        StorageUtil.SetFloatValue(target, key, prev)
        SLAFramework.SetActorExposureRate(target, param as float)
    elseif idx == 4
        ; One-shot: reset "days since orgasm" timer.
        SLAFramework.UpdateActorOrgasmDate(target)
    endif
EndFunction

Function onDeactivate(int idx, Actor target, int param, int param2)
    if SLAFramework == None || target == None
        return
    endif
    if idx == 3
        MTF_MainQuest h = _host()
        if h == None
            return
        endif
        int slot = h._getDispatchSlot()
        int eff  = h._getDispatchEffectIdx()
        if slot < 0 || eff < 0
            return
        endif
        string key = _rateStashKey(target, slot, eff)
        if !StorageUtil.HasFloatValue(target, key)
            return
        endif
        float prev = StorageUtil.GetFloatValue(target, key)
        StorageUtil.UnsetFloatValue(target, key)
        SLAFramework.SetActorExposureRate(target, prev)
    endif
EndFunction

Function onGameTime(int idx, Actor target, int param, int param2)
    if SLAFramework == None || target == None || param <= 0
        return
    endif
    if idx == 0
        if SLAFramework.GetActorArousal(target) < 99
            int cur = SLAFramework.GetActorExposure(target)
            SLAFramework.SetActorExposure(target, cur + param)
        endif
    elseif idx == 1
        int radiusM = param2
        if radiusM <= 0
            radiusM = 22
        endif
        float radius = (radiusM as float) * 70.0
        int cap = PHEROMONE_MAX_TARGETS()
        Actor[] nearby = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
        if nearby == None
            return
        endif
        int i = 0
        int affected = 0
        while i < nearby.Length && affected < cap
            Actor a = nearby[i]
            if a != None && a != target && !a.IsDead()
                if a.GetDistance(target) <= radius
                    int ar = SLAFramework.GetActorArousal(a)
                    if ar >= 0 && ar < 99
                        int curExp = SLAFramework.GetActorExposure(a)
                        SLAFramework.SetActorExposure(a, curExp + param)
                        affected += 1
                    endif
                endif
            endif
            i += 1
        endwhile
    endif
EndFunction

; ── Per-effect param2 (Pheromone Aura radius) ───────────────────────────────

string Function GetEffectParam2Label(int idx)
    if idx == 1
        return "Aura radius (m)"
    endif
    return ""
EndFunction

int Function GetEffectParam2Min(int idx)
    if idx == 1
        return 5
    endif
    return 0
EndFunction

int Function GetEffectParam2Max(int idx)
    if idx == 1
        return 100
    endif
    return 0
EndFunction

int Function GetEffectParam2Default(int idx)
    if idx == 1
        return 22
    endif
    return 0
EndFunction

string Function GetEffectParam2Format(int idx)
    if idx == 1
        return "{0}m"
    endif
    return "{0}"
EndFunction

; No plugin-level settings — both legacy knobs (radius, max_targets) are gone:
; radius is now per-slot via param2; max_targets is hardcoded to 30.
