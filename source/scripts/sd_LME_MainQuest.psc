Scriptname sd_LME_MainQuest extends Quest

import Debug
import Utility

; ── Global settings ──────────────────────────────────────────────────────────
bool Property ModActive = false Auto
bool Property DebugMode = false Auto
bool Property useSlaveTats = false Auto
int Property OverlaySlot = 2 Auto
int Property CurrentOverlaySlot = 2 Auto
float Property updateInterval = 2.0 Auto

; ── Per-slot arrays (index 0 = Default, 1-7 = Conditions) ───────────────────
; condPluginId: empty string = unset/disabled; otherwise plugin's GetPluginId()
string[] Property condPluginId Auto
int[] Property condParam Auto
int[] Property condTextureNum Auto
bool[] Property condUseGlow Auto
int[] Property condMarkTint Auto
int[] Property condMarkEmissive Auto
float[] Property condMarkEmissiveMult Auto
int[] Property condMarkAlpha Auto
int[] Property condHaloTint Auto
int[] Property condHaloEmissive Auto
float[] Property condHaloEmissiveMult Auto
int[] Property condHaloAlpha Auto
int[] Property condIncreaseExposure Auto
int[] Property condManaSiphonPct Auto       ; 0-100, % of current MagickaRateMult to drain
int[] Property condCarryWeightPct Auto      ; 0-100, % of current CarryWeight to drain
int[] Property condSneakPct Auto            ; 0-100, % of current Sneak skill to drain

; ── AV-drain runtime state (Hidden — persisted across save/load) ─────────────
float Property _appliedSiphon = 0.0 Auto Hidden       ; absolute amount currently subtracted from MagickaRateMult
float Property _appliedCarryWeight = 0.0 Auto Hidden  ; absolute amount currently subtracted from CarryWeight
float Property _appliedSneak = 0.0 Auto Hidden        ; absolute amount currently subtracted from Sneak
float Property _lastSiphonRecompute = 0.0 Auto Hidden ; (unused — kept for save compat)

; ── Plugin registry ──────────────────────────────────────────────────────────
; Stored as Form[] because Papyrus cannot allocate custom-script-typed arrays at runtime.
Form[] Property registeredPlugins Auto
int Property pluginCount = 0 Auto

; ── Internal ──────────────────────────────────────────────────────────────────
actor Property PlayerRef Auto
string Property texturePathNormal = "actors\\character\\overlays\\lewdmarks\\" Auto
string Property texturePathGlow   = "actors\\character\\overlays\\lewdmarks-glow\\" Auto
slaFrameWorkScr Property SLAFramework Auto    ; kept for legacy/sla-aware plugins to read

bool forceRedraw = false
int currentTier = -1
bool influenceTracking = false

; ─────────────────────────────────────────────────────────────────────────────

Event OnInit()
    Trace("[LME_Main] OnInit")
    EnsureArrays()
EndEvent

bool Property _arraysReady = false Auto Hidden

Function EnsureArrays()
{One-shot allocation — bool guard avoids reading array properties (Papyrus errors on None→Type[] casts).}
    if _arraysReady
        return
    endif
    Trace("[LME_Main] EnsureArrays: allocating arrays")
    condPluginId         = new string[8]
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
    condManaSiphonPct    = new int[8]
    condCarryWeightPct   = new int[8]
    condSneakPct         = new int[8]
    registeredPlugins    = new Form[32]
    pluginCount          = 0
    _arraysReady         = true
EndFunction

; ── Plugin API ───────────────────────────────────────────────────────────────
Function RegisterPlugin(sd_LME_ConditionPlugin p)
{Called by sd_LME_ConditionPlugin._tryRegister(). Idempotent.
 Plugins are responsible for waiting until registeredPlugins is allocated before calling.}
    if p == None || registeredPlugins == None
        return
    endif
    string pid = p.GetPluginId()
    if pid == ""
        Trace("[LME_Main] RegisterPlugin REJECTED: empty PluginId on " + p)
        return
    endif
    if FindPluginIndex(pid) >= 0
        return    ; already registered
    endif
    if pluginCount >= registeredPlugins.Length
        Trace("[LME_Main] RegisterPlugin REJECTED: registry full (" + pid + ")")
        return
    endif
    registeredPlugins[pluginCount] = p as Form
    pluginCount += 1
    Trace("[LME_Main] Registered plugin '" + pid + "' (" + p.GetLabel() + ") at index " + (pluginCount - 1))
EndFunction

int Function FindPluginIndex(string pid)
    if pid == "" || registeredPlugins == None
        return -1
    endif
    int i = 0
    while i < pluginCount
        sd_LME_ConditionPlugin slot = registeredPlugins[i] as sd_LME_ConditionPlugin
        if slot != None && slot.GetPluginId() == pid
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

sd_LME_ConditionPlugin Function FindPlugin(string pid)
    int idx = FindPluginIndex(pid)
    if idx < 0
        return None
    endif
    return registeredPlugins[idx] as sd_LME_ConditionPlugin
EndFunction

sd_LME_ConditionPlugin Function GetPluginAt(int idx)
    if idx < 0 || idx >= pluginCount
        return None
    endif
    return registeredPlugins[idx] as sd_LME_ConditionPlugin
EndFunction

; ── Priority evaluation ───────────────────────────────────────────────────────
int Function evaluateTier()
    if condPluginId == None
        return 0
    endif
    int i = 1
    while i < 8
        string pid = condPluginId[i]
        if pid != ""
            sd_LME_ConditionPlugin p = FindPlugin(pid)
            if p != None && p.check(PlayerRef, condParam[i])
                return i
            endif
        endif
        i += 1
    endwhile
    return 0
EndFunction

; ── AV-drain side effects ────────────────────────────────────────────────────
float Function _applyAvPctDrain(string avName, int pct, float prevApplied)
{Reverses any previous drain on this AV, then applies a new one as `pct`% of the
 current (post-reverse) value. Returns the new applied amount so caller can store it.
 Pass pct<=0 (or PlayerRef==None) to fully clear.}
    if prevApplied != 0.0 && PlayerRef != None
        PlayerRef.ModActorValue(avName, prevApplied)
    endif
    if PlayerRef == None || pct <= 0
        return 0.0
    endif
    float current = PlayerRef.GetActorValue(avName)
    if current <= 0.0
        return 0.0
    endif
    float amt = current * pct / 100.0
    PlayerRef.ModActorValue(avName, -amt)
    return amt
EndFunction

int Function _pctForTier(int[] arr, int tier)
    if arr == None || tier < 0 || tier >= 8
        return 0
    endif
    return arr[tier]
EndFunction

Function _applySiphonForTier(int tier)
{Recomputes all AV-drain side effects (Mana / Carry Weight / Sneak) for the given tier.
 Pass -1 (or any out-of-range tier) to fully clear all drains.}
    _appliedSiphon      = _applyAvPctDrain("MagickaRateMult", _pctForTier(condManaSiphonPct,  tier), _appliedSiphon)
    _appliedCarryWeight = _applyAvPctDrain("CarryWeight",     _pctForTier(condCarryWeightPct, tier), _appliedCarryWeight)
    _appliedSneak       = _applyAvPctDrain("Sneak",           _pctForTier(condSneakPct,       tier), _appliedSneak)
EndFunction

Function _notifyTierChange(int tier)
{Debug-only toast describing the new tier's active drains. Skipped when DebugMode is off.}
    if !DebugMode
        return
    endif
    if tier <= 0
        Notification("LewdMarks: condition cleared")
        return
    endif
    string msg = "LewdMarks: Tier " + tier
    int mana   = _pctForTier(condManaSiphonPct,   tier)
    int carry  = _pctForTier(condCarryWeightPct,  tier)
    int sneak  = _pctForTier(condSneakPct,        tier)
    int expose = _pctForTier(condIncreaseExposure, tier)
    if mana > 0
        msg += " - Mana " + mana + "%"
    endif
    if carry > 0
        msg += " - Carry " + carry + "%"
    endif
    if sneak > 0
        msg += " - Sneak " + sneak + "%"
    endif
    if expose > 0
        msg += " - Arousal +" + expose + "/h"
    endif
    Notification(msg)
EndFunction

; ── Update loop (state) ───────────────────────────────────────────────────────
State checkingAroused

    Event OnBeginState()
        RegisterForSingleUpdate(0.5)
    EndEvent

    Event OnUpdateGameTime()
        if !ModActive || !influenceTracking
            return
        endif
        int exposure = condIncreaseExposure[currentTier]
        if exposure > 0 && SLAFramework
            if SLAFramework.GetActorArousal(PlayerRef) < 99
                SLAFramework.setActorExposure(PlayerRef, SLAFramework.getActorExposure(PlayerRef) + exposure)
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
            _applySiphonForTier(-1)
            return
        endif

        if CurrentOverlaySlot != OverlaySlot
            removeOverlay(PlayerRef)
        endif

        int newTier = evaluateTier()
        bool tierChanged = (newTier != currentTier)

        if forceRedraw || tierChanged
            forceRedraw = false
            currentTier = newTier
            drawOverlay(PlayerRef, currentTier)
        endif

        ; AV drains: recompute every tick so they stay in sync with gear/buff changes
        _applySiphonForTier(currentTier)

        if tierChanged
            _notifyTierChange(currentTier)
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

; ── Overlay drawing ───────────────────────────────────────────────────────────
function drawOverlay(actor akTarget, int idx)
    if condTextureNum == None
        return
    endif
    bool isFemale = akTarget.GetLeveledActorBase().GetSex() as bool
    string Area = "Body"

    int texNum = condTextureNum[idx]
    if texNum == 0
        texNum = condTextureNum[0]
    endif

    string prefix = texPrefix(texNum)

    if condUseGlow[idx]
        string texGlow = texturePathGlow + prefix + texNum + ".dds"
        string texNorm = texturePathNormal + prefix + texNum + ".dds"
        applyOverlay(akTarget, isFemale, Area, OverlaySlot,     texGlow, condHaloTint[idx], condHaloEmissive[idx], true,  condHaloEmissiveMult[idx], condHaloAlpha[idx] * 0.01)
        applyOverlay(akTarget, isFemale, Area, OverlaySlot + 1, texNorm, condMarkTint[idx], condMarkEmissive[idx], true,  condMarkEmissiveMult[idx], condMarkAlpha[idx] * 0.01)
    else
        string texNorm = texturePathNormal + prefix + texNum + ".dds"
        clearOverlay(akTarget, isFemale, Area, OverlaySlot)
        applyOverlay(akTarget, isFemale, Area, OverlaySlot + 1, texNorm, condMarkTint[idx], 0, false, 0.0, condMarkAlpha[idx] * 0.01)
    endif

    CurrentOverlaySlot = OverlaySlot
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
    if !NiOverride.HasOverlays(Target)
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
