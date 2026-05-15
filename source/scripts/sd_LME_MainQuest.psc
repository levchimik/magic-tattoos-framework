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
; condPluginId: "<pluginId>:<itemId>" composite key; "" = unset/disabled.
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

; ── Per-slot effect lists (flat, 8 slots × MAX_EFFECTS_PER_SLOT) ─────────────
; effectKey: "<pluginId>:<itemId>" or ""; effectParam parallel.
; Index: slot S, effect E => S * MAX_EFFECTS_PER_SLOT + E.
string[] Property effectKey Auto
int[] Property effectParam Auto

; ── Plugin registries ────────────────────────────────────────────────────────
Form[] Property registeredPlugins Auto
int Property pluginCount = 0 Auto
Form[] Property registeredEffectPlugins Auto
int Property effectPluginCount = 0 Auto

; ── Internal ──────────────────────────────────────────────────────────────────
actor Property PlayerRef Auto
string Property texturePathNormal = "actors\\character\\overlays\\lewdmarks\\" Auto
string Property texturePathGlow   = "actors\\character\\overlays\\lewdmarks-glow\\" Auto
slaFrameWorkScr Property SLAFramework Auto Hidden    ; lazy-resolved from SexLabAroused.esm; None if SLA not loaded

bool forceRedraw = false
int currentTier = -1
bool influenceTracking = false

int Function MAX_EFFECTS_PER_SLOT() global
    return 4
EndFunction

; ─────────────────────────────────────────────────────────────────────────────

Event OnInit()
    Trace("[LME_Main] OnInit")
    EnsureArrays()
    _resolveSoftDeps()
EndEvent

Function _resolveSoftDeps()
{Lazy-resolve optional master forms so they don't appear as hard deps in the ESP.}
    if SLAFramework == None
        SLAFramework = Game.GetFormFromFile(0x04290F, "SexLabAroused.esm") as slaFrameWorkScr
        if SLAFramework == None
            Trace("[LME_Main] SexLabAroused.esm not loaded — SLA-dependent features disabled")
        endif
    endif
EndFunction

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
    effectKey            = new string[32]    ; 8 slots × 4 effects
    effectParam          = new int[32]
    registeredPlugins        = new Form[32]
    registeredEffectPlugins  = new Form[32]
    pluginCount          = 0
    effectPluginCount    = 0
    _arraysReady         = true
EndFunction

; ── Condition plugin registry ────────────────────────────────────────────────
Function RegisterPlugin(sd_LME_ConditionPlugin p)
{Called by sd_LME_ConditionPlugin._tryRegister(). Idempotent.}
    if p == None || registeredPlugins == None
        return
    endif
    string pid = p.GetPluginId()
    if pid == ""
        Trace("[LME_Main] RegisterPlugin REJECTED: empty PluginId on " + p)
        return
    endif
    if FindPluginIndex(pid) >= 0
        return
    endif
    if pluginCount >= registeredPlugins.Length
        Trace("[LME_Main] RegisterPlugin REJECTED: registry full (" + pid + ")")
        return
    endif
    registeredPlugins[pluginCount] = p as Form
    pluginCount += 1
    Trace("[LME_Main] Registered condition plugin '" + pid + "' (" + p.GetPluginLabel() + ", " + p.GetItemCount() + " items)")
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

; ── Effect plugin registry ───────────────────────────────────────────────────
Function RegisterEffectPlugin(sd_LME_EffectPlugin p)
    if p == None || registeredEffectPlugins == None
        return
    endif
    string pid = p.GetPluginId()
    if pid == ""
        Trace("[LME_Main] RegisterEffectPlugin REJECTED: empty PluginId on " + p)
        return
    endif
    if FindEffectPluginIndex(pid) >= 0
        return
    endif
    if effectPluginCount >= registeredEffectPlugins.Length
        Trace("[LME_Main] RegisterEffectPlugin REJECTED: registry full (" + pid + ")")
        return
    endif
    registeredEffectPlugins[effectPluginCount] = p as Form
    effectPluginCount += 1
    Trace("[LME_Main] Registered effect plugin '" + pid + "' (" + p.GetPluginLabel() + ", " + p.GetItemCount() + " items)")
EndFunction

int Function FindEffectPluginIndex(string pid)
    if pid == "" || registeredEffectPlugins == None
        return -1
    endif
    int i = 0
    while i < effectPluginCount
        sd_LME_EffectPlugin slot = registeredEffectPlugins[i] as sd_LME_EffectPlugin
        if slot != None && slot.GetPluginId() == pid
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

sd_LME_EffectPlugin Function FindEffectPlugin(string pid)
    int idx = FindEffectPluginIndex(pid)
    if idx < 0
        return None
    endif
    return registeredEffectPlugins[idx] as sd_LME_EffectPlugin
EndFunction

sd_LME_EffectPlugin Function GetEffectPluginAt(int idx)
    if idx < 0 || idx >= effectPluginCount
        return None
    endif
    return registeredEffectPlugins[idx] as sd_LME_EffectPlugin
EndFunction

; ── Key helpers (shared between condition and effect plugins) ─────────────────
string Function _keyPluginId(string key)
    int sep = StringUtil.Find(key, ":")
    if sep < 0
        return key
    endif
    return StringUtil.Substring(key, 0, sep)
EndFunction

string Function _keyItemId(string key)
    int sep = StringUtil.Find(key, ":")
    if sep < 0
        return ""
    endif
    return StringUtil.Substring(key, sep + 1)
EndFunction

int Function _itemIdxFor(sd_LME_ConditionPlugin p, string itemId)
    if p == None || itemId == ""
        return -1
    endif
    int n = p.GetItemCount()
    int i = 0
    while i < n
        if p.GetItemId(i) == itemId
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

int Function _itemIdxForEffect(sd_LME_EffectPlugin p, string itemId)
    if p == None || itemId == ""
        return -1
    endif
    int n = p.GetItemCount()
    int i = 0
    while i < n
        if p.GetItemId(i) == itemId
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

sd_LME_ConditionPlugin Function ResolveConditionPlugin(string key)
    if key == ""
        return None
    endif
    return FindPlugin(_keyPluginId(key))
EndFunction

sd_LME_EffectPlugin Function ResolveEffectPlugin(string key)
    if key == ""
        return None
    endif
    return FindEffectPlugin(_keyPluginId(key))
EndFunction

int Function ResolveConditionItemIdx(string key)
    sd_LME_ConditionPlugin p = ResolveConditionPlugin(key)
    return _itemIdxFor(p, _keyItemId(key))
EndFunction

; ── Flattened plugin×item views (for MCM dropdowns) ──────────────────────────
int Function GetTotalItemCount()
    int total = 0
    int i = 0
    while i < pluginCount
        sd_LME_ConditionPlugin p = GetPluginAt(i)
        if p != None
            total += p.GetItemCount()
        endif
        i += 1
    endwhile
    return total
EndFunction

string Function GetGlobalItemKey(int globalIdx)
    int seen = 0
    int pi = 0
    while pi < pluginCount
        sd_LME_ConditionPlugin p = GetPluginAt(pi)
        if p != None
            int n = p.GetItemCount()
            if globalIdx < seen + n
                return p.GetPluginId() + ":" + p.GetItemId(globalIdx - seen)
            endif
            seen += n
        endif
        pi += 1
    endwhile
    return ""
EndFunction

string Function GetGlobalItemLabel(int globalIdx)
    int seen = 0
    int pi = 0
    while pi < pluginCount
        sd_LME_ConditionPlugin p = GetPluginAt(pi)
        if p != None
            int n = p.GetItemCount()
            if globalIdx < seen + n
                string pl = p.GetPluginLabel()
                string il = p.GetItemLabel(globalIdx - seen)
                if pl == ""
                    return il
                endif
                return pl + " — " + il
            endif
            seen += n
        endif
        pi += 1
    endwhile
    return ""
EndFunction

int Function GetTotalEffectItemCount()
    int total = 0
    int i = 0
    while i < effectPluginCount
        sd_LME_EffectPlugin p = GetEffectPluginAt(i)
        if p != None
            total += p.GetItemCount()
        endif
        i += 1
    endwhile
    return total
EndFunction

string Function GetGlobalEffectKey(int globalIdx)
    int seen = 0
    int pi = 0
    while pi < effectPluginCount
        sd_LME_EffectPlugin p = GetEffectPluginAt(pi)
        if p != None
            int n = p.GetItemCount()
            if globalIdx < seen + n
                return p.GetPluginId() + ":" + p.GetItemId(globalIdx - seen)
            endif
            seen += n
        endif
        pi += 1
    endwhile
    return ""
EndFunction

string Function GetGlobalEffectLabel(int globalIdx)
    int seen = 0
    int pi = 0
    while pi < effectPluginCount
        sd_LME_EffectPlugin p = GetEffectPluginAt(pi)
        if p != None
            int n = p.GetItemCount()
            if globalIdx < seen + n
                string pl = p.GetPluginLabel()
                string il = p.GetItemLabel(globalIdx - seen)
                if pl == ""
                    return il
                endif
                return pl + " — " + il
            endif
            seen += n
        endif
        pi += 1
    endwhile
    return ""
EndFunction

; ── Per-slot effect-list helpers ─────────────────────────────────────────────
int Function _fxBaseIdx(int slot)
    return slot * MAX_EFFECTS_PER_SLOT()
EndFunction

string Function GetSlotEffectKey(int slot, int effectIdx)
    if effectKey == None || slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return ""
    endif
    return effectKey[_fxBaseIdx(slot) + effectIdx]
EndFunction

int Function GetSlotEffectParam(int slot, int effectIdx)
    if effectParam == None || slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return 0
    endif
    return effectParam[_fxBaseIdx(slot) + effectIdx]
EndFunction

Function SetSlotEffect(int slot, int effectIdx, string key, int param)
    if effectKey == None || slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    int globalI = _fxBaseIdx(slot) + effectIdx
    effectKey[globalI] = key
    effectParam[globalI] = param
EndFunction

; ── Priority evaluation ───────────────────────────────────────────────────────
int Function evaluateTier()
    if condPluginId == None
        return 0
    endif
    int i = 1
    while i < 8
        string key = condPluginId[i]
        if key != ""
            sd_LME_ConditionPlugin p = ResolveConditionPlugin(key)
            if p != None
                int itemIdx = _itemIdxFor(p, _keyItemId(key))
                if itemIdx >= 0 && p.checkItem(itemIdx, PlayerRef, condParam[i])
                    return i
                endif
            endif
        endif
        i += 1
    endwhile
    return 0
EndFunction

; ── Effect lifecycle dispatch ────────────────────────────────────────────────
Function _activateSlotEffects(int slot)
{Fires onActivate for every configured effect on `slot`.}
    if effectKey == None || slot < 0 || slot >= 8
        return
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_EffectPlugin p = ResolveEffectPlugin(key)
            if p != None
                int itemIdx = _itemIdxForEffect(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onActivate(itemIdx, PlayerRef, effectParam[base + e])
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _deactivateSlotEffects(int slot)
{Fires onDeactivate for every configured effect on `slot`. Safe to call with slot=-1 (no-op).}
    if effectKey == None || slot < 0 || slot >= 8
        return
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_EffectPlugin p = ResolveEffectPlugin(key)
            if p != None
                int itemIdx = _itemIdxForEffect(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onDeactivate(itemIdx, PlayerRef, effectParam[base + e])
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _tickSlotEffects(int slot)
{Fires onTick for every configured effect on `slot`. Called every OnUpdate.}
    if effectKey == None || slot < 0 || slot >= 8
        return
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_EffectPlugin p = ResolveEffectPlugin(key)
            if p != None
                int itemIdx = _itemIdxForEffect(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onTick(itemIdx, PlayerRef, effectParam[base + e])
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _gameTickSlotEffects(int slot)
{Fires onGameTime for every configured effect on `slot`. Called per in-game hour.}
    if effectKey == None || slot < 0 || slot >= 8
        return
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_EffectPlugin p = ResolveEffectPlugin(key)
            if p != None
                int itemIdx = _itemIdxForEffect(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onGameTime(itemIdx, PlayerRef, effectParam[base + e])
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

bool Function _slotHasEffects(int slot)
    if effectKey == None || slot < 0 || slot >= 8
        return false
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        if effectKey[base + e] != ""
            return true
        endif
        e += 1
    endwhile
    return false
EndFunction

Function _notifyTierChange(int tier)
{Debug-only toast describing the new tier and its configured effects.}
    if !DebugMode
        return
    endif
    if tier <= 0
        Notification("LewdMarks: condition cleared")
        return
    endif
    string msg = "LewdMarks: Tier " + tier
    int base = _fxBaseIdx(tier)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_EffectPlugin p = ResolveEffectPlugin(key)
            if p != None
                int itemIdx = _itemIdxForEffect(p, _keyItemId(key))
                if itemIdx >= 0
                    msg += " - " + p.GetItemLabel(itemIdx) + " " + effectParam[base + e]
                endif
            endif
        endif
        e += 1
    endwhile
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
        if currentTier < 0 || !_slotHasEffects(currentTier)
            influenceTracking = false
            return
        endif
        _gameTickSlotEffects(currentTier)
        RegisterForSingleUpdateGameTime(1.0)
    EndEvent

    Event OnUpdate()
        _resolveSoftDeps()    ; cheap; self-heals if SLA was loaded mid-session or after script update
        if !ModActive
            removeOverlay(PlayerRef)
            if currentTier >= 0
                _deactivateSlotEffects(currentTier)
            endif
            currentTier = -1
            influenceTracking = false
            return
        endif

        if CurrentOverlaySlot != OverlaySlot
            removeOverlay(PlayerRef)
        endif

        int newTier = evaluateTier()
        bool tierChanged = (newTier != currentTier)

        if forceRedraw || tierChanged
            forceRedraw = false
            if tierChanged && currentTier >= 0
                _deactivateSlotEffects(currentTier)
            endif
            currentTier = newTier
            drawOverlay(PlayerRef, currentTier)
            if tierChanged
                _activateSlotEffects(currentTier)
                _notifyTierChange(currentTier)
            endif
        endif

        ; Per-tick effect refresh (e.g. %-of-current AV drains shifting with gear).
        _tickSlotEffects(currentTier)

        if _slotHasEffects(currentTier)
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
