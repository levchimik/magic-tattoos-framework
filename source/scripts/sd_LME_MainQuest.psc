Scriptname sd_LME_MainQuest extends Quest

import Debug
import Utility

; ── Global settings ──────────────────────────────────────────────────────────
bool Property ModActive = false Auto
bool Property useSlaveTats = false Auto
int Property OverlaySlot = 2 Auto
int Property CurrentOverlaySlot = 2 Auto
float Property updateInterval = 2.0 Auto

; ── Per-slot arrays (index 0 = Default, 1-7 = Conditions) ───────────────────
; condType values: 0=none/disabled  1=arousal  2=pregnancy(FMR)  3=magicka  4=magic effects  5=ovulation(FMR)
int[] Property condType Auto
int[] Property condParam Auto           ; threshold / min value, interpreted per condType
int[] Property condTextureNum Auto      ; 0 = inherit from slot 0 (only meaningful for slots 1-7)
bool[] Property condUseGlow Auto
int[] Property condMarkTint Auto
int[] Property condMarkEmissive Auto
float[] Property condMarkEmissiveMult Auto
int[] Property condMarkAlpha Auto
int[] Property condHaloTint Auto
int[] Property condHaloEmissive Auto
float[] Property condHaloEmissiveMult Auto
int[] Property condHaloAlpha Auto
int[] Property condIncreaseExposure Auto    ; side effect: arousal exposure added per game hour

; ── External mod references (set in CK/xEdit) ───────────────────────────────
; FMR ImmersiveEffectsFaction rank reference:
;   1-100   pregnant (rank = belly progress %)
;   101-115 post-birth recovery
;   116-119 menstrual cycle phases (116=menstruation, 117=follicular, 118=ovulation, 119=luteal)
;   120     active labor
;   0       none / cleared
; For future expansion: cycle-phase conditions would check rank 116-119.
Faction Property FMR_PregnancyFaction Auto          ; point to FMR ImmersiveEffectsFaction
MagicEffect[] Property cond_magicfx_effects Auto    ; fill with desired effects
slaFrameWorkScr Property SLAFramework Auto          ; point to sla_Framework quest

; ── Internal ──────────────────────────────────────────────────────────────────
actor Property PlayerRef Auto
string Property texturePathNormal = "actors\\character\\overlays\\lewdmarks\\" Auto
string Property texturePathGlow = "actors\\character\\overlays\\lewdmarks-glow\\" Auto

bool forceRedraw = false
int currentTier = -1
bool influenceTracking = false

slaFrameWorkScr slAroused

; ─────────────────────────────────────────────────────────────────────────────

Event OnInit()
    Trace("[LME_Main] OnInit — initializing arrays")
    condType             = new int[8]
    condParam            = new int[8]
    condTextureNum       = new int[8]
    condUseGlow          = new bool[8]
    condMarkTint         = new int[8]
    condMarkEmissive     = new int[8]
    condMarkEmissiveMult = new float[8]
    condMarkAlpha        = new int[8]
    condHaloTint         = new int[8]
    condHaloEmissive     = new int[8]
    condHaloEmissiveMult = new float[8]
    condHaloAlpha        = new int[8]
    condIncreaseExposure = new int[8]
EndEvent

State checkingAroused

    Event OnBeginState()
        slAroused = SLAFramework
        RegisterForSingleUpdate(0.5)
    EndEvent

    Event OnUpdateGameTime()
        if !ModActive || !influenceTracking
            return
        endif
        int exposure = condIncreaseExposure[currentTier]
        if exposure > 0 && slAroused
            if slAroused.GetActorArousal(PlayerRef) < 99
                slAroused.setActorExposure(PlayerRef, slAroused.getActorExposure(PlayerRef) + exposure)
            endif
            RegisterForSingleUpdateGameTime(1.0)
        else
            influenceTracking = false
        endif
    EndEvent

    Event OnUpdate()
        if !ModActive
            removeOverlay(PlayerRef)
            currentTier = -1
            influenceTracking = false
            return
        endif

        if CurrentOverlaySlot != OverlaySlot
            removeOverlay(PlayerRef)
        endif

        int newTier = evaluateTier()

        if forceRedraw || newTier != currentTier
            forceRedraw = false
            currentTier = newTier
            drawOverlay(PlayerRef, currentTier)
        endif

        if condIncreaseExposure[currentTier] > 0
            if !influenceTracking
                influenceTracking = true
                RegisterForSingleUpdateGameTime(1.0)
            endif
        else
            influenceTracking = false
        endif

        RegisterForSingleUpdate(updateInterval)
    EndEvent

    Event OnEndState()
    EndEvent

EndState

; ── Priority evaluation ───────────────────────────────────────────────────────
; Iterates 1→7, returns the first satisfied condition index.
; Falls back to 0 (Default) if none match.
int Function evaluateTier()
    if condType == None
        return 0
    endif
    int i = 1
    while i < 8
        if condType[i] > 0 && checkCondition(i)
            return i
        endif
        i += 1
    endwhile
    return 0
EndFunction

bool Function checkCondition(int idx)
    int cType = condType[idx]
    int param = condParam[idx]

    if cType == 1   ; Arousal
        return slAroused != None && slAroused.GetActorArousal(PlayerRef) >= param

    elseIf cType == 2   ; Pregnancy (FMR) — rank 1-100 = pregnant
        if FMR_PregnancyFaction == None
            return false
        endif
        int rank = PlayerRef.GetFactionRank(FMR_PregnancyFaction)
        return rank >= param && rank <= 100

    elseIf cType == 3   ; Magicka
        float maxMp = PlayerRef.GetActorValueMax("Magicka")
        if maxMp <= 0.0
            return false
        endif
        return (PlayerRef.GetActorValue("Magicka") / maxMp) * 100.0 >= param as float

    elseIf cType == 5   ; Ovulation (FMR) — rank 118
        if FMR_PregnancyFaction == None
            return false
        endif
        return PlayerRef.GetFactionRank(FMR_PregnancyFaction) == 118

    elseIf cType == 4   ; Magic Effects
        if cond_magicfx_effects == None || cond_magicfx_effects.Length == 0
            return false
        endif
        int j = 0
        while j < cond_magicfx_effects.Length
            if cond_magicfx_effects[j] && PlayerRef.HasMagicEffect(cond_magicfx_effects[j])
                return true
            endif
            j += 1
        endwhile
        return false
    endif

    return false
EndFunction

; ── Overlay drawing ───────────────────────────────────────────────────────────
function drawOverlay(actor akTarget, int idx)
    Trace("[LME] drawOverlay idx=" + idx + " target=" + akTarget)
    if condTextureNum == None
        Trace("[LME] drawOverlay ABORT: condTextureNum is None")
        return
    endif
    bool isFemale = akTarget.GetLeveledActorBase().GetSex() as bool
    string Area = "Body"

    int texNum = condTextureNum[idx]
    if texNum == 0
        texNum = condTextureNum[0]
    endif

    string prefix = texPrefix(texNum)
    Trace("[LME] drawOverlay texNum=" + texNum + " prefix='" + prefix + "' useGlow=" + condUseGlow[idx] + " slot=" + OverlaySlot + " isFemale=" + isFemale + " pathNorm='" + texturePathNormal + "' pathGlow='" + texturePathGlow + "'")

    if condUseGlow[idx]
        string texGlow = texturePathGlow + prefix + texNum + ".dds"
        string texNorm = texturePathNormal + prefix + texNum + ".dds"
        Trace("[LME] drawOverlay GLOW texGlow='" + texGlow + "' texNorm='" + texNorm + "'")
        applyOverlay(akTarget, isFemale, Area, OverlaySlot,     texGlow, condHaloTint[idx], condHaloEmissive[idx], true,  condHaloEmissiveMult[idx], condHaloAlpha[idx] * 0.01)
        applyOverlay(akTarget, isFemale, Area, OverlaySlot + 1, texNorm, condMarkTint[idx], condMarkEmissive[idx], true,  condMarkEmissiveMult[idx], condMarkAlpha[idx] * 0.01)
    else
        string texNorm = texturePathNormal + prefix + texNum + ".dds"
        Trace("[LME] drawOverlay FLAT texNorm='" + texNorm + "'")
        clearOverlay(akTarget, isFemale, Area, OverlaySlot)
        applyOverlay(akTarget, isFemale, Area, OverlaySlot + 1, texNorm, condMarkTint[idx], 0, false, 0.0, condMarkAlpha[idx] * 0.01)
    endif

    CurrentOverlaySlot = OverlaySlot
    Trace("[LME] drawOverlay DONE")
endFunction

string Function texPrefix(int num)
    if num < 10
        return "00"
    elseIf num < 100
        return "0"
    endif
    return ""
EndFunction

function setRedraw()
    forceRedraw = true
endFunction

; ── NiOverride wrappers ───────────────────────────────────────────────────────
Function applyOverlay(actor Target, bool isFemale, string Area, int Slot, string Texture, int Tint, int Emissive, bool isGlow, float Intensity, float Alpha)
    string Node = Area + " [ovl" + Slot + "]"
    bool hadOverlays = NiOverride.HasOverlays(Target)
    Trace("[LME] applyOverlay node='" + Node + "' tex='" + Texture + "' tint=" + Tint + " alpha=" + Alpha + " hadOverlays=" + hadOverlays)
    if !hadOverlays
        NiOverride.AddOverlays(Target)
    endif
    NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 0, Texture, true)
    NiOverride.AddNodeOverrideInt(Target, isFemale, Node, 7, -1, Tint, true)
    NiOverride.AddNodeOverrideInt(Target, isFemale, Node, 0, -1, Emissive, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 1, -1, Intensity, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 8, -1, Alpha, true)
    if isGlow
        NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 2, -1, 5.0, true)
    else
        NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 2, -1, 0.0, true)
        NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 3, -1, 0.0, true)
    endif
    NiOverride.ApplyNodeOverrides(Target)
EndFunction

Function clearOverlay(actor Target, bool isFemale, string Area, int Slot)
    string Node = Area + " [ovl" + Slot + "]"
    string defaultTex = "actors\\character\\overlays\\default.dds"
    NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 0, defaultTex, true)
    if NiOverride.HasNodeOverride(Target, isFemale, Node, 9, 1)
        NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 1, defaultTex, true)
        NiOverride.RemoveNodeOverride(Target, isFemale, Node, 9, 1)
    endif
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 9, 0)
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 7, -1)
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 0, -1)
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 8, -1)
EndFunction

function removeOverlay(actor akTarget)
    bool isFemale = akTarget.GetLeveledActorBase().GetSex() as bool
    clearOverlay(akTarget, isFemale, "Body", CurrentOverlaySlot)
    clearOverlay(akTarget, isFemale, "Body", CurrentOverlaySlot + 1)
endFunction
