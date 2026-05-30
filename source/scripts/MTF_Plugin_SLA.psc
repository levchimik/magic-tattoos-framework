Scriptname MTF_Plugin_SLA extends MTF_Plugin
{Conditions and effects backed by SexLab Aroused. Soft-master: lookup at
 runtime; if SLA isn't loaded the plugin skips registration entirely.

 Metadata loaded from mtf.sla.json by the base class.

 All methods used here exist on the canonical slaFrameWorkScr class shared
 by every SLA fork (OSL Aroused, SLO Aroused NG, Aroused Redux), so the
 plugin works regardless of which fork the user has loaded.

 Conditions:
   0  arousal            — SLA exposure >= threshold (param 0..100)
   1  days.since.orgasm  — days since last orgasm >= threshold (param 0..30)
   2  exposure.rate      — per-actor exposure rate >= threshold (param 0..100)
   3  arousal.lock       — IsActorArousalLocked flag matches (0/1)

 Effects:
   0  arousal.rate       — exposure delta per game-hour (self)
   1  arousal.rate.npc   — exposure delta per game-hour (nearby NPCs); radius
                           is per-slot `param2` (meters, default 22)
   2  modify.arousal     — one-shot: add `param` exposure on self on switch
   3  set.exposure.rate  — set exposure rate while active, restore previous on deactivate
   4  trigger.orgasm     — one-shot: UpdateActorOrgasmDate (resets days-since timer)}

slaFrameWorkScr Property SLAFramework Auto Hidden

; _host() lifted to MTF_Plugin base class.

; Maximum NPCs the Pheromone Aura can affect in one game-hour tick.
; Caps the cost in crowds. Not user-tunable.
int Function PHEROMONE_MAX_TARGETS() global
    return 30
EndFunction

string Function GetPluginId()
    return "mtf.sla"
EndFunction

bool Function _resolveDeps()
    if SLAFramework != None
        return true
    endif
    SLAFramework = Game.GetFormFromFile(0x04290F, "SexLabAroused.esm") as slaFrameWorkScr
    return SLAFramework != None
EndFunction

; _tryRegister lifted to MTF_Plugin base class. _resolveDeps above is the
; only thing this plugin customises.

; ── Behaviour ───────────────────────────────────────────────────────────────
bool Function checkCondition(Actor target, int param, string cid)
    if target == None || SLAFramework == None
        return false
    endif
    if cid == "arousal"
        return SLAFramework.GetActorArousal(target) >= param
    elseif cid == "days.since.orgasm"
        ; GetActorDaysSinceLastOrgasm returns float days. Threshold is integer days.
        return SLAFramework.GetActorDaysSinceLastOrgasm(target) >= (param as float)
    elseif cid == "exposure.rate"
        ; ExposureRate is float. Threshold is integer.
        return SLAFramework.GetActorExposureRate(target) >= (param as float)
    elseif cid == "arousal.lock"
        ; v0.3.3: collapsed to a single boolean — fires when arousal is locked.
        ; The old "Unlocked"/"Locked" menu was dropped (arousal is unlocked by
        ; default, so the "unlocked" option fired on the resting state and was
        ; rarely useful). No param now; legacy presets that stored a lock-state
        ; menu id simply ignore it and check the locked flag directly.
        return SLAFramework.IsActorArousalLocked(target)
    endif
    return false
EndFunction

; ── set.exposure.rate state plumbing ────────────────────────────────────────
; Need to restore the previous rate on deactivate. Store the pre-apply rate
; in StorageUtil under a per-actor key keyed on (slot, eff). Following
; project_papyrus_storage_before_suspend: write storage BEFORE the suspending
; SetActorExposureRate call so a concurrent stack hits the "rate already
; applied" early-out.

string Function _rateStashKey(Actor target, int slot, int eff) global
    return "mtf.sla.rate.prev." + slot + "." + eff
EndFunction

Function onActivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if SLAFramework == None || target == None
        return
    endif
    if eid == "modify.arousal"
        if param <= 0
            return
        endif
        int cur = SLAFramework.GetActorExposure(target)
        if cur < 0
            return
        endif
        SLAFramework.SetActorExposure(target, cur + param)
    elseif eid == "set.exposure.rate"
        if slot < 0 || effectIdx < 0
            return
        endif
        string key = _rateStashKey(target, slot, effectIdx)
        ; Stash current rate so onDeactivate can restore it. Write BEFORE
        ; the suspending SetActorExposureRate to avoid a double-apply race.
        float prev = SLAFramework.GetActorExposureRate(target)
        StorageUtil.SetFloatValue(target, key, prev)
        SLAFramework.SetActorExposureRate(target, param as float)
    elseif eid == "trigger.orgasm"
        ; One-shot: reset "days since orgasm" timer.
        SLAFramework.UpdateActorOrgasmDate(target)
    endif
EndFunction

Function onDeactivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if SLAFramework == None || target == None
        return
    endif
    if eid == "set.exposure.rate"
        if slot < 0 || effectIdx < 0
            return
        endif
        string key = _rateStashKey(target, slot, effectIdx)
        if !StorageUtil.HasFloatValue(target, key)
            return
        endif
        float prev = StorageUtil.GetFloatValue(target, key)
        StorageUtil.UnsetFloatValue(target, key)
        SLAFramework.SetActorExposureRate(target, prev)
    endif
EndFunction

Function onGameTime(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if SLAFramework == None || target == None || param <= 0
        return
    endif
    if eid == "arousal.rate"
        if SLAFramework.GetActorArousal(target) < 99
            int cur = SLAFramework.GetActorExposure(target)
            SLAFramework.SetActorExposure(target, cur + param)
        endif
    elseif eid == "arousal.rate.npc"
        int radiusM = param2
        if radiusM <= 0
            radiusM = 22
        endif
        float radius = (radiusM as float) * 70.0
        ; v0.3.3: gender targeting. param3 menu id: "both" (default), "female",
        ; or "male". Read via the race-free explicit-context string accessor
        ; (menu ids live in the per-effect string slot), not the shared
        ; dispatch context. Empty => treat as "both" (legacy presets).
        string targetSex = _paramNStrEx(slot, effectIdx, useScratch, presetName, 3)
        int wantSex = -1
        if targetSex == "female"
            wantSex = 1
        elseif targetSex == "male"
            wantSex = 0
        endif
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
                ; Gender gate. GetActorBase().GetSex(): 0 = male, 1 = female.
                ; wantSex -1 means "both" — skip the check entirely.
                bool sexOk = true
                if wantSex >= 0
                    ActorBase ab = a.GetActorBase()
                    sexOk = ab != None && ab.GetSex() == wantSex
                endif
                if sexOk && a.GetDistance(target) <= radius
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
