Scriptname sd_LME_Plugin_SLA extends sd_LME_Plugin
{Conditions and effects backed by SexLab Aroused. Soft-master: lookup at
 runtime; if SLA isn't loaded the plugin skips registration entirely.

 Conditions:
   0  arousal            — SLA exposure >= threshold

 Effects:
   0  exposure.self      — increase target's SLA exposure by `param` per game-hour
   1  exposure.aura      — increase nearby NPCs' SLA exposure by `param` per game-hour

 Settings:
   0  radius_m           — pheromone aura scan radius, meters (default 22)
   1  max_targets        — pheromone aura per-tick NPC cap (default 32)}

slaFrameWorkScr Property SLAFramework Auto Hidden

int Property pheromoneRadiusM    = 22 Auto Hidden
int Property pheromoneMaxTargets = 32 Auto Hidden

string Function GetPluginId()
    return "lme.sla"
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
    return 2
EndFunction

string Function GetEffectId(int idx)
    if idx == 0
        return "exposure.self"
    elseif idx == 1
        return "exposure.aura"
    endif
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    if idx == 0
        return "Self Arousal +/hour"
    elseif idx == 1
        return "Pheromone Aura +/hour"
    endif
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    if idx == 0
        return "Exposure delta on self per game-hour"
    elseif idx == 1
        return "Exposure delta on nearby NPCs per game-hour"
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
    return 5
EndFunction

Function onGameTime(int idx, Actor target, int param)
    if SLAFramework == None || target == None || param <= 0
        return
    endif
    if idx == 0
        if SLAFramework.GetActorArousal(target) < 99
            int cur = SLAFramework.GetActorExposure(target)
            SLAFramework.SetActorExposure(target, cur + param)
        endif
    elseif idx == 1
        int radiusM = pheromoneRadiusM
        if radiusM <= 0
            radiusM = 22
        endif
        float radius = (radiusM as float) * 70.0
        int cap = pheromoneMaxTargets
        if cap <= 0
            cap = 32
        endif
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

; ── Settings ──────────────────────────────────────────────────────────────────

int Function GetSettingCount()
    return 2
EndFunction

string Function GetSettingId(int idx)
    if idx == 0
        return "radius_m"
    elseif idx == 1
        return "max_targets"
    endif
    return ""
EndFunction

string Function GetSettingLabel(int idx)
    if idx == 0
        return "Pheromone aura radius"
    elseif idx == 1
        return "Pheromone aura max targets"
    endif
    return ""
EndFunction

string Function GetSettingInfo(int idx)
    if idx == 0
        return "Scan radius for the Pheromone Aura effect, in meters (1m ≈ 70 game units). Default 22m."
    elseif idx == 1
        return "Maximum NPCs the Pheromone Aura can affect in a single game-hour tick. Caps the cost in crowds. Default 32."
    endif
    return ""
EndFunction

int Function GetSettingMin(int idx)
    return 1
EndFunction

int Function GetSettingMax(int idx)
    return 100
EndFunction

int Function GetSettingDefault(int idx)
    if idx == 0
        return 22
    elseif idx == 1
        return 32
    endif
    return 0
EndFunction

string Function GetSettingFormat(int idx)
    if idx == 0
        return "{0}m"
    endif
    return "{0}"
EndFunction

int Function GetSettingValue(int idx)
    if idx == 0
        if pheromoneRadiusM <= 0
            return 22
        endif
        return pheromoneRadiusM
    elseif idx == 1
        if pheromoneMaxTargets <= 0
            return 32
        endif
        return pheromoneMaxTargets
    endif
    return 0
EndFunction

Function SetSettingValue(int idx, int v)
    if idx == 0
        pheromoneRadiusM = v
    elseif idx == 1
        pheromoneMaxTargets = v
    endif
EndFunction
