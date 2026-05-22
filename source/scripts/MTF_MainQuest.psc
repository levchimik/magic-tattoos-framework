Scriptname MTF_MainQuest extends Quest

import Debug
import Utility

; ── Global settings ──────────────────────────────────────────────────────────
bool Property ModActive = false Auto
bool Property DebugMode = false Auto
int Property OverlaySlot = 2 Auto
int Property CurrentOverlaySlot = 2 Auto
; v0.1.17 Phase 2 (multi-area): per-area MCM base slot. Default = 0 so face
; tattoos paint into "Face [ovl0]" and stack upward; users can shift via
; MCM if other mods (SlaveTats, RaceMenu overlays) sit at the bottom face
; slots. Current<Area>OverlaySlot mirrors the MCM-driven base so the slow
; tick can detect MCM edits and wipe+redraw the affected area.
int Property FaceOverlaySlot = 0 Auto
int Property HandOverlaySlot = 0 Auto
int Property FeetOverlaySlot = 0 Auto
int Property CurrentFaceOverlaySlot = 0 Auto
int Property CurrentHandOverlaySlot = 0 Auto
int Property CurrentFeetOverlaySlot = 0 Auto
float Property updateInterval = 0.1 Auto

; ── Visual pack catalog cache ───────────────────────────────────────────────
; Pack list loaded once from JSON files under
;   Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/*.json
; LoadVisualCatalogs() scans the folder, caches packIds/labels/filenames.
; The "active pack" is now per-slot (see condPackId) rather than global.
string[] Property visualPackIds Auto Hidden
string[] Property visualPackLabels Auto Hidden
string[] Property visualPackFiles Auto Hidden   ; JsonUtil path: "MagicTattoosFramework/visuals/<basename>"
; v0.1.17 Phase 1 (multi-area): each pack declares an "area" field in its
; catalog JSON ("Body" | "Face" | "Hand" | "Feet"). Default "Body" for
; legacy packs that omit it. One area per pack — mixed-area packs require
; entry-level metadata (deferred). Populated alongside Ids/Labels/Files in
; ForceReloadVisualCatalogs and consumed via GetPackArea(packId).
string[] Property visualPackAreas Auto Hidden
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
; condPulseRate, condPulseDepth, condWaveform live in StorageUtil — see
; GetCondPulseRate/SetCondPulseRate, GetCondPulseDepth/SetCondPulseDepth,
; GetCondWaveform/SetCondWaveform. Reason: Auto properties added in a later
; version don't always attach to an already-saved script instance — and on a
; fresh load, reading them throws "Cannot cast from None to <Type>[]" because
; the backing slot is None-typed rather than default-typed. StorageUtil
; persists in the cosave and sidesteps both traps.

; ── Scratch preset buffer (v0.0.33) ──────────────────────────────────────────
; When evaluating a tracked NPC we hot-load the NPC's preset JSON into this
; parallel set of arrays so the rest of the eval/draw pipeline reads
; uniformly. The player keeps using cond*/effect*/cooldown* directly. This
; buffer is transient — re-populated by _loadPresetToScratch on switch.
; Per-actor scalars (tier, cooldowns, pulse phase, suspended/killed flags)
; live in StorageUtil keyed on the actor form, NOT here.
; NOTE: These were Auto Hidden Properties. Indexed writes to property
; arrays in Papyrus hit a transient copy (see the SetCondPluginId helper
; comment for the same bug on the player slot arrays). The _loadPresetToScratch
; loop's `_sCondPluginId[s] = ...` was silently no-oping, and reads later
; returned whatever transient snapshot Papyrus reused — including a stale
; JSON path string from a different array. Switching to script-level vars
; gives us real backing storage and fixes NPC condition eval entirely.
string[] _sCondPluginId
int[]    _sCondParam
string[] _sCondPackId
string[] _sCondEntryId
int[]    _sCondLayerTint
int[]    _sCondLayerEmissive
float[]  _sCondLayerEmissiveMult
int[]    _sCondLayerAlpha
float[]  _sCondPulseRate
int[]    _sCondPulseDepth
string[] _sCondWaveform
; _sEffectKey/Param/Param2 removed in v0.1.5 — scratch effect bindings
; now live in StorageUtil under mtf.fx.scratch.<slot>.<idx>.* (parallel to
; the player live keyspace mtf.fx.<slot>.<idx>.*).
int[]    _sCooldownMin
int[]    _sCooldownMode
; Per-preset cross-fade duration (seconds) read from .transition.duration
; in the preset JSON. Applies to ALL tier transitions on this preset. <=0
; disables cross-fade (instant snap). Per-tier override is a v0.1.2+
; candidate; v0.1.1 ships per-preset only.
float    _sTransitionDuration = 0.0
string   _scratchLoadedFor = ""

; ── NPC pulse roster (v0.0.33) ───────────────────────────────────────────────
; Cap 8 actors (hardcoded for now, MCM-tunable later). Pulse params and
; per-layer emissive multipliers are SNAPSHOTTED at roster-add time so the
; 20Hz hot path is JsonUtil-free — just float reads and NiOverride writes.
; NPC pulse therefore does NOT live-update from MCM slider drags the way
; player pulse does. Updates require taking the actor in/out of the roster
; (which happens naturally on tier change).
Form[]  Property _rosterActor       Auto Hidden
float[] Property _rosterPulseRate   Auto Hidden
int[]   Property _rosterPulseDepth  Auto Hidden
float[] Property _rosterPulsePause  Auto Hidden
int[]   Property _rosterTier        Auto Hidden
int[]   Property _rosterLayerN      Auto Hidden
bool[]  Property _rosterIsFemale    Auto Hidden
float[] Property _rosterStartRT     Auto Hidden
float[] Property _rosterLayerEmMult Auto Hidden  ; 8 slots × 4 layers
int     Property _rosterCount = 0   Auto Hidden

int Function ROSTER_CAP() global
    return 8
EndFunction

int Function MAX_EVALS_PER_TICK() global
{Slow-tick budget: at most this many tracked actors are evaluated per
 update tick. Default 16 means a 256-actor roster completes a full sweep
 in 16 ticks (~32s at default 2s interval) — fine for non-realtime
 conditions like location/weather/state.}
    return 16
EndFunction

float Function SUBJECT_EVAL_RADIUS() global
{Skip eval+draw when the actor is farther than this from the player.
 Out-of-render actors aren't visible anyway. 4096 units ≈ 80m, which
 spans most exterior cells the player can see.}
    return 4096.0
EndFunction

int Function MAX_LAYERS_PER_SLOT() global
    return 4
EndFunction

int Function _layerIdx(int slot, int layer)
    return slot * MAX_LAYERS_PER_SLOT() + layer
EndFunction

; ── Multi-tattoo: overlay area helpers ──────────────────────────────────────
; v0.1.17 Phase 1 (multi-area): all 4 NiOverride overlay pools are exposed.
; The area-keyed helpers (_numOverlays, _findFirstFreeOverlaySlotNPC,
; _drawOverlayForActorAt, _apply/_clearOverlayDeferred) already accept area
; and format node names as `area + " [ovl" + N + "]"`. Callers that walk
; this list (AddAppliedPreset, _drawPresetOnActor, _compactAppliedPresets)
; will now iterate over all four areas automatically.
;
; Pack-level area: a visual pack declares its area via `.area` in its JSON
; catalog (see GetPackArea / GetVisualPackAreaAt). Slots whose picked pack's
; area doesn't match the iteration's area contribute 0 layers — the
; _computePresetReservedLayers / _playerBaseLayers filter handles this.
;
; NiOverride node-name convention (verified against skee64.ini section
; headers in v0.1.17): "Body [Ovl#]", "Face [Ovl#]", "Hands [Ovl#]"
; (PLURAL), "Feet [Ovl#]" (plural). SKEE node lookup appears to be
; case-insensitive in the bracket part — `Body [ovlN]` matches even though
; the canonical form is `Body [OvlN]` — but the area prefix MUST match the
; canonical name. Initial Phase 1 plan assumed "Hand" singular and was
; wrong; "Hands" plural is correct.
string[] Function _OVERLAY_PARTS() global
    string[] r = new string[4]
    r[0] = "Body"
    r[1] = "Face"
    r[2] = "Hands"
    r[3] = "Feet"
    return r
EndFunction

; PapyrusUtil's JsonUtil returns string values with inconsistent casing
; (observed in 0.1.17: same content pack JSON literal "Body" comes back
; as "BODY" for some files, "face" for others, "Hands" preserved -- not
; reproducible to any single rule). Every consumer of `area` below
; (_numOverlays, _maxLayerSlots, _areaToInt, _OVERLAY_PARTS-keyed
; lookups, drawOverlay node-name building) uses case-sensitive ==
; against title-case strings, so an unnormalized "BODY" silently
; no-ops everywhere. Normalize once at the catalog read site.
string Function _canonArea(string a) global
    if a == "Body" || a == "body" || a == "BODY"
        return "Body"
    elseif a == "Face" || a == "face" || a == "FACE"
        return "Face"
    elseif a == "Hands" || a == "hands" || a == "HANDS" || a == "Hand" || a == "hand" || a == "HAND"
        return "Hands"
    elseif a == "Feet" || a == "feet" || a == "FEET" || a == "Foot" || a == "foot" || a == "FOOT"
        return "Feet"
    endif
    return "Body"
EndFunction

int _numOvBodyCache = -1
int _numOvFaceCache = -1
int _numOvHandCache = -1
int _numOvFeetCache = -1

int Function _numOverlays(string area)
    if area == "Body"
        if _numOvBodyCache < 0
            int n = NiOverride.GetNumBodyOverlays()
            if n < 1
                n = 6
            endif
            _numOvBodyCache = n
        endif
        return _numOvBodyCache
    elseif area == "Face"
        if _numOvFaceCache < 0
            int n = NiOverride.GetNumFaceOverlays()
            if n < 1
                n = 3
            endif
            _numOvFaceCache = n
        endif
        return _numOvFaceCache
    elseif area == "Hands"
        if _numOvHandCache < 0
            int n = NiOverride.GetNumHandOverlays()
            if n < 1
                n = 3
            endif
            _numOvHandCache = n
        endif
        return _numOvHandCache
    elseif area == "Feet"
        if _numOvFeetCache < 0
            int n = NiOverride.GetNumFeetOverlays()
            if n < 1
                n = 3
            endif
            _numOvFeetCache = n
        endif
        return _numOvFeetCache
    endif
    return 0
EndFunction

int Function _findFirstFreeOverlaySlotNPC(Actor target, string area)
{Scan an NPC's overlay slots top-down. Returns the index above the
 highest slot with any active NodeOverride at key 9 (texture). Used at
 apply time to stack a new preset above other mods' overlays (and our
 own previously-applied presets). Gaps from removed presets are not
 reclaimed — that's by design.}
    if target == None
        return 0
    endif
    bool isFemale = target.GetLeveledActorBase().GetSex() as bool
    int total = _numOverlays(area)
    int i = total - 1
    while i >= 0
        string node = area + " [ovl" + i + "]"
        if NiOverride.HasNodeOverride(target, isFemale, node, 9, 0)
            return i + 1
        endif
        i -= 1
    endwhile
    return 0
EndFunction

; ── Per-slot effect lists ────────────────────────────────────────────────────
; Effect bindings (key/param/param2) live in StorageUtil under
; mtf.fx.<slot>.<idx>.* — see _readFxKey/_writeFxKey. Moved out of flat
; Auto array properties in v0.1.5; the legacy effectKey/effectParam/
; effectParam2 declarations were dropped in v0.1.6 alongside the ESP VMAD
; cleanup. Anything still reading those would compile-error, which is the
; intended trip-wire.

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

; v0.1.20: external accessor for currentTier. Promoting the variable to a
; Property would migrate cleanly on existing saves but tradition for
; transient state in this script is plain script-level vars, so we
; expose a getter instead. Used by the SkyrimNet bridge decorator.
int Function GetCurrentTier()
    return currentTier
EndFunction

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

; Per-preset fade-on-death config (v0.1.4). Edited via the MCM Preset
; Editor, persisted into the .fadeondeath block of the active preset
; JSON, and forwarded to the C++ roster via MTFPulse.SetActorFade
; whenever a roster entry is registered (in _applyPulse for the player
; MCM-driven base and in _rosterAddOrUpdate for stacked / NPC presets).
;
; Preset-wide rather than per-slot: one toggle/mode/duration controls
; every overlay that this preset arms. When the toggle is off, every
; arming site calls ClearActorFade so the roster's fade lane stays cold.
bool  _sFadeOnDeathEnabled = false
int   _sFadeOnDeathMode = 0
int   _sFadeOnDeathDurationMs = 2000

int Function MAX_EFFECTS_PER_SLOT() global
    ; Storage cap — how many effect bindings the runtime can dispatch per
    ; condition slot. JSON presets and the dispatch loops obey this; the
    ; MCM page draws at most MAX_EFFECTS_PER_SLOT_MCM() rows regardless.
    ; Hidden effects (rows beyond the MCM cap) still dispatch normally —
    ; if you clear a visible row, CompactEffectsAfter shifts hidden ones
    ; up into view.
    ;
    ; v0.1.5: effect bindings moved to StorageUtil (see _readFxKey /
    ; _writeFxKey). The previous 128-element Papyrus array ceiling no
    ; longer applies — raise this freely up to the practical preset-JSON
    ; size limit (~128/slot before LoadPreset starts taking noticeable
    ; time). 32 doubles v0.1.4 with headroom to spare.
    return 32
EndFunction

int Function MAX_EFFECTS_PER_SLOT_MCM() global
    ; UI cap — how many `_drawEffectRow` calls fire in the conditions
    ; page. Each visible row needs 6 SkyUI state blocks
    ; (SLOT_EFFECT_<i>_TYPE, _PARAM, _P2, _EX1/2/3); Papyrus state names
    ; are compile-time so this can't be looped at runtime. Raising
    ; requires adding state-block boilerplate in MTF_MCMQuest.psc.
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
    ; Test-branch convenience: auto-enable mod + debug toasts on new game so
    ; we don't have to walk through MCM > General every iteration. Revert
    ; before shipping.
    ModActive = true
    DebugMode = true
EndEvent

; ── Lifecycle callbacks (called from MTF_HitListener via PO3 events) ───────
Function _onTrackedActorKilled(Actor victim)
{Tracked actor died → revert each applied preset to tier 0 and back out
 active effects so any lingering applied magnitudes (drains, cost penalty)
 come off the corpse. mtf.killed prevents evaluation from re-triggering.

 v0.1.4 fade-on-death race: this Papyrus handler runs ~100ms after the
 C++ DeathSink already armed fade_active on the roster entry. If we naively
 do the visual cleanup (tier-0 redraw + _rosterRemoveActor) the fade
 animation dies before the player can see it — the tier-0 redraw clobbers
 the C++ Tick's NiOverride writes, and _rosterRemoveActor pulls the entry
 out from under the still-running Tick. Skip the visual cleanup when ANY
 preset on this actor has fade-on-death enabled; the C++ Tick's deferred-
 removal of finished fade entries naturally cleans up the roster after the
 animation completes.}
    if victim == None || !IsTrackedActor(victim)
        return
    endif
    bool fadeArmed = _actorHasArmedFade(victim)
    int n = GetActorPresetCount(victim)
    int i = 0
    while i < n
        string nm = GetActorPresetAt(victim, i)
        if nm != ""
            int prevTier = _getActorPresetTier(victim, nm)
            if prevTier >= 0 && _loadPresetToScratch(nm)
                _deactivateSlotEffectsForActor(victim, prevTier, true, nm)
            endif
            _setActorPresetTier(victim, nm, 0)
            ; Draw tier 0 (baseline) for a clean corpse overlay. Skip when
            ; fade is armed — the C++ side owns the overlay until the
            ; animation completes.
            if !fadeArmed && _loadPresetToScratch(nm)
                _drawPresetOnActor(victim, nm, 0)
            endif
        endif
        i += 1
    endwhile
    if !fadeArmed && n <= 0
        removeOverlayForActor(victim)
    endif
    if !fadeArmed
        _rosterRemoveActor(victim)
    elseif DebugMode
        Debug.Notification("[MTF fade] death cleanup deferred — fade running on " + victim.GetDisplayName())
    endif
    _setActorKilled(victim, true)
EndFunction

bool Function _presetHasFadeOnDeath(string presetName)
{Read .fadeondeath.enabled directly from the preset JSON file — does NOT
 touch _loadPresetToScratch so it's safe to call from a context where a
 different preset is already scratch-loaded (e.g. inside the loop in
 _onTrackedActorKilled).}
    if presetName == ""
        return false
    endif
    string f = _presetFile(presetName)
    if !JsonUtil.JsonExists(f)
        return false
    endif
    return JsonUtil.GetPathIntValue(f, ".fadeondeath.enabled", 0) > 0
EndFunction

bool Function _actorHasArmedFade(Actor a)
{True if any preset applied to `a` has fade-on-death enabled. Used to gate
 the visual cleanup in _onTrackedActorKilled so the C++ fade animation can
 play to completion.}
    if a == None
        return false
    endif
    int n = GetActorPresetCount(a)
    int i = 0
    while i < n
        if _presetHasFadeOnDeath(GetActorPresetAt(a, i))
            return true
        endif
        i += 1
    endwhile
    return false
EndFunction

Function _onTrackedActorAttached(Actor target)
    if target == None || !IsTrackedActor(target)
        return
    endif
    _setActorSuspended(target, false)
EndFunction

Function _onTrackedActorDetached(Actor target)
    if target == None || !IsTrackedActor(target)
        return
    endif
    _setActorSuspended(target, true)
EndFunction

bool Property _arraysReady = false Auto Hidden
; v0.1.20: fires MTF_FrameworkReady exactly once per save load (gated in
; OnUpdate's slow tick after at least one plugin has registered). External
; integrations (e.g. SkyrimNet bridge) use the event as their "MTF is alive
; and discoverable" signal.
bool Property _readyEmitted = false Auto Hidden
; _migrationLevel persists schema-level migration progress across saves.
; Read+written cross-script by MTF_MCMQuest.OnVersionUpdate; do not
; remove. v0.1.5 effect-storage migration ran inline in EnsureArrays and
; required this flag too (collapsed in v0.1.6 once no v0.1.4 saves exist
; in the wild — pre-release, no upgrade contract).
int Property _migrationLevel = 0 Auto Hidden

; Post-load grace window. While Utility.GetCurrentRealTime() is below
; this value, the slow tick's eval/draw body is skipped. Reason: at
; save time the player can be in a state where the underlying condition
; is no longer met but a lock-on-activate (cooldownMode=1) timer is
; keeping the tier active. On reload, GameTime advances slightly during
; the load process, the cooldown can expire, and the eval at ~0.5s
; post-load sees condition=false → tier 0 → clears the overlay. Symptom:
; tattoo flashes on for ~500ms then disappears. The grace period gives
; cooldowns + condition sources room to settle before we start firing
; transitions. Not Auto Hidden — it's stamped via ArmPostLoadFreeze at
; load time and doesn't need to persist across saves itself.
float _postLoadFreezeUntilRT = 0.0

Function ArmPostLoadFreeze(float seconds)
    _postLoadFreezeUntilRT = Utility.GetCurrentRealTime() + seconds
EndFunction

Function EnsureArrays()
{One-shot allocation for per-slot Auto arrays. Effect bindings (key,
 param, param2) live in StorageUtil under mtf.fx.<slot>.<idx>.* (v0.1.5+);
 pulse rate/depth/waveform already lived there. This only allocates the
 8-element per-slot condition/layer/cooldown arrays. Calling repeatedly
 is cheap (early-return on the _arraysReady flag).}
    if _arraysReady && condPluginId != None && condPluginId.Length == 8
        return
    endif

    Trace("[MTF_Main] EnsureArrays: allocating per-slot arrays")
    condPluginId          = new string[8]
    condParam             = new int[8]
    condPackId            = new string[8]
    condEntryId           = new string[8]
    condLayerTint         = new int[32]   ; 8 slots × 4 layers
    condLayerEmissive     = new int[32]
    condLayerEmissiveMult = new float[32]
    condLayerAlpha        = new int[32]
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
    if !_arraysReady
        return ""
    endif
    string pid = condPackId[slot]
    if pid == "" && slot > 0
        return condPackId[0]
    endif
    return pid
EndFunction

string Function ResolveSlotEntryId(int slot)
    if !_arraysReady
        return ""
    endif
    if slot > 0 && condPackId[slot] == ""
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
    visualPackAreas  = new string[32]
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
            ; v0.1.17 Phase 1 (multi-area): read .area; default to "Body" for
            ; legacy packs. Single area per pack (pack-level granularity).
            ; JsonUtil mangles string-value case unpredictably; normalize.
            string rawArea = JsonUtil.GetPathStringValue(useFile, ".area", "Body")
            if rawArea == ""
                rawArea = "Body"
            endif
            string area = _canonArea(rawArea)
            Trace("[MTF_Main] visual probe raw='" + raw + "' useFile='" + useFile + "' packId='" + pid + "' rawArea='" + rawArea + "' area='" + area + "'")
            if pid != "" && _findPackFileIdx(useFile) < 0
                visualPackIds[visualPackCount]    = pid
                visualPackLabels[visualPackCount] = label
                visualPackFiles[visualPackCount]  = useFile
                visualPackAreas[visualPackCount]  = area
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
            string kareaRaw = JsonUtil.GetPathStringValue(kf, ".area", "Body")
            if kareaRaw == ""
                kareaRaw = "Body"
            endif
            string karea = _canonArea(kareaRaw)
            Trace("[MTF_Main] direct hit '" + kf + "' packId='" + kpid + "' rawArea='" + kareaRaw + "' area='" + karea + "'")
            if kpid != ""
                visualPackIds[visualPackCount]    = kpid
                visualPackLabels[visualPackCount] = klabel
                visualPackFiles[visualPackCount]  = kf
                visualPackAreas[visualPackCount]  = karea
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

string Function GetVisualPackAreaAt(int i)
{v0.1.17 Phase 1 (multi-area): which NiOverride overlay pool this pack
 paints into ("Body" | "Face" | "Hand" | "Feet"). Default "Body" for
 legacy packs that pre-date the .area JSON field.}
    LoadVisualCatalogs()
    if i < 0 || i >= visualPackCount
        return "Body"
    endif
    string a = visualPackAreas[i]
    if a == ""
        return "Body"
    endif
    return a
EndFunction

string Function GetPackArea(string packId)
{Convenience: look up area by packId. Returns "Body" for unknown / empty.
 Hot enough (called from _computePresetReservedLayers and _playerBaseLayers
 over slots 0..7) to bother with a tight loop instead of FindVisualPackIndex
 → GetVisualPackAreaAt double-bounce.}
    if packId == ""
        return "Body"
    endif
    LoadVisualCatalogs()
    int i = 0
    while i < visualPackCount
        if visualPackIds[i] == packId
            string a = visualPackAreas[i]
            if a == ""
                return "Body"
            endif
            return a
        endif
        i += 1
    endwhile
    return "Body"
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

; v0.1.20: optional per-entry human-readable description for LLM/AI
; integrations (SkyrimNet). Pack JSONs MAY include a "description" string
; on each entry; absent or empty falls back to "" so callers can use the
; entry label instead. Decorators that surface tattoos to language models
; should prefer this over the label when present.
string Function GetEntryDescription(string packId, string entryId)
    string f = _packFileById(packId)
    int idx = _findEntryIdx(packId, entryId)
    if f == "" || idx < 0
        return ""
    endif
    return JsonUtil.GetPathStringValue(f, ".entries[" + idx + "].description", "")
EndFunction

; v0.1.20: optional pack-level description (e.g. "A set of fertility runes
; from the Reach"). Same fallback: empty string when missing.
string Function GetPackDescription(string packId)
    string f = _packFileById(packId)
    if f == ""
        return ""
    endif
    return JsonUtil.GetPathStringValue(f, ".description", "")
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

; ── Per-slot second condition parameter (StorageUtil-backed) ─────────────────
; Optional 2nd knob for conditions that need two values (e.g. time.range
; from/till). StorageUtil-backed to dodge the Auto-property attachment trap.
int Function GetCondParam2(int slot)
    if slot < 0 || slot >= 8
        return 0
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.param2." + slot, 0)
EndFunction

Function SetCondParam2(int slot, int val)
    if slot < 0 || slot >= 8
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.param2." + slot, val)
EndFunction

; ── Evaluation-time scratch for current slot's param2 ────────────────────────
; evaluateTier sets this just before calling plugin.checkCondition so that
; the plugin (which gets only `param` via the call) can read param2 via
; _host().GetEvalParam2(). Scoped per-evaluation; not persistent.
Function _setEvalParam2(int val)
    StorageUtil.SetIntValue(self, "mtf.evalParam2", val)
EndFunction

int Function GetEvalParam2()
    return StorageUtil.GetIntValue(self, "mtf.evalParam2", 0)
EndFunction

float Function GetCondPulseRate(int slot)
    if slot < 0 || slot >= 8
        return 0.0
    endif
    return StorageUtil.GetFloatValue(self, "mtf.cond.pulse.rate." + slot, 0.0)
EndFunction

Function SetCondPulseRate(int slot, float v)
    if slot < 0 || slot >= 8
        return
    endif
    StorageUtil.SetFloatValue(self, "mtf.cond.pulse.rate." + slot, v)
EndFunction

int Function GetCondPulseDepth(int slot)
    if slot < 0 || slot >= 8
        return 0
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.pulse.depth." + slot, 0)
EndFunction

Function SetCondPulseDepth(int slot, int v)
    if slot < 0 || slot >= 8
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.pulse.depth." + slot, v)
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

string Function GetCondWaveform(int slot)
    if slot < 0 || slot >= 8
        return ""
    endif
    return StorageUtil.GetStringValue(self, "mtf.cond.pulse.waveform." + slot, "")
EndFunction

Function SetCondWaveform(int slot, string name)
    if slot < 0 || slot >= 8
        return
    endif
    if name == ""
        StorageUtil.UnsetStringValue(self, "mtf.cond.pulse.waveform." + slot)
    else
        StorageUtil.SetStringValue(self, "mtf.cond.pulse.waveform." + slot, name)
    endif
EndFunction

; ── Per-effect extras storage (v0.1.3) ──────────────────────────────────────
; Effects that need more than the two stock (param/param2) knobs declare extra
; fields via the MTF_Plugin GetEffectExtraFieldCount/Name/Label/Min/Max/Step
; /Default getters. Values live as floats keyed by (condSlot, effectIdx,
; fieldName) on this quest — round-tripped through preset JSON under
; slot[s].effect[e].extras.
;
; All keys are lowercase ASCII (JsonUtil lowercases on write — mixed case
; would round-trip blank).

float Function GetSlotEffectExtra(int slot, int effectIdx, string fieldName)
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return 0.0
    endif
    string k
    if _getDispatchUseScratch()
        ; NPC / stacked-preset dispatch — read from scratch keys populated
        ; by _loadPresetToScratch. The player's persistent slot extras live
        ; on different effect[][] indices and don't apply here.
        ; v0.2: namespaced by the currently-loaded scratch preset so the
        ; Plan B v2 cache keeps each preset's extras separate.
        k = "mtf.scratch.fx." + _scratchLoadedFor + "." + slot + "." + effectIdx + ".ex." + fieldName
    else
        k = "mtf.fx." + slot + "." + effectIdx + ".ex." + fieldName
    endif
    return StorageUtil.GetFloatValue(self, k, 0.0)
EndFunction

Function SetSlotEffectExtra(int slot, int effectIdx, string fieldName, float value)
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    string k = "mtf.fx." + slot + "." + effectIdx + ".ex." + fieldName
    StorageUtil.SetFloatValue(self, k, value)
EndFunction

Function _populateEffectExtrasDefaults(int slot, int effectIdx, string key)
{Called when the bound effect on (slot, effectIdx) changes. Asks the new
 plugin for declared extra fields, stamps each one's default into storage.
 Wipes are handled by _clearEffectExtras (called before this with the OLD
 key). Empty key (effect unbound) is a no-op — caller should still wipe
 the old extras.}
    if key == ""
        return
    endif
    MTF_Plugin p = ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = _effectIdxFor(p, _keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetEffectExtraFieldCount(itemIdx)
    int i = 0
    while i < n
        string fieldName = p.GetEffectExtraFieldName(itemIdx, i)
        if fieldName != ""
            float defVal = p.GetEffectExtraFieldDefault(itemIdx, i) as float
            SetSlotEffectExtra(slot, effectIdx, fieldName, defVal)
        endif
        i += 1
    endwhile
EndFunction

Function _clearEffectExtras(int slot, int effectIdx)
{Wipe any extras stored for (slot, effectIdx). Called before binding a new
 effect or when the effect is unbound. We don't know the previous plugin's
 field list (the old key may already be gone), so we sweep via key prefix.}
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    string prefix = "mtf.fx." + slot + "." + effectIdx + ".ex."
    ; StorageUtil doesn't expose a prefix-wipe; iterate known keys via the
    ; live plugin if we can resolve it, otherwise leave stale floats (they
    ; cost ~24 bytes each in the cosave and won't be read by anyone — the
    ; new key's extras live under a different fieldName set).
    string oldKey = GetSlotEffectKey(slot, effectIdx)
    if oldKey != ""
        MTF_Plugin p = ResolvePluginByKey(oldKey)
        if p != None
            int itemIdx = _effectIdxFor(p, _keyItemId(oldKey))
            if itemIdx >= 0
                int n = p.GetEffectExtraFieldCount(itemIdx)
                int i = 0
                while i < n
                    string fieldName = p.GetEffectExtraFieldName(itemIdx, i)
                    if fieldName != ""
                        StorageUtil.UnsetFloatValue(self, prefix + fieldName)
                    endif
                    i += 1
                endwhile
            endif
        endif
    endif
EndFunction

; ── Effect dispatch context (v0.1.3) ────────────────────────────────────────
; Set by the effect-iteration loops in _activateSlotEffects /
; _deactivateSlotEffects / _dispatchTickEffects right before each
; plugin.onActivate/.onDeactivate/.onTick call, so the plugin can read back
; which (slot, effectIdx) it is currently servicing — needed for any plugin
; that uses extras storage.
;
; Backed by StorageUtil ints (not Auto properties) — the v0.0.32+ "Auto
; property attach trap" makes adding new Auto-Hidden vars to a long-lived
; script unsafe.

int Function _getDispatchSlot()
    return StorageUtil.GetIntValue(self, "mtf.dispatch.slot", -1)
EndFunction

int Function _getDispatchEffectIdx()
    return StorageUtil.GetIntValue(self, "mtf.dispatch.effectidx", -1)
EndFunction

Function _setDispatchContext(int slot, int effectIdx)
    StorageUtil.SetIntValue(self, "mtf.dispatch.slot", slot)
    StorageUtil.SetIntValue(self, "mtf.dispatch.effectidx", effectIdx)
EndFunction

Function _clearDispatchContext()
    StorageUtil.SetIntValue(self, "mtf.dispatch.slot", -1)
    StorageUtil.SetIntValue(self, "mtf.dispatch.effectidx", -1)
    StorageUtil.SetIntValue(self, "mtf.dispatch.baseslot", -1)
EndFunction

; The actor's actual base overlay slot for whichever preset is firing. For
; the player, this is currently h.OverlaySlot (the MCM-managed slot). For
; NPCs (and stacked player presets), it's the per-preset
; _getActorPresetBase(target, presetName, "Body") value.
;
; Set by the per-actor activation paths right before each onActivate so
; plugins (specifically _applyFlashOnHit) can push C++ flash params to
; the same roster entry the overlay actually lives on. Without this the
; flash params land at h.OverlaySlot for everyone — fine for the player,
; wrong for NPCs whose preset base is dynamically chosen by
; _findFirstFreeOverlaySlotNPC.
Function _setDispatchBaseSlot(int baseSlot)
    StorageUtil.SetIntValue(self, "mtf.dispatch.baseslot", baseSlot)
EndFunction

int Function _getDispatchBaseSlot()
{Returns the preset's actual base overlay slot for the currently-firing
 effect, or h.OverlaySlot as a safe fallback when not set (covers older
 call sites that haven't been updated yet).}
    int v = StorageUtil.GetIntValue(self, "mtf.dispatch.baseslot", -1)
    if v < 0
        return OverlaySlot
    endif
    return v
EndFunction

; v0.1.17 Phase 3 (multi-area): companion to _setDispatchBaseSlot — stores
; the area integer (0=Body, 1=Face, 2=Hand, 3=Feet) for the currently-firing
; preset. Effects that push C++ roster params (flash.onhit, ondeath.fade)
; read this so they target the same roster entry _drawPresetOnActor wrote.
Function _setDispatchArea(int areaIdx)
    StorageUtil.SetIntValue(self, "mtf.dispatch.area", areaIdx)
EndFunction

int Function _getDispatchArea()
{Returns 0..3; defaults to 0 (Body) when unset. Mirrors _getDispatchBaseSlot's
 fallback so the player single-preset legacy path lands on the body roster
 entry without needing per-call setup.}
    return StorageUtil.GetIntValue(self, "mtf.dispatch.area", 0)
EndFunction

; Scratch dispatch flag — when 1, GetSlotEffectExtra reads from the
; "mtf.scratch.fx.*" key family (populated by _loadPresetToScratch) instead
; of the player's "mtf.fx.*" persistent storage. Set by the ForActor
; dispatch wrappers; the player single-preset path leaves it 0.
Function _setDispatchUseScratch(bool useScratch)
    int v = 0
    if useScratch
        v = 1
    endif
    StorageUtil.SetIntValue(self, "mtf.dispatch.usescratch", v)
EndFunction

bool Function _getDispatchUseScratch()
    return StorageUtil.GetIntValue(self, "mtf.dispatch.usescratch", 0) != 0
EndFunction

Function _loadScratchExtra(string f, string ep, int slot, int effectIdx, string xname)
{Helper for _loadPresetToScratch — reads one known extra from the preset
 JSON and stores it at the scratch StorageUtil key. Zero is fine for
 missing extras (the consumer applies its own fallback default).
 v0.2: namespaced by current scratch preset so the StorageUtil cache
 (Plan B v2) keeps each preset's extras under its own slot.}
    float xval = JsonUtil.GetPathFloatValue(f, ep + ".extras." + xname, 0.0)
    StorageUtil.SetFloatValue(self, "mtf.scratch.fx." + _scratchLoadedFor + "." + slot + "." + effectIdx + ".ex." + xname, xval)
EndFunction

int Function WAVE_LUT_SIZE() global
{Resolution of one pulse cycle. Picked so a 1Hz cycle samples at ~64 Hz —
 well above visual flicker frequency, well below per-frame jitter. C++
 plugin uses the same constant; keep them in sync.}
    return 64
EndFunction

string Function _waveformFile(string name)
    return "MagicTattoosFramework/waveforms/" + name
EndFunction

Float[] Function _builtinCosLUT()
    int N = WAVE_LUT_SIZE()
    Float[] lut = Utility.CreateFloatArray(N, 0.0)
    int i = 0
    while i < N
        float phase = (i as float) / (N as float)
        lut[i] = 0.5 - 0.5 * Math.Cos(phase * 360.0)
        i += 1
    endwhile
    return lut
EndFunction

Float[] Function _buildWaveformLUT(string name)
{Build a 64-entry [0,1]→[0,1] pulse curve sampled across one cycle. Falls
 back to cosine when name is empty, the JSON is missing, or the kind is
 unrecognised. Supported kinds: cos, triangle, square (shape=duty),
 sawtooth, keyframes (.points[].t/.v, lerped, up to 16 points).}
    int N = WAVE_LUT_SIZE()
    if name == ""
        return _builtinCosLUT()
    endif
    string file = _waveformFile(name)
    if !JsonUtil.JsonExists(file)
        return _builtinCosLUT()
    endif
    string kind = JsonUtil.GetPathStringValue(file, ".kind", "cos")
    float shape = JsonUtil.GetPathFloatValue(file, ".shape", 0.5)
    Float[] lut = Utility.CreateFloatArray(N, 0.0)
    int i = 0
    if kind == "cos" || kind == ""
        while i < N
            float phase = (i as float) / (N as float)
            lut[i] = 0.5 - 0.5 * Math.Cos(phase * 360.0)
            i += 1
        endwhile
    elseif kind == "triangle"
        while i < N
            float phase = (i as float) / (N as float)
            float v
            if phase < 0.5
                v = phase * 2.0
            else
                v = 2.0 - phase * 2.0
            endif
            lut[i] = v
            i += 1
        endwhile
    elseif kind == "square"
        float duty = shape
        if duty <= 0.0 || duty >= 1.0
            duty = 0.5
        endif
        while i < N
            float phase = (i as float) / (N as float)
            if phase < duty
                lut[i] = 1.0
            else
                lut[i] = 0.0
            endif
            i += 1
        endwhile
    elseif kind == "sawtooth"
        while i < N
            lut[i] = (i as float) / (N as float)
            i += 1
        endwhile
    elseif kind == "keyframes"
        Float[] tArr = Utility.CreateFloatArray(16, -1.0)
        Float[] vArr = Utility.CreateFloatArray(16, 0.0)
        int np = 0
        int k = 0
        bool done = false
        while k < 16 && !done
            string pp = ".points[" + k + "]"
            float tk = JsonUtil.GetPathFloatValue(file, pp + ".t", -1.0)
            if tk < 0.0
                done = true
            else
                tArr[np] = tk
                vArr[np] = JsonUtil.GetPathFloatValue(file, pp + ".v", 0.0)
                np += 1
                k += 1
            endif
        endwhile
        if np < 2
            return _builtinCosLUT()
        endif
        while i < N
            float phase = (i as float) / (N as float)
            int seg = 0
            while seg < np - 1 && tArr[seg + 1] < phase
                seg += 1
            endwhile
            if seg >= np - 1
                lut[i] = vArr[np - 1]
            else
                float t0 = tArr[seg]
                float t1 = tArr[seg + 1]
                float v0 = vArr[seg]
                float v1 = vArr[seg + 1]
                if t1 <= t0
                    lut[i] = v0
                else
                    float a = (phase - t0) / (t1 - t0)
                    lut[i] = v0 + (v1 - v0) * a
                endif
            endif
            i += 1
        endwhile
    else
        return _builtinCosLUT()
    endif
    return lut
EndFunction

Float[] Function _waveformLUTForTier(int tier, bool useScratch)
{Resolve waveform name for a tier and return its LUT.}
    string name = ""
    if useScratch
        if _sCondWaveform != None && tier >= 0 && tier < 8
            name = _sCondWaveform[tier]
        endif
    else
        name = GetCondWaveform(tier)
    endif
    return _buildWaveformLUT(name)
EndFunction

bool Function _slotHasPulse(int slot)
    if slot < 0 || slot >= 8
        return false
    endif
    return GetCondPulseRate(slot) > 0.0 && GetCondPulseDepth(slot) > 0
EndFunction

bool Function _slotHasFlashEffect(int slot)
{Returns true if any of the slot's 4 effect rows is bound to the
 mtf.base:flash.onhit effect. Used by _resyncPulseCache to register a
 (rate=0) roster entry for flash-only tiers — the C++ Tick needs a live
 entry to run the additive flash lane on top of the (no-pulse) ceiling.}
    if slot < 0 || slot >= 8
        return false
    endif
    int e = 0
    while e < MAX_EFFECTS_PER_SLOT()
        if GetSlotEffectKey(slot, e) == "mtf.base:flash.onhit"
            return true
        endif
        e += 1
    endwhile
    return false
EndFunction

Function _resyncPulseCache(int tier)
{Snapshot per-tier overlay context for the fast pulse tick. Triggers a
 roster entry when the tier has pulse, a flash.onhit effect, OR the
 preset-wide fade-on-death toggle is on. Fade params themselves live in
 _sFadeOnDeath... and are read directly at the arming sites.}
    _pulseTier = -1
    if tier < 0 || tier >= 8 || PlayerRef == None
        return
    endif
    if !_slotHasPulse(tier) && !_slotHasFlashEffect(tier) && !_sFadeOnDeathEnabled
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
    if DebugMode && _sFadeOnDeathEnabled
        Debug.Notification("[MTF fade] cache armed tier=" + tier + " mode=" + _sFadeOnDeathMode + " dur=" + _sFadeOnDeathDurationMs + "ms")
    endif
EndFunction

Function _applyPulse()
{Hot path. Forwards the player's pulse parameters into the MTFPulse C++
 roster. C++ does the per-frame wave math + NiOverride writes at full
 frame rate via the PlayerCharacter::Update vtable hook in MTFPulse.dll.

 This function still runs at the OnUpdate fast tick (~10 Hz) so MCM
 slider edits to rate / depth / pause / per-layer emissive multiplier
 propagate to the roster within 100 ms.

 Flash-only tiers (no pulse, just a bound flash.onhit effect) also pass
 through here: _resyncPulseCache registers them with rate=0 / depth=0 so
 a roster entry exists for the flash.onhit effect's onActivate to write
 SetActorFlash into. C++ Tick treats wave=0 → pulsed=1 → ceiling passes
 through; flash_add adds on top.

 v0.1.4 dead-actor gate: once the player actually dies, the C++ fade
 lane plays out and self-evicts via Tick's deferred-removal. Without
 this gate, the very next 10 Hz cycle would call SetActorPulse again
 and re-create the entry — fade_armed re-set by SetActorFade, normal
 pulse processing writing emissive but not alpha, leaving the alpha=0
 from the final fade frame stuck in NiOverride. Stopping recreation
 lets the corpse keep its faded visual cleanly. Bleedout for essential
 / protected actors doesn't reach IsDead()=true so this gate doesn't
 fire for recoverable knockdowns.

 If the MTFPulse plugin isn't loaded, the natives log a Papyrus warning
 once and the visual is just "no pulse" — graceful degradation.}
    if PlayerRef != None && PlayerRef.IsDead()
        ; v0.1.17 Phase 3 (multi-area): player MCM-base pulse cache is
        ; body-only — pass area=0 (kAreaBody).
        MTFPulse.ClearActorAt(PlayerRef, OverlaySlot, 0)
        _pulseTier = -1
        return
    endif
    if _pulseTier < 0 || _pulseLayerN <= 0 || PlayerRef == None
        ; Drop just the base-layer pulse entry. Stacked presets sit at
        ; their own base_slots and must keep pulsing — only kill ours
        ; (the MCM-driven OverlaySlot one).
        MTFPulse.ClearActorAt(PlayerRef, OverlaySlot, 0)
        return
    endif

    int depthPct = GetCondPulseDepth(_pulseTier)
    float rate   = GetCondPulseRate(_pulseTier)
    float pause  = GetCondPulsePause(_pulseTier)

    ; Snapshot live per-layer emissive ceilings (length == _pulseLayerN).
    ; MCM slider changes to condLayerEmissiveMult[] become visible on the
    ; next call to SetActorPulse — i.e. within this 10 Hz window.
    Float[] emMults = Utility.CreateFloatArray(_pulseLayerN)
    int i = 0
    while i < _pulseLayerN
        int lidx = _pulseTier * 4 + i
        emMults[i] = condLayerEmissiveMult[lidx]
        i += 1
    endwhile

    Float[] lut = _waveformLUTForTier(_pulseTier, false)
    ; v0.1.17 Phase 3 (multi-area): player MCM-base pulse is body-only —
    ; pass area=0 (kAreaBody). Face/Hand/Feet MCM-base packs apply
    ; statically (no pulse on the MCM-driven base path; stacked-preset
    ; pulse goes through _rosterAddOrUpdate which is multi-area aware).
    MTFPulse.SetActorPulse(PlayerRef, rate, depthPct, pause, \
                           _pulseLayerN, _pulseStartRT, emMults, \
                           OverlaySlot, _pulseIsFemale, lut, 0)

    ; v0.1.4 per-preset fade: re-arm or clear after the roster entry is
    ; up. Idempotent on the C++ side — re-issuing the same params each
    ; tick is a no-op for an already-armed entry; an in-flight fade
    ; (fade_active=true) isn't disturbed by SetActorFade either.
    if _sFadeOnDeathEnabled
        MTFPulse.SetActorFade(PlayerRef, OverlaySlot, _sFadeOnDeathMode, _sFadeOnDeathDurationMs, 0)
    else
        MTFPulse.ClearActorFade(PlayerRef, OverlaySlot, 0)
    endif
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

; Flash dispatch (v0.1.3). Called from MTF_HitListener.OnHit alongside
; IncHitCount. Stamps the flash trigger time on the player's base-layer
; roster entry. C++ side filters by class mask + retrigger logic.
;
; classIdx is the 7-class enum from HitListener._classify:
;   0 ANY (unclassified), 1 BLUNT, 2 BLADED, 3 RANGED,
;   4 FIRE, 5 FROST, 6 SHOCK
; The C++ mask treats bit 0 as a wildcard — masks containing ANY fire
; on every hit regardless of class.
;
; Currently player-only — OnHit is registered on the player
; ReferenceAlias. NPC flash would require additional alias listeners
; (deferred).
Function DispatchFlashHit(string tag)
{Public extension hook. External mods (or built-in HitListener) call this
 with a short tag identifying the event ("blunt", "fire",
 "sla.aroused.over80", etc.). Any active flash.onhit effect whose tagsCsv
 contains the tag — or the "*" wildcard — flashes. Cheap; fire as often
 as you like (the C++ side throttles via the retrigger window).}
    if PlayerRef == None || tag == ""
        return
    endif
    ; v0.1.17 Phase 3 (multi-area): player MCM-base flash is body-only.
    MTFPulse.TriggerActorFlash(PlayerRef, OverlaySlot, tag, 0)
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
    JsonUtil.SetPathIntValue(f,    ".schemaversion", 7)

    ; Preset-wide cross-fade duration (live value, edited via MCM slider).
    ; Always emit so the saved JSON reflects exactly what's in the scratch
    ; buffer — including zero, which legitimately disables fading.
    JsonUtil.SetPathFloatValue(f, ".transition.duration", _sTransitionDuration)

    ; Preset-wide fade-on-death config (v0.1.4). Always persist all three
    ; keys so legacy presets that lack the block get cleanly upgraded on
    ; first re-save and downstream JsonUtil reads see consistent shape.
    JsonUtil.SetPathIntValue(f, ".fadeondeath.enabled",    _sFadeOnDeathEnabled as int)
    JsonUtil.SetPathIntValue(f, ".fadeondeath.mode",       _sFadeOnDeathMode)
    JsonUtil.SetPathIntValue(f, ".fadeondeath.durationms", _sFadeOnDeathDurationMs)
    if DebugMode && _sFadeOnDeathEnabled
        Debug.Notification("[MTF fade] saved preset fade enabled=1 mode=" + _sFadeOnDeathMode + " dur=" + _sFadeOnDeathDurationMs + "ms")
    endif

    EnsureArrays()
    int maxL = MAX_LAYERS_PER_SLOT()
    int maxE = MAX_EFFECTS_PER_SLOT()
    int s = 0
    while s < 8
        string sp = ".slot[" + s + "]"
        JsonUtil.SetPathStringValue(f, sp + ".cond.pluginid", condPluginId[s])
        JsonUtil.SetPathIntValue(f,    sp + ".cond.param",    condParam[s])
        int p2 = GetCondParam2(s)
        if p2 != 0
            JsonUtil.SetPathIntValue(f, sp + ".cond.param2", p2)
        endif
        JsonUtil.SetPathStringValue(f, sp + ".cond.packid",   condPackId[s])
        JsonUtil.SetPathStringValue(f, sp + ".cond.entryid",  condEntryId[s])
        JsonUtil.SetPathIntValue(f,    sp + ".cooldown.min",  cooldownMin[s])
        JsonUtil.SetPathIntValue(f,    sp + ".cooldown.mode", cooldownMode[s])
        ; Skip pulse rows when disabled — keeps the file readable.
        float rateS  = GetCondPulseRate(s)
        int   depthS = GetCondPulseDepth(s)
        float pausePersist = GetCondPulsePause(s)
        string waveName = GetCondWaveform(s)
        if rateS > 0.0 || depthS > 0 || pausePersist > 0.0 || waveName != ""
            JsonUtil.SetPathFloatValue(f, sp + ".pulse.rate",  rateS)
            JsonUtil.SetPathIntValue(f,   sp + ".pulse.depth", depthS)
            if pausePersist > 0.0
                JsonUtil.SetPathFloatValue(f, sp + ".pulse.pause", pausePersist)
            endif
            if waveName != ""
                JsonUtil.SetPathStringValue(f, sp + ".pulse.waveform", waveName)
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
            ; Skip serializing effect rows with empty key — load uses defaults.
            string fxKey = _readFxKey(s, e, false)
            if fxKey != ""
                string ep = sp + ".effect[" + e + "]"
                JsonUtil.SetPathStringValue(f, ep + ".key",    fxKey)
                JsonUtil.SetPathIntValue(f,    ep + ".param",  _readFxParam(s, e, false))
                JsonUtil.SetPathIntValue(f,    ep + ".param2", _readFxParam2(s, e, false))
                ; v0.1.3 extras — per-effect named float fields (ramp/decay/etc.)
                ; Walk the bound plugin's declared extra field names and emit
                ; each one. JsonUtil lowercases keys; our spec already uses
                ; lowercase ASCII names so round-trip is faithful.
                MTF_Plugin pSerExt = ResolvePluginByKey(fxKey)
                if pSerExt != None
                    int itemIdxSerExt = _effectIdxFor(pSerExt, _keyItemId(fxKey))
                    if itemIdxSerExt >= 0
                        int xN = pSerExt.GetEffectExtraFieldCount(itemIdxSerExt)
                        int xi = 0
                        while xi < xN
                            string xname = pSerExt.GetEffectExtraFieldName(itemIdxSerExt, xi)
                            if xname != ""
                                JsonUtil.SetPathFloatValue(f, ep + ".extras." + xname, \
                                    GetSlotEffectExtra(s, e, xname))
                            endif
                            xi += 1
                        endwhile
                    endif
                endif
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
    ; Drop the cached scratch (Plan B v2) so the next _loadPresetToScratch
    ; for this preset goes through the cold path and picks up the freshly-
    ; saved JSON. Otherwise edits via MCM wouldn't propagate to the
    ; stacked-preset render path until session restart.
    _invalidateScratchCache(name)
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

    ; Tear down whatever is currently active BEFORE we overwrite the slot
    ; storage. _deactivateSlotEffects reads the StorageUtil mtf.fx.* keys —
    ; if we let LoadPreset clobber those first, it removes the wrong
    ; effects (or none) and the old buffs linger forever. Also force
    ; currentTier = -1 so the next OnUpdate sees a real tier change even
    ; when the new preset evaluates to the same integer tier index as the
    ; old one.
    if currentTier >= 0
        _deactivateSlotEffects(currentTier)
    endif
    removeOverlay(PlayerRef)
    currentTier = -1

    ; Pull the preset-wide transition duration into the live scratch slot so
    ; the MCM Transition Duration slider reflects whatever was saved. Default
    ; 1.0s when the key is absent (legacy presets pre-v0.1.1).
    _sTransitionDuration = JsonUtil.GetPathFloatValue(f, ".transition.duration", 1.0)

    ; Preset-wide fade-on-death (v0.1.4). Defaults to disabled when block
    ; is absent — legacy presets keep their existing behavior.
    _sFadeOnDeathEnabled    = JsonUtil.GetPathIntValue(f, ".fadeondeath.enabled", 0) > 0
    _sFadeOnDeathMode       = JsonUtil.GetPathIntValue(f, ".fadeondeath.mode", 0)
    if _sFadeOnDeathMode < 0 || _sFadeOnDeathMode > 2
        _sFadeOnDeathMode = 0
    endif
    _sFadeOnDeathDurationMs = JsonUtil.GetPathIntValue(f, ".fadeondeath.durationms", 2000)
    if _sFadeOnDeathDurationMs < 1
        _sFadeOnDeathDurationMs = 2000
    endif
    if DebugMode && _sFadeOnDeathEnabled
        Debug.Notification("[MTF fade] loaded preset fade enabled=1 mode=" + _sFadeOnDeathMode + " dur=" + _sFadeOnDeathDurationMs + "ms")
    endif

    int maxL = MAX_LAYERS_PER_SLOT()
    int maxE = MAX_EFFECTS_PER_SLOT()

    ; All indexed writes happen on local copies — direct `prop[i] = v` on Auto
    ; array properties silently no-ops (writes hit a transient copy). At the
    ; end of the function we write the whole locals back through the property
    ; setters. The SetCond* helpers already do this correctly for the per-slot
    ; scalars, but the multi-index arrays (layer/effect/packId/etc.) need the
    ; same workaround applied explicitly here.
    string[] aPackId   = condPackId
    string[] aEntryId  = condEntryId
    int[]    aCdMin    = cooldownMin
    int[]    aCdMode   = cooldownMode
    int[]    aLTint    = condLayerTint
    int[]    aLEmiss   = condLayerEmissive
    float[]  aLEmult   = condLayerEmissiveMult
    int[]    aLAlpha   = condLayerAlpha

    int s = 0
    while s < 8
        string sp = ".slot[" + s + "]"
        SetCondPluginId(s, JsonUtil.GetPathStringValue(f, sp + ".cond.pluginid", ""))
        SetCondParam(s,    JsonUtil.GetPathIntValue(f,    sp + ".cond.param",    0))
        SetCondParam2(s,   JsonUtil.GetPathIntValue(f,    sp + ".cond.param2",   0))
        aPackId[s]   = JsonUtil.GetPathStringValue(f, sp + ".cond.packid",  "")
        aEntryId[s]  = JsonUtil.GetPathStringValue(f, sp + ".cond.entryid", "")
        aCdMin[s]    = JsonUtil.GetPathIntValue(f,    sp + ".cooldown.min",  0)
        aCdMode[s]   = JsonUtil.GetPathIntValue(f,    sp + ".cooldown.mode", 0)
        SetCondPulseRate(s, JsonUtil.GetPathFloatValue(f, sp + ".pulse.rate",  0.0))
        SetCondPulseDepth(s, JsonUtil.GetPathIntValue(f,   sp + ".pulse.depth", 0))
        SetCondPulsePause(s, JsonUtil.GetPathFloatValue(f, sp + ".pulse.pause", 0.0))
        SetCondWaveform(s, JsonUtil.GetPathStringValue(f, sp + ".pulse.waveform", ""))
        int L = 0
        while L < maxL
            int li = _layerIdx(s, L)
            string lp = sp + ".layer[" + L + "]"
            aLTint[li]   = _readColor(f, lp + ".tint",         16777215)
            aLEmiss[li]  = _readColor(f, lp + ".emissive",     16777215)
            aLEmult[li]  = JsonUtil.GetPathFloatValue(f, lp + ".emissivemult", 0.0)
            aLAlpha[li]  = JsonUtil.GetPathIntValue(f,   lp + ".alpha",        100)
            L += 1
        endwhile
        int e = 0
        while e < maxE
            string ep = sp + ".effect[" + e + "]"
            ; Wipe the OLD effect's extras BEFORE overwriting the key — the
            ; helper needs the live key string in StorageUtil to look up
            ; declared extra field names. _writeFxKey below clobbers it.
            _clearEffectExtras(s, e)
            string newKey = JsonUtil.GetPathStringValue(f, ep + ".key",    "")
            _writeFxKey(s, e, false, newKey)
            _writeFxParam(s, e, false, JsonUtil.GetPathIntValue(f,    ep + ".param",  0))
            _writeFxParam2(s, e, false, JsonUtil.GetPathIntValue(f,    ep + ".param2", 0))
            ; v0.1.3 extras restore — read each declared extra field from
            ; JSON, falling back to the plugin's declared default when the
            ; preset omits the key. Stamps directly into StorageUtil (the
            ; per-slot/effectIdx float keyspace) — not part of the array
            ; round-trip above.
            if newKey != ""
                MTF_Plugin pLoadExt = ResolvePluginByKey(newKey)
                if pLoadExt != None
                    int itemIdxLoadExt = _effectIdxFor(pLoadExt, _keyItemId(newKey))
                    if itemIdxLoadExt >= 0
                        int xN = pLoadExt.GetEffectExtraFieldCount(itemIdxLoadExt)
                        int xi = 0
                        while xi < xN
                            string xname = pLoadExt.GetEffectExtraFieldName(itemIdxLoadExt, xi)
                            if xname != ""
                                float defVal = pLoadExt.GetEffectExtraFieldDefault(itemIdxLoadExt, xi) as float
                                SetSlotEffectExtra(s, e, xname, \
                                    JsonUtil.GetPathFloatValue(f, ep + ".extras." + xname, defVal))
                            endif
                            xi += 1
                        endwhile
                    endif
                endif
            endif
            e += 1
        endwhile
        s += 1
    endwhile

    ; Write the whole arrays back through the property setters so the
    ; per-index mutations actually persist. (Effect arrays moved to
    ; StorageUtil in v0.1.5 and are written directly above, no bulk
    ; assign needed for fx.)
    condPackId            = aPackId
    condEntryId           = aEntryId
    cooldownMin           = aCdMin
    cooldownMode          = aCdMode
    condLayerTint         = aLTint
    condLayerEmissive     = aLEmiss
    condLayerEmissiveMult = aLEmult
    condLayerAlpha        = aLAlpha

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

; Reset all PRESET CONTENT (slot definitions, layers, effects, cooldowns,
; transition) to a clean-canvas state. Engine state (ModActive, OverlaySlot,
; updateInterval, DebugMode) and plugin-wide settings are left alone — those
; are not preset-scoped. Used by MCM "New preset".
Function ResetEditor()
    EnsureArrays()
    if currentTier >= 0
        _deactivateSlotEffects(currentTier)
    endif
    removeOverlay(PlayerRef)
    currentTier = -1

    _sTransitionDuration = 1.0
    _sFadeOnDeathEnabled    = false
    _sFadeOnDeathMode       = 0
    _sFadeOnDeathDurationMs = 2000

    int maxL = MAX_LAYERS_PER_SLOT()
    int maxE = MAX_EFFECTS_PER_SLOT()

    ; Local copies — direct indexed writes to Auto array properties silently
    ; no-op (see LoadPreset for the same workaround).
    string[] aPackId   = condPackId
    string[] aEntryId  = condEntryId
    int[]    aCdMin    = cooldownMin
    int[]    aCdMode   = cooldownMode
    int[]    aLTint    = condLayerTint
    int[]    aLEmiss   = condLayerEmissive
    float[]  aLEmult   = condLayerEmissiveMult
    int[]    aLAlpha   = condLayerAlpha

    int s = 0
    while s < 8
        SetCondPluginId(s, "")
        SetCondParam(s, 0)
        SetCondParam2(s, 0)
        aPackId[s]   = ""
        aEntryId[s]  = ""
        aCdMin[s]    = 0
        aCdMode[s]   = 0
        SetCondPulseRate(s, 0.0)
        SetCondPulseDepth(s, 0)
        SetCondPulsePause(s, 0.0)
        SetCondWaveform(s, "")
        int L = 0
        while L < maxL
            int li = _layerIdx(s, L)
            aLTint[li]  = 16777215
            aLEmiss[li] = 16777215
            aLEmult[li] = 0.0
            aLAlpha[li] = 100
            L += 1
        endwhile
        int e = 0
        while e < maxE
            ; Wipe extras for the old binding before clearing the key
            ; (the helper needs the live key to look up field names).
            _clearEffectExtras(s, e)
            _writeFxKey(s, e, false, "")
            _writeFxParam(s, e, false, 0)
            _writeFxParam2(s, e, false, 0)
            e += 1
        endwhile
        s += 1
    endwhile

    condPackId            = aPackId
    condEntryId           = aEntryId
    cooldownMin           = aCdMin
    cooldownMode          = aCdMode
    condLayerTint         = aLTint
    condLayerEmissive     = aLEmiss
    condLayerEmissiveMult = aLEmult
    condLayerAlpha        = aLAlpha

    forceRedraw = true
EndFunction

bool Function DeletePreset(string name)
    string f = _presetFile(name)
    if !JsonUtil.JsonExists(f)
        return false
    endif
    JsonUtil.SetIntValue(f, "valid", 0)
    JsonUtil.Save(f)
    ; Drop any cached scratch buffer for this preset (Plan B v2) — even
    ; though the .valid flag will gate future cold loads, a stale cached
    ; copy would still hit the warm path until invalidated.
    _invalidateScratchCache(name)
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

string[] Function ListWaveforms()
{Enumerate JSONs in MagicTattoosFramework/waveforms/. Fixed-size 32 array;
 valid names first, empty strings after. The "" slot is the "use built-in
 cosine" sentinel and is always offered as the first option by MCM.}
    string[] raw = JsonUtil.JsonInFolder("MagicTattoosFramework/waveforms")
    string[] result = new string[32]
    if raw == None || raw.Length == 0
        return result
    endif
    int n = 0
    int i = 0
    while i < raw.Length && n < 32
        string nm = raw[i]
        int dot = StringUtil.Find(nm, ".json")
        if dot > 0
            nm = StringUtil.Substring(nm, 0, dot)
        endif
        result[n] = nm
        n += 1
        i += 1
    endwhile
    return result
EndFunction

int Function ListWaveformsCount()
    string[] r = ListWaveforms()
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

; v0.1.16: backend moved from the Auto Hidden `disabledItems[]` Property to
; StorageUtil StringList `mtf.disabled`. The old Property suffered the
; indexed-write transient-copy bug — `disabledItems[i] = key` silently
; no-op'd on this quest script, so every toggle reverted on MCM re-open.
; (See KB → Properties/Arrays → "Indexed cross-script writes" + MEMORY
; "Papyrus array indexed-writes hit transient copy".) StorageUtil natives
; bypass the Property attach + indexed-write traps entirely.
;
; The `disabledItems` Property is retained ONLY for the ml=38 migration
; (MCMQuest.OnVersionUpdate copies any surviving entries on first load).
; Do not read or write it from new code.

bool Function IsItemEnabled(string key)
    if key == ""
        return true
    endif
    return StorageUtil.StringListFind(self, "mtf.disabled", key) < 0
EndFunction

Function SetItemEnabled(string key, bool on)
    if key == ""
        return
    endif
    int idx = StorageUtil.StringListFind(self, "mtf.disabled", key)
    if on
        if idx >= 0
            ; Remove ALL instances in case the legacy migration ever
            ; double-added (it can't currently, but defensive).
            StorageUtil.StringListRemove(self, "mtf.disabled", key, true)
        endif
    else
        if idx < 0
            StorageUtil.StringListAdd(self, "mtf.disabled", key, false)
        endif
    endif
EndFunction

; ── Per-plugin enable/disable ───────────────────────────────────────────────
; Plugin-level toggle reuses the disabledItems[] storage with a "plugin:<pid>"
; key shape. Same persistence, same scratch wipe semantics — just a different
; key namespace. When a plugin is disabled, all of its conditions and effects
; are hidden from the slot dropdowns (regardless of per-item flags).

bool Function IsPluginEnabled(string pid)
    if pid == ""
        return true
    endif
    return IsItemEnabled("plugin:" + pid)
EndFunction

Function SetPluginEnabled(string pid, bool on)
    if pid == ""
        return
    endif
    SetItemEnabled("plugin:" + pid, on)
EndFunction

; ── Plugin registry ──────────────────────────────────────────────────────────
Function RegisterPlugin(MTF_Plugin p)
{Called by MTF_Plugin._tryRegister(). Idempotent.}
    if p == None || !_arraysReady
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
    if pid == "" || !_arraysReady
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

Function _stripDiagnostics()
EndFunction

Function BuildVisibleConditionMenu(string includeKey)
    ; Walk plugins ONCE and inline the global-idx → plugin/item resolution.
    ; The old version called GetGlobalConditionKey(i) and
    ; GetGlobalConditionLabel(i) per i — each of those re-walks plugins,
    ; turning the menu rebuild into O(N²) cross-script calls (60 effects ×
    ; 2 lookups × ~120 cross-script ops = ~14k calls = ~20s page load).
    ; Build into LOCAL arrays — indexed writes to Auto array properties
    ; silently no-op ([[project_papyrus_property_array_writes]]).
    string[] localKeys   = new string[64]
    string[] localLabels = new string[64]
    int n = 0
    int pi = 0
    while pi < pluginCount && n < 64
        MTF_Plugin p = GetPluginAt(pi)
        if p != None
            string pl = p.GetPluginLabel()
            string pid = p.GetPluginId()
            ; Plugin-level disable hides all this plugin's conditions from
            ; the selector unless the currently-bound key is one of them
            ; (so users can see what's wired in even while the plugin is off).
            bool pluginOn = IsPluginEnabled(pid)
            int cCount = p.GetConditionCount()
            int ei = 0
            while ei < cCount && n < 64
                string k = pid + ":" + p.GetConditionId(ei)
                bool keep = k == includeKey
                if !keep && pluginOn && IsItemEnabled(k)
                    keep = true
                endif
                if keep
                    localKeys[n] = k
                    string il = p.GetConditionLabel(ei)
                    if pl == ""
                        localLabels[n] = il
                    else
                        localLabels[n] = pl + " — " + il
                    endif
                    n += 1
                endif
                ei += 1
            endwhile
        endif
        pi += 1
    endwhile
    menuKeys   = localKeys
    menuLabels = localLabels
    menuCount  = n
EndFunction

Function BuildVisibleEffectMenu(string includeKey)
    ; See BuildVisibleConditionMenu — single plugin pass to avoid O(N²)
    ; cross-script calls.
    string[] localKeys   = new string[64]
    string[] localLabels = new string[64]
    int n = 0
    int pi = 0
    while pi < pluginCount && n < 64
        MTF_Plugin p = GetPluginAt(pi)
        if p != None
            string pl = p.GetPluginLabel()
            string pid = p.GetPluginId()
            bool pluginOn = IsPluginEnabled(pid)
            int eCount = p.GetEffectCount()
            int ei = 0
            while ei < eCount && n < 64
                string k = pid + ":" + p.GetEffectId(ei)
                bool keep = k == includeKey
                if !keep && pluginOn && IsItemEnabled(k)
                    keep = true
                endif
                if keep
                    localKeys[n] = k
                    string il = p.GetEffectLabel(ei)
                    if pl == ""
                        localLabels[n] = il
                    else
                        localLabels[n] = pl + " — " + il
                    endif
                    n += 1
                endif
                ei += 1
            endwhile
        endif
        pi += 1
    endwhile
    menuKeys   = localKeys
    menuLabels = localLabels
    menuCount  = n
EndFunction

; ── Visible (enabled-only) views, with currently-bound key kept visible ─────
;
; A composite "pluginId:itemId" key is visible iff:
;   (a) it matches the currently-bound key (always shown so users see what's
;       wired), OR
;   (b) its plugin is enabled AND the item itself is enabled.

bool Function _isKeyVisible(string k, string includeKey)
    if k == ""
        return false
    endif
    if k == includeKey
        return true
    endif
    int colon = StringUtil.Find(k, ":")
    if colon > 0
        string pid = StringUtil.Substring(k, 0, colon)
        if !IsPluginEnabled(pid)
            return false
        endif
    endif
    return IsItemEnabled(k)
EndFunction

int Function GetVisibleConditionCount(string includeKey)
    int total = GetTotalConditionItemCount()
    int n = 0
    int i = 0
    while i < total
        string k = GetGlobalConditionKey(i)
        if _isKeyVisible(k, includeKey)
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
        if _isKeyVisible(k, includeKey)
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
        if _isKeyVisible(k, includeKey)
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
        if _isKeyVisible(k, includeKey)
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

; ── StorageUtil-backed effect storage ───────────────────────────────────────
; Effect bindings (key/param/param2 per slot+idx) live in PapyrusUtil cosave
; rather than Auto array properties. Three reasons:
;  • Papyrus arrays cap at 128 elements; flat 8*N indexing topped out at N=16.
;    With StorageUtil we can raise MAX_EFFECTS_PER_SLOT freely.
;  • Auto array properties added post-release sometimes fail to attach to an
;    existing save instance (see [[project_papyrus_property_attach]]). Each
;    new array we add risks repeating the wipe we hit on 2026-05-19.
;  • Per-effect extras (mtf.fx.<s>.<e>.ex.*) already live in StorageUtil;
;    moving key/param/param2 alongside keeps the keyspace uniform.
; useScratch picks the prefix: `false` → player live (mtf.fx.), `true` →
; NPC scratch (mtf.fx.scratch.). _loadPresetToScratch overwrites every
; (slot, idx) on switch so stale scratch from a previous actor is naturally
; replaced; no explicit clear needed.

; Plan B v2: scratch FX keys gain a per-preset segment so the StorageUtil-
; backed scratch cache can hold each preset's bindings under its own
; namespace; cache hits don't have to replay FX writes between swaps.
; _scratchLoadedFor is the implicit "current preset" — set before any
; FX write in _loadPresetToScratch (cold load) and updated on cache hits.
; Player path (useScratch=false) keeps the legacy mtf.fx.<slot>.<idx>.*
; keyspace.

string Function _readFxKey(int slot, int idx, bool useScratch)
    if useScratch
        return StorageUtil.GetStringValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".key", "")
    endif
    return StorageUtil.GetStringValue(None, "mtf.fx." + slot + "." + idx + ".key", "")
EndFunction

int Function _readFxParam(int slot, int idx, bool useScratch)
    if useScratch
        return StorageUtil.GetIntValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".param", 0)
    endif
    return StorageUtil.GetIntValue(None, "mtf.fx." + slot + "." + idx + ".param", 0)
EndFunction

int Function _readFxParam2(int slot, int idx, bool useScratch)
    if useScratch
        return StorageUtil.GetIntValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".param2", 0)
    endif
    return StorageUtil.GetIntValue(None, "mtf.fx." + slot + "." + idx + ".param2", 0)
EndFunction

Function _writeFxKey(int slot, int idx, bool useScratch, string val)
    if useScratch
        StorageUtil.SetStringValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".key", val)
        return
    endif
    StorageUtil.SetStringValue(None, "mtf.fx." + slot + "." + idx + ".key", val)
EndFunction

Function _writeFxParam(int slot, int idx, bool useScratch, int val)
    if useScratch
        StorageUtil.SetIntValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".param", val)
        return
    endif
    StorageUtil.SetIntValue(None, "mtf.fx." + slot + "." + idx + ".param", val)
EndFunction

Function _writeFxParam2(int slot, int idx, bool useScratch, int val)
    if useScratch
        StorageUtil.SetIntValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".param2", val)
        return
    endif
    StorageUtil.SetIntValue(None, "mtf.fx." + slot + "." + idx + ".param2", val)
EndFunction

; ── Per-slot effect-list helpers ─────────────────────────────────────────────

string Function GetSlotEffectKey(int slot, int effectIdx)
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return ""
    endif
    return _readFxKey(slot, effectIdx, false)
EndFunction

int Function GetSlotEffectParam(int slot, int effectIdx)
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return 0
    endif
    return _readFxParam(slot, effectIdx, false)
EndFunction

int Function GetSlotEffectParam2(int slot, int effectIdx)
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return 0
    endif
    return _readFxParam2(slot, effectIdx, false)
EndFunction

Function SetSlotEffect(int slot, int effectIdx, string key, int param)
{Legacy 4-arg setter — preserves existing param2.}
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    bool live = (slot == currentTier)
    if live
        _deactivateSingleEffect(slot, effectIdx)
    endif
    _writeFxKey(slot, effectIdx, false, key)
    _writeFxParam(slot, effectIdx, false, param)
    if live && key != ""
        _activateSingleEffect(slot, effectIdx)
    endif
EndFunction

Function SetSlotEffectFull(int slot, int effectIdx, string key, int param, int param2)
{Sets all three at once. Used when picking a new effect type so the
 default param2 is applied alongside default param. Also wipes the old
 effect's extras and stamps the new effect's declared defaults.}
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    bool live = (slot == currentTier)
    if live
        _deactivateSingleEffect(slot, effectIdx)
    endif
    ; Wipe extras tied to the OLD key (StorageUtil still has the old binding
    ; for the duration of this call, so _clearEffectExtras can look up names).
    _clearEffectExtras(slot, effectIdx)
    _writeFxKey(slot, effectIdx, false, key)
    _writeFxParam(slot, effectIdx, false, param)
    _writeFxParam2(slot, effectIdx, false, param2)
    ; Populate extras defaults for the NEW key (no-op if key=="" or no extras).
    _populateEffectExtrasDefaults(slot, effectIdx, key)
    if live
        ; Re-prime the pulse roster state — flash.onhit needs a (rate=0)
        ; roster entry as the back-store for SetActorFlash, and conversely
        ; removing the last flash.onhit on a no-pulse tier should clear the
        ; orphan entry. _resyncPulseCache re-evaluates _pulseTier; _applyPulse
        ; pushes (or clears) the entry accordingly. Both directions are
        ; covered without special-casing the key.
        _resyncPulseCache(slot)
        _applyPulse()
        if key != ""
            _activateSingleEffect(slot, effectIdx)
        endif
    endif
EndFunction

Function CompactEffectsAfter(int slot, int fromIdx)
{Effect row [fromIdx] was just cleared via MCM. If any later row has data,
 shift effect[fromIdx+1..maxE-1] into [fromIdx..maxE-2] so the
 progressive-disclosure UI never leaves a configured-but-hidden row.

 Walks front-to-back. Each iteration reads from src = i+1 (untouched by
 prior iterations because we only ever wrote to indices ≤ i and i+1=src
 was still pristine), copies into dst = i via SetSlotEffectFull, then
 blanks src. Extras are snapshotted before the move and re-stamped onto
 dst — SetSlotEffectFull resets dst extras to the NEW key's defaults, so
 the snapshot overwrite is required to carry actual user-tuned values.

 Stops early at the first empty src — nothing beyond a gap to compact.}
    if slot < 0 || slot >= 8 || fromIdx < 0 || fromIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    int maxE = MAX_EFFECTS_PER_SLOT()
    int i = fromIdx
    while i < maxE - 1
        string srcKey = _readFxKey(slot, i + 1, false)
        if srcKey == ""
            return
        endif
        int srcParam = _readFxParam(slot, i + 1, false)
        int srcParam2 = _readFxParam2(slot, i + 1, false)
        ; Snapshot src extras before SetSlotEffectFull resets dst extras.
        MTF_Plugin p = ResolvePluginByKey(srcKey)
        int xN = 0
        string[] xnames
        float[] xvals
        if p != None
            int itemIdx = _effectIdxFor(p, _keyItemId(srcKey))
            if itemIdx >= 0
                xN = p.GetEffectExtraFieldCount(itemIdx)
                if xN > 0
                    xnames = Utility.CreateStringArray(xN, "")
                    xvals  = Utility.CreateFloatArray(xN, 0.0)
                    int xi = 0
                    while xi < xN
                        string xname = p.GetEffectExtraFieldName(itemIdx, xi)
                        xnames[xi] = xname
                        if xname != ""
                            xvals[xi] = GetSlotEffectExtra(slot, i + 1, xname)
                        endif
                        xi += 1
                    endwhile
                endif
            endif
        endif
        ; Move src → dst.
        SetSlotEffectFull(slot, i, srcKey, srcParam, srcParam2)
        int xi2 = 0
        while xi2 < xN
            if xnames[xi2] != ""
                SetSlotEffectExtra(slot, i, xnames[xi2], xvals[xi2])
            endif
            xi2 += 1
        endwhile
        ; Blank src now that dst owns the data.
        SetSlotEffectFull(slot, i + 1, "", 0, 0)
        i += 1
    endwhile
EndFunction

; Deactivate / activate a SINGLE effect within an active slot. Used when MCM
; rebinds an effect on a tier that's currently live — without this, the old
; effect's onDeactivate is never called and its applied state lingers
; (Magic/Fire resist abilities stay on, +pct shifts stay applied, …).
Function _deactivateSingleEffect(int slot, int effectIdx)
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    string key = _readFxKey(slot, effectIdx, false)
    if key == ""
        return
    endif
    MTF_Plugin p = ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = _effectIdxFor(p, _keyItemId(key))
    if itemIdx >= 0
        _setDispatchContext(slot, effectIdx)
        p.onDeactivate(itemIdx, PlayerRef, _readFxParam(slot, effectIdx, false), _readFxParam2(slot, effectIdx, false))
        _emitEffectDeactivated(PlayerRef, key, slot)
        _clearDispatchContext()
    endif
EndFunction

Function _activateSingleEffect(int slot, int effectIdx)
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    string key = _readFxKey(slot, effectIdx, false)
    if key == ""
        return
    endif
    MTF_Plugin p = ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = _effectIdxFor(p, _keyItemId(key))
    if itemIdx >= 0
        _setDispatchContext(slot, effectIdx)
        p.onActivate(itemIdx, PlayerRef, _readFxParam(slot, effectIdx, false), _readFxParam2(slot, effectIdx, false))
        _emitEffectActivated(PlayerRef, key, slot)
        _clearDispatchContext()
    endif
EndFunction

Function SetSlotEffectParam2(int slot, int effectIdx, int param2)
    if slot < 0 || slot >= 8 || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    _writeFxParam2(slot, effectIdx, false, param2)
EndFunction

; ── Priority evaluation ───────────────────────────────────────────────────────
int Function evaluateTier()
    if !_arraysReady
        return 0
    endif
    float now = Utility.GetCurrentGameTime()
    int i = 1
    while i < 8
        string key = condPluginId[i]
        if key != ""
            bool timerActive = (now < cooldownUntilGT[i])
            int mode = cooldownMode[i]
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
                    if itemIdx >= 0
                        _setEvalParam2(GetCondParam2(i))
                        if p.checkCondition(itemIdx, PlayerRef, condParam[i])
                            return i
                        endif
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
    if slot <= 0 || slot >= 8 || !_arraysReady
        return
    endif
    int mins = cooldownMin[slot]
    if mins <= 0
        return
    endif
    cooldownUntilGT[slot] = Utility.GetCurrentGameTime() + (mins as float) / 1440.0
EndFunction

; ── Effect lifecycle dispatch ────────────────────────────────────────────────
; Player single-preset path. The base overlay slot is the MCM-managed
; OverlaySlot — for NPCs and stacked player presets, the parallel
; ForActor variants do their own _setDispatchBaseSlot per preset.
Function _activateSlotEffects(int slot)
    if slot < 0 || slot >= 8
        return
    endif
    _setDispatchBaseSlot(OverlaySlot)
    _setDispatchUseScratch(false)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _setDispatchContext(slot, e)
                    p.onActivate(itemIdx, PlayerRef, _readFxParam(slot, e, false), _readFxParam2(slot, e, false))
                    _emitEffectActivated(PlayerRef, key, slot)
                endif
            endif
        endif
        e += 1
    endwhile
    _clearDispatchContext()
EndFunction

Function _deactivateSlotEffects(int slot)
    if slot < 0 || slot >= 8
        return
    endif
    _setDispatchBaseSlot(OverlaySlot)
    _setDispatchUseScratch(false)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _setDispatchContext(slot, e)
                    p.onDeactivate(itemIdx, PlayerRef, _readFxParam(slot, e, false), _readFxParam2(slot, e, false))
                    _emitEffectDeactivated(PlayerRef, key, slot)
                endif
            endif
        endif
        e += 1
    endwhile
    _clearDispatchContext()
EndFunction

Function _tickSlotEffects(int slot)
    if slot < 0 || slot >= 8
        return
    endif
    _setDispatchBaseSlot(OverlaySlot)
    _setDispatchUseScratch(false)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _setDispatchContext(slot, e)
                    p.onTick(itemIdx, PlayerRef, _readFxParam(slot, e, false), _readFxParam2(slot, e, false))
                endif
            endif
        endif
        e += 1
    endwhile
    _clearDispatchContext()
EndFunction

Function _gameTickSlotEffects(int slot)
    if slot < 0 || slot >= 8
        return
    endif
    _setDispatchBaseSlot(OverlaySlot)
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _setDispatchContext(slot, e)
                    p.onGameTime(itemIdx, PlayerRef, _readFxParam(slot, e, false), _readFxParam2(slot, e, false))
                endif
            endif
        endif
        e += 1
    endwhile
    _clearDispatchContext()
EndFunction

bool Function _slotHasEffects(int slot)
    if slot < 0 || slot >= 8
        return false
    endif
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        if _readFxKey(slot, e, false) != ""
            return true
        endif
        e += 1
    endwhile
    return false
EndFunction

Function _notifyTierChangeForActor(Actor target, int tier, bool useScratch)
{Debug-only toast for NPC tier transitions. Reads effect labels from
 scratch (preset loaded for `target`) so the message matches what
 actually got applied. Same format as the player notification but
 prefixed with the actor's display name so we can distinguish them
 in NotificationLog.}
    if !DebugMode || target == None
        return
    endif
    string nm = target.GetDisplayName()
    if tier <= 0
        Notification("MTF: " + nm + " - condition cleared")
        return
    endif
    string msg = "MTF: " + nm + " - Tier " + tier
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(tier, e, useScratch)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    msg += " - " + p.GetEffectLabel(itemIdx) + " " + _readFxParam(tier, e, useScratch)
                endif
            endif
        endif
        e += 1
    endwhile
    Notification(msg)
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
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(tier, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    msg += " - " + p.GetEffectLabel(itemIdx) + " " + _readFxParam(tier, e, false)
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
        ; Post-load grace: skip every eval/draw branch for the first ~5s
        ; after OnPlayerLoadGame, just keep ticking. See the
        ; _postLoadFreezeUntilRT comment near the property declaration.
        float postLoadNow = Utility.GetCurrentRealTime()
        if postLoadNow < _postLoadFreezeUntilRT
            float freezeRemain = _postLoadFreezeUntilRT - postLoadNow
            if freezeRemain < 0.05
                freezeRemain = 0.05
            endif
            RegisterForSingleUpdate(freezeRemain)
            return
        endif

        if !ModActive
            removeOverlay(PlayerRef)
            if currentTier >= 0
                _deactivateSlotEffects(currentTier)
            endif
            currentTier = -1
            influenceTracking = false
            return
        endif

        ; v0.1.17 Phase 2 (multi-area): detect per-area MCM base slider edits.
        ; Any of the four sliders moving triggers a full wipe + redraw so the
        ; old slot range is cleared before the new one is painted.
        if CurrentOverlaySlot != OverlaySlot \
                || CurrentFaceOverlaySlot != FaceOverlaySlot \
                || CurrentHandOverlaySlot != HandOverlaySlot \
                || CurrentFeetOverlaySlot != FeetOverlaySlot
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
            ; Plugin-registration heartbeat: alias scripts attached to each
            ; plugin quest listen for this and call _tryRegister(). Survives
            ; the Papyrus "function differs since save" quirk that drops
            ; queued OnUpdate resumptions after a mid-save .pex rebuild —
            ; mod events fire fresh function calls rather than resuming
            ; queued ones. Already-registered plugins early-out cheaply.
            ;
            ; Uses the global ModEvent.Create/Send API rather than
            ; SendModEvent (the latter is on Alias/AMF only — Quest scripts
            ; can't call it). Zero args; the receiver callback takes none.
            int kickHandle = ModEvent.Create("MTF_PluginKick")
            if kickHandle != 0
                ModEvent.Send(kickHandle)
            endif
            ; v0.1.20: one-shot framework-ready broadcast for external
            ; integrations. Self-gated on pluginCount > 0 + _readyEmitted.
            _emitFrameworkReady()
            int newTier = evaluateTier()
            bool tierChanged = (newTier != currentTier)
            ; Snapshot before currentTier overwrite — _emitTierChanged
            ; needs the prevTier value after the activation pass runs.
            int prevTierForEmit = currentTier

            ; Batched Apply: defer NiOverride.ApplyNodeOverrides across the
            ; MCM-base draw AND every stacked-preset draw, then issue one
            ; Apply at the end. Each Apply call rebuilds the live shader and
            ; runs in real time (~hundreds of ms on a heavily-stacked
            ; character); N back-to-back Applies show as visible staircase —
            ; the player sees their tattoos light up one-by-one with ~0.5s
            ; gaps instead of all together. One Apply covers every override
            ; written this tick.
            bool needPlayerApply = false

            if forceRedraw || tierChanged
                forceRedraw = false
                if tierChanged && currentTier >= 0
                    _deactivateSlotEffects(currentTier)
                    ; Mode 0: arm cooldown so the slot can't reactivate.
                    if _arraysReady && cooldownMode[currentTier] == 0
                        _armCooldownTimer(currentTier)
                    endif
                endif
                currentTier = newTier
                drawOverlay(PlayerRef, currentTier, true)
                needPlayerApply = true
                ; Reset pulse phase so the new tier starts cleanly at sin(0)=0.
                _pulseStartRT = now
                if tierChanged
                    ; Push the pulse roster entry BEFORE activating effects.
                    ; v0.1.3 flash.onhit's onActivate calls MTFPulse.SetActorFlash,
                    ; which silently no-ops unless a (actor, base_slot) entry
                    ; already exists. _applyPulse runs anyway at the bottom of
                    ; OnUpdate at 10Hz, but the first SetActorFlash on tier
                    ; activation would miss without this priming call.
                    _applyPulse()
                    _activateSlotEffects(currentTier)
                    ; Mode 1: arm lock so the slot stays active for the duration.
                    if currentTier > 0 && _arraysReady && cooldownMode[currentTier] == 1
                        _armCooldownTimer(currentTier)
                    endif
                    _notifyTierChange(currentTier)
                    ; v0.1.20: external-integration broadcast. After the
                    ; activation pass so SkyrimNet decorators called from
                    ; the listener see the new state's effects already on.
                    _emitTierChanged(PlayerRef, "player", "", prevTierForEmit, currentTier)
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

            ; Stacked presets on the player (applied via the Apply Tattoo
            ; spell, layered above the MCM-driven base). Each one carries
            ; its own per-(preset, slot) cooldown and tier state and gets
            ; the full eval/draw/effect cycle independently of the base.
            ;
            ; First, detect player MCM-base layout drift: if the first
            ; stacked preset's stored base no longer matches OverlaySlot +
            ; _playerBaseLayers, re-pack the whole stack. Triggers naturally
            ; on OverlaySlot edits and pack/entry edits that change the
            ; max layer count of the player's cond config.
            ;
            ; v0.1.17 Phase 1 (multi-area) bug fix: walk presets to find the
            ; first one with a BODY reservation (base >= 0). Face/Hand/Feet-
            ; only presets store -1 as their Body base by default, and a
            ; naive `firstBase != expectedFirstBase` check against -1 would
            ; trip the compaction every tick → re-stamp → ApplyNodeOverrides
            ; flash every 2s. The drift detector is body-floor-specific, so
            ; only presets that actually own a body floor are relevant.
            int playerPresetN = GetActorPresetCount(PlayerRef)
            if playerPresetN > 0
                int expectedFirstBase = OverlaySlot + _playerBaseLayers("Body")
                int driftIdx = 0
                while driftIdx < playerPresetN
                    string driftPP = GetActorPresetAt(PlayerRef, driftIdx)
                    if driftPP != ""
                        int driftBase = _getActorPresetBase(PlayerRef, driftPP, "Body")
                        if driftBase >= 0
                            if driftBase != expectedFirstBase
                                _compactAppliedPresets(PlayerRef)
                            endif
                            driftIdx = playerPresetN  ; break — only check first body-using preset
                        endif
                    endif
                    driftIdx += 1
                endwhile
            endif
            ; Batch every roster update across the stacked-preset loop so
            ; the C++ side queues incoming SetActorPulse* calls and
            ; installs them all at EndTransitionBatch with one shared
            ; transition_start. This is the only way to get every stacked
            ; preset's cross-fade to lerp in lockstep — without the batch,
            ; each Set() captured its own NowSec inside Roster::Set, and
            ; the Papyrus burst (sequential JsonUtil reads + effect
            ; activate per preset) spreads those NowSec values over
            ; hundreds of milliseconds → later slots either jumped past
            ; earlier ones mid-lerp or, if the burst exceeded
            ; transition_duration, hit Tick's snap path and popped on
            ; without any fade. EndTransitionBatch runs unconditionally
            ; so a mid-loop early-return doesn't leave the C++ side
            ; permanently in batch mode.
            ; Plan A (v0.2 perf pass): Two-pass slow-tick.
            ;
            ; Pass 1 — pre-eval. Walk every loaded preset and capture its
            ; target tier via _quickEvalCondsFromJson, which reads
            ; cond+cooldown straight from the preset JSON (no scratch load).
            ; This snapshots all tiers atomically at the start of the tick,
            ; before any apply work runs. Without this, a multi-preset
            ; transition staircases — slot 2's eval reads an actor value
            ; that already shifted past the threshold during the seconds
            ; spent applying slot 1, so slot 2 ends up on the wrong tier
            ; until the next slow tick catches it back up.
            ;
            ; Pass 2 — apply. Load scratch per preset and forward the
            ; pre-eval'd tier to _evalAndDrawPresetForActorWithKnownTier
            ; so the apply branch acts on the snapshot, not a re-evaluation.
            ; BeginTransitionBatch/EndTransitionBatch still pin one shared
            ; transition_start across the whole apply pass so the C++ side
            ; lerps every changed slot in lockstep.
            string[] presetNames
            int[]    preEvalTiers
            if playerPresetN > 0
                presetNames  = Utility.CreateStringArray(playerPresetN, "")
                preEvalTiers = Utility.CreateIntArray(playerPresetN, 0)
                int ppe = 0
                while ppe < playerPresetN
                    string ppNameE = GetActorPresetAt(PlayerRef, ppe)
                    presetNames[ppe] = ppNameE
                    if ppNameE != ""
                        preEvalTiers[ppe] = _quickEvalCondsFromJson(PlayerRef, ppNameE)
                    endif
                    ppe += 1
                endwhile
            endif

            MTFPulse.BeginTransitionBatch()
            int ppi = 0
            while ppi < playerPresetN
                string ppName = presetNames[ppi]
                ; Concurrent-remove guard. RemoveAppliedPreset removes from
                ; mtf.presets and then runs a long deactivate loop (21+
                ; cross-script calls). If a slow-tick was already in flight
                ; with this preset captured in the snapshot, _evalAndDraw
                ; would still call _tickSlotEffectsForActor for it — and
                ; onTick re-applies the AV shifts that the concurrent
                ; deactivate just zeroed (it reads prev=0, sees amt=20, and
                ; ModActorValue(+20) puts the buff right back). Re-check
                ; list membership and skip if the preset was removed
                ; between snapshot and now.
                bool stillApplied = ppName != "" && _findActorPresetIdx(PlayerRef, ppName) >= 0
                bool loadedOk = stillApplied && _loadPresetToScratch(ppName)
                if loadedOk
                    if _evalAndDrawPresetForActorWithKnownTier(PlayerRef, ppName, preEvalTiers[ppi], true)
                        needPlayerApply = true
                    endif
                endif
                ppi += 1
            endwhile
            MTFPulse.EndTransitionBatch()

            if needPlayerApply
                NiOverride.ApplyNodeOverrides(PlayerRef)
            endif

            ; Tracked NPC rotation: stagger MAX_EVALS_PER_TICK per slow tick.
            ; Each evaluated actor goes through Is3DLoaded + distance gates
            ; in _processTrackedActorOnce; out-of-range actors cost ~2 calls.
            _processTrackedActorsSlowTick(MAX_EVALS_PER_TICK())
        endif

        ; Pulse step. Player path resyncs to native at 10 Hz so MCM slider
        ; edits to rate/depth/emMult propagate within 100 ms. NPC roster
        ; entries are pushed once on _rosterAddOrUpdate — the MTFPulse C++
        ; plugin owns their per-frame wave; we don't loop over them here.
        bool wantFast = (_pulseTier >= 0)
        if _pulseTier >= 0
            _applyPulse()
        endif
        if wantFast
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

int Function _maxLayerSlots(string area = "Body")
    ; Player MCM-base reachable slot count from <Area>OverlaySlot upward,
    ; clamped to NiOverride's iNumOverlays. Used by the player legacy draw
    ; path and pulse cache; stacked presets use their stored per-
    ; (preset, area) reservation instead.
    ;
    ; v0.1.17 Phase 2 (multi-area): default param keeps existing call sites
    ; (pulse cache, etc.) body-only; removeOverlay loops _OVERLAY_PARTS() and
    ; passes area explicitly to clear each area's MCM-base range.
    int total = _numOverlays(area)
    int rem = total - _areaBaseSlot(area)
    if rem < 1
        rem = 1
    endif
    if rem > total
        rem = total
    endif
    return rem
EndFunction

int Function _areaBaseSlot(string area)
{v0.1.17 Phase 2 (multi-area): MCM-driven base slot for the player, per
 area. Used by AddAppliedPreset (player floor), _compactAppliedPresets,
 _playerBaseLayers, drawOverlayForActor, and removeOverlay so the area-
 specific MCM slider value is the single source of truth.}
    if area == "Body"
        return OverlaySlot
    elseif area == "Face"
        return FaceOverlaySlot
    elseif area == "Hands"
        return HandOverlaySlot
    elseif area == "Feet"
        return FeetOverlaySlot
    endif
    return 0
EndFunction

int Function _areaCurrentBaseSlot(string area)
{Companion of _areaBaseSlot but reads the Current<Area>OverlaySlot mirror
 — the value the slow tick wrote during the last successful redraw. Used
 by removeOverlay so we clear the slots we actually painted, not the
 slots the MCM was edited to AFTER the paint.}
    if area == "Body"
        return CurrentOverlaySlot
    elseif area == "Face"
        return CurrentFaceOverlaySlot
    elseif area == "Hands"
        return CurrentHandOverlaySlot
    elseif area == "Feet"
        return CurrentFeetOverlaySlot
    endif
    return 0
EndFunction

Function _setAreaCurrentBaseSlot(string area, int value)
{Mirror writer for Current<Area>OverlaySlot. Called by drawOverlayForActor
 after a successful per-area paint.}
    if area == "Body"
        CurrentOverlaySlot = value
    elseif area == "Face"
        CurrentFaceOverlaySlot = value
    elseif area == "Hands"
        CurrentHandOverlaySlot = value
    elseif area == "Feet"
        CurrentFeetOverlaySlot = value
    endif
EndFunction

; Per-area record of how many layers the player MCM-base draw last
; reserved. Needed by drawOverlayForActor's reserved==0 branch so a
; transition from "pack configured (N layers)" to "(no texture)" can
; clear the N slots we previously painted. Without this tracking the
; old NiOverride state persists indefinitely and the user sees the
; overlay stuck on. StorageUtil-backed (not an Auto property) so new
; saves can pick it up mid-session without the
; project_papyrus_property_attach footgun.
int Function _areaLastReservedLayers(string area)
    return StorageUtil.GetIntValue(self, "mtf.lastreserved." + area, 0)
EndFunction

Function _setAreaLastReservedLayers(string area, int value)
    StorageUtil.SetIntValue(self, "mtf.lastreserved." + area, value)
EndFunction

int Function _playerBaseLayers(string area)
{Player MCM base reservation per area. Max over cond slots 0..7 of the
 chosen entry's layer count, capped at MAX_LAYERS_PER_SLOT and at what
 remains beyond OverlaySlot. Stacked presets on the player start at
 OverlaySlot + _playerBaseLayers(area).

 v0.1.17 Phase 1 (multi-area): only slots whose picked pack's declared
 area matches `area` contribute. Phase 1 keeps the player MCM-base path
 body-only at draw time (drawOverlayForActor still passes area="Body"),
 so the non-Body branches here always return 0 for now — but Phase 2's
 expanded draw path will reuse this directly. The early-return guard
 isn't needed: a body-only preset returns 0 for Face/Hand/Feet naturally
 because no slot picks a non-Body pack.}
    int maxL = 0
    int maxLayers = MAX_LAYERS_PER_SLOT()
    int s = 0
    while s < 8
        string packId  = ResolveSlotPackId(s)
        string entryId = ResolveSlotEntryId(s)
        if packId != "" && packId != "<none>" && entryId != "" && GetPackArea(packId) == area
            int L = GetEntryLayerCount(packId, entryId)
            if L > maxL
                maxL = L
            endif
        endif
        s += 1
    endwhile
    if maxL > maxLayers
        maxL = maxLayers
    endif
    ; v0.1.17 Phase 2 (multi-area): per-area MCM base slot via helper.
    int areaBase = _areaBaseSlot(area)
    int rem = _numOverlays(area) - areaBase
    if rem < 0
        rem = 0
    endif
    if maxL > rem
        maxL = rem
    endif
    return maxL
EndFunction

int Function _computePresetReservedLayers(string area, bool useScratch)
{Reserved slot count for a preset (player cond* arrays or scratch). Same
 algorithm as _playerBaseLayers but reads from the generalized accessors
 so the same code works for NPC scratch and player cond* arrays. Caller
 is responsible for further capping to remaining free slots.

 v0.1.17 Phase 1 (multi-area): only slots whose picked pack's declared
 area matches `area` contribute. A preset mixing body and face packs
 across its 8 slots produces independent reservations for each area;
 unused areas return 0 and AddAppliedPreset's per-area branch leaves
 their `bases[]` at -1 (sentinel = "no reservation for this area").}
    int maxL = 0
    int maxLayers = MAX_LAYERS_PER_SLOT()
    int s = 0
    while s < 8
        string packId  = _g_resolvePackId(s, useScratch)
        string entryId = _g_resolveEntryId(s, useScratch)
        if packId != "" && packId != "<none>" && entryId != "" && GetPackArea(packId) == area
            int L = GetEntryLayerCount(packId, entryId)
            if L > maxL
                maxL = L
            endif
        endif
        s += 1
    endwhile
    if maxL > maxLayers
        maxL = maxLayers
    endif
    return maxL
EndFunction

function drawOverlay(actor akTarget, int idx, bool deferApply = false)
    drawOverlayForActor(akTarget, idx, false, deferApply)
    ; Pulse cache snapshot stays player-specific in step 2 — NPC pulse
    ; roster (step 5) introduces its own per-actor pulse state.
    if akTarget == PlayerRef
        _resyncPulseCache(idx)
    endif
endFunction

function drawOverlayForActor(actor akTarget, int idx, bool useScratch, bool deferApply = false)
{Legacy entry — used only by the player MCM-driven base layer path. Stamps
 at <Area>OverlaySlot upward with reservation sized to the player's cond
 config (_playerBaseLayers). NPC presets and player stacked presets go
 through _drawOverlayForActorAt directly with their stored base + layers.

 v0.1.17 Phase 2 (multi-area): loops over _OVERLAY_PARTS() so the player
 MCM-base path also paints Face/Hand/Feet packs. Each area's reservation
 is independent — a body-only preset paints only Body; a preset mixing
 a face pack in slot 0 + body packs in 1..7 paints both.}
    if akTarget == None
        return
    endif
    string[] parts = _OVERLAY_PARTS()
    int p = 0
    while p < parts.Length
        string area = parts[p]
        int areaBase = _areaBaseSlot(area)
        int reserved = _playerBaseLayers(area)
        if reserved <= 0
            ; No MCM base configured for this area — but we may have
            ; PAINTED here on the previous draw. Without an explicit clear,
            ; the prior NiOverride state persists when the user transitions
            ; a slot from a configured pack to "(no texture)" — visible
            ; overlay stays on indefinitely (SlaveTats sees it as
            ; "external", any consumer that scans NiOverride sees it as
            ; live). Clear our previously-reserved range using the
            ; PAINT-TIME base (_areaCurrentBaseSlot, not the live
            ; _areaBaseSlot) so a mid-session OverlaySlot slider change
            ; doesn't misroute the clear to fresh slots.
            int lastReserved = _areaLastReservedLayers(area)
            if lastReserved > 0
                int prevBase = _areaCurrentBaseSlot(area)
                bool isFemaleClear = akTarget.GetLeveledActorBase().GetSex() as bool
                int ci = 0
                while ci < lastReserved
                    _clearOverlayDeferred(akTarget, isFemaleClear, area, prevBase + ci)
                    ci += 1
                endwhile
                if !deferApply
                    NiOverride.ApplyNodeOverrides(akTarget)
                endif
                if !useScratch
                    _setAreaLastReservedLayers(area, 0)
                endif
            endif
            if !useScratch
                _setAreaCurrentBaseSlot(area, areaBase)
            endif
        else
            _drawOverlayForActorAt(akTarget, idx, useScratch, area, areaBase, reserved, deferApply)
            if !useScratch
                _setAreaCurrentBaseSlot(area, areaBase)
                _setAreaLastReservedLayers(area, reserved)
            endif
        endif
        p += 1
    endwhile
endFunction

function _drawOverlayForActorAt(actor akTarget, int idx, bool useScratch, string area, int baseSlot, int reservedLayers, bool deferApply = false)
{Stamp the entry chosen by `idx` into [baseSlot, baseSlot+reservedLayers).
 Layers the entry doesn't use within that range get cleared so leftover
 textures don't bleed through after a tier change. Slots outside the
 range are left untouched — the caller owns slot ownership.

 All NiOverride store writes are batched into a SINGLE ApplyNodeOverrides
 at the end. Calling apply/clearOverlay per-layer (each of which Applies)
 caused 4 sequential overlay rebuilds per draw on a 4-layer reservation,
 and each rebuild flashed visibly on tier transitions. One Apply = one
 rebuild = no flash.}
    if akTarget == None || baseSlot < 0 || reservedLayers <= 0
        return
    endif
    if idx < 0 || idx >= 8
        bool isFemaleClear = akTarget.GetLeveledActorBase().GetSex() as bool
        int ci = 0
        while ci < reservedLayers
            _clearOverlayDeferred(akTarget, isFemaleClear, area, baseSlot + ci)
            ci += 1
        endwhile
        if !deferApply
            NiOverride.ApplyNodeOverrides(akTarget)
        endif
        return
    endif
    int total = _numOverlays(area)
    if baseSlot >= total
        return
    endif
    if baseSlot + reservedLayers > total
        reservedLayers = total - baseSlot
    endif
    bool isFemale = akTarget.GetLeveledActorBase().GetSex() as bool

    string packId  = _g_resolvePackId(idx, useScratch)
    string entryId = _g_resolveEntryId(idx, useScratch)

    int maxLayers = MAX_LAYERS_PER_SLOT()
    int layerN = 0
    ; v0.1.17 Phase 1 (multi-area) correctness fix: only paint this area's
    ; nodes when the tier's resolved pack BELONGS to this area. Without
    ; the area-match guard, a body-pack in slot 0 + face-pack in slot 1
    ; would cause the face area's draw to paint the body texture into
    ; "Face [ovlN]" (because the face reservation exists for the preset,
    ; and the tier-0 draw blindly forwarded the resolved pack). Mismatch
    ; → layerN stays 0, the trailing-clear branch wipes the area's slots
    ; for this tier — which is the correct semantics ("tier 0 has no face
    ; content; the face area shows nothing").
    if packId != "" && packId != "<none>" && entryId != "" && GetPackArea(packId) == area
        layerN = GetEntryLayerCount(packId, entryId)
        if layerN > reservedLayers
            layerN = reservedLayers
        endif
        if layerN > maxLayers
            layerN = maxLayers
        endif
    endif

    ; Unconditional AddOverlays: SKEE's HasOverlays checks an internal flag,
    ; not the actual NiAVObject graph. When the body's 3D is rebuilt (armor
    ; swap, BodyGen, in-session reload, 3BA refresh) the "Body [ovlN]"
    ; sub-nodes can be torn down while the flag stays true. Subsequent Add*
    ; calls then look up missing nodes and silently no-op on the live shader,
    ; even though the override store gets updated. AddOverlays is idempotent
    ; on attached actors and re-creates the sub-nodes if missing.
    NiOverride.AddOverlays(akTarget)

    int i = 0
    while i < layerN
        int lidx     = _layerIdx(idx, i)
        string tex   = GetEntryLayerTexture(packId, entryId, i)
        int tint     = _g_layerTint(lidx, useScratch)
        int emissive = _g_layerEmissive(lidx, useScratch)
        float emMult = _g_layerEmissiveMult(lidx, useScratch)
        float alpha  = (_g_layerAlpha(lidx, useScratch) as float) * 0.01
        _applyOverlayDeferred(akTarget, isFemale, area, baseSlot + i, tex, tint, emissive, emMult, alpha)
        i += 1
    endwhile
    while i < reservedLayers
        _clearOverlayDeferred(akTarget, isFemale, area, baseSlot + i)
        i += 1
    endwhile
    if !deferApply
        NiOverride.ApplyNodeOverrides(akTarget)
    endif
endFunction

Function _applyOverlayDeferred(actor Target, bool isFemale, string Area, int Slot, string Texture, int Tint, int Emissive, float Intensity, float Alpha)
{Store-only variant of applyOverlay — populates the NiOverride override
 store but does NOT call ApplyNodeOverrides. Caller batches a single
 Apply after the full draw. HasOverlays/AddOverlays setup must already
 have been done by the caller (we don't repeat the check per layer).}
    string Node = Area + " [ovl" + Slot + "]"
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
EndFunction

Function _clearOverlayDeferred(actor Target, bool isFemale, string Area, int Slot)
{Store-only variant of clearOverlay. Writes the inert "off" values into
 the override store and leaves them there — the batched ApplyNodeOverrides
 at the end of _drawOverlayForActorAt pushes them to the live node. Unlike
 the standalone clearOverlay we don't scrub the store afterwards because
 there's no intervening Apply for the live node to drift from; the off
 values can sit in the store harmlessly and get overwritten by the next
 applyOverlay on this slot.}
    string Node = Area + " [ovl" + Slot + "]"
    string defaultTex = "actors\\character\\overlays\\default.dds"
    NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 0, defaultTex, true)
    if NiOverride.HasNodeOverride(Target, isFemale, Node, 9, 1)
        NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 1, defaultTex, true)
    endif
    NiOverride.AddNodeOverrideInt(Target,   isFemale, Node, 7, -1, 16777215, true)
    NiOverride.AddNodeOverrideInt(Target,   isFemale, Node, 0, -1, 16777215, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 1, -1, 0.0, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 2, -1, 0.0, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 3, -1, 0.0, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 8, -1, 0.0, true)
EndFunction

function _drawPresetOnActor(actor target, string name, int tier, bool deferApply = false)
{Draws preset `name` on `target` at `tier`, using stored per-(preset, area)
 base + reservedLayers. Caller must have _loadPresetToScratch(name) loaded.
 With `deferApply=true`, the caller owns the trailing
 NiOverride.ApplyNodeOverrides — used by batched callers to collapse N
 stacked-preset draws into a single Apply (see _evalAndDrawPresetForActor).}
    if target == None || name == ""
        return
    endif
    string[] parts = _OVERLAY_PARTS()
    int p = 0
    while p < parts.Length
        string area = parts[p]
        int base = _getActorPresetBase(target, name, area)
        int reserved = _getActorPresetLayers(target, name, area)
        if base >= 0 && reserved > 0
            _drawOverlayForActorAt(target, tier, true, area, base, reserved, deferApply)
        endif
        p += 1
    endwhile
endFunction

function _clearPresetOverlayForActor(actor target, string name)
{Clear the slot range a preset reserved. Used on removal and on full
 actor wipe.}
    if target == None || name == ""
        return
    endif
    bool isFemale = target.GetLeveledActorBase().GetSex() as bool
    string[] parts = _OVERLAY_PARTS()
    int p = 0
    while p < parts.Length
        string area = parts[p]
        int base = _getActorPresetBase(target, name, area)
        int reserved = _getActorPresetLayers(target, name, area)
        if base >= 0 && reserved > 0
            int i = 0
            while i < reserved
                clearOverlay(target, isFemale, area, base + i)
                i += 1
            endwhile
        endif
        p += 1
    endwhile
endFunction

Function _compactAppliedPresets(Actor target)
{Re-pack every applied preset's slot range tight against the floor.
 Floor = OverlaySlot + player base for the player, scan result for NPCs.
 Each remaining preset (in mtf.presets order) gets its stored base
 rewritten and is re-stamped at the new location. Reserved layer counts
 are preserved; we don't try to grow truncated reservations back.

 Call this after RemoveAppliedPreset so gaps in the slot space close.
 Slot ownership of EXTERNAL overlays (SlaveTats etc.) is preserved
 because we only ever clear OUR stored ranges.}
    if target == None
        return
    endif
    int n = GetActorPresetCount(target)
    if n <= 0
        return
    endif
    bool isPlayer = (target == PlayerRef)
    bool isFemale = target.GetLeveledActorBase().GetSex() as bool
    string[] parts = _OVERLAY_PARTS()

    ; Step 1: clear every applied preset's stored slot range so the next
    ; scan sees only external overlays. Also kill all C++ pulse entries
    ; for this actor — their (formID, base_slot) keys are about to go
    ; stale; Step 3 below will re-push them at the new base_slots.
    MTFPulse.ClearActor(target)
    int i = 0
    while i < n
        string nm = GetActorPresetAt(target, i)
        if nm != ""
            int pp = 0
            while pp < parts.Length
                string ar = parts[pp]
                int b = _getActorPresetBase(target, nm, ar)
                int r = _getActorPresetLayers(target, nm, ar)
                if b >= 0 && r > 0
                    int c = 0
                    while c < r
                        clearOverlay(target, isFemale, ar, b + c)
                        c += 1
                    endwhile
                endif
                pp += 1
            endwhile
        endif
        i += 1
    endwhile

    ; Step 2: per-area, derive starting floor and walk presets in order,
    ; assigning fresh bases and re-stamping.
    int p = 0
    while p < parts.Length
        string area = parts[p]
        int total = _numOverlays(area)
        int floor
        if isPlayer
            ; v0.1.17 Phase 2 (multi-area): per-area MCM base slot via helper.
            floor = _areaBaseSlot(area) + _playerBaseLayers(area)
        else
            floor = _findFirstFreeOverlaySlotNPC(target, area)
        endif
        int j = 0
        while j < n
            string nmJ = GetActorPresetAt(target, j)
            if nmJ != ""
                int reserved = _getActorPresetLayers(target, nmJ, area)
                if reserved > 0
                    int newReserved = reserved
                    if floor + newReserved > total
                        newReserved = total - floor
                        if newReserved < 0
                            newReserved = 0
                        endif
                    endif
                    if newReserved > 0
                        _setActorPresetBase(target, nmJ, area, floor)
                        _setActorPresetLayers(target, nmJ, area, newReserved)
                        int tier = _getActorPresetTier(target, nmJ)
                        if tier < 0
                            tier = 0
                        endif
                        if _loadPresetToScratch(nmJ)
                            _drawOverlayForActorAt(target, tier, true, area, floor, newReserved)
                            ; Re-push roster entry for this preset at the new base.
                            ; Without this the actor would render but the
                            ; C++ roster (cleared in Step 1) stays empty
                            ; until the next tier transition.
                            ;
                            ; v0.1.1: re-push tier 0 entries too. The cross-
                            ; fade needs a continuously-alive C++ entry to
                            ; capture from-state on the next tier transition;
                            ; if compaction leaves tier-0 presets without
                            ; entries, the next tier-up snaps because there's
                            ; nothing to lerp from.
                            float rtNow = _getActorPresetPulseStartRT(target, nmJ)
                            if rtNow <= 0.0
                                rtNow = Utility.GetCurrentRealTime()
                            endif
                            _rosterAddOrUpdate(target, nmJ, tier, rtNow)
                        endif
                        floor += newReserved
                    else
                        ; Ran out of room — this preset can't render this area.
                        _setActorPresetBase(target, nmJ, area, -1)
                        _setActorPresetLayers(target, nmJ, area, 0)
                    endif
                endif
            endif
            j += 1
        endwhile
        p += 1
    endwhile
EndFunction

function setRedraw()
    forceRedraw = true
endFunction

Function postLoadRedrawNow()
{Second-chance redraw kicked from MTF_HitListener.OnUpdate ~3s post-load.
 Runs DURING the post-load grace window (see _postLoadFreezeUntilRT) —
 the slow tick is still frozen at this point, so we don't compete with
 eval/draw transitions.

 Two jobs:
 1. AddOverlays + setRedraw — defense in depth in case SKEE's overlay
    sub-nodes were torn down by an in-session 3D reload. The actual
    redraw runs after the grace period when the slow tick unfreezes.
 2. Re-populate the C++ MTFPulse roster for each applied preset. The
    roster is in-memory only (lost on save/load); without this, stacked
    presets stay frozen at SKEE's restored em_mult ceiling instead of
    resuming their pulse animation. _rosterAddOrUpdate writes only to
    MTFPulse — it doesn't touch the NiOverride store, so it can't
    accidentally clear an overlay (the failure mode that bit earlier
    attempts at this fix).}
    if PlayerRef == None
        return
    endif
    if DebugMode
        Notification("MTF: post-load redraw")
    endif
    NiOverride.AddOverlays(PlayerRef)
    setRedraw()

    float rtNow = Utility.GetCurrentRealTime()
    int n = GetActorPresetCount(PlayerRef)
    int i = 0
    while i < n
        string nm = GetActorPresetAt(PlayerRef, i)
        if nm != "" && _loadPresetToScratch(nm)
            int storedTier = _getActorPresetTier(PlayerRef, nm)
            if storedTier >= 0
                _rosterAddOrUpdate(PlayerRef, nm, storedTier, rtNow)
            endif
        endif
        i += 1
    endwhile
EndFunction

; ── NiOverride wrappers ───────────────────────────────────────────────────────
; applyOverlay: stamps Texture into ovlSlot with per-layer effective emissive
; intensity (caller pre-multiplies condEmissiveMult by the layer's bias).
; Falloff (param 2) is set to 5.0 when intensity > 0 ("glow on"), else 0.0
; — same convention as before.

Function applyOverlay(actor Target, bool isFemale, string Area, int Slot, string Texture, int Tint, int Emissive, float Intensity, float Alpha)
    string Node = Area + " [ovl" + Slot + "]"
    ; See _drawOverlayForActorAt for why we don't gate on HasOverlays.
    NiOverride.AddOverlays(Target)
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
    ; Two-phase clear. NiOverride's override store and the live NiAVObject
    ; are decoupled: Add* mutates the store, Remove* mutates the store,
    ; ApplyNodeOverrides pushes the store onto the live node. The MTFPulse
    ; C++ hot path also writes directly to the live node (via SKEE's
    ; SetNodeProperty), bypassing the store entirely. So the old pattern
    ;   Add(default) → Remove(everything) → Apply
    ; pushed an empty store onto the node, leaving the live texture /
    ; emissive at whatever C++ last wrote (a pulse value if the actor
    ; was deactivating mid-pulse). Caller must already have stopped C++
    ; writes — see _rosterRemovePreset.
    ;
    ; Phase 1: set the store to an inert "off" state and push to live.
    NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 0, defaultTex, true)
    if NiOverride.HasNodeOverride(Target, isFemale, Node, 9, 1)
        NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 1, defaultTex, true)
    endif
    NiOverride.AddNodeOverrideInt(Target,   isFemale, Node, 7, -1, 16777215, true)  ; tint white
    NiOverride.AddNodeOverrideInt(Target,   isFemale, Node, 0, -1, 16777215, true)  ; emissive color white
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 1, -1, 0.0, true)       ; emissive mult off
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 2, -1, 0.0, true)       ; falloff off
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 3, -1, 0.0, true)       ; falloff distance off
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 8, -1, 0.0, true)       ; alpha fully transparent
    NiOverride.ApplyNodeOverrides(Target)
    ; Phase 2: scrub the store so nothing leaks into saves / future Applies.
    ; Live node retains the values pushed in Phase 1 — there's nothing
    ; remaining in the store to re-apply, so removing the entries is safe.
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 9, 0)
    if NiOverride.HasNodeOverride(Target, isFemale, Node, 9, 1)
        NiOverride.RemoveNodeOverride(Target, isFemale, Node, 9, 1)
    endif
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 7, -1)
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 0, -1)
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 1, -1)
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 2, -1)
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 3, -1)
    NiOverride.RemoveNodeOverride(Target, isFemale, Node, 8, -1)
EndFunction

function removeOverlay(actor akTarget)
    removeOverlayForActor(akTarget)
endFunction

function removeOverlayForActor(actor akTarget)
{Clear every overlay slot this mod owns on `akTarget`. For the player that
 includes the MCM-driven base range starting at CurrentOverlaySlot; for
 every actor (player or NPC) it includes the slots reserved by each
 applied preset in `mtf.presets`.}
    if akTarget == None
        return
    endif
    bool isFemale = akTarget.GetLeveledActorBase().GetSex() as bool
    if akTarget == PlayerRef
        ; v0.1.17 Phase 2 (multi-area): clear the MCM-base range per area
        ; using the Current<Area>OverlaySlot mirror (where we actually
        ; painted) so a mid-session MCM slider edit still clears the right
        ; slots.
        string[] parts = _OVERLAY_PARTS()
        int pp = 0
        while pp < parts.Length
            string area = parts[pp]
            int max = _maxLayerSlots(area)
            int areaBase = _areaCurrentBaseSlot(area)
            int i = 0
            while i < max
                clearOverlay(akTarget, isFemale, area, areaBase + i)
                i += 1
            endwhile
            pp += 1
        endwhile
        _pulseTier = -1
    endif
    ; Iterate applied presets and clear their reserved ranges per area.
    int n = GetActorPresetCount(akTarget)
    int p = 0
    while p < n
        string nm = GetActorPresetAt(akTarget, p)
        if nm != ""
            _clearPresetOverlayForActor(akTarget, nm)
        endif
        p += 1
    endwhile
    ; Make sure the MTFPulse C++ roster doesn't keep pulsing emissive
    ; on a slot we just cleared.
    MTFPulse.ClearActor(akTarget)
endFunction

; ═════════════════════════════════════════════════════════════════════════════
; NPC SUPPORT (v0.0.33)
; ═════════════════════════════════════════════════════════════════════════════
; Tracked-actor list lives in StorageUtil.FormList(self, "mtf.tracked").
; Per-actor scalars live in StorageUtil on each target form. Preset config
; is loaded on demand from preset JSON into the _sCond* scratch buffer and
; the mtf.fx.scratch.* StorageUtil keyspace (no per-actor snapshot — keeps
; storage footprint linear in tracked count, not slot/layer/effect
; cardinality).
;
; Step 2 scope: tracked-list machinery, scratch buffer, generalized
; draw + evaluate + effects dispatch, console smoke-test entry. The
; slow-tick rotation that walks tracked actors is added in step 5; the
; player flow is unchanged.

int Function TRACKED_CAP() global
    return 256
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

int Function AddAppliedPreset(Actor target, string name)
{Apply preset `name` to `target`. For NPCs, also tracks the actor.
 Computes base slot + reserved layer count per overlay area. Rejects with
 -6 / -7 if visuals can't fit cleanly (see codes below). Per-preset state
 (tier, pulse start) is initialized; _evalAndDrawPresetForActor fires the
 first eval+draw cycle synchronously.

 Return codes:
   1  applied
   0  preset already on this actor (dedupe — no-op)
  -2  None target
  -3  tracked-subject cap reached (NPC only)
  -4  preset name empty
  -5  preset JSON missing / invalid schema
  -6  preset wanted visual layers but every area is full (headless
      presets — those that request zero layers in every area — bypass
      this check and apply as effects-only)
  -7  preset would render with a truncated visual: at least one area has
      free slots, but fewer than max(GetEntryLayerCount) across the
      preset's slots. Reserving fewer slots than the largest tier needs
      means that tier's texture would render only its first N layers
      (silent visual breakage). Hard-rejecting forces the user to free
      slots before applying. Same protection threshold as -6 — only
      headless presets (wantAny == 0) bypass.}
    if target == None
        return -2
    endif
    if name == ""
        return -4
    endif
    if !_loadPresetToScratch(name)
        return -5
    endif
    if HasActorPreset(target, name)
        return 0
    endif
    bool isPlayer = (target == PlayerRef)
    bool isNewTracked = false
    if !isPlayer && !IsTrackedActor(target)
        if GetTrackedCount() >= TRACKED_CAP()
            return -3
        endif
        isNewTracked = true
    endif
    string[] parts = _OVERLAY_PARTS()
    int[] bases = Utility.CreateIntArray(parts.Length, -1)
    int[] reservs = Utility.CreateIntArray(parts.Length, 0)
    int reservedAny = 0
    int wantAny = 0
    bool truncated = false
    int p = 0
    while p < parts.Length
        string area = parts[p]
        int total = _numOverlays(area)
        int base = 0
        if isPlayer
            ; Stack after the player's MCM-driven base layer and any presets
            ; already applied. Each existing applied preset contributes its
            ; stored reserved layer count for THIS area.
            ;
            ; v0.1.17 Phase 2 (multi-area): per-area MCM base slot via helper.
            base = _areaBaseSlot(area) + _playerBaseLayers(area)
            int j = 0
            int nApplied = GetActorPresetCount(target)
            while j < nApplied
                string prev = GetActorPresetAt(target, j)
                base += _getActorPresetLayers(target, prev, area)
                j += 1
            endwhile
        else
            ; NPC: scan top-down, stack above any existing overlay (ours or
            ; another mod's).
            base = _findFirstFreeOverlaySlotNPC(target, area)
        endif
        int want = _computePresetReservedLayers(area, true)
        wantAny += want
        int reserved = 0
        int free = total - base
        if free > 0 && want > 0
            reserved = want
            if reserved > free
                reserved = free
            endif
            if reserved > 0
                bases[p] = base
                reservs[p] = reserved
                reservedAny += reserved
            endif
        endif
        ; Hard-reject visual truncation: if this area wanted N layers but
        ; we could only reserve M < N, the largest tier's texture would
        ; render only its first M layers (silent visual breakage). Flag it
        ; and bail after the loop so the docstring's reservation table is
        ; never persisted for a doomed-to-look-broken apply.
        if want > 0 && reserved < want
            truncated = true
        endif
        p += 1
    endwhile
    ; Headless preset (no layers requested in any area) → bypass both the
    ; -6 (no-room) and -7 (truncation) gates. Effects-only presets still
    ; apply: _drawPresetOnActor early-outs per-area when reserved == 0,
    ; and _activateSlotEffectsForActor / _tickSlotEffectsForActor iterate
    ; slots independently of visual state.
    if wantAny > 0 && reservedAny <= 0
        return -6
    endif
    if truncated
        return -7
    endif
    ; Persist tracking + per-(actor, preset, area) state.
    if isNewTracked
        StorageUtil.FormListAdd(self, "mtf.tracked", target, true)
        _setActorSuspended(target, false)
        _setActorKilled(target, false)
    endif
    StorageUtil.StringListAdd(target, "mtf.presets", name, false)
    p = 0
    while p < parts.Length
        if reservs[p] > 0
            _setActorPresetBase(target, name, parts[p], bases[p])
            _setActorPresetLayers(target, name, parts[p], reservs[p])
        endif
        p += 1
    endwhile
    _setActorPresetTier(target, name, -1)
    _setActorPresetPulseStartRT(target, name, Utility.GetCurrentRealTime())
    _evalAndDrawPresetForActor(target, name)
    return 1
EndFunction

Function RemoveAppliedPreset(Actor target, string name)
{Remove a single applied preset from an actor. Deactivates active effects,
 clears its slot range, drops it from mtf.presets, wipes its per-preset
 state, then compacts the remaining presets so they fill the gap.}
    if target == None || name == ""
        return
    endif
    int idx = _findActorPresetIdx(target, name)
    if idx < 0
        return
    endif
    int prevTier = _getActorPresetTier(target, name)
    ; CRITICAL ORDER: drop the preset from mtf.presets BEFORE running the
    ; deactivate loop. _deactivateSlotEffectsForActor makes 21+ cross-script
    ; calls to plugin.onDeactivate; each cross-script call suspends the
    ; MainQuest VM thread, letting OnUpdate's slow-tick interleave on a
    ; different thread. If the preset is still in mtf.presets at that point,
    ; the slow-tick fires _tickSlotEffectsForActor for this preset — which
    ; calls _recomputeAbsShift(idx, target, 20). It sees prev=0 (the
    ; deactivate just cleared it) and immediately RE-APPLIES the AV shift.
    ; Net effect: dip-and-return; effects persist after removal.
    ;
    ; Removing from the list first means slow-tick interleaves see no
    ; preset to iterate, so onTick can't fight the deactivate.
    ;
    ; Scratch read is still safe — useScratch=true reads
    ; mtf.fx.scratch.<name>.* which is keyed by name, not list membership.
    ; tier >= 0 (not > 0): baseline-slot effects (slot 0) are activated by
    ; _applyPresetTierChange whenever any tier is selected — including
    ; tier 0 itself.
    StorageUtil.StringListRemoveAt(target, "mtf.presets", idx)
    if prevTier >= 0 && _loadPresetToScratch(name)
        _deactivateSlotEffectsForActor(target, prevTier, true, name)
    endif
    ; Kill the C++ pulse entry for THIS preset before we wipe its state
    ; (need the stored base_slot to address it). Other presets on the same
    ; actor keep pulsing — each owns its own (actor, base_slot) entry.
    _rosterRemovePreset(target, name)
    _clearPresetOverlayForActor(target, name)
    _clearActorPresetState(target, name)
    ; Close the gap: re-pack remaining presets against the floor.
    _compactAppliedPresets(target)
EndFunction

Function RemoveTrackedActor(Actor target)
{Untrack an NPC entirely: deactivate effects for every applied preset,
 clear their overlay ranges, drop tracking state.}
    if target == None || !IsTrackedActor(target)
        return
    endif
    int n = GetActorPresetCount(target)
    int i = n - 1
    while i >= 0
        string nm = GetActorPresetAt(target, i)
        if nm != ""
            int tier = _getActorPresetTier(target, nm)
            ; tier >= 0 (not > 0): see RemoveAppliedPreset for rationale —
            ; baseline-slot effects need deactivation too.
            if tier >= 0 && _loadPresetToScratch(nm)
                _deactivateSlotEffectsForActor(target, tier, true, nm)
            endif
        endif
        i -= 1
    endwhile
    _rosterRemoveActor(target)
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

; ── Multi-tattoo: per-actor applied-preset list ─────────────────────────────
; mtf.presets (StringList per actor) — ordered list of applied preset names.
; For NPCs this is the only source of tattoo state. For the player the
; MCM-edited cond* arrays still drive a "base" layer at [OverlaySlot,
; OverlaySlot+playerBaseLayers); mtf.presets stacks on top of that.
;
; Per (actor, preset) state — tier, cooldowns, pulse start — uses keys
; "mtf.preset.<name>.tier" etc. Per (actor, preset, area) base + reserved
; layer count uses "mtf.preset.<name>.<area>.base/.layers". Suspended /
; killed remain actor-wide (a corpse is a corpse for every preset).

int Function GetActorPresetCount(Actor target)
    if target == None
        return 0
    endif
    return StorageUtil.StringListCount(target, "mtf.presets")
EndFunction

string Function GetActorPresetAt(Actor target, int idx)
    if target == None
        return ""
    endif
    return StorageUtil.StringListGet(target, "mtf.presets", idx)
EndFunction

bool Function HasActorPreset(Actor target, string name)
    if target == None || name == ""
        return false
    endif
    return StorageUtil.StringListHas(target, "mtf.presets", name)
EndFunction

int Function _findActorPresetIdx(Actor target, string name)
    if target == None || name == ""
        return -1
    endif
    return StorageUtil.StringListFind(target, "mtf.presets", name)
EndFunction

; Per (actor, preset) tier / pulse-start / cooldown.
int Function _getActorPresetTier(Actor target, string name)
    if target == None || name == ""
        return -1
    endif
    return StorageUtil.GetIntValue(target, "mtf.preset." + name + ".tier", -1)
EndFunction
Function _setActorPresetTier(Actor target, string name, int tier)
    if target != None && name != ""
        StorageUtil.SetIntValue(target, "mtf.preset." + name + ".tier", tier)
    endif
EndFunction

float Function _getActorPresetCooldown(Actor target, string name, int slot)
    if target == None || name == ""
        return 0.0
    endif
    return StorageUtil.GetFloatValue(target, "mtf.preset." + name + ".cd." + slot, 0.0)
EndFunction
Function _setActorPresetCooldown(Actor target, string name, int slot, float gameTime)
    if target != None && name != ""
        StorageUtil.SetFloatValue(target, "mtf.preset." + name + ".cd." + slot, gameTime)
    endif
EndFunction

float Function _getActorPresetPulseStartRT(Actor target, string name)
    if target == None || name == ""
        return 0.0
    endif
    return StorageUtil.GetFloatValue(target, "mtf.preset." + name + ".pulse.start", 0.0)
EndFunction
Function _setActorPresetPulseStartRT(Actor target, string name, float t)
    if target != None && name != ""
        StorageUtil.SetFloatValue(target, "mtf.preset." + name + ".pulse.start", t)
    endif
EndFunction

; Per (actor, preset, area) base slot + reserved layer count.
int Function _getActorPresetBase(Actor target, string name, string area)
    if target == None || name == ""
        return -1
    endif
    return StorageUtil.GetIntValue(target, "mtf.preset." + name + "." + area + ".base", -1)
EndFunction
Function _setActorPresetBase(Actor target, string name, string area, int base)
    if target != None && name != ""
        StorageUtil.SetIntValue(target, "mtf.preset." + name + "." + area + ".base", base)
    endif
EndFunction
int Function _getActorPresetLayers(Actor target, string name, string area)
    if target == None || name == ""
        return 0
    endif
    return StorageUtil.GetIntValue(target, "mtf.preset." + name + "." + area + ".layers", 0)
EndFunction
Function _setActorPresetLayers(Actor target, string name, string area, int layers)
    if target != None && name != ""
        StorageUtil.SetIntValue(target, "mtf.preset." + name + "." + area + ".layers", layers)
    endif
EndFunction

Function _clearActorPresetState(Actor target, string name)
    if target == None || name == ""
        return
    endif
    StorageUtil.UnsetIntValue(target, "mtf.preset." + name + ".tier")
    StorageUtil.UnsetFloatValue(target, "mtf.preset." + name + ".pulse.start")
    int s = 0
    while s < 8
        StorageUtil.UnsetFloatValue(target, "mtf.preset." + name + ".cd." + s)
        s += 1
    endwhile
    string[] parts = _OVERLAY_PARTS()
    int p = 0
    while p < parts.Length
        StorageUtil.UnsetIntValue(target, "mtf.preset." + name + "." + parts[p] + ".base")
        StorageUtil.UnsetIntValue(target, "mtf.preset." + name + "." + parts[p] + ".layers")
        p += 1
    endwhile
EndFunction

; ── Per-actor scalar state (actor-wide, not per-preset) ─────────────────────
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
    ; Clear per-preset state for every applied preset, then drop the list.
    int n = GetActorPresetCount(target)
    int i = 0
    while i < n
        string nm = GetActorPresetAt(target, i)
        if nm != ""
            _clearActorPresetState(target, nm)
        endif
        i += 1
    endwhile
    StorageUtil.StringListClear(target, "mtf.presets")
    StorageUtil.UnsetIntValue(target, "mtf.suspended")
    StorageUtil.UnsetIntValue(target, "mtf.killed")
    i = 0
    while i < 16
        StorageUtil.UnsetFloatValue(target, "mtf.applied." + i)
        i += 1
    endwhile
    StorageUtil.UnsetFloatValue(target, "mtf.applied.spellcost")
EndFunction

; ── Scratch buffer ──────────────────────────────────────────────────────────
Function _ensureScratchArrays()
    ; Allocate once. Re-allocating each call would WIPE the cached preset
    ; data — _loadPresetToScratch's cache check returns early without
    ; re-loading, so the second eval tick would see empty arrays.
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
        _sCondWaveform          = new string[8]
        _sCooldownMin           = new int[8]
        _sCooldownMode          = new int[8]
    endif
EndFunction

float Function _getScratchPulsePause(int slot)
    return StorageUtil.GetFloatValue(self, "mtf.scratch.pulse.pause." + _scratchLoadedFor + "." + slot, 0.0)
EndFunction
Function _setScratchPulsePause(int slot, float v)
    StorageUtil.SetFloatValue(self, "mtf.scratch.pulse.pause." + _scratchLoadedFor + "." + slot, v)
EndFunction

; ── Plan B v2: StorageUtil-backed scratch cache ─────────────────────────────
; Each preset's fully-loaded scratch buffer (the `_s*` array + scalar set)
; is snapshotted into per-preset StorageUtil keys after every cold load.
; A `_loadPresetToScratch(name)` cache hit reads those back into `_s*`
; via ~21 *ListToArray calls (~2.5 ms) instead of doing the ~480 ms
; cold JSON + StorageUtil-effect-write work. This sidesteps the
; [[project_papyrus_bulk_var_add]] failure the original Plan B attempt
; hit — no new script-level vars to attach.
;
; Eviction is implicit: cache entries persist in StorageUtil until
; explicitly invalidated. SavePreset / preset deletion call
; _invalidateScratchCache(name). On a schema bump, increment the literal
; in CACHED_SCRATCH_VERSION() so existing caches fail the version check
; and get cold-rebuilt on next access.

int Function CACHED_SCRATCH_VERSION() global
{Bump when the _s* field set OR the FX scratch keys written during cold
 load change — old caches will fail the version check and get
 cold-rebuilt on next _loadPresetToScratch. Single-source of truth for
 the cache layout version.

 v2: extras loader switched from hardcoded list (flash.onhit's rampms/
 decayms/retrigms only) to plugin-driven walk over GetEffectExtraField*.
 Caches written under v1 are missing shader.play's `sound` extra in the
 FX scratch namespace; bumping invalidates them so cold load re-runs
 with the plugin-driven path.}
    return 2
EndFunction

bool Function _isScratchCached(string name)
    if name == ""
        return false
    endif
    return StorageUtil.GetIntValue(None, "mtf.scratch.cached." + name + ".version", 0) == CACHED_SCRATCH_VERSION()
EndFunction

bool Function _loadScratchFromCache(string name)
{Read the cached scratch buffer for `name` from StorageUtil lists into
 the live `_s*` arrays via whole-array reference assignment. Returns
 false when no cache exists (caller falls back to cold JSON load).
 Caller is responsible for setting `_scratchLoadedFor = name` after
 this returns true.}
    if !_isScratchCached(name)
        return false
    endif
    string ck = "mtf.scratch.cached." + name
    _sCondPluginId          = StorageUtil.StringListToArray(None, ck + ".cond.pluginid")
    _sCondParam             = StorageUtil.IntListToArray(None,    ck + ".cond.param")
    _sCondPackId            = StorageUtil.StringListToArray(None, ck + ".cond.packid")
    _sCondEntryId           = StorageUtil.StringListToArray(None, ck + ".cond.entryid")
    _sCooldownMin           = StorageUtil.IntListToArray(None,    ck + ".cooldown.min")
    _sCooldownMode          = StorageUtil.IntListToArray(None,    ck + ".cooldown.mode")
    _sCondPulseRate         = StorageUtil.FloatListToArray(None,  ck + ".pulse.rate")
    _sCondPulseDepth        = StorageUtil.IntListToArray(None,    ck + ".pulse.depth")
    _sCondWaveform          = StorageUtil.StringListToArray(None, ck + ".pulse.waveform")
    _sCondLayerTint         = StorageUtil.IntListToArray(None,    ck + ".layer.tint")
    _sCondLayerEmissive     = StorageUtil.IntListToArray(None,    ck + ".layer.emissive")
    _sCondLayerEmissiveMult = StorageUtil.FloatListToArray(None,  ck + ".layer.emissivemult")
    _sCondLayerAlpha        = StorageUtil.IntListToArray(None,    ck + ".layer.alpha")
    _sTransitionDuration    = StorageUtil.GetFloatValue(None, ck + ".transition.duration", 1.0)
    _sFadeOnDeathEnabled    = StorageUtil.GetIntValue(None, ck + ".fadeondeath.enabled", 0) > 0
    _sFadeOnDeathMode       = StorageUtil.GetIntValue(None, ck + ".fadeondeath.mode", 0)
    _sFadeOnDeathDurationMs = StorageUtil.GetIntValue(None, ck + ".fadeondeath.durationms", 2000)
    return true
EndFunction

Function _saveScratchToCache(string name)
{Persist the freshly-cold-loaded `_s*` arrays into StorageUtil lists so
 the next _loadPresetToScratch(name) can hit the warm path. Called once
 per cold load at the very end of _loadPresetToScratch. Version stamp
 is written LAST so a crash mid-write leaves the cache invalid (next
 read sees version mismatch → cold rebuild) rather than partially
 populated.}
    if name == ""
        return
    endif
    string ck = "mtf.scratch.cached." + name
    StorageUtil.StringListCopy(None, ck + ".cond.pluginid",       _sCondPluginId)
    StorageUtil.IntListCopy(None,    ck + ".cond.param",          _sCondParam)
    StorageUtil.StringListCopy(None, ck + ".cond.packid",         _sCondPackId)
    StorageUtil.StringListCopy(None, ck + ".cond.entryid",        _sCondEntryId)
    StorageUtil.IntListCopy(None,    ck + ".cooldown.min",        _sCooldownMin)
    StorageUtil.IntListCopy(None,    ck + ".cooldown.mode",       _sCooldownMode)
    StorageUtil.FloatListCopy(None,  ck + ".pulse.rate",          _sCondPulseRate)
    StorageUtil.IntListCopy(None,    ck + ".pulse.depth",         _sCondPulseDepth)
    StorageUtil.StringListCopy(None, ck + ".pulse.waveform",      _sCondWaveform)
    StorageUtil.IntListCopy(None,    ck + ".layer.tint",          _sCondLayerTint)
    StorageUtil.IntListCopy(None,    ck + ".layer.emissive",      _sCondLayerEmissive)
    StorageUtil.FloatListCopy(None,  ck + ".layer.emissivemult",  _sCondLayerEmissiveMult)
    StorageUtil.IntListCopy(None,    ck + ".layer.alpha",         _sCondLayerAlpha)
    StorageUtil.SetFloatValue(None,  ck + ".transition.duration",  _sTransitionDuration)
    StorageUtil.SetIntValue(None,    ck + ".fadeondeath.enabled",  _sFadeOnDeathEnabled as int)
    StorageUtil.SetIntValue(None,    ck + ".fadeondeath.mode",     _sFadeOnDeathMode)
    StorageUtil.SetIntValue(None,    ck + ".fadeondeath.durationms", _sFadeOnDeathDurationMs)
    StorageUtil.SetIntValue(None,    ck + ".version",              CACHED_SCRATCH_VERSION())
EndFunction

Function _invalidateScratchCache(string name)
{Drop the cached scratch buffer for `name` so the next read goes through
 the cold JSON path. Clears the version flag (cheap; cache lists stay
 in StorageUtil until next save trims them but become unreadable).
 Also resets `_scratchLoadedFor` when it matches, so a subsequent
 _loadPresetToScratch(name) doesn't fast-return on the now-stale buffer.}
    if name == ""
        return
    endif
    StorageUtil.UnsetIntValue(None, "mtf.scratch.cached." + name + ".version")
    if _scratchLoadedFor == name
        _scratchLoadedFor = ""
    endif
EndFunction

bool Function _loadPresetToScratch(string name)
{Populate the scratch preset buffer from preset JSON. Skips re-load when
 already cached for `name`. Returns true on success; pass "" to clear.

 Plan B v2 caching: after the hot `name == _scratchLoadedFor` fast-return,
 checks the StorageUtil-backed cache (`_loadScratchFromCache`). On hit:
 swap `_s*` to the cached lists in ~21 *ListToArray calls (~2.5 ms) and
 we're done — no JSON, no effect-write replay (FX scratch keys are
 namespaced by preset name). On miss: full JSON cold load + final
 `_saveScratchToCache` so future swaps to this preset are warm.}
    _ensureScratchArrays()
    if name == _scratchLoadedFor
        return name != ""
    endif
    if name == ""
        _scratchLoadedFor = ""
        return false
    endif
    ; Warm cache hit — restore `_s*` from StorageUtil lists, done.
    if _loadScratchFromCache(name)
        _scratchLoadedFor = name
        return true
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
    ; Set _scratchLoadedFor early so namespaced FX scratch writers (which
    ; key on _scratchLoadedFor) write under this preset's name rather than
    ; the previously-loaded preset. The cache write at the end of cold
    ; load also relies on _scratchLoadedFor being correct.
    _scratchLoadedFor = name
    ; Per-preset cross-fade duration. Default 1.0s — a clearly-visible
    ; cinematic-feeling fade that flatters most stat-driven tier changes
    ; (the typical use case is "stat drops, tattoo glow rises" which the
    ; player should be able to track without it feeling snappy). Authors
    ; can speed it up or disable with "transition": { "duration": 0.0 }
    ; at the preset root.
    _sTransitionDuration = JsonUtil.GetPathFloatValue(f, ".transition.duration", 1.0)

    ; Per-preset fade-on-death (v0.1.4). Off when block absent.
    _sFadeOnDeathEnabled    = JsonUtil.GetPathIntValue(f, ".fadeondeath.enabled", 0) > 0
    _sFadeOnDeathMode       = JsonUtil.GetPathIntValue(f, ".fadeondeath.mode", 0)
    if _sFadeOnDeathMode < 0 || _sFadeOnDeathMode > 2
        _sFadeOnDeathMode = 0
    endif
    _sFadeOnDeathDurationMs = JsonUtil.GetPathIntValue(f, ".fadeondeath.durationms", 2000)
    if _sFadeOnDeathDurationMs < 1
        _sFadeOnDeathDurationMs = 2000
    endif
    int maxL = MAX_LAYERS_PER_SLOT()
    int maxE = MAX_EFFECTS_PER_SLOT()
    ; Build into LOCAL arrays inside the loop, then assign each whole array
    ; back to the script-level vars at the end. Indexed writes to script-
    ; level array vars on quest scripts can hit transient copies just like
    ; properties (same Papyrus quirk). Whole-array reference assignment is
    ; the only pattern that reliably persists.
    string[] localCondPluginId    = new string[8]
    int[]    localCondParam       = new int[8]
    string[] localCondPackId      = new string[8]
    string[] localCondEntryId     = new string[8]
    int[]    localCooldownMin     = new int[8]
    int[]    localCooldownMode    = new int[8]
    float[]  localPulseRate       = new float[8]
    int[]    localPulseDepth      = new int[8]
    string[] localWaveform        = new string[8]
    int[]    localLayerTint       = new int[32]
    int[]    localLayerEmissive   = new int[32]
    float[]  localLayerEmMult     = new float[32]
    int[]    localLayerAlpha      = new int[32]
    int s = 0
    while s < 8
        string sp = ".slot[" + s + "]"
        localCondPluginId[s] = JsonUtil.GetPathStringValue(f, sp + ".cond.pluginid", "")
        localCondParam[s]    = JsonUtil.GetPathIntValue(f,    sp + ".cond.param",    0)
        localCondPackId[s]   = JsonUtil.GetPathStringValue(f, sp + ".cond.packid",   "")
        localCondEntryId[s]  = JsonUtil.GetPathStringValue(f, sp + ".cond.entryid",  "")
        localCooldownMin[s]  = JsonUtil.GetPathIntValue(f,    sp + ".cooldown.min",  0)
        localCooldownMode[s] = JsonUtil.GetPathIntValue(f,    sp + ".cooldown.mode", 0)
        localPulseRate[s]    = JsonUtil.GetPathFloatValue(f,  sp + ".pulse.rate",   0.0)
        localPulseDepth[s]   = JsonUtil.GetPathIntValue(f,    sp + ".pulse.depth",  0)
        localWaveform[s]     = JsonUtil.GetPathStringValue(f, sp + ".pulse.waveform", "")
        _setScratchPulsePause(s, JsonUtil.GetPathFloatValue(f, sp + ".pulse.pause", 0.0))
        int L = 0
        while L < maxL
            int li = s * maxL + L
            string lp = sp + ".layer[" + L + "]"
            localLayerTint[li]     = _readColor(f, lp + ".tint",         16777215)
            localLayerEmissive[li] = _readColor(f, lp + ".emissive",     16777215)
            localLayerEmMult[li]   = JsonUtil.GetPathFloatValue(f, lp + ".emissivemult", 0.0)
            localLayerAlpha[li]    = JsonUtil.GetPathIntValue(f,   lp + ".alpha",        100)
            L += 1
        endwhile
        int e = 0
        while e < maxE
            string ep = sp + ".effect[" + e + "]"
            ; Scratch effect storage lives in StorageUtil under
            ; mtf.fx.scratch.<_scratchLoadedFor>.<slot>.<idx>.*. Per-preset
            ; namespacing (Plan B v2) lets the StorageUtil cache hit path
            ; skip these writes — each preset's effect bindings persist
            ; across swaps under its own key segment. Missing entries
            ; default to "" / 0.
            string effKey = JsonUtil.GetPathStringValue(f, ep + ".key", "")
            _writeFxKey(s, e, true, effKey)
            _writeFxParam(s, e, true, JsonUtil.GetPathIntValue(f, ep + ".param", 0))
            _writeFxParam2(s, e, true, JsonUtil.GetPathIntValue(f, ep + ".param2", 0))
            ; Plugin-driven extras load — walk the bound effect's declared
            ; extra fields and copy each one from JSON into the scratch
            ; namespace so GetSlotEffectExtra can read them under the
            ; dispatch scratch flag. Pre-v0.2.x this was a hardcoded list of
            ; flash.onhit's three fields (rampms/decayms/retrigms); any
            ; newly-added extras silently dropped to scratch default 0,
            ; producing "preset value ignored on apply" bugs (shader.play's
            ; `sound` toggle was the first casualty). Discovering via the
            ; plugin keeps this future-proof — adding an extra to any
            ; plugin's effect declaration automatically participates.
            if effKey != ""
                MTF_Plugin pLoadX = ResolvePluginByKey(effKey)
                if pLoadX != None
                    int itemIdxX = _effectIdxFor(pLoadX, _keyItemId(effKey))
                    if itemIdxX >= 0
                        int xN = pLoadX.GetEffectExtraFieldCount(itemIdxX)
                        int xi = 0
                        while xi < xN
                            string xname = pLoadX.GetEffectExtraFieldName(itemIdxX, xi)
                            if xname != ""
                                _loadScratchExtra(f, ep, s, e, xname)
                            endif
                            xi += 1
                        endwhile
                    endif
                endif
            endif
            e += 1
        endwhile
        s += 1
    endwhile
    ; Whole-array reference assignments — the safe pattern. (Effect arrays
    ; moved to StorageUtil scratch keys above; no array assign needed.)
    _sCondPluginId          = localCondPluginId
    _sCondParam             = localCondParam
    _sCondPackId            = localCondPackId
    _sCondEntryId           = localCondEntryId
    _sCooldownMin           = localCooldownMin
    _sCooldownMode          = localCooldownMode
    _sCondPulseRate         = localPulseRate
    _sCondPulseDepth        = localPulseDepth
    _sCondWaveform          = localWaveform
    _sCondLayerTint         = localLayerTint
    _sCondLayerEmissive     = localLayerEmissive
    _sCondLayerEmissiveMult = localLayerEmMult
    _sCondLayerAlpha        = localLayerAlpha
    ; _scratchLoadedFor was already set at the top of cold load so the
    ; namespaced FX writes above resolved correctly. Persist the
    ; just-loaded scratch into the StorageUtil cache so the next
    ; _loadPresetToScratch(name) skips the JSON work entirely.
    _saveScratchToCache(name)
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
    if !_arraysReady
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
    if !_arraysReady
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
    if !_arraysReady
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
    if !_arraysReady
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
    return GetCondPulseRate(slot)
EndFunction

int Function _g_pulseDepth(int slot, bool useScratch)
    if useScratch
        if _sCondPulseDepth == None
            return 0
        endif
        return _sCondPulseDepth[slot]
    endif
    return GetCondPulseDepth(slot)
EndFunction

float Function _g_pulsePause(int slot, bool useScratch)
    if useScratch
        return _getScratchPulsePause(slot)
    endif
    return GetCondPulsePause(slot)
EndFunction

; Per-preset cross-fade duration. Per-tier in the API for forward-compat
; (a future v0.1.x can add per-condition override under .slot[s].transition),
; but v0.1.1 just returns the preset-level value regardless of slot.
;
; The "live" path (useScratch=false) is currently unused — every caller
; reads off the scratch buffer, which is hot-loaded for the active preset.
; If we ever need a live read, plumb it through MTF.psc next to
; GetCondPulsePause.
float Function _g_transitionDuration(int slot, bool useScratch)
    if useScratch
        return _sTransitionDuration
    endif
    return 0.0
EndFunction

; MCM-bound getter/setter for the preset-level transition duration. The slider
; on the Preset editor page reads via GetTransitionDuration and writes via
; SetTransitionDuration; the value is then persisted into the active preset
; JSON by SavePreset (under .transition.duration).
float Function GetTransitionDuration()
    return _sTransitionDuration
EndFunction

Function SetTransitionDuration(float v)
    if v < 0.0
        v = 0.0
    endif
    _sTransitionDuration = v
    setRedraw()
EndFunction

; ── Preset-level fade-on-death accessors (v0.1.4) ─────────────────────────
; MCM Preset Editor binds three controls (toggle/mode/duration) to these.
; SavePreset persists them under .fadeondeath.{enabled,mode,durationms}.
; All three arming sites (_applyPulse, _rosterAddOrUpdate) read the script
; vars directly — no caching layer needed, the vars themselves are the
; live source of truth for the scratch-loaded preset.

bool Function GetFadeOnDeathEnabled()
    return _sFadeOnDeathEnabled
EndFunction

Function SetFadeOnDeathEnabled(bool v)
    _sFadeOnDeathEnabled = v
    ; Force a pulse-cache resync against the current tier so the roster
    ; entry survives even when the only reason to keep it alive is fade
    ; (no pulse, no flash). Without this, toggling fade ON for a pulse-
    ; less preset would leave _pulseTier=-1 and _applyPulse early-out,
    ; never calling SetActorFade.
    if currentTier >= 0
        _resyncPulseCache(currentTier)
        _applyPulse()
    endif
    setRedraw()
EndFunction

int Function GetFadeOnDeathMode()
    return _sFadeOnDeathMode
EndFunction

Function SetFadeOnDeathMode(int v)
    if v < 0 || v > 2
        v = 0
    endif
    _sFadeOnDeathMode = v
    if _sFadeOnDeathEnabled && currentTier >= 0
        _applyPulse()
    endif
EndFunction

int Function GetFadeOnDeathDurationMs()
    return _sFadeOnDeathDurationMs
EndFunction

Function SetFadeOnDeathDurationMs(int v)
    if v < 1
        v = 1
    endif
    _sFadeOnDeathDurationMs = v
    if _sFadeOnDeathEnabled && currentTier >= 0
        _applyPulse()
    endif
EndFunction

; Console-callable diagnostic — bypasses the unreliable player.kill path
; (player is essential, TESDeathEvent often doesn't fire) by directly
; invoking the C++ fade trigger on the player's OverlaySlot. Call via
;   cqf MTF DebugFireFade
; (where MTF is the quest's editor ID) to verify SetActorFade arming and
; Tick interpolation are working independently of the death-event sink.
Function DebugFireFade()
    if PlayerRef == None
        Debug.Notification("[MTF fade] DebugFireFade: no PlayerRef")
        return
    endif
    MTFPulse.TriggerActorFade(PlayerRef, OverlaySlot, 0)
    Debug.Notification("[MTF fade] DebugFireFade fired against OverlaySlot=" + OverlaySlot)
EndFunction

; Recovery from stuck-alpha state. If the player's tattoo ends up invisible
; — typically because fade was triggered (player death event fired during
; bleedout / godmode testing / DebugFireFade) and the animation's final
; alpha=0 frame stuck in NiOverride after the entry self-evicted — call:
;   cqf MTF DebugRestorePlayerOverlay
; This clears any in-flight fade, drops the roster entry, and forces a
; full redraw so _drawOverlayForActorAt re-writes alpha to the configured
; per-tier value.
Function DebugRestorePlayerOverlay()
    if PlayerRef == None
        Debug.Notification("[MTF] DebugRestorePlayerOverlay: no PlayerRef")
        return
    endif
    MTFPulse.ClearActorFade(PlayerRef, OverlaySlot, 0)
    MTFPulse.ClearActorAt(PlayerRef, OverlaySlot, 0)
    setRedraw()
    Debug.Notification("[MTF] Player overlay restore requested — redraw next tick")
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

; _g_effectKey/Param/Param2 removed in v0.1.5 — effect storage moved to
; StorageUtil. Call sites now use _readFxKey/Param/Param2(slot, idx, useScratch)
; directly with the natural (slot, idx) shape instead of a flat fxIdx.

; ── Generalized eval + effect dispatch ──────────────────────────────────────
int Function _quickEvalCondsFromJson(Actor target, string presetName)
{Fast scratch-free tier evaluator. Reads cond.pluginid / cond.param /
 cooldown.mode directly from the preset JSON, dispatches checkCondition,
 and returns the winning slot — same semantics as
 evaluateTierForActor(target, presetName, true) but without the
 ~480ms _loadPresetToScratch round-trip. Used by the slow-tick pre-eval
 pass to capture every loaded preset's target tier atomically before any
 apply work runs, so multi-preset cross-fades don't staircase because
 slot 2's eval saw an AV that already shifted during slot 1's apply.

 Always uses the scratch-path evalParam2 = 0 convention (stacked presets
 don't carry param2). Cooldowns are read via _getActorPresetCooldown,
 which is actor-keyed and doesn't touch scratch. Returns 0 on any
 failure path (no preset file, killed actor, no matching slot).}
    if target == None || presetName == ""
        return 0
    endif
    if _getActorKilled(target)
        return 0
    endif
    string f = _presetFile(presetName)
    if !JsonUtil.JsonExists(f)
        return 0
    endif
    float now = Utility.GetCurrentGameTime()
    int i = 1
    while i < 8
        string sp = ".slot[" + i + "]"
        string key = JsonUtil.GetPathStringValue(f, sp + ".cond.pluginid", "")
        if key != ""
            float cdEnd = _getActorPresetCooldown(target, presetName, i)
            bool timerActive = (now < cdEnd)
            int mode = JsonUtil.GetPathIntValue(f, sp + ".cooldown.mode", 0)
            if mode == 1 && timerActive
                return i
            endif
            bool inCooldown = (mode == 0 && timerActive)
            if !inCooldown
                MTF_Plugin p = ResolvePluginByKey(key)
                if p != None
                    int itemIdx = _condIdxFor(p, _keyItemId(key))
                    if itemIdx >= 0
                        int param = JsonUtil.GetPathIntValue(f, sp + ".cond.param", 0)
                        ; Stacked presets always use scratch path → evalParam2 = 0.
                        _setEvalParam2(0)
                        if p.checkCondition(itemIdx, target, param)
                            return i
                        endif
                    endif
                endif
            endif
        endif
        i += 1
    endwhile
    return 0
EndFunction

int Function evaluateTierForActor(Actor target, string presetName, bool useScratch)
{Evaluate the winning condition slot for `target`. When useScratch is true,
 the per-(actor, preset, slot) cooldown is consulted via presetName; when
 false, the player's own cooldownUntilGT array is consulted (presetName is
 ignored).}
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
                cdEnd = _getActorPresetCooldown(target, presetName, i)
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
                    if itemIdx >= 0
                        ; Param2: only wired for the player path (non-scratch).
                        ; NPC tracked-subject scratch presets don't carry
                        ; param2 yet — reset to 0 so a stale value can't leak.
                        if useScratch
                            _setEvalParam2(0)
                        else
                            _setEvalParam2(GetCondParam2(i))
                        endif
                        if p.checkCondition(itemIdx, target, _g_condParam(i, useScratch))
                            return i
                        endif
                    endif
                endif
            endif
        endif
        i += 1
    endwhile
    return 0
EndFunction

Function _activateSlotEffectsForActor(Actor target, int slot, bool useScratch, string presetName = "")
{`presetName` lets the dispatch resolve the actor's actual base overlay
 slot via _getActorPresetBase. NPCs (and stacked player presets) need
 this — h.OverlaySlot is the player's MCM-managed primary slot, wrong for
 every other case. Optional / empty string falls back to OverlaySlot via
 _getDispatchBaseSlot's fallback, preserving the player single-preset
 behaviour for callers that haven't been updated.}
    if target == None || slot < 0 || slot >= 8
        return
    endif
    _setDispatchBaseSlot(_resolveDispatchBaseSlot(target, presetName))
    _setDispatchUseScratch(useScratch)
    int maxE = MAX_EFFECTS_PER_SLOT()
    ; SNAPSHOT before dispatch — see _deactivateSlotEffectsForActor for
    ; the full race-rationale comment. Short version: each p.onActivate is
    ; a cross-script call that suspends our VM; during the suspension the
    ; slow-tick can interleave and call _loadPresetToScratch(otherName),
    ; rebinding the script-level _scratchLoadedFor. Without this snapshot,
    ; subsequent _readFxKey/Param/Param2 calls read from the wrong preset's
    ; scratch namespace and silently skip/mis-dispatch the remaining
    ; effects.
    string[] keys    = Utility.CreateStringArray(maxE, "")
    int[]    params  = Utility.CreateIntArray(maxE, 0)
    int[]    params2 = Utility.CreateIntArray(maxE, 0)
    int e = 0
    while e < maxE
        keys[e]    = _readFxKey(slot, e, useScratch)
        params[e]  = _readFxParam(slot, e, useScratch)
        params2[e] = _readFxParam2(slot, e, useScratch)
        e += 1
    endwhile
    e = 0
    while e < maxE
        string key = keys[e]
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _setDispatchContext(slot, e)
                    p.onActivate(itemIdx, target, params[e], params2[e])
                    _emitEffectActivated(target, key, slot)
                endif
            endif
        endif
        e += 1
    endwhile
    _clearDispatchContext()
EndFunction

Function _deactivateSlotEffectsForActor(Actor target, int slot, bool useScratch, string presetName = "")
    if target == None || slot < 0 || slot >= 8
        return
    endif
    _setDispatchBaseSlot(_resolveDispatchBaseSlot(target, presetName))
    _setDispatchUseScratch(useScratch)
    int maxE = MAX_EFFECTS_PER_SLOT()
    ; SNAPSHOT effect bindings into locals BEFORE the dispatch loop. Each
    ; p.onDeactivate is a cross-script call that suspends our VM thread.
    ; During the suspension the slow-tick can interleave on a different
    ; thread and call _loadPresetToScratch(otherName) — this rebinds the
    ; script-level _scratchLoadedFor. When our loop resumes, the next
    ; _readFxKey(slot, e, useScratch=true) reads from the WRONG preset's
    ; namespace ("mtf.fx.scratch.<otherName>.<slot>.<e>.key") and either
    ; returns "" (we skip the rest of OUR preset's effects) or a stale
    ; key from the other preset (we dispatch the wrong onDeactivate).
    ;
    ; Snapshotting all 32 bindings via SKSE-native StorageUtil reads
    ; before any suspending call eliminates the race: the snapshot phase
    ; is atomic (no suspends), and the dispatch phase reads from local
    ; arrays that no other thread can mutate.
    ;
    ; Symptom this fixes (2026-05-21): 17-effect Test_Modifies_Skills
    ; preset only reverts ~3 skills on RemoveAppliedPreset; the rest
    ; stay shifted forever because their _readFxKey returned "" from a
    ; clobbered _scratchLoadedFor namespace.
    string[] keys    = Utility.CreateStringArray(maxE, "")
    int[]    params  = Utility.CreateIntArray(maxE, 0)
    int[]    params2 = Utility.CreateIntArray(maxE, 0)
    int e = 0
    while e < maxE
        keys[e]    = _readFxKey(slot, e, useScratch)
        params[e]  = _readFxParam(slot, e, useScratch)
        params2[e] = _readFxParam2(slot, e, useScratch)
        e += 1
    endwhile
    e = 0
    while e < maxE
        string key = keys[e]
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _setDispatchContext(slot, e)
                    p.onDeactivate(itemIdx, target, params[e], params2[e])
                    _emitEffectDeactivated(target, key, slot)
                endif
            endif
        endif
        e += 1
    endwhile
    _clearDispatchContext()
EndFunction

Function _tickSlotEffectsForActor(Actor target, int slot, bool useScratch, string presetName = "")
    if target == None || slot < 0 || slot >= 8
        return
    endif
    _setDispatchBaseSlot(_resolveDispatchBaseSlot(target, presetName))
    _setDispatchUseScratch(useScratch)
    int maxE = MAX_EFFECTS_PER_SLOT()
    ; SNAPSHOT before dispatch — see _deactivateSlotEffectsForActor for
    ; the race-rationale. _scratchLoadedFor gets clobbered by interleaved
    ; _loadPresetToScratch calls during suspending p.onTick dispatches.
    string[] keys    = Utility.CreateStringArray(maxE, "")
    int[]    params  = Utility.CreateIntArray(maxE, 0)
    int[]    params2 = Utility.CreateIntArray(maxE, 0)
    int e = 0
    while e < maxE
        keys[e]    = _readFxKey(slot, e, useScratch)
        params[e]  = _readFxParam(slot, e, useScratch)
        params2[e] = _readFxParam2(slot, e, useScratch)
        e += 1
    endwhile
    e = 0
    while e < maxE
        string key = keys[e]
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _setDispatchContext(slot, e)
                    p.onTick(itemIdx, target, params[e], params2[e])
                endif
            endif
        endif
        e += 1
    endwhile
    _clearDispatchContext()
EndFunction

int Function _resolveDispatchBaseSlot(Actor target, string presetName)
{Pick the right base overlay slot for the dispatch. NPCs and stacked
 player presets use the per-preset base. Old single-preset player paths
 (and any caller passing an empty name) get OverlaySlot — the MCM-managed
 default. Returns OverlaySlot as the safe last resort.}
    if target == None
        return OverlaySlot
    endif
    if presetName == ""
        ; Player old-path — expected, silent.
        return OverlaySlot
    endif
    int v = _getActorPresetBase(target, presetName, "Body")
    if v < 0
        return OverlaySlot
    endif
    return v
EndFunction

; ── Per-preset eval + draw cycle ────────────────────────────────────────────
bool Function _evalAndDrawPresetForActor(Actor target, string name, bool deferApply = false)
{One preset's eval+draw cycle on a target. Caller must already have run
 _loadPresetToScratch(name). Fires tier transition edges, arms cooldowns,
 stamps the overlay at the preset's stored base/layers, and updates the
 pulse roster (one-pulse-per-actor on the C++ side — last transition wins).

 Returns true if the tier-change branch was taken (i.e. an overlay was
 stamped via _drawPresetOnActor). Same-tier same-frame calls return false.
 With `deferApply=true`, _drawPresetOnActor skips its trailing
 ApplyNodeOverrides — the caller is responsible for issuing one Apply
 after batching multiple presets, so all stacked tattoos light up in the
 same frame instead of staircasing 0.5s apart (one expensive Apply per
 preset on a moderately stacked character).

 Stacked-preset cross-fade synchronization (v0.1.7): callers running a
 multi-preset loop should wrap it in MTFPulse.BeginTransitionBatch /
 EndTransitionBatch — that pins ONE shared transition_start across every
 roster Set queued during the batch so all stacked transitions lerp in
 lockstep regardless of how long the per-preset Papyrus work between
 Sets takes. See slow-tick player loop for the canonical pattern.}
    if target == None || name == ""
        return false
    endif
    int prev = _getActorPresetTier(target, name)
    int now  = evaluateTierForActor(target, name, true)
    return _applyPresetTierChange(target, name, prev, now, deferApply)
EndFunction

bool Function _evalAndDrawPresetForActorWithKnownTier(Actor target, string name, int newTier, bool deferApply = false)
{Variant of _evalAndDrawPresetForActor that uses a pre-computed `newTier`
 instead of running evaluateTierForActor again. Used by the slow-tick
 pre-eval pass (Plan A v0.2) to apply tier changes against a snapshot
 taken atomically before any apply work began — without this, multi-preset
 transitions can staircase because slot 2's eval reads an AV that already
 shifted past the threshold during slot 1's apply. Same precondition as
 _evalAndDrawPresetForActor: caller must have already run
 _loadPresetToScratch(name).}
    if target == None || name == ""
        return false
    endif
    int prev = _getActorPresetTier(target, name)
    return _applyPresetTierChange(target, name, prev, newTier, deferApply)
EndFunction

bool Function _applyPresetTierChange(Actor target, string name, int prev, int now, bool deferApply)
{Shared body for both _evalAndDrawPresetForActor (self-eval) and
 _evalAndDrawPresetForActorWithKnownTier (pre-eval). Handles the tier
 transition edge — deactivate prev effects, update roster, draw, activate
 new effects, fire notification — plus the same-tier per-tick effect pulse.
 Caller is responsible for scratch load.}
    float rtNow = Utility.GetCurrentRealTime()
    bool drew = false
    if now != prev
        if prev >= 0
            _deactivateSlotEffectsForActor(target, prev, true, name)
            if _g_cooldownMode(prev, true) == 0
                int mins = _g_cooldownMin(prev, true)
                if mins > 0
                    _setActorPresetCooldown(target, name, prev, Utility.GetCurrentGameTime() + (mins as float) / 1440.0)
                endif
            endif
        endif
        ; CRITICAL ORDER: update the C++ pulse roster FIRST, then stamp
        ; the new tier's visuals. The C++ hot path writes emissive directly
        ; to the live NiAVObject (bypassing the override layer), so its
        ; last frame's write would persist past a deactivation if we
        ; cleared after stamping — leaving the slot stuck at whatever
        ; pulse phase happened to be active. Stamping AFTER the clear
        ; means Papyrus's ApplyNodeOverrides is the final write to the
        ; live node, which puts the slot in the right resting state.
        ;
        ; v0.1.1 cross-fade: we now ALWAYS forward to _rosterAddOrUpdate
        ; when a tier is selected (now >= 0), even for tier 0 / no-pulse
        ; tiers. The C++ roster owns the from-state needed to lerp
        ; alpha/tint/em_mult across the tier boundary; if we destroyed
        ; the entry on the way down (tier 1 → 0), there'd be nothing for
        ; the next tier-up to fade from, and the way-down itself would
        ; snap to off because Papyrus's stamp here is the final write
        ; before any C++ Tick gets to run the fade. Rate=0 / depth=0
        ; entries cost ~4 SetNodeProperty calls per frame writing the
        ; ceiling value (zero for off tiers) — negligible at production
        ; roster sizes.
        _setActorPresetTier(target, name, now)
        _setActorPresetPulseStartRT(target, name, rtNow)
        if now >= 0
            _rosterAddOrUpdate(target, name, now, rtNow)
        else
            _rosterRemovePreset(target, name)
        endif
        _drawPresetOnActor(target, name, now, deferApply)
        drew = true
        if now >= 0
            _activateSlotEffectsForActor(target, now, true, name)
            if _g_cooldownMode(now, true) == 1
                int mins2 = _g_cooldownMin(now, true)
                if mins2 > 0
                    _setActorPresetCooldown(target, name, now, Utility.GetCurrentGameTime() + (mins2 as float) / 1440.0)
                endif
            endif
        endif
        _notifyTierChangeForActor(target, now, true)
        ; v0.1.20: external-integration broadcast for NPC preset tiers.
        _emitTierChanged(target, "preset", name, prev, now)
    endif
    ; Same-tier path used to re-stamp the overlay every eval to handle the
    ; "freshly applied" edge. With AddAppliedPreset initializing tier=-1,
    ; the first eval always takes the change branch above; subsequent
    ; same-tier eval calls don't need to re-stamp. Constant re-stamping at
    ; the poll cadence (10 Hz on default updateInterval) was causing
    ; visible flicker — every ApplyNodeOverrides triggers a full overlay
    ; rebuild and fights the C++ pulse hot path that owns the emissive
    ; channel between Papyrus stamps.
    if now >= 0
        _tickSlotEffectsForActor(target, now, true, name)
    endif
    return drew
EndFunction

; ── Console smoke-test entry ────────────────────────────────────────────────
Function EvalAndDrawActor(Actor target)
{Iterate every applied preset on `target` and run the per-preset eval+draw
 cycle. Useful from the console after an Apply Tattoo cast.}
    if target == None
        if DebugMode
            Notification("MTF: EvalAndDrawActor: None target")
        endif
        return
    endif
    int n = GetActorPresetCount(target)
    if n <= 0
        if DebugMode
            Notification("MTF: target has no applied presets")
        endif
        return
    endif
    int i = 0
    bool needApply = false
    ; Roster batch — see slow-tick player loop comment for the why.
    MTFPulse.BeginTransitionBatch()
    while i < n
        string nm = GetActorPresetAt(target, i)
        if nm != "" && _loadPresetToScratch(nm)
            if _evalAndDrawPresetForActor(target, nm, true)
                needApply = true
            endif
        endif
        i += 1
    endwhile
    MTFPulse.EndTransitionBatch()
    if needApply
        NiOverride.ApplyNodeOverrides(target)
    endif
EndFunction

; ═════════════════════════════════════════════════════════════════════════════
; NPC PULSE ROSTER + SLOW-TICK ROTATION (v0.0.33 step 5)
; ═════════════════════════════════════════════════════════════════════════════

; ── Roster: C++ owns it, Papyrus is just a forwarder ───────────────────────
; The MTFPulse C++ plugin keys entries by (actor formID, base_overlay_slot),
; so an actor with N stacked presets registers N distinct entries — each
; pulses its own disjoint NiOverride slot range. Capacity is whatever the
; C++ plugin sets (kCapacity in pulse_roster.h). Eviction (farthest-from-
; player) lives in C++ too, so we no longer need to mirror state in Papyrus
; just to track who's "on the roster."
;
; The old _rosterActor[]/_rosterPulse*[]/_rosterCount Auto Hidden properties
; remain declared above for save-compat; they are simply not written to.

Function _rosterRemovePreset(Actor a, string name)
{Clear the C++ pulse entry for ONE preset on actor `a`. v0.1.17 Phase 3
 (multi-area): loops every area's reservation since a single preset can
 push entries into multiple area pools when it mixes body/face/hand/feet
 packs across its 8 condition slots. Safe to call with a None / unknown
 preset; just no-ops.}
    if a == None || name == ""
        return
    endif
    string[] parts = _OVERLAY_PARTS()
    int p = 0
    while p < parts.Length
        string area = parts[p]
        int b = _getActorPresetBase(a, name, area)
        if b >= 0
            MTFPulse.ClearActorAt(a, b, _areaIndex(area))
        endif
        p += 1
    endwhile
EndFunction

int Function _areaIndex(string area) global
{Papyrus<->C++ area encoding: "Body"=0, "Face"=1, "Hands"=2, "Feet"=3.
 (SKEE node names are pluralised for Hands and Feet — see _OVERLAY_PARTS.)
 Unknown → 0 (Body) — same fallback as the C++ NormArea normaliser.}
    if area == "Face"
        return 1
    elseif area == "Hands"
        return 2
    elseif area == "Feet"
        return 3
    endif
    return 0
EndFunction

Function _rosterRemoveActor(Actor a)
{Clear ALL pulse entries the actor owns (every base_slot). Use on death,
 unload, or untracking — anything that says "this actor should pulse on
 nothing anymore."}
    if a == None
        return
    endif
    MTFPulse.ClearActor(a)
EndFunction

Function _rosterAddOrUpdate(Actor a, string name, int tier, float startRT)
{Snapshot the preset's tier params and push to the MTFPulse C++ roster,
 keyed by (a, preset's stored base_slot). Caller must have
 _loadPresetToScratch(name) loaded so the _g_* readers see this preset's
 cond/layer/pulse data.

 v0.1.1 cross-fade: this also handles no-pulse tiers (rate=0 or depth=0),
 forwarding them to the C++ roster with rate=0 so the per-frame Tick keeps
 the cross-fade lerp running on em/alpha/tint. Without this path, tier
 1→0 transitions snap because the C++ entry that held the from-state gets
 destroyed before any lerp frame runs. The cost of an idle (rate=0) entry
 is ~4 SetNodeProperty writes per frame of a constant value — trivial.

 Only no-ops (and clears any existing per-preset entry) when the preset
 has no visual layers for this tier — i.e. tier resolves to no overlay.

 Stacked-preset sync (v0.1.7): callers wrap their multi-preset loop in
 MTFPulse.BeginTransitionBatch / EndTransitionBatch — every Set() between
 the two queues into the C++ pending list and they're all installed at
 once with a single shared transition_start at EndBatch. Nothing extra
 is needed here.}
    if a == None || name == "" || tier < 0 || tier >= 8
        return
    endif
    ; v0.1.17 Phase 3 (multi-area): a preset can paint across multiple area
    ; pools (a face pack in slot 0 + body packs in slots 1..7 produces
    ; reservations for BOTH "Face" and "Body"). Iterate parts and push one
    ; roster entry per area-with-reservation. The tier's picked pack
    ; determines which area's reservation actually carries this tier's
    ; texture — entries for other areas paint nothing for this tier
    ; (layerN=0 → ClearActorAt branch) but stay registered so a future
    ; tier whose pack matches THEIR area finds a live entry.
    string packId  = _g_resolvePackId(tier, true)
    string entryId = _g_resolveEntryId(tier, true)
    string activeArea = ""
    if packId != "" && packId != "<none>" && entryId != ""
        activeArea = GetPackArea(packId)
    endif
    float rate  = _g_pulseRate(tier, true)
    int   depth = _g_pulseDepth(tier, true)
    Float[] lut = _waveformLUTForTier(tier, true)
    Float   tDur = _g_transitionDuration(tier, true)
    int maxL = MAX_LAYERS_PER_SLOT()
    bool isFemale = a.GetLeveledActorBase().GetSex() as bool

    string[] parts = _OVERLAY_PARTS()
    int p = 0
    while p < parts.Length
        string area = parts[p]
        int baseSlot = _getActorPresetBase(a, name, area)
        if baseSlot >= 0
            int areaIdx = _areaIndex(area)
            int layerN = 0
            if area == activeArea && packId != "" && packId != "<none>" && entryId != ""
                layerN = GetEntryLayerCount(packId, entryId)
                int reserved = _getActorPresetLayers(a, name, area)
                if layerN > reserved
                    layerN = reserved
                endif
                if layerN > maxL
                    layerN = maxL
                endif
            endif
            if layerN <= 0
                ; This area has a reservation but the tier's pack lives in a
                ; different area. Clear any stale entry so the C++ roster
                ; doesn't pulse a slot that should be tier-empty.
                MTFPulse.ClearActorAt(a, baseSlot, areaIdx)
            else
                Float[] emMults   = Utility.CreateFloatArray(layerN)
                Int[]   tints     = Utility.CreateIntArray(layerN)
                Int[]   alphas    = Utility.CreateIntArray(layerN)
                Int[]   emissives = Utility.CreateIntArray(layerN)
                int L = 0
                while L < layerN
                    int li = tier * maxL + L
                    emMults[L]   = _g_layerEmissiveMult(li, true)
                    tints[L]     = _g_layerTint(li, true)
                    alphas[L]    = _g_layerAlpha(li, true)
                    emissives[L] = _g_layerEmissive(li, true)
                    L += 1
                endwhile
                ; SetActorPulseWithTransition is a strict superset of
                ; SetActorPulse: with tDur <= 0 it behaves identically
                ; (instant snap, no cross-fade). Calling it unconditionally
                ; keeps the C++ side aware of the target alpha/tint/emissive
                ; at all times — see v0.1.1 design notes preserved below.
                MTFPulse.SetActorPulseWithTransition(a, rate, depth, _g_pulsePause(tier, true), \
                                                     layerN, startRT, emMults, \
                                                     baseSlot, isFemale, lut, \
                                                     tints, alphas, emissives, tDur, \
                                                     areaIdx)
                ; v0.1.4 per-preset fade-on-death: arm the fade lane on the
                ; roster entry. _sFadeOnDeath* state was loaded from the
                ; scratch-loaded preset's .fadeondeath block by the caller.
                if _sFadeOnDeathEnabled
                    MTFPulse.SetActorFade(a, baseSlot, _sFadeOnDeathMode, _sFadeOnDeathDurationMs, areaIdx)
                    if DebugMode
                        Debug.Notification("[MTF fade] armed " + a.GetDisplayName() + " area=" + area + " slot=" + baseSlot + " mode=" + _sFadeOnDeathMode)
                    endif
                else
                    MTFPulse.ClearActorFade(a, baseSlot, areaIdx)
                endif
            endif
        endif
        p += 1
    endwhile
EndFunction

; ── Tracked actor evaluation (full pass — Step 6 adds stagger + distance) ──
int _rotIdx = 0

Function _processTrackedActorOnce(Actor target)
{Eval, draw, lifecycle one tracked actor. Updates roster membership for
 pulse on tier transition. Step 6 gates: skip when suspended (cell detach),
 killed, missing 3D, or farther than SUBJECT_EVAL_RADIUS from the player.
 Out-of-range actors that have an active pulse roster slot stay on the
 roster — the pulse hot path issues NiOverride writes regardless of
 visibility and the cost per slot is trivial. They get evicted on tier
 transition or by the farthest-from-player eviction rule.}
    if target == None
        return
    endif
    if _getActorSuspended(target)
        return
    endif
    if _getActorKilled(target)
        return
    endif
    if !target.Is3DLoaded()
        ; Treat unloaded actors as suspended even if we missed the
        ; OnObjectUnloaded event (e.g. registration was set up after
        ; the actor already unloaded).
        _setActorSuspended(target, true)
        _rosterRemoveActor(target)
        return
    endif
    if PlayerRef != None && target.GetDistance(PlayerRef) > SUBJECT_EVAL_RADIUS()
        return
    endif
    int n = GetActorPresetCount(target)
    if n <= 0
        return
    endif
    int i = 0
    bool needApply = false
    ; Roster batch — see slow-tick player loop comment for the why.
    MTFPulse.BeginTransitionBatch()
    while i < n
        string nm = GetActorPresetAt(target, i)
        if nm != "" && _loadPresetToScratch(nm)
            if _evalAndDrawPresetForActor(target, nm, true)
                needApply = true
            endif
        endif
        i += 1
    endwhile
    MTFPulse.EndTransitionBatch()
    if needApply
        NiOverride.ApplyNodeOverrides(target)
    endif
EndFunction

Function _processTrackedActorsSlowTick(int maxThisTick)
{Round-robin walk of the tracked list. Up to maxThisTick actors get
 evaluated per call. State persists across calls via _rotIdx, so a long
 list eventually completes a full sweep over multiple slow ticks.
 maxThisTick <= 0 means "all of them this tick" (Step 5 baseline).}
    int total = GetTrackedCount()
    if total <= 0
        return
    endif
    if maxThisTick <= 0
        maxThisTick = total
    elseif maxThisTick > total
        maxThisTick = total
    endif
    if _rotIdx < 0 || _rotIdx >= total
        _rotIdx = 0
    endif
    int processed = 0
    int idx = _rotIdx
    while processed < maxThisTick
        Actor a = GetTrackedAt(idx)
        if a == None
            ; Stale FormList entry. Drop and shift rotation.
            StorageUtil.FormListRemoveAt(self, "mtf.tracked", idx)
            total = GetTrackedCount()
            if total <= 0
                _rotIdx = 0
                return
            endif
            if idx >= total
                idx = 0
            endif
        else
            _processTrackedActorOnce(a)
            idx += 1
            if idx >= total
                idx = 0
            endif
            processed += 1
        endif
    endwhile
    _rotIdx = idx
EndFunction

; ══════════════════════════════════════════════════════════════════════════
; EXTERNAL INTEGRATION EVENTS (v0.1.20)
; ══════════════════════════════════════════════════════════════════════════
; Universal mod events fired at well-defined transition points so third-
; party integrations (LLM-driven NPCs, MCM mirrors, dialogue mods) can
; react to tattoo state without polling.
;
; Quest scripts cannot call SendModEvent (Alias/AMF only) — use the global
; ModEvent.Create/Push/Send API. Listeners register with:
;   RegisterForModEvent("MTF_TierChanged", "OnMTFTierChanged")
;   Event OnMTFTierChanged(string strArg, float numArg, Form sender)
;
; The (string, float, Form) signature matches SkyrimNet's YAML trigger
; event-criteria fields (str_arg, num_arg, sender_form_id) so a SkyrimNet
; user can author triggers against MTF events with zero Papyrus glue.
;
; ── EVENT CATALOG ──
;
;   MTF_FrameworkReady
;     Fires once per save load, after at least one plugin has registered.
;     str  = "<version>|<pluginCount>"          e.g. "0.1.20|5"
;     num  = pluginCount as float
;     sender = self (MTF_MainQuest)
;
;   MTF_TierChanged
;     Fires every time a slot/preset transitions between tiers. Includes
;     transitions to/from tier -1 (no slot winning). Fires AFTER the new
;     tier's onActivate effects have run, so a listener calling back into
;     MTF sees the new state.
;     str  = "<scope>|<presetName>|<prevTier>|<newTier>"
;            scope = "player" | "preset"  (player slots vs. NPC presets)
;            presetName = "" for player, preset name for NPC
;     num  = newTier as float
;     sender = the actor (PlayerRef or NPC)
;
;   MTF_EffectActivated  /  MTF_EffectDeactivated
;     Fires once per individual effect on tier transitions. A 3-effect tier
;     fires 3 events. Listeners that only care about ANY-effect transitions
;     can dedupe on MTF_TierChanged instead.
;     str  = "<pluginId>:<effectId>|<slot>"     e.g. "mtf.base:modify.magickaRegen|3"
;     num  = slot as float
;     sender = the actor (PlayerRef or NPC)

string Function MTF_VERSION() global
    return "0.1.20"
EndFunction

Function _emitFrameworkReady()
    if _readyEmitted || pluginCount <= 0
        return
    endif
    int h = ModEvent.Create("MTF_FrameworkReady")
    if h == 0
        return
    endif
    ModEvent.PushString(h, MTF_VERSION() + "|" + pluginCount)
    ModEvent.PushFloat(h, pluginCount as float)
    ModEvent.PushForm(h, self as Form)
    ModEvent.Send(h)
    _readyEmitted = true
EndFunction

Function _emitTierChanged(Actor target, string scope, string presetName, int prevTier, int newTier)
    if target == None
        return
    endif
    int h = ModEvent.Create("MTF_TierChanged")
    if h == 0
        return
    endif
    ModEvent.PushString(h, scope + "|" + presetName + "|" + prevTier + "|" + newTier)
    ModEvent.PushFloat(h, newTier as float)
    ModEvent.PushForm(h, target as Form)
    ModEvent.Send(h)
EndFunction

Function _emitEffectActivated(Actor target, string key, int slot)
    if target == None || key == ""
        return
    endif
    int h = ModEvent.Create("MTF_EffectActivated")
    if h == 0
        return
    endif
    ModEvent.PushString(h, key + "|" + slot)
    ModEvent.PushFloat(h, slot as float)
    ModEvent.PushForm(h, target as Form)
    ModEvent.Send(h)
EndFunction

Function _emitEffectDeactivated(Actor target, string key, int slot)
    if target == None || key == ""
        return
    endif
    int h = ModEvent.Create("MTF_EffectDeactivated")
    if h == 0
        return
    endif
    ModEvent.PushString(h, key + "|" + slot)
    ModEvent.PushFloat(h, slot as float)
    ModEvent.PushForm(h, target as Form)
    ModEvent.Send(h)
EndFunction
