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
; condPluginId: "<pluginId>:<conditionItemId>" composite key; "" = unset.
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
; effectKey: "<pluginId>:<effectItemId>" or ""; effectParam parallel.
; Index: slot S, effect E => S * MAX_EFFECTS_PER_SLOT + E.
string[] Property effectKey Auto
int[] Property effectParam Auto

; ── Per-slot cooldown ────────────────────────────────────────────────────────
; cooldownMin:     duration in minutes (0 = disabled, max 1440 = 24h).
; cooldownMode:    0 = "after deactivate"  — slot can't reactivate during timer
;                  1 = "lock on activate"  — slot stays active during timer
;                                            and lower-priority slots are
;                                            blocked. Higher-priority slots
;                                            can still override.
; cooldownUntilGT: GameTime (days) when the timer ends. Armed at deactivate
;                  (mode 0) or activate (mode 1).
int[] Property cooldownMin Auto
int[] Property cooldownMode Auto
float[] Property cooldownUntilGT Auto Hidden

; ── Plugin registry (single unified registry — both conditions and effects) ──
Form[] Property registeredPlugins Auto
int Property pluginCount = 0 Auto

; ── Disabled items (composite "<pluginId>:<itemId>" keys) ───────────────────
; Fixed-size pool; "" = empty slot. Disabled items are hidden from MCM
; dropdowns. Items not in this list are enabled by default.
string[] Property disabledItems Auto Hidden
bool _disabledReady = false

; ── MCM picker cache ────────────────────────────────────────────────────────
; Filled by BuildVisibleConditionMenu / BuildVisibleEffectMenu and consumed
; by the MCM. Kept here (not on the MCM script) because Auto Hidden array
; properties on the persistent main quest behave reliably, whereas the same
; pattern on the MCM script returned empty arrays in testing.
string[] Property menuKeys Auto Hidden
string[] Property menuLabels Auto Hidden
int Property menuCount = 0 Auto Hidden

; ── Internal ──────────────────────────────────────────────────────────────────
actor Property PlayerRef Auto
string Property texturePathNormal = "actors\\character\\overlays\\lewdmarks\\" Auto
string Property texturePathGlow   = "actors\\character\\overlays\\lewdmarks-glow\\" Auto

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
EndEvent

bool Property _arraysReady = false Auto Hidden
int Property _migrationLevel = 0 Auto Hidden

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
    cooldownMin          = new int[8]
    cooldownMode         = new int[8]
    cooldownUntilGT      = new float[8]
    registeredPlugins    = new Form[32]
    pluginCount          = 0
    _arraysReady         = true
EndFunction

; Indexed write helpers — `obj.arrayProp[i] = val` syntax can fail to
; persist on Papyrus property arrays (writes hit a transient copy, not the
; backing storage). Reading the array into a local, mutating, and writing
; the whole reference back through the setter is reliable.
Function SetCondPluginId(int slot, string key)
    string[] a = condPluginId
    if a == None || a.Length < 8
        a = new string[8]
    endif
    a[slot] = key
    condPluginId = a
EndFunction

Function SetCondParam(int slot, int val)
    int[] a = condParam
    if a == None || a.Length < 8
        a = new int[8]
    endif
    a[slot] = val
    condParam = a
EndFunction

; Hit-class counters (7 classes: ANY/BLUNT/BLADED/RANGED/FIRE/FROST/SHOCK).
; Stored via PapyrusUtil StorageUtil. Auto Hidden array properties added
; post-release do not get attached to existing script instances and even
; whole-array writes (`_hitCount = new int[7]`) don't read back — verified
; empirically. StorageUtil persists in the cosave, no init-order traps.

Function IncHitCount(int classIdx)
    int cur = StorageUtil.GetIntValue(self, "lme.hit.count.0", 0)
    StorageUtil.SetIntValue(self, "lme.hit.count.0", cur + 1)
    if classIdx >= 1 && classIdx <= 6
        int curC = StorageUtil.GetIntValue(self, "lme.hit.count." + classIdx, 0)
        StorageUtil.SetIntValue(self, "lme.hit.count." + classIdx, curC + 1)
    endif
EndFunction

int Function GetHitCount(int classIdx)
    return StorageUtil.GetIntValue(self, "lme.hit.count." + classIdx, 0)
EndFunction

int Function GetHitRolled(int classIdx)
    return StorageUtil.GetIntValue(self, "lme.hit.rolled." + classIdx, 0)
EndFunction

Function SetHitRolled(int classIdx, int val)
    StorageUtil.SetIntValue(self, "lme.hit.rolled." + classIdx, val)
EndFunction

float Function GetHitArmedRT(int classIdx)
    return StorageUtil.GetFloatValue(self, "lme.hit.armed." + classIdx, 0.0)
EndFunction

Function SetHitArmedRT(int classIdx, float val)
    StorageUtil.SetFloatValue(self, "lme.hit.armed." + classIdx, val)
EndFunction

Function EnsureDisabledArray()
    if _disabledReady
        return
    endif
    if disabledItems == None
        disabledItems = new string[64]
    endif
    _disabledReady = true
EndFunction

bool Function IsItemEnabled(string key)
    EnsureDisabledArray()
    if key == ""
        return true
    endif
    int i = 0
    while i < disabledItems.Length
        if disabledItems[i] == key
            return false
        endif
        i += 1
    endwhile
    return true
EndFunction

Function SetItemEnabled(string key, bool on)
    EnsureDisabledArray()
    if key == ""
        return
    endif
    int existing = -1
    int empty = -1
    int i = 0
    while i < disabledItems.Length
        if disabledItems[i] == key
            existing = i
        elseif empty < 0 && disabledItems[i] == ""
            empty = i
        endif
        i += 1
    endwhile
    if on
        if existing >= 0
            disabledItems[existing] = ""
        endif
    else
        if existing < 0 && empty >= 0
            disabledItems[empty] = key
        endif
    endif
EndFunction

; ── Plugin registry ──────────────────────────────────────────────────────────
Function RegisterPlugin(sd_LME_Plugin p)
{Called by sd_LME_Plugin._tryRegister(). Idempotent.}
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
    Trace("[LME_Main] Registered '" + pid + "' (" + p.GetPluginLabel() + ", " + p.GetConditionCount() + " conditions, " + p.GetEffectCount() + " effects)")
EndFunction

int Function FindPluginIndex(string pid)
    if pid == "" || registeredPlugins == None
        return -1
    endif
    int i = 0
    while i < pluginCount
        sd_LME_Plugin slot = registeredPlugins[i] as sd_LME_Plugin
        if slot != None && slot.GetPluginId() == pid
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

sd_LME_Plugin Function FindPlugin(string pid)
    int idx = FindPluginIndex(pid)
    if idx < 0
        return None
    endif
    return registeredPlugins[idx] as sd_LME_Plugin
EndFunction

sd_LME_Plugin Function GetPluginAt(int idx)
    if idx < 0 || idx >= pluginCount
        return None
    endif
    return registeredPlugins[idx] as sd_LME_Plugin
EndFunction

; ── Key helpers ───────────────────────────────────────────────────────────────
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

int Function _condIdxFor(sd_LME_Plugin p, string itemId)
    if p == None || itemId == ""
        return -1
    endif
    int n = p.GetConditionCount()
    int i = 0
    while i < n
        if p.GetConditionId(i) == itemId
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

int Function _effectIdxFor(sd_LME_Plugin p, string itemId)
    if p == None || itemId == ""
        return -1
    endif
    int n = p.GetEffectCount()
    int i = 0
    while i < n
        if p.GetEffectId(i) == itemId
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

sd_LME_Plugin Function ResolvePluginByKey(string key)
    if key == ""
        return None
    endif
    return FindPlugin(_keyPluginId(key))
EndFunction

; ── Flattened condition view (for MCM dropdown) ──────────────────────────────
int Function GetTotalConditionItemCount()
    int total = 0
    int i = 0
    while i < pluginCount
        sd_LME_Plugin p = GetPluginAt(i)
        if p != None
            total += p.GetConditionCount()
        endif
        i += 1
    endwhile
    return total
EndFunction

string Function GetGlobalConditionKey(int globalIdx)
    int seen = 0
    int pi = 0
    while pi < pluginCount
        sd_LME_Plugin p = GetPluginAt(pi)
        if p != None
            int n = p.GetConditionCount()
            if globalIdx < seen + n
                return p.GetPluginId() + ":" + p.GetConditionId(globalIdx - seen)
            endif
            seen += n
        endif
        pi += 1
    endwhile
    return ""
EndFunction

string Function GetGlobalConditionLabel(int globalIdx)
    int seen = 0
    int pi = 0
    while pi < pluginCount
        sd_LME_Plugin p = GetPluginAt(pi)
        if p != None
            int n = p.GetConditionCount()
            if globalIdx < seen + n
                string pl = p.GetPluginLabel()
                string il = p.GetConditionLabel(globalIdx - seen)
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

; ── Flattened effect view (for MCM dropdown) ─────────────────────────────────
int Function GetTotalEffectItemCount()
    int total = 0
    int i = 0
    while i < pluginCount
        sd_LME_Plugin p = GetPluginAt(i)
        if p != None
            total += p.GetEffectCount()
        endif
        i += 1
    endwhile
    return total
EndFunction

string Function GetGlobalEffectKey(int globalIdx)
    int seen = 0
    int pi = 0
    while pi < pluginCount
        sd_LME_Plugin p = GetPluginAt(pi)
        if p != None
            int n = p.GetEffectCount()
            if globalIdx < seen + n
                return p.GetPluginId() + ":" + p.GetEffectId(globalIdx - seen)
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
    while pi < pluginCount
        sd_LME_Plugin p = GetPluginAt(pi)
        if p != None
            int n = p.GetEffectCount()
            if globalIdx < seen + n
                string pl = p.GetPluginLabel()
                string il = p.GetEffectLabel(globalIdx - seen)
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

; ── MCM picker cache builders ─────────────────────────────────────────────────
; One pass each. Caller snapshots references to menuKeys/menuLabels/menuCount
; locally and reads from them in a tight loop — that turns the picker rebuild
; from O(N^2) cross-script calls (the old GetVisibleConditionKey/Label loop)
; into O(N) total with only a handful of cross-script hops.

Function _ensureMenuArrays()
    ; Force-reallocate every call so any stale 0-length array from prior
    ; broken builds gets overwritten.
    menuKeys = new string[64]
    menuLabels = new string[64]
EndFunction

Function _stripDiagnostics()
EndFunction

Function BuildVisibleConditionMenu(string includeKey)
    _ensureMenuArrays()
    int total = GetTotalConditionItemCount()
    int n = 0
    int i = 0
    while i < total && n < 64
        string k = GetGlobalConditionKey(i)
        if IsItemEnabled(k) || k == includeKey
            menuKeys[n] = k
            menuLabels[n] = GetGlobalConditionLabel(i)
            n += 1
        endif
        i += 1
    endwhile
    menuCount = n
EndFunction

Function BuildVisibleEffectMenu(string includeKey)
    _ensureMenuArrays()
    int total = GetTotalEffectItemCount()
    int n = 0
    int i = 0
    while i < total && n < 64
        string k = GetGlobalEffectKey(i)
        if IsItemEnabled(k) || k == includeKey
            menuKeys[n] = k
            menuLabels[n] = GetGlobalEffectLabel(i)
            n += 1
        endif
        i += 1
    endwhile
    menuCount = n
EndFunction

; ── Visible (enabled-only) views, with currently-bound key kept visible ─────
int Function GetVisibleConditionCount(string includeKey)
    int total = GetTotalConditionItemCount()
    int n = 0
    int i = 0
    while i < total
        string k = GetGlobalConditionKey(i)
        if IsItemEnabled(k) || k == includeKey
            n += 1
        endif
        i += 1
    endwhile
    return n
EndFunction

int Function _visibleConditionGlobalIdx(int visIdx, string includeKey)
    int total = GetTotalConditionItemCount()
    int seen = 0
    int i = 0
    while i < total
        string k = GetGlobalConditionKey(i)
        if IsItemEnabled(k) || k == includeKey
            if seen == visIdx
                return i
            endif
            seen += 1
        endif
        i += 1
    endwhile
    return -1
EndFunction

string Function GetVisibleConditionKey(int visIdx, string includeKey)
    int gi = _visibleConditionGlobalIdx(visIdx, includeKey)
    if gi < 0
        return ""
    endif
    return GetGlobalConditionKey(gi)
EndFunction

string Function GetVisibleConditionLabel(int visIdx, string includeKey)
    int gi = _visibleConditionGlobalIdx(visIdx, includeKey)
    if gi < 0
        return ""
    endif
    return GetGlobalConditionLabel(gi)
EndFunction

int Function GetVisibleEffectCount(string includeKey)
    int total = GetTotalEffectItemCount()
    int n = 0
    int i = 0
    while i < total
        string k = GetGlobalEffectKey(i)
        if IsItemEnabled(k) || k == includeKey
            n += 1
        endif
        i += 1
    endwhile
    return n
EndFunction

int Function _visibleEffectGlobalIdx(int visIdx, string includeKey)
    int total = GetTotalEffectItemCount()
    int seen = 0
    int i = 0
    while i < total
        string k = GetGlobalEffectKey(i)
        if IsItemEnabled(k) || k == includeKey
            if seen == visIdx
                return i
            endif
            seen += 1
        endif
        i += 1
    endwhile
    return -1
EndFunction

string Function GetVisibleEffectKey(int visIdx, string includeKey)
    int gi = _visibleEffectGlobalIdx(visIdx, includeKey)
    if gi < 0
        return ""
    endif
    return GetGlobalEffectKey(gi)
EndFunction

string Function GetVisibleEffectLabel(int visIdx, string includeKey)
    int gi = _visibleEffectGlobalIdx(visIdx, includeKey)
    if gi < 0
        return ""
    endif
    return GetGlobalEffectLabel(gi)
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
    float now = Utility.GetCurrentGameTime()
    int i = 1
    while i < 8
        string key = condPluginId[i]
        if key != ""
            bool timerActive = (cooldownUntilGT != None && now < cooldownUntilGT[i])
            int mode = 0
            if cooldownMode != None
                mode = cooldownMode[i]
            endif
            if mode == 1 && timerActive
                ; Lock-on-activate: slot is locked active. We've already
                ; checked higher-priority slots (lower i) above; they
                ; didn't win, so this slot stays in front.
                return i
            endif
            bool inCooldown = (mode == 0 && timerActive)
            if !inCooldown
                sd_LME_Plugin p = ResolvePluginByKey(key)
                if p != None
                    int itemIdx = _condIdxFor(p, _keyItemId(key))
                    if itemIdx >= 0 && p.checkCondition(itemIdx, PlayerRef, condParam[i])
                        return i
                    endif
                endif
            endif
        endif
        i += 1
    endwhile
    return 0
EndFunction

Function _armCooldownTimer(int slot)
{Sets cooldownUntilGT[slot] = now + cooldownMin[slot] minutes. Caller decides
 whether to arm based on mode (deactivate vs activate edge).}
    if slot <= 0 || slot >= 8 || cooldownMin == None || cooldownUntilGT == None
        return
    endif
    int mins = cooldownMin[slot]
    if mins <= 0
        return
    endif
    cooldownUntilGT[slot] = Utility.GetCurrentGameTime() + (mins as float) / 1440.0
EndFunction

; ── Effect lifecycle dispatch ────────────────────────────────────────────────
Function _activateSlotEffects(int slot)
    if effectKey == None || slot < 0 || slot >= 8
        return
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onActivate(itemIdx, PlayerRef, effectParam[base + e])
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _deactivateSlotEffects(int slot)
    if effectKey == None || slot < 0 || slot >= 8
        return
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onDeactivate(itemIdx, PlayerRef, effectParam[base + e])
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _tickSlotEffects(int slot)
    if effectKey == None || slot < 0 || slot >= 8
        return
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onTick(itemIdx, PlayerRef, effectParam[base + e])
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _gameTickSlotEffects(int slot)
    if effectKey == None || slot < 0 || slot >= 8
        return
    endif
    int base = _fxBaseIdx(slot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            sd_LME_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
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
            sd_LME_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    msg += " - " + p.GetEffectLabel(itemIdx) + " " + effectParam[base + e]
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
                ; Mode 0: arm cooldown so the slot can't reactivate.
                if cooldownMode != None && cooldownMode[currentTier] == 0
                    _armCooldownTimer(currentTier)
                endif
            endif
            currentTier = newTier
            drawOverlay(PlayerRef, currentTier)
            if tierChanged
                _activateSlotEffects(currentTier)
                ; Mode 1: arm lock so the slot stays active for the duration.
                if currentTier > 0 && cooldownMode != None && cooldownMode[currentTier] == 1
                    _armCooldownTimer(currentTier)
                endif
                _notifyTierChange(currentTier)
            endif
        endif

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
        applyOverlay(akTarget, isFemale, Area, OverlaySlot,     texNorm, condMarkTint[idx], condMarkEmissive[idx], true,  condMarkEmissiveMult[idx], condMarkAlpha[idx] * 0.01)
        applyOverlay(akTarget, isFemale, Area, OverlaySlot + 1, texGlow, condHaloTint[idx], condHaloEmissive[idx], true,  condHaloEmissiveMult[idx], condHaloAlpha[idx] * 0.01)
    else
        string texNorm = texturePathNormal + prefix + texNum + ".dds"
        applyOverlay(akTarget, isFemale, Area, OverlaySlot,     texNorm, condMarkTint[idx], 0, false, 0.0, condMarkAlpha[idx] * 0.01)
        clearOverlay(akTarget, isFemale, Area, OverlaySlot + 1)
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
