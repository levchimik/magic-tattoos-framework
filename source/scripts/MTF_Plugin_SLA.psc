Scriptname MTF_Plugin_SLA extends MTF_Plugin
{Conditions and effects backed by SexLab Aroused. Soft-master: lookup at
 runtime; if SLA isn't loaded the plugin skips registration entirely.

 Conditions:
   0  arousal            — SLA exposure >= threshold

 Effects:
   0  exposure.self      — increase target's SLA exposure by `param` per game-hour
   1  exposure.aura      — increase nearby NPCs' SLA exposure by `param` per game-hour;
                          radius is per-slot `param2` (meters, default 22)
   2  arousal.burst.self — one-shot: add `param` exposure on self on switch

 No plugin-level settings — the aura radius is per-slot (effect param2);
 the per-tick NPC cap is hardcoded to PHEROMONE_MAX_TARGETS (30).}

slaFrameWorkScr Property SLAFramework Auto Hidden

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
    return 1
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "arousal"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "Arousal"
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx == 0
        return "Arousal threshold"
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    return 0
EndFunction
int Function GetConditionParamMax(int idx)
    return 100
EndFunction
int Function GetConditionParamDefault(int idx)
    if idx == 0
        return 80
    endif
    return 0
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None || SLAFramework == None
        return false
    endif
    if idx == 0
        return SLAFramework.GetActorArousal(target) >= param
    endif
    return false
EndFunction

; ── Effects ───────────────────────────────────────────────────────────────────

int Function GetEffectCount()
    return 3
EndFunction

string Function GetEffectId(int idx)
    if idx == 0
        return "arousal.rate"
    elseif idx == 1
        return "arousal.rate.npc"
    elseif idx == 2
        return "modify.arousal"
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
    endif
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    return 0
EndFunction
int Function GetEffectParamMax(int idx)
    return 100
EndFunction
int Function GetEffectParamDefault(int idx)
    if idx == 2
        return 25
    endif
    return 5
EndFunction

Function onActivate(int idx, Actor target, int param, int param2)
    if idx != 2 || SLAFramework == None || target == None || param <= 0
        return
    endif
    int cur = SLAFramework.GetActorExposure(target)
    if cur < 0
        return
    endif
    SLAFramework.SetActorExposure(target, cur + param)
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
