Scriptname MTF_MainQuest extends Quest

import Debug
import Utility

; ── Global settings ──────────────────────────────────────────────────────────
bool Property ModActive = false Auto
bool Property DebugMode = false Auto
int Property OverlaySlot = 2 Auto
int Property CurrentOverlaySlot = 2 Auto
float Property updateInterval = 2.0 Auto

; ── Visual pack catalog cache ───────────────────────────────────────────────
; Pack list loaded once from JSON files under
;   Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/*.json
; LoadVisualCatalogs() scans the folder, caches packIds/labels/filenames.
; The "active pack" is now per-slot (see condPackId) rather than global.
string[] Property visualPackIds Auto Hidden
string[] Property visualPackLabels Auto Hidden
string[] Property visualPackFiles Auto Hidden   ; JsonUtil path: "MagicTattoosFramework/visuals/<basename>"
int Property visualPackCount = 0 Auto Hidden
bool _visualsLoaded = false

; ── Per-slot arrays (index 0 = Default, 1-7 = Conditions) ───────────────────
; condPluginId: "<pluginId>:<conditionItemId>" composite key; "" = unset.
string[] Property condPluginId Auto
int[] Property condParam Auto
; condPackId / condEntryId: stable pack + entry id (e.g. "mtf.lewdmarks-racemenu", "001").
; For slots 1-7, condPackId == "" means "inherit Default's pack+entry".
; For slot 0, condPackId must be non-empty when a visual pack is desired.
string[] Property condPackId Auto
string[] Property condEntryId Auto
; Per-layer visual params. Indexed by [slot * MAX_LAYERS_PER_SLOT() + layer].
; Each entry's picked layers consume layer indices 0..layerCount-1.
int[] Property condLayerTint Auto
int[] Property condLayerEmissive Auto
float[] Property condLayerEmissiveMult Auto
int[] Property condLayerAlpha Auto
; Per-slot pulse (animated emissive). Rate=0 disables. Modulates each
; layer's effective emissive intensity as base * (1 + depth% * sin(2π·rate·t))
; on a dedicated fast tick (PULSE_INTERVAL()). Pause is an optional
; hold-at-base interval inserted between sine cycles — full cycle takes
; (1/rate) seconds, then mult stays at 1.0 for `pause` seconds before
; the next cycle begins.
float[] Property condPulseRate Auto
int[]   Property condPulseDepth Auto
; condPulsePause lives in StorageUtil — see GetCondPulsePause/SetCondPulsePause
; below. Reason: an Auto property added in a later version doesn't always
; attach to an already-saved script instance (writes silently no-op).
; StorageUtil persists in the cosave and sidesteps the trap.

; ── Scratch preset buffer (v0.0.33) ──────────────────────────────────────────
; When evaluating a tracked NPC we hot-load the NPC's preset JSON into this
; parallel set of arrays so the rest of the eval/draw pipeline reads
; uniformly. The player keeps using cond*/effect*/cooldown* directly. This
; buffer is transient — re-populated by _loadPresetToScratch on switch.
; Per-actor scalars (tier, cooldowns, pulse phase, suspended/killed flags)
; live in StorageUtil keyed on the actor form, NOT here.
string[] Property _sCondPluginId       Auto Hidden
int[]    Property _sCondParam          Auto Hidden
string[] Property _sCondPackId         Auto Hidden
string[] Property _sCondEntryId        Auto Hidden
int[]    Property _sCondLayerTint      Auto Hidden
int[]    Property _sCondLayerEmissive  Auto Hidden
float[]  Property _sCondLayerEmissiveMult Auto Hidden
int[]    Property _sCondLayerAlpha     Auto Hidden
float[]  Property _sCondPulseRate      Auto Hidden
int[]    Property _sCondPulseDepth     Auto Hidden
string[] Property _sEffectKey          Auto Hidden
int[]    Property _sEffectParam        Auto Hidden
int[]    Property _sEffectParam2       Auto Hidden
int[]    Property _sCooldownMin        Auto Hidden
int[]    Property _sCooldownMode       Auto Hidden
string   _scratchLoadedFor = ""

int Function MAX_LAYERS_PER_SLOT() global
    return 4
EndFunction

int Function _layerIdx(int slot, int layer)
    return slot * MAX_LAYERS_PER_SLOT() + layer
EndFunction

; ── Per-slot effect lists (flat, 8 slots × MAX_EFFECTS_PER_SLOT) ─────────────
; effectKey: "<pluginId>:<effectItemId>" or ""; effectParam parallel.
; Index: slot S, effect E => S * MAX_EFFECTS_PER_SLOT + E.
string[] Property effectKey Auto
int[] Property effectParam Auto
int[] Property effectParam2 Auto Hidden

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

bool forceRedraw = false
int currentTier = -1
bool influenceTracking = false

; Pulse animation state (transient).
float _pulseStartRT = 0.0
float _nextSlowRT = 0.0

; Cached per-tier pulse context: layer count and sex only. Base emissive
; intensity is read LIVE each tick from condLayerEmissiveMult so MCM
; slider changes take effect within one pulse tick (50ms) instead of
; waiting up to one slow tick (~2s) for cache refresh.
int   _pulseTier = -1
int   _pulseLayerN = 0
bool  _pulseIsFemale = false

int Function MAX_EFFECTS_PER_SLOT() global
    return 4
EndFunction

float Function PULSE_INTERVAL() global
    ; Fast OnUpdate cadence for pulse animation. 0.05s = 20 Hz, just above
    ; the practical Papyrus RegisterForSingleUpdate floor (~30ms). Going
    ; lower won't help — the VM throttles to fUpdateBudgetMS. Only fired
    ; while the current tier actually has pulse configured.
    return 0.05
EndFunction

; ─────────────────────────────────────────────────────────────────────────────

Event OnInit()
    Trace("[MTF_Main] OnInit")
    EnsureArrays()
EndEvent

bool Property _arraysReady = false Auto Hidden
int Property _migrationLevel = 0 Auto Hidden

Function EnsureArrays()
{One-shot allocation — bool guard avoids reading array properties (Papyrus errors on None→Type[] casts).
 Post-release-added arrays are patched in unconditionally below the guard
 so upgraders whose _arraysReady is already true still get them allocated.}
    if _arraysReady
        ; Defensive lazy-allocate for properties added in later versions.
        ; Cheap: just None-checks per call.
        if condPulseRate == None
            condPulseRate = new float[8]
        endif
        if condPulseDepth == None
            condPulseDepth = new int[8]
        endif
        return
    endif
    Trace("[MTF_Main] EnsureArrays: allocating arrays")
    condPluginId          = new string[8]
    condParam             = new int[8]
    condPackId            = new string[8]
    condEntryId           = new string[8]
    condLayerTint         = new int[32]   ; 8 slots × 4 layers
    condLayerEmissive     = new int[32]
    condLayerEmissiveMult = new float[32]
    condLayerAlpha        = new int[32]
    condPulseRate         = new float[8]
    condPulseDepth        = new int[8]
    effectKey             = new string[32]    ; 8 slots × 4 effects
    effectParam           = new int[32]
    effectParam2          = new int[32]       ; optional 2nd param per effect slot
    cooldownMin           = new int[8]
    cooldownMode          = new int[8]
    cooldownUntilGT       = new float[8]
    registeredPlugins     = new Form[32]
    pluginCount           = 0
    _arraysReady          = true
EndFunction

; Inheritance helpers — slots 1-7 with empty condPackId fall back to slot 0.
; The "<none>" sentinel means "explicit no-texture / effects-only" and never
; inherits; drawOverlay skips drawing when it sees this value.
string Function ResolveSlotPackId(int slot)
    if condPackId == None
        return ""
    endif
    string pid = condPackId[slot]
    if pid == "" && slot > 0
        return condPackId[0]
    endif
    return pid
EndFunction

string Function ResolveSlotEntryId(int slot)
    if condEntryId == None
        return ""
    endif
    if slot > 0 && condPackId != None && condPackId[slot] == ""
        return condEntryId[0]
    endif
    return condEntryId[slot]
EndFunction

; ─────────────────────────────────────────────────────────────────────────────
; Visual catalog (JSON-driven texture packs)
; ─────────────────────────────────────────────────────────────────────────────
; A "visual pack" is a JSON file under
;   Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/
; describing a set of "entries", each with one or more texture "layers".
; Picking an entry in MCM stamps that entry's layers into consecutive
; NiOverride overlay slots (OverlaySlot + layerIndex). Per-layer
; emissiveMult / alphaMult biases let the catalog encode e.g. "this glow
; layer should be 2× brighter than the base mark" without exposing
; per-layer sliders in the MCM.
;
; The pack list itself is cached once into visualPackIds/Labels/Files
; arrays; entry details (id/label/layer count/textures) are looked up
; on demand via JsonUtil PathCount/GetPathStringValue/GetPathFloatValue
; because 96+ entries × 2 layers = too much to flatten into Papyrus
; arrays up-front.

Function LoadVisualCatalogs()
    if _visualsLoaded
        return
    endif
    ForceReloadVisualCatalogs()
EndFunction

Function ForceReloadVisualCatalogs()
{Bypasses the _visualsLoaded cache. Two-pass:
   1. JsonInFolder enumeration — picks up third-party drop-in packs.
   2. Hardcoded fallback for the two ship-included catalogs — defends
      against JsonInFolder native quirks (some VFS overlays don't expose
      newly-added subdirectories to its FindFirstFile-style scan).}
    visualPackIds    = new string[32]
    visualPackLabels = new string[32]
    visualPackFiles  = new string[32]
    visualPackCount  = 0

    int rawCount = 0
    int probedCount = 0
    int directHits = 0

    ; Pass 1: folder scan
    string[] files = JsonUtil.JsonInFolder("MagicTattoosFramework/visuals")
    if files != None
        rawCount = files.Length
        int i = 0
        while i < files.Length && visualPackCount < 32
            ; Try TWO path forms — different PapyrusUtil builds disagree
            ; about whether the .json suffix should be on the filename
            ; passed to GetStringValue. Take whichever returns a packId.
            string raw = files[i]
            string withExt    = "MagicTattoosFramework/visuals/" + raw
            string withoutExt = withExt
            int dot = StringUtil.Find(raw, ".json")
            if dot > 0
                withoutExt = "MagicTattoosFramework/visuals/" + StringUtil.Substring(raw, 0, dot)
            endif
            probedCount += 1
            string useFile = withoutExt
            string pid   = JsonUtil.GetPathStringValue(useFile, ".packId", "")
            if pid == ""
                useFile = withExt
                pid = JsonUtil.GetPathStringValue(useFile, ".packId", "")
            endif
            string label = JsonUtil.GetPathStringValue(useFile, ".label", pid)
            Trace("[MTF_Main] visual probe raw='" + raw + "' useFile='" + useFile + "' packId='" + pid + "'")
            if pid != "" && _findPackFileIdx(useFile) < 0
                visualPackIds[visualPackCount]    = pid
                visualPackLabels[visualPackCount] = label
                visualPackFiles[visualPackCount]  = useFile
                visualPackCount += 1
            endif
            i += 1
        endwhile
    endif

    ; Pass 2: hardcoded probe for ship-included packs
    string[] known = new string[2]
    known[0] = "MagicTattoosFramework/visuals/mtf.lewdmarks-racemenu"
    known[1] = "MagicTattoosFramework/visuals/mtf.lewdmarks-slavetats"
    int k = 0
    while k < known.Length && visualPackCount < 32
        string kf = known[k]
        string kpid = ""
        string klabel = ""
        if _findPackFileIdx(kf) < 0
            kpid = JsonUtil.GetPathStringValue(kf, ".packId", "")
            if kpid == ""
                kf = kf + ".json"
                if _findPackFileIdx(kf) < 0
                    kpid = JsonUtil.GetPathStringValue(kf, ".packId", "")
                endif
            endif
            klabel = JsonUtil.GetPathStringValue(kf, ".label", kpid)
            Trace("[MTF_Main] direct hit '" + kf + "' packId='" + kpid + "'")
            if kpid != ""
                visualPackIds[visualPackCount]    = kpid
                visualPackLabels[visualPackCount] = klabel
                visualPackFiles[visualPackCount]  = kf
                visualPackCount += 1
                directHits += 1
            endif
        endif
        k += 1
    endwhile

    _visualsLoaded = true
    Trace("[MTF_Main] LoadVisualCatalogs: folderRaw=" + rawCount + " probed=" + probedCount + " direct=" + directHits + " loaded=" + visualPackCount)
    string sample = "(none)"
    if files != None && files.Length > 0
        sample = files[0]
    endif
    if DebugMode
        Notification("MTF visuals: folder=" + rawCount + " direct=" + directHits + " loaded=" + visualPackCount)
        Notification("MTF first file: '" + sample + "'")
    endif
EndFunction

int Function _findPackFileIdx(string f)
    int i = 0
    while i < visualPackCount
        if visualPackFiles[i] == f
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

int Function GetVisualPackCount()
    LoadVisualCatalogs()
    return visualPackCount
EndFunction

string Function GetVisualPackIdAt(int i)
    LoadVisualCatalogs()
    if i < 0 || i >= visualPackCount
        return ""
    endif
    return visualPackIds[i]
EndFunction

string Function GetVisualPackLabelAt(int i)
    LoadVisualCatalogs()
    if i < 0 || i >= visualPackCount
        return ""
    endif
    return visualPackLabels[i]
EndFunction

int Function FindVisualPackIndex(string packId)
    LoadVisualCatalogs()
    if packId == ""
        return -1
    endif
    int i = 0
    while i < visualPackCount
        if visualPackIds[i] == packId
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

string Function _packFileById(string packId)
    int idx = FindVisualPackIndex(packId)
    if idx < 0
        return ""
    endif
    return visualPackFiles[idx]
EndFunction

int Function GetPackEntryCount(string packId)
    string f = _packFileById(packId)
    if f == ""
        return 0
    endif
    return JsonUtil.PathCount(f, ".entries")
EndFunction

string Function GetPackEntryIdAt(string packId, int entryIdx)
    string f = _packFileById(packId)
    if f == "" || entryIdx < 0
        return ""
    endif
    return JsonUtil.GetPathStringValue(f, ".entries[" + entryIdx + "].id", "")
EndFunction

string Function GetPackEntryLabelAt(string packId, int entryIdx)
    string f = _packFileById(packId)
    if f == "" || entryIdx < 0
        return ""
    endif
    return JsonUtil.GetPathStringValue(f, ".entries[" + entryIdx + "].label", "")
EndFunction

int Function _findEntryIdx(string packId, string entryId)
    if entryId == ""
        return -1
    endif
    int n = GetPackEntryCount(packId)
    int i = 0
    while i < n
        if GetPackEntryIdAt(packId, i) == entryId
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

int Function GetEntryLayerCount(string packId, string entryId)
    string f = _packFileById(packId)
    int idx = _findEntryIdx(packId, entryId)
    if f == "" || idx < 0
        return 0
    endif
    return JsonUtil.PathCount(f, ".entries[" + idx + "].layers")
EndFunction

string Function GetEntryLayerTexture(string packId, string entryId, int layer)
    string f = _packFileById(packId)
    int idx = _findEntryIdx(packId, entryId)
    if f == "" || idx < 0 || layer < 0
        return ""
    endif
    return JsonUtil.GetPathStringValue(f, ".entries[" + idx + "].layers[" + layer + "].texture", "")
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

Function SetCondPulseRate(int slot, float v)
    float[] a = condPulseRate
    if a == None || a.Length < 8
        a = new float[8]
    endif
    a[slot] = v
    condPulseRate = a
EndFunction

Function SetCondPulseDepth(int slot, int v)
    int[] a = condPulseDepth
    if a == None || a.Length < 8
        a = new int[8]
    endif
    a[slot] = v
    condPulseDepth = a
EndFunction

float Function GetCondPulsePause(int slot)
    if slot < 0 || slot >= 8
        return 0.0
    endif
    return StorageUtil.GetFloatValue(self, "mtf.pulse.pause." + slot, 0.0)
EndFunction

Function SetCondPulsePause(int slot, float v)
    if slot < 0 || slot >= 8
        return
    endif
    StorageUtil.SetFloatValue(self, "mtf.pulse.pause." + slot, v)
EndFunction

bool Function _slotHasPulse(int slot)
    if slot < 0 || slot >= 8
        return false
    endif
    if condPulseRate == None || condPulseDepth == None
        return false
    endif
    return condPulseRate[slot] > 0.0 && condPulseDepth[slot] > 0
EndFunction

Function _resyncPulseCache(int tier)
{Snapshot the per-tier overlay context so the fast pulse tick can run
 with only int/float ops and NiOverride writes — no JsonUtil lookups,
 no actor base/sex queries. Call from drawOverlay on tier change.}
    _pulseTier = -1
    if tier < 0 || tier >= 8 || PlayerRef == None
        return
    endif
    if !_slotHasPulse(tier)
        return
    endif
    string packId  = ResolveSlotPackId(tier)
    string entryId = ResolveSlotEntryId(tier)
    if packId == "" || packId == "<none>" || entryId == ""
        return
    endif
    int layerN = GetEntryLayerCount(packId, entryId)
    int max = _maxLayerSlots()
    if layerN > max
        layerN = max
    endif
    int maxLayers = MAX_LAYERS_PER_SLOT()
    if layerN > maxLayers
        layerN = maxLayers
    endif
    if layerN <= 0
        return
    endif
    _pulseIsFemale = PlayerRef.GetLeveledActorBase().GetSex() as bool
    _pulseLayerN = layerN
    _pulseTier = tier
EndFunction

Function _applyPulse()
{Hot path. Reads cached context only — must stay branch-light.}
    if _pulseTier < 0 || _pulseLayerN <= 0 || PlayerRef == None
        return
    endif
    float rate  = condPulseRate[_pulseTier]
    float depth = (condPulseDepth[_pulseTier] as float) * 0.01
    float pause = GetCondPulsePause(_pulseTier)
    float t = Utility.GetCurrentRealTime() - _pulseStartRT
    ; Wave model: emissive strength slider = peak (ceiling). Depth = how
    ; far it dims down from peak. mult ∈ [1-depth, 1]:
    ;   cycle start  → mult = 1-depth (trough, dim)
    ;   cycle middle → mult = 1.0     (peak, full base intensity)
    ;   cycle end    → mult = 1-depth (trough)
    ;   pause        → mult = 1-depth (continuous with cycle end)
    ; Uses (0.5 - 0.5·cos) so the wave starts and ends at the trough.
    float wave
    float floor = 1.0 - depth
    if pause > 0.0 && rate > 0.0
        float cycle = 1.0 / rate
        float period = cycle + pause
        float tMod = t - (((t / period) as int) as float) * period
        if tMod < cycle
            wave = 0.5 - 0.5 * Math.Cos(tMod * rate * 360.0)
        else
            wave = 0.0
        endif
    else
        ; No pause — continuous rise/fall between trough and peak.
        wave = 0.5 - 0.5 * Math.Cos(t * rate * 360.0)
    endif
    float mult = floor + depth * wave
    if mult < 0.0
        mult = 0.0
    endif
    int i = 0
    int baseSlot = OverlaySlot
    while i < _pulseLayerN
        ; Read base intensity live each tick so any MCM slider change
        ; takes effect on the next pulse step (no waiting for cache
        ; refresh via forceRedraw).
        int lidx = _pulseTier * 4 + i
        float baseEm = condLayerEmissiveMult[lidx]
        float pulsed = baseEm * mult
        string Node = "Body [ovl" + (baseSlot + i) + "]"
        NiOverride.AddNodeOverrideFloat(PlayerRef, _pulseIsFemale, Node, 1, -1, pulsed, true)
        i += 1
    endwhile
    NiOverride.ApplyNodeOverrides(PlayerRef)
EndFunction

; Hit-class counters (7 classes: ANY/BLUNT/BLADED/RANGED/FIRE/FROST/SHOCK).
; Stored via PapyrusUtil StorageUtil. Auto Hidden array properties added
; post-release do not get attached to existing script instances and even
; whole-array writes (`_hitCount = new int[7]`) don't read back — verified
; empirically. StorageUtil persists in the cosave, no init-order traps.

Function IncHitCount(int classIdx)
    int cur = StorageUtil.GetIntValue(self, "mtf.hit.count.0", 0)
    StorageUtil.SetIntValue(self, "mtf.hit.count.0", cur + 1)
    if classIdx >= 1 && classIdx <= 6
        int curC = StorageUtil.GetIntValue(self, "mtf.hit.count." + classIdx, 0)
        StorageUtil.SetIntValue(self, "mtf.hit.count." + classIdx, curC + 1)
    endif
EndFunction

int Function GetHitCount(int classIdx)
    return StorageUtil.GetIntValue(self, "mtf.hit.count." + classIdx, 0)
EndFunction

int Function GetHitRolled(int classIdx)
    return StorageUtil.GetIntValue(self, "mtf.hit.rolled." + classIdx, 0)
EndFunction

Function SetHitRolled(int classIdx, int val)
    StorageUtil.SetIntValue(self, "mtf.hit.rolled." + classIdx, val)
EndFunction

float Function GetHitArmedRT(int classIdx)
    return StorageUtil.GetFloatValue(self, "mtf.hit.armed." + classIdx, 0.0)
EndFunction

Function SetHitArmedRT(int classIdx, float val)
    StorageUtil.SetFloatValue(self, "mtf.hit.armed." + classIdx, val)
EndFunction

; ── Presets (PapyrusUtil JsonUtil, cross-save) ──────────────────────────────
; One JSON file per preset under
;   Data/SKSE/Plugins/StorageUtil/MagicTattoosFramework/presets/<name>.json
; JsonUtil has no native delete, so each file carries a `valid` int (1=live,
; 0=deleted). ListPresets filters by it so the file can stay on disk harmless.
; Captures slot config (cond + effects + cooldown + visuals) and each
; registered plugin's per-plugin Setting values. Globals (ModActive, etc.)
; are intentionally excluded.

string Function _presetFile(string name)
    return "MagicTattoosFramework/presets/" + name
EndFunction

; ── Hex color helpers ────────────────────────────────────────────────────────
; Tint/emissive on disk are stored as "#RRGGBB" hex strings so the JSON is
; readable. Loader also accepts a plain int for legacy values / authors
; who prefer decimal.

string Function _intToHex(int v)
    if v < 0
        v = 0
    elseif v > 16777215
        v = 16777215
    endif
    string digits = "0123456789ABCDEF"
    string result = ""
    int i = 0
    while i < 6
        int d = v % 16
        result = StringUtil.Substring(digits, d, 1) + result
        v = v / 16
        i += 1
    endwhile
    return "#" + result
EndFunction

int Function _hexCharToInt(string c)
    string lo = "0123456789abcdef"
    int idx = StringUtil.Find(lo, c)
    if idx >= 0 && idx < 16
        return idx
    endif
    string up = "0123456789ABCDEF"
    return StringUtil.Find(up, c)
EndFunction

int Function _parseHex(string s)
    int len = StringUtil.GetLength(s)
    if len < 6
        return -1
    endif
    int start = 0
    if StringUtil.Substring(s, 0, 1) == "#"
        start = 1
    endif
    if len - start < 6
        return -1
    endif
    int result = 0
    int i = 0
    while i < 6
        int d = _hexCharToInt(StringUtil.Substring(s, start + i, 1))
        if d < 0
            return -1
        endif
        result = result * 16 + d
        i += 1
    endwhile
    return result
EndFunction

int Function _readColor(string f, string path, int default)
    ; Prefer string ("#RRGGBB" or "RRGGBB"); fall back to int (decimal).
    string s = JsonUtil.GetPathStringValue(f, path, "")
    if s != ""
        int parsed = _parseHex(s)
        if parsed >= 0
            return parsed
        endif
    endif
    return JsonUtil.GetPathIntValue(f, path, default)
EndFunction

string Function _sanitizePresetName(string raw)
    ; Keep only [A-Za-z0-9_-], cap length to 32. Anything else becomes "_".
    if raw == ""
        return ""
    endif
    string allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
    string out = ""
    int i = 0
    int maxL = 32
    int rawLen = StringUtil.GetLength(raw)
    while i < rawLen && i < maxL
        string ch = StringUtil.Substring(raw, i, 1)
        if StringUtil.Find(allowed, ch) >= 0
            out += ch
        else
            out += "_"
        endif
        i += 1
    endwhile
    return out
EndFunction

bool Function SavePreset(string rawName)
    string name = _sanitizePresetName(rawName)
    if name == ""
        return false
    endif
    string f = _presetFile(name)
    JsonUtil.ClearAll(f)
    JsonUtil.SetPathIntValue(f,    ".valid",         1)
    JsonUtil.SetPathStringValue(f, ".displayname",   rawName)
    JsonUtil.SetPathIntValue(f,    ".schemaversion", 5)

    EnsureArrays()
    int maxL = MAX_LAYERS_PER_SLOT()
    int maxE = MAX_EFFECTS_PER_SLOT()
    int s = 0
    while s < 8
        string sp = ".slot[" + s + "]"
        JsonUtil.SetPathStringValue(f, sp + ".cond.pluginid", condPluginId[s])
        JsonUtil.SetPathIntValue(f,    sp + ".cond.param",    condParam[s])
        JsonUtil.SetPathStringValue(f, sp + ".cond.packid",   condPackId[s])
        JsonUtil.SetPathStringValue(f, sp + ".cond.entryid",  condEntryId[s])
        JsonUtil.SetPathIntValue(f,    sp + ".cooldown.min",  cooldownMin[s])
        JsonUtil.SetPathIntValue(f,    sp + ".cooldown.mode", cooldownMode[s])
        ; Skip pulse rows when disabled — keeps the file readable.
        float pausePersist = GetCondPulsePause(s)
        if condPulseRate[s] > 0.0 || condPulseDepth[s] > 0 || pausePersist > 0.0
            JsonUtil.SetPathFloatValue(f, sp + ".pulse.rate",  condPulseRate[s])
            JsonUtil.SetPathIntValue(f,   sp + ".pulse.depth", condPulseDepth[s])
            if pausePersist > 0.0
                JsonUtil.SetPathFloatValue(f, sp + ".pulse.pause", pausePersist)
            endif
        endif
        int L = 0
        while L < maxL
            int li = _layerIdx(s, L)
            string lp = sp + ".layer[" + L + "]"
            JsonUtil.SetPathStringValue(f, lp + ".tint",         _intToHex(condLayerTint[li]))
            JsonUtil.SetPathStringValue(f, lp + ".emissive",     _intToHex(condLayerEmissive[li]))
            JsonUtil.SetPathFloatValue(f,  lp + ".emissivemult", condLayerEmissiveMult[li])
            JsonUtil.SetPathIntValue(f,    lp + ".alpha",        condLayerAlpha[li])
            L += 1
        endwhile
        int e = 0
        while e < maxE
            int fxI = s * maxE + e
            ; Skip serializing effect rows with empty key — load uses defaults.
            if effectKey[fxI] != ""
                string ep = sp + ".effect[" + e + "]"
                JsonUtil.SetPathStringValue(f, ep + ".key",    effectKey[fxI])
                JsonUtil.SetPathIntValue(f,    ep + ".param",  effectParam[fxI])
                JsonUtil.SetPathIntValue(f,    ep + ".param2", effectParam2[fxI])
            endif
            e += 1
        endwhile
        s += 1
    endwhile

    ; Plugin settings — walk registered plugins; key by stable pluginId+settingId.
    int p = 0
    while p < pluginCount
        MTF_Plugin plug = GetPluginAt(p)
        if plug != None
            string pid = plug.GetPluginId()
            int n = plug.GetSettingCount()
            int si = 0
            while si < n
                string sid = plug.GetSettingId(si)
                JsonUtil.SetPathIntValue(f, ".setting." + pid + "." + sid, plug.GetSettingValue(si))
                si += 1
            endwhile
        endif
        p += 1
    endwhile

    JsonUtil.Save(f)
    return true
EndFunction

bool Function LoadPreset(string name)
    string f = _presetFile(name)
    if !JsonUtil.JsonExists(f)
        return false
    endif
    if JsonUtil.GetPathIntValue(f, ".valid", 0) != 1
        return false
    endif
    if JsonUtil.GetPathIntValue(f, ".schemaversion", 1) < 4
        Notification("MTF: preset '" + name + "' uses an unsupported schema")
        return false
    endif
    EnsureArrays()

    int maxL = MAX_LAYERS_PER_SLOT()
    int maxE = MAX_EFFECTS_PER_SLOT()
    int s = 0
    while s < 8
        string sp = ".slot[" + s + "]"
        SetCondPluginId(s, JsonUtil.GetPathStringValue(f, sp + ".cond.pluginid", ""))
        SetCondParam(s,    JsonUtil.GetPathIntValue(f,    sp + ".cond.param",    0))
        condPackId[s]   = JsonUtil.GetPathStringValue(f, sp + ".cond.packid",  "")
        condEntryId[s]  = JsonUtil.GetPathStringValue(f, sp + ".cond.entryid", "")
        cooldownMin[s]  = JsonUtil.GetPathIntValue(f,    sp + ".cooldown.min",  0)
        cooldownMode[s] = JsonUtil.GetPathIntValue(f,    sp + ".cooldown.mode", 0)
        condPulseRate[s]  = JsonUtil.GetPathFloatValue(f, sp + ".pulse.rate",  0.0)
        condPulseDepth[s] = JsonUtil.GetPathIntValue(f,   sp + ".pulse.depth", 0)
        SetCondPulsePause(s, JsonUtil.GetPathFloatValue(f, sp + ".pulse.pause", 0.0))
        int L = 0
        while L < maxL
            int li = _layerIdx(s, L)
            string lp = sp + ".layer[" + L + "]"
            condLayerTint[li]         = _readColor(f, lp + ".tint",         16777215)
            condLayerEmissive[li]     = _readColor(f, lp + ".emissive",     16777215)
            condLayerEmissiveMult[li] = JsonUtil.GetPathFloatValue(f, lp + ".emissivemult", 0.0)
            condLayerAlpha[li]        = JsonUtil.GetPathIntValue(f,   lp + ".alpha",        100)
            L += 1
        endwhile
        int e = 0
        while e < maxE
            int fxI = s * maxE + e
            string ep = sp + ".effect[" + e + "]"
            effectKey[fxI]    = JsonUtil.GetPathStringValue(f, ep + ".key",    "")
            effectParam[fxI]  = JsonUtil.GetPathIntValue(f,    ep + ".param",  0)
            effectParam2[fxI] = JsonUtil.GetPathIntValue(f,    ep + ".param2", 0)
            e += 1
        endwhile
        s += 1
    endwhile

    int p = 0
    while p < pluginCount
        MTF_Plugin plug = GetPluginAt(p)
        if plug != None
            string pid = plug.GetPluginId()
            int n = plug.GetSettingCount()
            int si = 0
            while si < n
                string sid = plug.GetSettingId(si)
                int key = -999999
                int v = JsonUtil.GetPathIntValue(f, ".setting." + pid + "." + sid, key)
                if v != key
                    plug.SetSettingValue(si, v)
                endif
                si += 1
            endwhile
        endif
        p += 1
    endwhile

    forceRedraw = true
    return true
EndFunction

bool Function DeletePreset(string name)
    string f = _presetFile(name)
    if !JsonUtil.JsonExists(f)
        return false
    endif
    JsonUtil.SetIntValue(f, "valid", 0)
    JsonUtil.Save(f)
    return true
EndFunction

string[] Function ListPresets()
{Returns a fixed-size 64 array. Valid names come first; empty strings after.
 Caller iterates and stops on the first empty string (or use ListPresetsCount).}
    string[] raw = JsonUtil.JsonInFolder("MagicTattoosFramework/presets")
    string[] result = new string[64]
    if raw == None || raw.Length == 0
        return result
    endif
    int n = 0
    int i = 0
    while i < raw.Length && n < 64
        string nm = raw[i]
        int dot = StringUtil.Find(nm, ".json")
        if dot > 0
            nm = StringUtil.Substring(nm, 0, dot)
        endif
        if JsonUtil.GetPathIntValue(_presetFile(nm), ".valid", 0) == 1
            result[n] = nm
            n += 1
        endif
        i += 1
    endwhile
    return result
EndFunction

int Function ListPresetsCount()
    string[] r = ListPresets()
    if r == None
        return 0
    endif
    int i = 0
    while i < r.Length && r[i] != ""
        i += 1
    endwhile
    return i
EndFunction

string Function GetPresetDisplayName(string name)
    return JsonUtil.GetPathStringValue(_presetFile(name), ".displayname", name)
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
Function RegisterPlugin(MTF_Plugin p)
{Called by MTF_Plugin._tryRegister(). Idempotent.}
    if p == None || registeredPlugins == None
        return
    endif
    string pid = p.GetPluginId()
    if pid == ""
        Trace("[MTF_Main] RegisterPlugin REJECTED: empty PluginId on " + p)
        return
    endif
    if FindPluginIndex(pid) >= 0
        return
    endif
    if pluginCount >= registeredPlugins.Length
        Trace("[MTF_Main] RegisterPlugin REJECTED: registry full (" + pid + ")")
        return
    endif
    registeredPlugins[pluginCount] = p as Form
    pluginCount += 1
    Trace("[MTF_Main] Registered '" + pid + "' (" + p.GetPluginLabel() + ", " + p.GetConditionCount() + " conditions, " + p.GetEffectCount() + " effects)")
EndFunction

int Function FindPluginIndex(string pid)
    if pid == "" || registeredPlugins == None
        return -1
    endif
    int i = 0
    while i < pluginCount
        MTF_Plugin slot = registeredPlugins[i] as MTF_Plugin
        if slot != None && slot.GetPluginId() == pid
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

MTF_Plugin Function FindPlugin(string pid)
    int idx = FindPluginIndex(pid)
    if idx < 0
        return None
    endif
    return registeredPlugins[idx] as MTF_Plugin
EndFunction

MTF_Plugin Function GetPluginAt(int idx)
    if idx < 0 || idx >= pluginCount
        return None
    endif
    return registeredPlugins[idx] as MTF_Plugin
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

int Function _condIdxFor(MTF_Plugin p, string itemId)
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

int Function _effectIdxFor(MTF_Plugin p, string itemId)
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

MTF_Plugin Function ResolvePluginByKey(string key)
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
        MTF_Plugin p = GetPluginAt(i)
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
        MTF_Plugin p = GetPluginAt(pi)
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
        MTF_Plugin p = GetPluginAt(pi)
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
        MTF_Plugin p = GetPluginAt(i)
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
        MTF_Plugin p = GetPluginAt(pi)
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
        MTF_Plugin p = GetPluginAt(pi)
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

int Function GetSlotEffectParam2(int slot, int effectIdx)
    if effectParam2 == None || slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return 0
    endif
    return effectParam2[_fxBaseIdx(slot) + effectIdx]
EndFunction

Function SetSlotEffect(int slot, int effectIdx, string key, int param)
{Legacy 4-arg setter — preserves existing param2.}
    if effectKey == None || slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    int globalI = _fxBaseIdx(slot) + effectIdx
    effectKey[globalI] = key
    effectParam[globalI] = param
EndFunction

Function SetSlotEffectFull(int slot, int effectIdx, string key, int param, int param2)
{Sets all three at once. Used when picking a new effect type so the
 default param2 is applied alongside default param.}
    if effectKey == None || effectParam2 == None || slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    int globalI = _fxBaseIdx(slot) + effectIdx
    effectKey[globalI] = key
    effectParam[globalI] = param
    effectParam2[globalI] = param2
EndFunction

Function SetSlotEffectParam2(int slot, int effectIdx, int param2)
    if effectParam2 == None || slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    effectParam2[_fxBaseIdx(slot) + effectIdx] = param2
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
                MTF_Plugin p = ResolvePluginByKey(key)
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
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onActivate(itemIdx, PlayerRef, effectParam[base + e], effectParam2[base + e])
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
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onDeactivate(itemIdx, PlayerRef, effectParam[base + e], effectParam2[base + e])
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
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onTick(itemIdx, PlayerRef, effectParam[base + e], effectParam2[base + e])
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
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onGameTime(itemIdx, PlayerRef, effectParam[base + e], effectParam2[base + e])
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
        Notification("MTF: condition cleared")
        return
    endif
    string msg = "MTF: Tier " + tier
    int base = _fxBaseIdx(tier)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = effectKey[base + e]
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
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

        ; Two cadences share the same OnUpdate:
        ;   - Slow tick (updateInterval, default 2s): evaluate conditions,
        ;     redraw on tier change, run effect ticks.
        ;   - Fast tick (PULSE_INTERVAL, 0.1s): animate emissive pulse.
        ; We schedule the next OnUpdate based on whichever fires sooner.
        float now = Utility.GetCurrentRealTime()
        bool doEval = forceRedraw || (now >= _nextSlowRT)

        if doEval
            _nextSlowRT = now + updateInterval
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
                ; Reset pulse phase so the new tier starts cleanly at sin(0)=0.
                _pulseStartRT = now
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
        endif

        ; Pulse step (independent of slow eval — runs every fast tick).
        if _pulseTier >= 0
            _applyPulse()
            RegisterForSingleUpdate(PULSE_INTERVAL())
        else
            float remain = _nextSlowRT - now
            if remain < 0.05
                remain = 0.05
            endif
            RegisterForSingleUpdate(remain)
        endif
    EndEvent

    Event OnEndState()
    EndEvent

EndState

; ── Overlay drawing ───────────────────────────────────────────────────────────
; Resolves the active visual pack + the slot's picked entryId, then stamps
; each of the entry's layers into consecutive overlay slots (OverlaySlot,
; OverlaySlot+1, ...). Per-layer JSON pre-multipliers bias each layer's
; emissive intensity / alpha relative to the shared per-slot sliders.
;
; Trailing slots that the previous entry used but the new one doesn't are
; cleared so leftover textures don't bleed through after a tier change.

int Function _maxLayerSlots()
    ; NiOverride exposes 6 body overlay slots (ovl0..ovl5). Clamp to what's
    ; reachable from OverlaySlot upward.
    int rem = 6 - OverlaySlot
    if rem < 1
        rem = 1
    endif
    if rem > 6
        rem = 6
    endif
    return rem
EndFunction

function drawOverlay(actor akTarget, int idx)
    drawOverlayForActor(akTarget, idx, false)
    ; Pulse cache snapshot stays player-specific in step 2 — NPC pulse
    ; roster (step 5) introduces its own per-actor pulse state.
    if akTarget == PlayerRef
        _resyncPulseCache(idx)
    endif
endFunction

function drawOverlayForActor(actor akTarget, int idx, bool useScratch)
{Stamp overlay layers for one actor at one tier. When useScratch is true the
 scratch preset buffer (_sCond*) supplies the slot config; otherwise the
 player-owned cond* arrays do. Trailing slots are cleared like before.}
    if akTarget == None
        return
    endif
    bool isFemale = akTarget.GetLeveledActorBase().GetSex() as bool
    string Area = "Body"

    string packId  = _g_resolvePackId(idx, useScratch)
    string entryId = _g_resolveEntryId(idx, useScratch)

    int max = _maxLayerSlots()
    int maxLayers = MAX_LAYERS_PER_SLOT()
    int layerN = 0
    if packId != "" && packId != "<none>" && entryId != ""
        layerN = GetEntryLayerCount(packId, entryId)
        if layerN > max
            layerN = max
        endif
        if layerN > maxLayers
            layerN = maxLayers
        endif
    endif

    int i = 0
    while i < layerN
        int lidx     = _layerIdx(idx, i)
        string tex   = GetEntryLayerTexture(packId, entryId, i)
        int tint     = _g_layerTint(lidx, useScratch)
        int emissive = _g_layerEmissive(lidx, useScratch)
        float emMult = _g_layerEmissiveMult(lidx, useScratch)
        float alpha  = (_g_layerAlpha(lidx, useScratch) as float) * 0.01
        applyOverlay(akTarget, isFemale, Area, OverlaySlot + i, tex, tint, emissive, emMult, alpha)
        i += 1
    endwhile
    ; Clear unused trailing slots (previous entry may have had more layers).
    while i < max
        clearOverlay(akTarget, isFemale, Area, OverlaySlot + i)
        i += 1
    endwhile

    ; CurrentOverlaySlot tracks player's chosen base ovl slot. NPC overlays
    ; share the same base (OverlaySlot) so the same value works for both.
    if !useScratch
        CurrentOverlaySlot = OverlaySlot
    endif
endFunction

function setRedraw()
    forceRedraw = true
endFunction

; ── NiOverride wrappers ───────────────────────────────────────────────────────
; applyOverlay: stamps Texture into ovlSlot with per-layer effective emissive
; intensity (caller pre-multiplies condEmissiveMult by the layer's bias).
; Falloff (param 2) is set to 5.0 when intensity > 0 ("glow on"), else 0.0
; — same convention as before.

Function applyOverlay(actor Target, bool isFemale, string Area, int Slot, string Texture, int Tint, int Emissive, float Intensity, float Alpha)
    string Node = Area + " [ovl" + Slot + "]"
    if !NiOverride.HasOverlays(Target)
        NiOverride.AddOverlays(Target)
    endif
    NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 0, Texture, true)
    NiOverride.AddNodeOverrideInt(Target, isFemale, Node, 7, -1, Tint, true)
    NiOverride.AddNodeOverrideInt(Target, isFemale, Node, 0, -1, Emissive, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 1, -1, Intensity, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 8, -1, Alpha, true)
    if Intensity > 0.0
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
    removeOverlayForActor(akTarget)
endFunction

function removeOverlayForActor(actor akTarget)
    if akTarget == None
        return
    endif
    bool isFemale = akTarget.GetLeveledActorBase().GetSex() as bool
    int max = _maxLayerSlots()
    int i = 0
    while i < max
        clearOverlay(akTarget, isFemale, "Body", CurrentOverlaySlot + i)
        i += 1
    endwhile
endFunction

; ═════════════════════════════════════════════════════════════════════════════
; NPC SUPPORT (v0.0.33)
; ═════════════════════════════════════════════════════════════════════════════
; Tracked-actor list lives in StorageUtil.FormList(self, "mtf.tracked").
; Per-actor scalars live in StorageUtil on each target form. Preset config
; is loaded on demand from preset JSON into the _sCond*/_sEffect* scratch
; buffer (no per-actor snapshot — keeps storage footprint linear in
; tracked count, not slot/layer/effect cardinality).
;
; Step 2 scope: tracked-list machinery, scratch buffer, generalized
; draw + evaluate + effects dispatch, console smoke-test entry. The
; slow-tick rotation that walks tracked actors is added in step 5; the
; player flow is unchanged.

int Function TRACKED_CAP() global
    return 256
EndFunction

; New scalars added in v0.0.33 → StorageUtil (Auto property post-release
; attachment trap).
string Function GetDefaultSubjectPreset()
    return StorageUtil.GetStringValue(self, "mtf.subject.default_preset", "")
EndFunction
Function SetDefaultSubjectPreset(string name)
    StorageUtil.SetStringValue(self, "mtf.subject.default_preset", name)
EndFunction

int Function GetSubjectHotkey()
    return StorageUtil.GetIntValue(self, "mtf.subject.hotkey", -1)
EndFunction
Function SetSubjectHotkey(int code)
    StorageUtil.SetIntValue(self, "mtf.subject.hotkey", code)
EndFunction

; ── Tracked-actor list ───────────────────────────────────────────────────────
int Function GetTrackedCount()
    return StorageUtil.FormListCount(self, "mtf.tracked")
EndFunction

Actor Function GetTrackedAt(int idx)
    return StorageUtil.FormListGet(self, "mtf.tracked", idx) as Actor
EndFunction

bool Function IsTrackedActor(Actor target)
    if target == None
        return false
    endif
    return StorageUtil.FormListHas(self, "mtf.tracked", target)
EndFunction

int Function AddTrackedActor(Actor target, string presetName)
{Adds target with the given preset. Returns:
   1  added       0  already tracked (preset updated)
  -1  is player  -2  None  -3  capacity full  -4  no preset (and no default)}
    if target == None
        return -2
    endif
    if target == PlayerRef
        return -1
    endif
    if presetName == ""
        presetName = GetDefaultSubjectPreset()
        if presetName == ""
            return -4
        endif
    endif
    if IsTrackedActor(target)
        SetActorPreset(target, presetName)
        return 0
    endif
    if GetTrackedCount() >= TRACKED_CAP()
        return -3
    endif
    StorageUtil.FormListAdd(self, "mtf.tracked", target, true)
    SetActorPreset(target, presetName)
    _setActorTier(target, -1)
    _setActorPulseStartRT(target, Utility.GetCurrentRealTime())
    _setActorSuspended(target, false)
    _setActorKilled(target, false)
    return 1
EndFunction

Function RemoveTrackedActor(Actor target)
    if target == None || !IsTrackedActor(target)
        return
    endif
    int tier = _getActorTier(target)
    if tier > 0
        string preset = GetActorPreset(target)
        if preset != "" && _loadPresetToScratch(preset)
            _deactivateSlotEffectsForActor(target, tier, true)
        endif
    endif
    removeOverlayForActor(target)
    StorageUtil.FormListRemove(self, "mtf.tracked", target, true)
    _clearAllActorState(target)
EndFunction

Function ClearAllTrackedActors()
    int n = GetTrackedCount()
    int i = n - 1
    while i >= 0
        Actor a = GetTrackedAt(i)
        if a != None
            RemoveTrackedActor(a)
        else
            StorageUtil.FormListRemoveAt(self, "mtf.tracked", i)
        endif
        i -= 1
    endwhile
EndFunction

Function SetActorPreset(Actor target, string name)
    if target == None
        return
    endif
    StorageUtil.SetStringValue(target, "mtf.preset", name)
EndFunction

string Function GetActorPreset(Actor target)
    if target == None
        return ""
    endif
    return StorageUtil.GetStringValue(target, "mtf.preset", "")
EndFunction

; ── Per-actor scalar state ──────────────────────────────────────────────────
int Function _getActorTier(Actor target)
    if target == None
        return -1
    endif
    return StorageUtil.GetIntValue(target, "mtf.tier", -1)
EndFunction
Function _setActorTier(Actor target, int tier)
    if target != None
        StorageUtil.SetIntValue(target, "mtf.tier", tier)
    endif
EndFunction

float Function _getActorCooldown(Actor target, int slot)
    if target == None
        return 0.0
    endif
    return StorageUtil.GetFloatValue(target, "mtf.cd." + slot, 0.0)
EndFunction
Function _setActorCooldown(Actor target, int slot, float gameTime)
    if target != None
        StorageUtil.SetFloatValue(target, "mtf.cd." + slot, gameTime)
    endif
EndFunction

float Function _getActorPulseStartRT(Actor target)
    if target == None
        return 0.0
    endif
    return StorageUtil.GetFloatValue(target, "mtf.pulse.start", 0.0)
EndFunction
Function _setActorPulseStartRT(Actor target, float t)
    if target != None
        StorageUtil.SetFloatValue(target, "mtf.pulse.start", t)
    endif
EndFunction

bool Function _getActorSuspended(Actor target)
    if target == None
        return false
    endif
    return StorageUtil.GetIntValue(target, "mtf.suspended", 0) != 0
EndFunction
Function _setActorSuspended(Actor target, bool v)
    if target != None
        StorageUtil.SetIntValue(target, "mtf.suspended", v as int)
    endif
EndFunction

bool Function _getActorKilled(Actor target)
    if target == None
        return false
    endif
    return StorageUtil.GetIntValue(target, "mtf.killed", 0) != 0
EndFunction
Function _setActorKilled(Actor target, bool v)
    if target != None
        StorageUtil.SetIntValue(target, "mtf.killed", v as int)
    endif
EndFunction

Function _clearAllActorState(Actor target)
    if target == None
        return
    endif
    StorageUtil.UnsetStringValue(target, "mtf.preset")
    StorageUtil.UnsetIntValue(target, "mtf.tier")
    StorageUtil.UnsetFloatValue(target, "mtf.pulse.start")
    StorageUtil.UnsetIntValue(target, "mtf.suspended")
    StorageUtil.UnsetIntValue(target, "mtf.killed")
    int s = 0
    while s < 8
        StorageUtil.UnsetFloatValue(target, "mtf.cd." + s)
        s += 1
    endwhile
    int i = 0
    while i < 16
        StorageUtil.UnsetFloatValue(target, "mtf.applied." + i)
        i += 1
    endwhile
    StorageUtil.UnsetFloatValue(target, "mtf.applied.spellcost")
EndFunction

; ── Scratch buffer ──────────────────────────────────────────────────────────
Function _ensureScratchArrays()
    if _sCondPluginId == None
        _sCondPluginId          = new string[8]
        _sCondParam             = new int[8]
        _sCondPackId            = new string[8]
        _sCondEntryId           = new string[8]
        _sCondLayerTint         = new int[32]
        _sCondLayerEmissive     = new int[32]
        _sCondLayerEmissiveMult = new float[32]
        _sCondLayerAlpha        = new int[32]
        _sCondPulseRate         = new float[8]
        _sCondPulseDepth        = new int[8]
        _sEffectKey             = new string[32]
        _sEffectParam           = new int[32]
        _sEffectParam2          = new int[32]
        _sCooldownMin           = new int[8]
        _sCooldownMode          = new int[8]
    endif
EndFunction

float Function _getScratchPulsePause(int slot)
    return StorageUtil.GetFloatValue(self, "mtf.scratch.pulse.pause." + slot, 0.0)
EndFunction
Function _setScratchPulsePause(int slot, float v)
    StorageUtil.SetFloatValue(self, "mtf.scratch.pulse.pause." + slot, v)
EndFunction

bool Function _loadPresetToScratch(string name)
{Populate the scratch preset buffer from preset JSON. Skips re-load when
 already cached for `name`. Returns true on success; pass "" to clear.}
    _ensureScratchArrays()
    if name == _scratchLoadedFor
        return name != ""
    endif
    if name == ""
        _scratchLoadedFor = ""
        return false
    endif
    string f = _presetFile(name)
    if !JsonUtil.JsonExists(f)
        return false
    endif
    if JsonUtil.GetPathIntValue(f, ".valid", 0) != 1
        return false
    endif
    if JsonUtil.GetPathIntValue(f, ".schemaversion", 1) < 4
        return false
    endif
    int maxL = MAX_LAYERS_PER_SLOT()
    int maxE = MAX_EFFECTS_PER_SLOT()
    int s = 0
    while s < 8
        string sp = ".slot[" + s + "]"
        _sCondPluginId[s] = JsonUtil.GetPathStringValue(f, sp + ".cond.pluginid", "")
        _sCondParam[s]    = JsonUtil.GetPathIntValue(f,    sp + ".cond.param",    0)
        _sCondPackId[s]   = JsonUtil.GetPathStringValue(f, sp + ".cond.packid",   "")
        _sCondEntryId[s]  = JsonUtil.GetPathStringValue(f, sp + ".cond.entryid",  "")
        _sCooldownMin[s]  = JsonUtil.GetPathIntValue(f,    sp + ".cooldown.min",  0)
        _sCooldownMode[s] = JsonUtil.GetPathIntValue(f,    sp + ".cooldown.mode", 0)
        _sCondPulseRate[s]  = JsonUtil.GetPathFloatValue(f, sp + ".pulse.rate",  0.0)
        _sCondPulseDepth[s] = JsonUtil.GetPathIntValue(f,   sp + ".pulse.depth", 0)
        _setScratchPulsePause(s, JsonUtil.GetPathFloatValue(f, sp + ".pulse.pause", 0.0))
        int L = 0
        while L < maxL
            int li = s * maxL + L
            string lp = sp + ".layer[" + L + "]"
            _sCondLayerTint[li]         = _readColor(f, lp + ".tint",         16777215)
            _sCondLayerEmissive[li]     = _readColor(f, lp + ".emissive",     16777215)
            _sCondLayerEmissiveMult[li] = JsonUtil.GetPathFloatValue(f, lp + ".emissivemult", 0.0)
            _sCondLayerAlpha[li]        = JsonUtil.GetPathIntValue(f,   lp + ".alpha",        100)
            L += 1
        endwhile
        int e = 0
        while e < maxE
            int fxI = s * maxE + e
            string ep = sp + ".effect[" + e + "]"
            _sEffectKey[fxI]    = JsonUtil.GetPathStringValue(f, ep + ".key",    "")
            _sEffectParam[fxI]  = JsonUtil.GetPathIntValue(f,    ep + ".param",  0)
            _sEffectParam2[fxI] = JsonUtil.GetPathIntValue(f,    ep + ".param2", 0)
            e += 1
        endwhile
        s += 1
    endwhile
    _scratchLoadedFor = name
    return true
EndFunction

string Function GetScratchLoadedFor()
    return _scratchLoadedFor
EndFunction

; ── Generalized slot/layer/effect getters ───────────────────────────────────
; useScratch=true reads the scratch buffer (NPC preset). false reads the
; player-owned cond*/effect* arrays.
string Function _g_condPluginId(int slot, bool useScratch)
    if useScratch
        if _sCondPluginId == None
            return ""
        endif
        return _sCondPluginId[slot]
    endif
    if condPluginId == None
        return ""
    endif
    return condPluginId[slot]
EndFunction

int Function _g_condParam(int slot, bool useScratch)
    if useScratch
        if _sCondParam == None
            return 0
        endif
        return _sCondParam[slot]
    endif
    if condParam == None
        return 0
    endif
    return condParam[slot]
EndFunction

int Function _g_cooldownMode(int slot, bool useScratch)
    if useScratch
        if _sCooldownMode == None
            return 0
        endif
        return _sCooldownMode[slot]
    endif
    if cooldownMode == None
        return 0
    endif
    return cooldownMode[slot]
EndFunction

int Function _g_cooldownMin(int slot, bool useScratch)
    if useScratch
        if _sCooldownMin == None
            return 0
        endif
        return _sCooldownMin[slot]
    endif
    if cooldownMin == None
        return 0
    endif
    return cooldownMin[slot]
EndFunction

float Function _g_pulseRate(int slot, bool useScratch)
    if useScratch
        if _sCondPulseRate == None
            return 0.0
        endif
        return _sCondPulseRate[slot]
    endif
    if condPulseRate == None
        return 0.0
    endif
    return condPulseRate[slot]
EndFunction

int Function _g_pulseDepth(int slot, bool useScratch)
    if useScratch
        if _sCondPulseDepth == None
            return 0
        endif
        return _sCondPulseDepth[slot]
    endif
    if condPulseDepth == None
        return 0
    endif
    return condPulseDepth[slot]
EndFunction

float Function _g_pulsePause(int slot, bool useScratch)
    if useScratch
        return _getScratchPulsePause(slot)
    endif
    return GetCondPulsePause(slot)
EndFunction

string Function _g_resolvePackId(int slot, bool useScratch)
    if !useScratch
        return ResolveSlotPackId(slot)
    endif
    if _sCondPackId == None
        return ""
    endif
    string pid = _sCondPackId[slot]
    if pid == "" && slot > 0
        return _sCondPackId[0]
    endif
    return pid
EndFunction

string Function _g_resolveEntryId(int slot, bool useScratch)
    if !useScratch
        return ResolveSlotEntryId(slot)
    endif
    if _sCondEntryId == None
        return ""
    endif
    if slot > 0 && _sCondPackId != None && _sCondPackId[slot] == ""
        return _sCondEntryId[0]
    endif
    return _sCondEntryId[slot]
EndFunction

int Function _g_layerTint(int lidx, bool useScratch)
    if useScratch
        if _sCondLayerTint == None
            return 16777215
        endif
        return _sCondLayerTint[lidx]
    endif
    return condLayerTint[lidx]
EndFunction
int Function _g_layerEmissive(int lidx, bool useScratch)
    if useScratch
        if _sCondLayerEmissive == None
            return 16777215
        endif
        return _sCondLayerEmissive[lidx]
    endif
    return condLayerEmissive[lidx]
EndFunction
float Function _g_layerEmissiveMult(int lidx, bool useScratch)
    if useScratch
        if _sCondLayerEmissiveMult == None
            return 0.0
        endif
        return _sCondLayerEmissiveMult[lidx]
    endif
    return condLayerEmissiveMult[lidx]
EndFunction
int Function _g_layerAlpha(int lidx, bool useScratch)
    if useScratch
        if _sCondLayerAlpha == None
            return 100
        endif
        return _sCondLayerAlpha[lidx]
    endif
    return condLayerAlpha[lidx]
EndFunction

string Function _g_effectKey(int fxIdx, bool useScratch)
    if useScratch
        if _sEffectKey == None
            return ""
        endif
        return _sEffectKey[fxIdx]
    endif
    if effectKey == None
        return ""
    endif
    return effectKey[fxIdx]
EndFunction
int Function _g_effectParam(int fxIdx, bool useScratch)
    if useScratch
        if _sEffectParam == None
            return 0
        endif
        return _sEffectParam[fxIdx]
    endif
    if effectParam == None
        return 0
    endif
    return effectParam[fxIdx]
EndFunction
int Function _g_effectParam2(int fxIdx, bool useScratch)
    if useScratch
        if _sEffectParam2 == None
            return 0
        endif
        return _sEffectParam2[fxIdx]
    endif
    if effectParam2 == None
        return 0
    endif
    return effectParam2[fxIdx]
EndFunction

; ── Generalized eval + effect dispatch ──────────────────────────────────────
int Function evaluateTierForActor(Actor target, bool useScratch)
    if target == None
        return 0
    endif
    if _getActorKilled(target)
        return 0
    endif
    float now = Utility.GetCurrentGameTime()
    int i = 1
    while i < 8
        string key = _g_condPluginId(i, useScratch)
        if key != ""
            float cdEnd
            if useScratch
                cdEnd = _getActorCooldown(target, i)
            else
                cdEnd = 0.0
                if cooldownUntilGT != None
                    cdEnd = cooldownUntilGT[i]
                endif
            endif
            bool timerActive = (now < cdEnd)
            int mode = _g_cooldownMode(i, useScratch)
            if mode == 1 && timerActive
                return i
            endif
            bool inCooldown = (mode == 0 && timerActive)
            if !inCooldown
                MTF_Plugin p = ResolvePluginByKey(key)
                if p != None
                    int itemIdx = _condIdxFor(p, _keyItemId(key))
                    if itemIdx >= 0 && p.checkCondition(itemIdx, target, _g_condParam(i, useScratch))
                        return i
                    endif
                endif
            endif
        endif
        i += 1
    endwhile
    return 0
EndFunction

Function _activateSlotEffectsForActor(Actor target, int slot, bool useScratch)
    if target == None || slot < 0 || slot >= 8
        return
    endif
    int base = slot * MAX_EFFECTS_PER_SLOT()
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _g_effectKey(base + e, useScratch)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onActivate(itemIdx, target, _g_effectParam(base + e, useScratch), _g_effectParam2(base + e, useScratch))
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _deactivateSlotEffectsForActor(Actor target, int slot, bool useScratch)
    if target == None || slot < 0 || slot >= 8
        return
    endif
    int base = slot * MAX_EFFECTS_PER_SLOT()
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _g_effectKey(base + e, useScratch)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onDeactivate(itemIdx, target, _g_effectParam(base + e, useScratch), _g_effectParam2(base + e, useScratch))
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _tickSlotEffectsForActor(Actor target, int slot, bool useScratch)
    if target == None || slot < 0 || slot >= 8
        return
    endif
    int base = slot * MAX_EFFECTS_PER_SLOT()
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _g_effectKey(base + e, useScratch)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onTick(itemIdx, target, _g_effectParam(base + e, useScratch), _g_effectParam2(base + e, useScratch))
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

; ── Console smoke-test entry ────────────────────────────────────────────────
Function EvalAndDrawActor(Actor target)
{One-shot: load `target`'s preset into scratch, eval current tier, draw the
 overlay, fire activate/deactivate edges. Useful for console smoke testing
 before step 5 wires up the slow-tick rotation.}
    if target == None
        if DebugMode
            Notification("MTF: EvalAndDrawActor: None target")
        endif
        return
    endif
    string preset = GetActorPreset(target)
    if preset == ""
        if DebugMode
            Notification("MTF: target has no preset assigned")
        endif
        return
    endif
    if !_loadPresetToScratch(preset)
        if DebugMode
            Notification("MTF: failed to load preset '" + preset + "'")
        endif
        return
    endif
    int prevTier = _getActorTier(target)
    int newTier  = evaluateTierForActor(target, true)
    if newTier != prevTier
        if prevTier > 0
            _deactivateSlotEffectsForActor(target, prevTier, true)
        endif
        drawOverlayForActor(target, newTier, true)
        if newTier > 0
            _activateSlotEffectsForActor(target, newTier, true)
        endif
        _setActorTier(target, newTier)
        _setActorPulseStartRT(target, Utility.GetCurrentRealTime())
    else
        drawOverlayForActor(target, newTier, true)
    endif
    if newTier > 0
        _tickSlotEffectsForActor(target, newTier, true)
    endif
    if DebugMode
        Notification("MTF: " + prevTier + " -> " + newTier + " (preset=" + preset + ")")
    endif
EndFunction
