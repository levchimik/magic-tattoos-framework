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
        ; Deps not yet loaded — re-arm. Without this the bail is silent and
        ; we'd stay unregistered for the session.
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
        bool locked = SLAFramework.IsActorArousalLocked(target)
        if param == 1
            return locked
        endif
        return !locked
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

Function onActivate(Actor target, int param, int param2, string eid)
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
    elseif eid == "trigger.orgasm"
        ; One-shot: reset "days since orgasm" timer.
        SLAFramework.UpdateActorOrgasmDate(target)
    endif
EndFunction

Function onDeactivate(Actor target, int param, int param2, string eid)
    if SLAFramework == None || target == None
        return
    endif
    if eid == "set.exposure.rate"
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

Function onGameTime(Actor target, int param, int param2, string eid)
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
