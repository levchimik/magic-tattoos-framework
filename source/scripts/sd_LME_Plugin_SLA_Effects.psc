Scriptname sd_LME_Plugin_SLA_Effects extends sd_LME_EffectPlugin
{SLA-backed side effects. Soft-master on SexLabAroused.esm.

 Items:
   0  exposure.self      — increase target's SLA exposure by `param` per game-hour
   1  exposure.aura      — increase nearby NPCs' SLA exposure by `param` per game-hour

 Settings (rendered on the MCM General page):
   0  radius_m       — pheromone aura scan radius, meters (default 22)
   1  max_targets    — pheromone aura per-tick NPC cap (default 32)}

slaFrameWorkScr Property SLAFramework Auto Hidden

int Property pheromoneRadiusM   = 22 Auto Hidden   ; meters; 1m ≈ 70 game units
int Property pheromoneMaxTargets = 32 Auto Hidden

string Function GetPluginId()
    return "lme.sla.fx"
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
    if host == None || host.registeredEffectPlugins == None
        RegisterForSingleUpdate(1.0)
        return
    endif
    host.RegisterEffectPlugin(self)
    _registered = true
EndFunction

int Function GetItemCount()
    return 2
EndFunction

string Function GetItemId(int idx)
    if idx == 0
        return "exposure.self"
    elseif idx == 1
        return "exposure.aura"
    endif
    return ""
EndFunction

string Function GetItemLabel(int idx)
    if idx == 0
        return "Self Arousal +/hour"
    elseif idx == 1
        return "Pheromone Aura +/hour"
    endif
    return ""
EndFunction

string Function GetItemParamLabel(int idx)
    if idx == 0
        return "Exposure delta on self per game-hour"
    elseif idx == 1
        return "Exposure delta on nearby NPCs per game-hour"
    endif
    return ""
EndFunction

int Function GetItemParamMin(int idx)
    return 0
EndFunction
int Function GetItemParamMax(int idx)
    return 100
EndFunction
int Function GetItemParamDefault(int idx)
    return 5
EndFunction

; ── Plugin settings ──────────────────────────────────────────────────────────

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
    if idx == 0
        return 100    ; meters
    elseif idx == 1
        return 100    ; targets
    endif
    return 0
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

; ── Lifecycle ────────────────────────────────────────────────────────────────

Function onGameTime(int idx, Actor target, int param)
    if SLAFramework == None || target == None || param <= 0
        return
    endif
    if idx == 0
        ; self exposure (clamp at 99)
        if SLAFramework.GetActorArousal(target) < 99
            int cur = SLAFramework.GetActorExposure(target)
            SLAFramework.SetActorExposure(target, cur + param)
        endif
    elseif idx == 1
        ; pheromone aura — scan nearby actors
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
