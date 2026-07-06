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

; ── Per-slot arrays (index 0 = Default, 1-MAX_CONDITIONS_MCM = MCM conds) ───
; condPluginId / condParam moved to StorageUtil (mtf.cond.pluginid.<slot> /
; mtf.cond.param.<slot>) in v0.2.7 -- decoupled backend cap (MAX_CONDITIONS,
; 32) from MCM cap (MAX_CONDITIONS_MCM, 7). Same escape from Auto-property
; attachment hell as the v0.1.5 effect refactor. Access via the
; Get/SetCondPluginId / Get/SetCondParam wrappers below.
; v0.2.8: condPackId, condEntryId, condLayerTint/Emissive/EmissiveMult/Alpha
; lifted off Auto array properties to StorageUtil. Access via GetCondPackId /
; SetCondPackId / GetCondLayerTint(slot, L) / SetCondLayerTint(slot, L, v) etc.
; (see the unified per-slot block below the pulse accessors). Same motivation
; as the v0.2.7 cond.pluginid migration — every backend slot (1..MAX_CONDITIONS)
; gets the same access path as the MCM-cap 8, no dual-track. VMAD inspection
; confirmed these props weren't CK-exposed, so deleting the declarations
; doesn't trigger project_vmad_stale_property_reattach.
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
; v6: the _sCond* per-slot scratch arrays were removed — all scratch cond /
; layer / pulse state now lives in per-preset namespaced StorageUtil keys (see
; the _getScratch* / _setScratch* accessors). Removing script vars is save-safe
; (the reverse of the array-widen crash that froze them at length 8); existing
; saves discard the orphaned array data on load.
; v0.2.6: Bool sentinel for the _s* scratch arrays. Per memory note
; project_papyrus_array_none_cast_noise, `if arr == None` checks on
; script-level arrays log "Cannot cast from None to T[]" EVEN WHEN
; allocated. Each error is a sync-disk stack trace; ~150 errors per
; preset eval was costing real frame time. _sArraysReady is set true
; once after _ensureScratchArrays allocates, and all accessors gate
; on it instead of the spurious == None check.
bool     _sArraysReady = false
; _sEffectKey/Param/Param2 removed in v0.1.5 — scratch effect bindings
; now live in StorageUtil under mtf.fx.scratch.<slot>.<idx>.* (parallel to
; the player live keyspace mtf.fx.<slot>.<idx>.*).
; v0.1.24 cooldown rework: same storage, new semantics.
; _sCooldownMin   → semantically "persistMin"   (how long slot stays active after firing)
; _sCooldownMode  → semantically "allowOverride" (1 = higher-priority slots can take over during
;                                                  persist, 0 = locked — was 1=lock, 0=after-deact)
; New "cool" durations (post-persist re-arm lockout) live under per-preset StorageUtil keys —
; see _getScratchCoolMin / _setScratchCoolMin. Vars renamed only in comment; Papyrus vars keep
; their physical names to preserve save attachment.
; v6: _sCooldownMin / _sCooldownMode (persistMin / allowOverride) likewise moved
; to per-preset StorageUtil keys — see _get/_setScratchPersistMin and
; _get/_setScratchAllowOverride.
; Per-preset cross-fade duration (seconds) read from .transition.duration
; in the preset JSON. Applies to ALL tier transitions on this preset. <=0
; disables cross-fade (instant snap). Per-tier override is a v0.1.2+
; candidate; v0.1.1 ships per-preset only.
float    _sTransitionDuration = 0.0
; v0.1.28 V4 cross-fade: absolute real-time at which the current cross-fade
; ends. `_applyPulse` passes (end - now) as tDur to SetActorPulseWithTransition
; on every 10 Hz refresh so the lerp lands at the original target time even
; though each install resets C++ transition_start. 0 = no transition in flight.
float    _transitionEndRT = 0.0
; v0.1.29 different-texture cross-blend: two-phase fade for tier changes
; where the resolved (pack, entry) differs. Phase A fades alpha → 0 over
; tDur/2 keeping OLD texture; Phase B swaps texture to NEW and fades
; alpha 0 → target over tDur/2. Same slot range used throughout — at the
; midpoint texture binding swaps while alpha = 0 so no snap is visible.
; Condition re-evaluation is locked for the full tDur window via
; _transitionEndRT (set when the cross-blend starts).
bool     _crossBlendActive    = false
float    _crossBlendStartRT   = 0.0
float    _crossBlendDuration  = 0.0
bool     _crossBlendInPhaseA  = false
int      _crossBlendNewTier   = -1
; Snapshot of the prev tier's resolved pack/entry — read at tier-change
; time to detect "different texture" without re-resolving OLD's pack
; (which is gone after currentTier flips). Empty string = no prev (e.g.
; fresh load before first tier eval).
string   _prevPackId          = ""
string   _prevEntryId         = ""
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

; ── Per-slot cooldown (v0.1.24 rework) ──────────────────────────────────────
; Old (v0.1.23-): two-mode system — mode 0 "after deactivate" + mode 1 "lock
; on activate", single duration `cooldownMin`. The new model splits the timer
; into TWO independent durations (persist + cool) and a single override toggle:
;
;   1. PERSIST phase — when condition fires, slot stays active for persistMin
;      minutes regardless of whether the condition keeps firing. During this
;      phase, higher-priority slots can take over IF allowOverride==1; if
;      allowOverride==0, the slot is locked solid until persist expires.
;   2. COOL phase    — after persist ends (or after a normal-eval deactivation
;      when persistMin==0), the slot can't re-arm for coolMin minutes.
;   3. NORMAL eval   — after cool expires, the slot evaluates its condition
;      normally on the next tick.
;
; Property reuse (NOT a rename — Papyrus VM attaches by name, renaming risks
; save corruption per project_papyrus_property_attach memory entry):
;   cooldownMin      → semantically "persistMin"   (minutes, 0 = no persist)
;   cooldownMode     → semantically "allowOverride" (1 = allow, 0 = block;
;                                                    default flipped to 1 — see
;                                                    EnsureArrays + v124 migration)
;   cooldownUntilGT  → semantically "persistUntilGT" (GameTime end of persist)
;
; v0.2.8: cooldownMin/cooldownMode/cooldownUntilGT (semantic: persistMin /
; allowOverride / persistUntilGT) lifted off Auto array properties to
; StorageUtil. Access via GetCondPersistMin/Set, GetCondAllowOverride/Set,
; GetCondPersistUntilGT/Set (defined alongside the visual accessors below the
; pulse block). The v0.1.24 one-shot allowOverride migration was deleted —
; "ignore old saves" was the directive for the v0.2.8 unification; fresh
; saves start with allowOverride defaulting to 1 from the accessor.
; Cool-phase (post-persist re-arm lockout) storage at mtf.cool.min.<slot> /
; mtf.cool.until.<slot> stays — see _getCoolMin/_setCoolMin etc.

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
; v0.3.7 multi-area MCM-base: the active tier's pack can live in any area
; (Body/Face/Hands/Feet). Cached by _resyncPulseCache so _applyPulse installs
; the roster entry at the matching <Area>OverlaySlot / area index instead of
; the old hardcoded Body slot.
string _pulseArea = "Body"

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
    ; time).
    ;
    ; v0.2.7: tunable via Data/SKSE/Plugins/MagicTattoosFramework.ini
    ; iMaxEffectsPerSlot (same key the C++ plugin reads). Out-of-range
    ; falls back to 32. Bumping triggers EnsureArrays' migration path on
    ; next load — existing saves re-indexed s*OLD+e → s*NEW+e, no data
    ; loss. Lowering is destructive (bindings beyond the new cap drop).
    int v = MTFPulse.GetConfigInt("General.iMaxEffectsPerSlot", 32)
    if v < 1 || v > 99
        return 32
    endif
    return v
EndFunction

; v0.2.8 perf cache: MAX_CONDITIONS() is read once at quest start (via
; EnsureArrays → _cachedMaxConditions) and re-used by every per-slot
; accessor's bounds check. Without this, each evaluateTier did ~64
; calls to MTFPulse.GetConfigInt (the INI lookup), and the trace
; revealed eval at 670 ms — the C++ native appears to task-queue,
; pinning the VM to 60 fps × 40+ frames per call. Reading the cached
; int keeps the bounds check at one in-script comparison.
int _cachedMaxConditions = 32

int Function MAX_CONDITIONS_CACHED()
{Returns the cached iMaxConditions value populated by EnsureArrays.
 Defaults to 32 if the cache is somehow stale, matching the same
 fallback MAX_CONDITIONS() uses for out-of-range INI values.}
    if _cachedMaxConditions < 1 || _cachedMaxConditions > 256
        return 32
    endif
    return _cachedMaxConditions
EndFunction

int Function MAX_CONDITIONS() global
    ; Backend cap -- how many condition slots evaluateTier scans (1..N).
    ; Slot 0 is the always-on Default and isn't part of this count. JSON
    ; presets and SkyrimNet automation can populate any slot up to N; MCM
    ; only renders up to MAX_CONDITIONS_MCM() rows.
    ;
    ; v0.2.7: condition config moved to StorageUtil (mtf.cond.pluginid.<slot>
    ; / mtf.cond.param.<slot> / mtf.cond.param2.<slot>). Same StorageUtil
    ; freedom the effects refactor gained -- raise this freely.
    ; Visual/cooldown per-slot Auto arrays still cap at MAX_CONDITIONS_MCM+1,
    ; so slots beyond the MCM cap inherit Default's visual and have no
    ; cooldown/persist timer (bounds-checked via _getPersistMode/_getPersistUntilGT).
    ;
    ; Tunable via Data/SKSE/Plugins/MagicTattoosFramework.ini iMaxConditions.
    ; Out-of-range falls back to 32 (same default the INI ships with).
    int v = MTFPulse.GetConfigInt("General.iMaxConditions", 32)
    if v < 1 || v > 256
        return 32
    endif
    return v
EndFunction

; ── SkyrimNet persistent visual-change toggle (v0.4.4) ──────────────────────
; Shared on/off switch for the SkyrimNet bridge's persistent visual-change
; event. Stored as a GLOBAL StorageUtil int (None target) so this MCM-driven
; host in MagicTattoosFramework.esp and the separate MTF_Plugin_SkyrimNet.esp
; read the SAME value. The MCM writes it; the bridge reads it on every tier
; change via GetSkyrimNetPersistVisualChange(). Sentinel -1 = "the user has
; never touched the MCM toggle" -> fall back to the INI default
; (Data/SKSE/Plugins/MagicTattoosFramework.ini [SkyrimNet] bPersistVisualChange,
; default 1), so existing saves and headless setups keep their behaviour until
; the toggle is first flipped, after which the per-save override wins.
string Function SN_PERSIST_VISUAL_KEY() global
    return "mtf.cfg.snPersistVisual"
EndFunction

bool Function GetSkyrimNetPersistVisualChange()
    int v = StorageUtil.GetIntValue(None, SN_PERSIST_VISUAL_KEY(), -1)
    if v < 0
        return MTFPulse.GetConfigInt("SkyrimNet.bPersistVisualChange", 1) != 0
    endif
    return v != 0
EndFunction

Function SetSkyrimNetPersistVisualChange(bool enabled)
    int v = 0
    if enabled
        v = 1
    endif
    StorageUtil.SetIntValue(None, SN_PERSIST_VISUAL_KEY(), v)
EndFunction

; Clear the per-save override (restore the -1 sentinel) so the getter falls
; back to the INI default. Wired to the MCM toggle's Default/reset key.
Function ResetSkyrimNetPersistVisualChange()
    StorageUtil.SetIntValue(None, SN_PERSIST_VISUAL_KEY(), -1)
EndFunction

int Function MAX_CONDITIONS_MCM() global
    ; UI cap -- how many condition rows the MCM page renders. Slot 0 is
    ; the Default row on its own page; this counts conditional slots 1..N.
    return 7
EndFunction

int Function MAX_EFFECTS_PER_SLOT_MCM() global
    ; UI cap — how many `_drawEffectRow` calls fire in the conditions
    ; page. Rows 1-4 use 6 SkyUI state blocks each
    ; (SLOT_EFFECT_<i>_TYPE, _PARAM, _P2, _EX1/2/3); rows 5-8 use only 3
    ; (TYPE+PARAM+P2 — no extras, because each additional state ate into
    ; the 127-named-state ceiling). Papyrus state names are compile-time
    ; so this can't be looped at runtime — raising past 8 requires
    ; either freeing state-name budget elsewhere or paging the editor.
    return 8
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
    ; Framework active by default: the base mod ships no content, so nothing
    ; renders until the user assigns a pack + slot in MCM. DebugMode is left
    ; at its declared default (false) — it was force-enabled here as a dev
    ; convenience (tier-change toasts + lifecycle audit); users opt in via
    ; MCM > General > Debug mode.
    ModActive = true
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
            ; Death forces tier=0 without going through _applyPresetTierChange,
            ; which means the normal _emitTierChanged broadcast never fires.
            ; Listeners (e.g. the SkyrimNet bridge's StorageUtil bio cache) would
            ; otherwise miss the transition and keep showing the pre-death tier.
            ; Only emit when the tier actually changed — corpses already at
            ; tier 0 don't need an event.
            if prevTier > 0
                _emitTierChanged(victim, "preset", nm, prevTier, 0)
            endif
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
    else
        ; v0.3.1 (#A parallel-safe): eagerly arm fade params on every
        ; (preset, area, baseSlot) for this actor. Without this, a
        ; parallel fiber mid-tier-transition may not have flushed its
        ; fadePacked to the Roster yet — the C++ DeathSink fires now,
        ; finds entries with fade_armed=false, and the pulse continues
        ; running on the corpse instead of fading out. Reads fade params
        ; from per-preset cache directly (race-safe, no _s* dependence).
        ; SetActorFade is idempotent — if the fiber later writes the
        ; same params, no harm.
        int j = 0
        while j < n
            string nmFade = GetActorPresetAt(victim, j)
            if nmFade != ""
                string ckFade = "mtf.scratch.cached." + nmFade
                bool fEnabled  = StorageUtil.GetIntValue(None, ckFade + ".fadeondeath.enabled", 0) > 0
                if fEnabled
                    int fMode = StorageUtil.GetIntValue(None, ckFade + ".fadeondeath.mode", 0)
                    int fDur  = StorageUtil.GetIntValue(None, ckFade + ".fadeondeath.durationms", 2000)
                    if fMode < 0 || fMode > 2
                        fMode = 0
                    endif
                    if fDur < 1
                        fDur = 2000
                    endif
                    ; Inline scalar base reads (no _readActorAreaBases helper on main).
                    ; Order matches _OVERLAY_PARTS(): Body/Face/Hands/Feet.
                    Int[] fadeBases = new Int[4]
                    fadeBases[0] = StorageUtil.GetIntValue(victim, "mtf.preset." + nmFade + ".Body.base",  -1)
                    fadeBases[1] = StorageUtil.GetIntValue(victim, "mtf.preset." + nmFade + ".Face.base",  -1)
                    fadeBases[2] = StorageUtil.GetIntValue(victim, "mtf.preset." + nmFade + ".Hands.base", -1)
                    fadeBases[3] = StorageUtil.GetIntValue(victim, "mtf.preset." + nmFade + ".Feet.base",  -1)
                    string[] fadeParts = _OVERLAY_PARTS()
                    int k = 0
                    while k < fadeParts.Length && k < fadeBases.Length
                        int fBase = fadeBases[k]
                        if fBase >= 0
                            MTFPulse.SetActorFade(victim, fBase, fMode, fDur, _areaIndex(fadeParts[k]))
                        endif
                        k += 1
                    endwhile
                endif
            endif
            j += 1
        endwhile
        if DebugMode
            Debug.Notification("[MTF fade] death cleanup deferred — fade armed on " + victim.GetDisplayName())
        endif
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
; is no longer met but a persist timer (v0.1.24+, formerly a
; lock-on-activate cooldown) is keeping the tier active. On reload,
; GameTime advances slightly during the load process, the persist timer
; can expire, and the eval at ~0.5s post-load sees condition=false →
; tier 0 → clears the overlay. Symptom: tattoo flashes on for ~500ms
; then disappears. The grace period gives persist + cool timers and
; condition sources room to settle before we start firing transitions. Not Auto Hidden — it's stamped via ArmPostLoadFreeze at
; load time and doesn't need to persist across saves itself.
float _postLoadFreezeUntilRT = 0.0

Function ArmPostLoadFreeze(float seconds)
    _postLoadFreezeUntilRT = Utility.GetCurrentRealTime() + seconds
EndFunction

Function SetStressN(int n)
{Set the concurrent-fiber count for the F10 PgDn stress test (MTF_TestRunner).
 Call from the in-game console:
     cqf MTF_MainQuest SetStressN 10
 Range 1..30 (clamped). Default is 2 when never set. Persists in the save.}
    if n < 1
        n = 1
    elseif n > 30
        n = 30
    endif
    StorageUtil.SetIntValue(None, "mtf.stress.n", n)
    Debug.Notification("MTF stress N = " + n)
    Trace("[MTF_Main] SetStressN n=" + n)
EndFunction

Function EnsureArrays()
{v0.2.8: per-slot condition/layer/cooldown Auto arrays were lifted to
 StorageUtil (see GetCondPackId / GetCondLayerTint / GetCondPersistMin
 etc.). This now just allocates the plugin registry once and sets the
 _arraysReady sentinel for callers that still gate on it. Effect bindings
 (key, param, param2) live in StorageUtil under mtf.fx.<slot>.<idx>.*
 (v0.1.5+); cond.pluginid/param under mtf.cond.* (v0.2.7+); visual /
 persist fields under mtf.cond.layer.* / mtf.cond.packid / mtf.cond.entryid
 / mtf.cond.persistmin / .allowoverride / .persistgt (v0.2.8+).}
    if _arraysReady
        return
    endif

    Trace("[MTF_Main] EnsureArrays: allocating plugin registry (per-slot cond/layer/cooldown now in StorageUtil)")
    registeredPlugins     = new Form[32]
    pluginCount           = 0
    _arraysReady          = true
    ; v0.2.8 perf: cache iMaxConditions once so the per-accessor bounds
    ; check doesn't re-cross into MTFPulse.GetConfigInt 64+ times per
    ; evaluateTier (~670 ms regression vs in-script Int compare).
    _cachedMaxConditions = MAX_CONDITIONS()
EndFunction

Function _migrateV124CooldownIfNeeded()
{v0.2.8: the v0.1.24 cooldown-semantics migration was deleted along with
 the cooldownMode/cooldownUntilGT Auto array properties. Fresh saves get
 allowOverride=1 from the GetCondAllowOverride default; persistUntilGT
 defaults to 0.0 from GetCondPersistUntilGT. Kept as an empty function so
 any stale callsites compile (will be cleaned up in a follow-up sweep).}
EndFunction

; ── v0.3.9 mtf.base → themed-module migrator ─────────────────────────────────
; The monolithic mtf.base pack was split into 5 themed modules (mtf.attributes
; / mtf.combat / mtf.magic / mtf.world / mtf.fx). Slots persist the bound key
; ("<pluginid>:<id>") by value in the cosave, so existing saves still carry
; "mtf.base:<id>". This one-shot rewrites each stored key to "<module>:<id>"
; using the generated id→module map. Idempotent and version-gated: bump
; MODULE_SPLIT_SCHEMA() if a future split needs to re-run it. Preset JSON files
; (shipped + the user's own) are remapped offline by tools/migrate_preset_modules.py,
; so this only has to fix the live in-save slots.
int Function MODULE_SPLIT_SCHEMA() global
    ; v2: the v1 migration used a camelCase JsonUtil map lookup that silently
    ; missed every camelCase id (JsonUtil lowercases stored keys). Those slots
    ; were left as stale "mtf.base:..." keys. Bumping forces a re-migrate now
    ; that _remapBaseKey lowercases its lookup. (ResolvePluginByKey's fallback
    ; also covers stale keys at runtime, but re-migrating persists the fix.)
    return 2
EndFunction

string Function _moduleMapFile() global
    ; Relative to Data/SKSE/Plugins/StorageUtilData/ (same root as catalogs).
    return "MagicTattoosFramework/mtf.module_map.json"
EndFunction

; "mtf.base:<id>" → "<module>:<id>" via the JsonUtil map. `prefix` is "cond:"
; or "eff:" (the two id namespaces are stored under distinct keys). Any key
; not under mtf.base, or an id missing from the map, is returned UNCHANGED so
; a partial/unknown entry is never corrupted.
; ASCII lowercaser. Papyrus has no built-in ToLower. Used to normalise the
; module-map lookup key — JsonUtil lowercases STORED keys on load but does NOT
; lowercase the query, so a camelCase query ("eff:modify.magickaRegen") misses
; the lowercased store and silently returns the default. We lowercase the
; lookup key here to match. (Memory: project_papyrusutil_lowercase.)
string Function _toLowerAscii(string s)
    string up = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    string lo = "abcdefghijklmnopqrstuvwxyz"
    string out = ""
    int i = 0
    int n = StringUtil.GetLength(s)
    while i < n
        string c = StringUtil.GetNthChar(s, i)
        int idx = StringUtil.Find(up, c)
        if idx >= 0
            out += StringUtil.GetNthChar(lo, idx)
        else
            out += c
        endif
        i += 1
    endwhile
    return out
EndFunction

string Function _remapBaseKey(string key, string prefix)
    if key == "" || _keyPluginId(key) != "mtf.base"
        return key
    endif
    string id  = _keyItemId(key)
    ; Lowercase the lookup key (NOT the id) — see _toLowerAscii. The returned
    ; module key keeps the original camelCase id so it matches the catalogs.
    string mod = JsonUtil.GetStringValue(_moduleMapFile(), _toLowerAscii(prefix + id), "")
    if mod == ""
        return key
    endif
    return mod + ":" + id
EndFunction

Function _migrateModuleSplit()
{One-shot: rewrite every slot's stored mtf.base key to its themed module.
 Called from MTF_HitListener.OnPlayerLoadGame, inside the post-load freeze.}
    if StorageUtil.GetIntValue(None, "mtf.migrated.moduleSplit", 0) >= MODULE_SPLIT_SCHEMA()
        return
    endif
    EnsureArrays()
    int changed = 0
    int slot = 0
    int maxSlot = MAX_CONDITIONS_CACHED()
    int maxE = MAX_EFFECTS_PER_SLOT()
    while slot <= maxSlot
        ; Conditions — every AND/OR entry j (slot 0/Default has none; the
        ; loop just no-ops there because GetCondCount returns 0).
        int cc = GetCondCount(slot)
        int j = 0
        while j < cc
            string ck  = GetCondPluginIdAt(slot, j)
            string nck = _remapBaseKey(ck, "cond:")
            if nck != ck
                SetCondPluginIdAt(slot, j, nck)
                changed += 1
            endif
            j += 1
        endwhile
        ; Effect rows — rewrite only the ".key" string; params under
        ; .param1.. are keyed separately and stay untouched.
        int e = 0
        while e < maxE
            string ek  = _readFxKey(slot, e, false)
            string nek = _remapBaseKey(ek, "eff:")
            if nek != ek
                _writeFxKey(slot, e, false, nek)
                changed += 1
            endif
            e += 1
        endwhile
        slot += 1
    endwhile
    StorageUtil.SetIntValue(None, "mtf.migrated.moduleSplit", MODULE_SPLIT_SCHEMA())
    Trace("[MTF_Main] module-split migrator: rewrote " + changed + " mtf.base key(s)")
EndFunction

; ── Cooldown-phase StorageUtil-backed accessors (v0.1.24) ────────────────────
; The "cool" phase (post-persist re-arm lockout) lives entirely in StorageUtil
; rather than as new Auto array properties — adding Auto properties to a
; script that's already in a save doesn't reliably attach backing storage
; (project_papyrus_property_attach). Per-slot keyed on self for the player
; path; per-(actor, preset, slot) for stacked / NPC presets (see
; _setActorPresetCoolUntil).

int Function _getCoolMin(int slot)
    return StorageUtil.GetIntValue(self, "mtf.cool.min." + slot, 0)
EndFunction
Function _setCoolMin(int slot, int v)
    StorageUtil.SetIntValue(self, "mtf.cool.min." + slot, v)
EndFunction

float Function _getCoolUntilGT(int slot)
    return StorageUtil.GetFloatValue(self, "mtf.cool.until." + slot, 0.0)
EndFunction
Function _setCoolUntilGT(int slot, float t)
    StorageUtil.SetFloatValue(self, "mtf.cool.until." + slot, t)
EndFunction

; Inheritance helpers — any slot 1..MAX_CONDITIONS with empty packid inherits
; slot 0 (Default). v0.2.8: all slots are first-class now (StorageUtil-backed),
; no MCM-cap special case. The "<none>" sentinel means "explicit no-texture /
; effects-only" and never inherits; drawOverlay skips drawing when it sees
; that value.
string Function ResolveSlotPackId(int slot)
    if slot < 0
        return ""
    endif
    string pid = GetCondPackId(slot)
    if pid == "" && slot > 0
        return GetCondPackId(0)
    endif
    return pid
EndFunction

string Function ResolveSlotEntryId(int slot)
    if slot < 0
        return ""
    endif
    if slot > 0 && GetCondPackId(slot) == ""
        return GetCondEntryId(0)
    endif
    return GetCondEntryId(slot)
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
    ; Pre-allocate the Pass-2 "known" array HERE — immediately after the
    ; JsonInFolder native return and BEFORE the `files != None` guard. A
    ; PapyrusUtil array return followed by an `== None`/`!= None` comparison
    ; corrupts the array ::temp register (KB: temp1-corruption); a `new
    ; string[]` placed AFTER that comparison (the old Pass-2 layout) got
    ; clobbered, so `known` came back None and every `known[k]` threw
    ; "Cannot access an element of a None array" (+ "Cannot create an array").
    ; Allocating before the guard matches the error-free ListPresets ordering.
    string[] known = new string[2]
    known[0] = "MagicTattoosFramework/visuals/mtf.lewdmarks-racemenu"
    known[1] = "MagicTattoosFramework/visuals/mtf.lewdmarks-slavetats"
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

    ; Pass 2: hardcoded probe for ship-included packs (uses the `known`
    ; array allocated above, before the None guard — see note there).
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

bool Function GetRescanOnLoad()
{Whether the post-load handler (MTF_HitListener) auto-rescans the visual
 pack catalogs on every save load. Backed by StorageUtil rather than a
 script var so it attaches cleanly on saves that predate this option —
 a new Auto property/var added post-release doesn't reliably get backing
 storage (KB: "Post-release Auto properties don't attach"). Default ON.}
    return StorageUtil.GetIntValue(None, "mtf.rescanOnLoad", 1) != 0
EndFunction

Function SetRescanOnLoad(bool v)
    int iv = 0
    if v
        iv = 1
    endif
    StorageUtil.SetIntValue(None, "mtf.rescanOnLoad", iv)
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

; v0.4.4: optional per-layer semantic name (e.g. "fill", "glow"). A pack MAY
; add "name" to any layer object; absent/empty -> "" so callers fall back to
; "Layer N". Lets a pack explain what each overlay layer represents — say a
; solid base design vs. an edge-glow emissive — so LLM/UI surfaces read
; "glow #X -> #Y" instead of "Layer 2 #X -> #Y". Purely cosmetic; no engine
; behaviour keys off it.
string Function GetEntryLayerName(string packId, string entryId, int layer)
    string f = _packFileById(packId)
    int idx = _findEntryIdx(packId, entryId)
    if f == "" || idx < 0 || layer < 0
        return ""
    endif
    return JsonUtil.GetPathStringValue(f, ".entries[" + idx + "].layers[" + layer + "].name", "")
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

; v0.3.x: anatomical placement tag (e.g. "lower abdomen, just below the
; navel"). Near-universal across content packs; surfaced in the SkyrimNet
; bio so the LLM knows WHERE the tattoo sits even when the prose
; description omits it. Empty string when the pack entry has no tag.
string Function GetEntryPlacement(string packId, string entryId)
    string f = _packFileById(packId)
    int idx = _findEntryIdx(packId, entryId)
    if f == "" || idx < 0
        return ""
    endif
    return JsonUtil.GetPathStringValue(f, ".entries[" + idx + "].tags.placement", "")
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
; ── Per-slot pluginid / param (StorageUtil-backed) ──────────────────────────
; Keys: mtf.cond.pluginid.<slot> (string), mtf.cond.param.<slot> (int).
; Same StorageUtil escape from Auto-property attachment hell that effects got
; in v0.1.5 (see _readFxKey/_writeFxKey). Decouples backend slot count
; (MAX_CONDITIONS = 32) from MCM display cap (MAX_CONDITIONS_MCM = 7).
string Function GetCondPluginId(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return ""
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.pluginid." + slot, "")
EndFunction

Function SetCondPluginId(int slot, string key)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if key == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.pluginid." + slot)
    else
        StorageUtil.SetStringValue(None, "mtf.cond.pluginid." + slot, key)
    endif
EndFunction

int Function GetCondParam(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.param." + slot, 0)
EndFunction

Function SetCondParam(int slot, int val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if val == 0
        StorageUtil.UnsetIntValue(self, "mtf.cond.param." + slot)
    else
        StorageUtil.SetIntValue(self, "mtf.cond.param." + slot, val)
    endif
EndFunction

; ── Per-slot second condition parameter (StorageUtil-backed) ─────────────────
; Optional 2nd knob for conditions that need two values (e.g. time.range
; from/till). StorageUtil-backed to dodge the Auto-property attachment trap.
int Function GetCondParam2(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.param2." + slot, 0)
EndFunction

Function SetCondParam2(int slot, int val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.param2." + slot, val)
EndFunction

; ── String-typed cond.param accessors (v0.2.9) ──────────────────────────────
; Menu params now store a stable id string (e.g. "sneak") instead of an int
; position. Slider params keep using the int-typed Get/SetCondParam above.
; The catalog tells the caller which to use: probe via
; GetConditionParamMenuOptionCount > 0 from the bound MTF_Plugin.
; Key shape: `mtf.cond.param.<slot>.s` (NEW string slot, distinct from the
; existing int `mtf.cond.param.<slot>`). Two key families keep slider
; behavior bit-identical and let v8 in-game preset state for legacy menus
; cleanly orphan rather than silently misread.
string Function GetCondParamStr(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return ""
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.param." + slot + ".s", "")
EndFunction

Function SetCondParamStr(int slot, string val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if val == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.param." + slot + ".s")
    else
        StorageUtil.SetStringValue(None, "mtf.cond.param." + slot + ".s", val)
    endif
EndFunction

string Function GetCondParam2Str(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return ""
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.param2." + slot + ".s", "")
EndFunction

Function SetCondParam2Str(int slot, string val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if val == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.param2." + slot + ".s")
    else
        StorageUtil.SetStringValue(None, "mtf.cond.param2." + slot + ".s", val)
    endif
EndFunction

; ── Per-slot THIRD condition parameter (StorageUtil-backed, v0.4.x) ───────────
; Optional 3rd knob for conditions needing three values (e.g. npc.faction.near:
; EditorID + radius + display name). Mirrors the param2 keyspace exactly so the
; At(s,0) delegators, Save/Load, and MCM behave identically. param3 supports
; slider + free-text only (no menu — the third param is realistically always a
; threshold or a name/id).
int Function GetCondParam3(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.param3." + slot, 0)
EndFunction

Function SetCondParam3(int slot, int val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.param3." + slot, val)
EndFunction

string Function GetCondParam3Str(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return ""
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.param3." + slot + ".s", "")
EndFunction

Function SetCondParam3Str(int slot, string val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if val == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.param3." + slot + ".s")
    else
        StorageUtil.SetStringValue(None, "mtf.cond.param3." + slot + ".s", val)
    endif
EndFunction

; ── Multi-condition per slot (AND/OR) — v0.3.0 ──────────────────────────────
; A slot can hold N conditions combined by ONE operator. Condition index 0
; reuses the legacy scalar keys (GetCondPluginId/Param/... above) for 100%
; back-compat with existing saves + presets; indices >= 1 live under the new
; keyspace mtf.cond.x.<slot>.<j>.*. GetCondCount returns the effective count
; (a legacy single-condition slot reports 1). Op: 0 = AND (all must pass),
; 1 = OR (any passes). MAX_CONDS_PER_SLOT bounds the backend (MCM exposes 2).
int Function MAX_CONDS_PER_SLOT() global
    return 8
EndFunction

int Function GetCondOp(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.op." + slot, 0)
EndFunction

Function SetCondOp(int slot, int op)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if op == 0
        StorageUtil.UnsetIntValue(self, "mtf.cond.op." + slot)
    else
        StorageUtil.SetIntValue(self, "mtf.cond.op." + slot, op)
    endif
EndFunction

int Function GetCondCount(int slot)
{Effective number of conditions in the slot. Legacy slots with no explicit
 count report 1 when cond[0] is set, else 0 — so old presets evaluate
 unchanged.}
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0
    endif
    int c = StorageUtil.GetIntValue(self, "mtf.cond.count." + slot, -1)
    if c < 0
        if GetCondPluginId(slot) != ""
            return 1
        endif
        return 0
    endif
    return c
EndFunction

Function SetCondCount(int slot, int c)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if c <= 1
        ; 0 or 1 collapses to the legacy representation (no explicit key)
        StorageUtil.UnsetIntValue(self, "mtf.cond.count." + slot)
    else
        StorageUtil.SetIntValue(self, "mtf.cond.count." + slot, c)
    endif
EndFunction

; Indexed accessors. j == 0 delegates to the legacy scalar keys; j >= 1 uses
; the mtf.cond.x.<slot>.<j>.* sub-keyspace. Strings live on the None scope
; (matching the legacy string keys); ints on `self` (matching legacy int keys).
string Function GetCondPluginIdAt(int slot, int j)
    if j <= 0
        return GetCondPluginId(slot)
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.x." + slot + "." + j + ".pluginid", "")
EndFunction

Function SetCondPluginIdAt(int slot, int j, string key)
    if j <= 0
        SetCondPluginId(slot, key)
        return
    endif
    if key == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.x." + slot + "." + j + ".pluginid")
    else
        StorageUtil.SetStringValue(None, "mtf.cond.x." + slot + "." + j + ".pluginid", key)
    endif
EndFunction

int Function GetCondParamAt(int slot, int j)
    if j <= 0
        return GetCondParam(slot)
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.x." + slot + "." + j + ".param", 0)
EndFunction

Function SetCondParamAt(int slot, int j, int val)
    if j <= 0
        SetCondParam(slot, val)
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.x." + slot + "." + j + ".param", val)
EndFunction

int Function GetCondParam2At(int slot, int j)
    if j <= 0
        return GetCondParam2(slot)
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.x." + slot + "." + j + ".param2", 0)
EndFunction

Function SetCondParam2At(int slot, int j, int val)
    if j <= 0
        SetCondParam2(slot, val)
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.x." + slot + "." + j + ".param2", val)
EndFunction

string Function GetCondParamStrAt(int slot, int j)
    if j <= 0
        return GetCondParamStr(slot)
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param.s", "")
EndFunction

Function SetCondParamStrAt(int slot, int j, string val)
    if j <= 0
        SetCondParamStr(slot, val)
        return
    endif
    if val == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param.s")
    else
        StorageUtil.SetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param.s", val)
    endif
EndFunction

string Function GetCondParam2StrAt(int slot, int j)
    if j <= 0
        return GetCondParam2Str(slot)
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param2.s", "")
EndFunction

Function SetCondParam2StrAt(int slot, int j, string val)
    if j <= 0
        SetCondParam2Str(slot, val)
        return
    endif
    if val == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param2.s")
    else
        StorageUtil.SetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param2.s", val)
    endif
EndFunction

int Function GetCondParam3At(int slot, int j)
    if j <= 0
        return GetCondParam3(slot)
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.x." + slot + "." + j + ".param3", 0)
EndFunction

Function SetCondParam3At(int slot, int j, int val)
    if j <= 0
        SetCondParam3(slot, val)
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.x." + slot + "." + j + ".param3", val)
EndFunction

string Function GetCondParam3StrAt(int slot, int j)
    if j <= 0
        return GetCondParam3Str(slot)
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param3.s", "")
EndFunction

Function SetCondParam3StrAt(int slot, int j, string val)
    if j <= 0
        SetCondParam3Str(slot, val)
        return
    endif
    if val == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param3.s")
    else
        StorageUtil.SetStringValue(None, "mtf.cond.x." + slot + "." + j + ".param3.s", val)
    endif
EndFunction

; Clears every extra condition (index >= 1) for a slot back to empty, and
; resets count/op to the legacy single-condition representation. Used by
; LoadPreset before re-reading and by the MCM "clear slot" path.
Function ClearSlotExtraConds(int slot)
    int j = 1
    while j < MAX_CONDS_PER_SLOT()
        SetCondPluginIdAt(slot, j, "")
        SetCondParamAt(slot, j, 0)
        SetCondParam2At(slot, j, 0)
        SetCondParam3At(slot, j, 0)
        SetCondParamStrAt(slot, j, "")
        SetCondParam2StrAt(slot, j, "")
        SetCondParam3StrAt(slot, j, "")
        j += 1
    endwhile
    SetCondCount(slot, 1)
    SetCondOp(slot, 0)
EndFunction

; ── Catalog probe helpers (v0.2.9) ──────────────────────────────────────────
; "Does this cond/effect param have a menu in the catalog?" Resolves the
; plugin + item from a slot key. Used by SavePreset/LoadPreset to route to
; the right string-vs-int accessor family per param.
;
; Empty key returns false (treat as slider so default int read returns 0).
bool Function _condParamIsMenu(string condKey)
    if condKey == ""
        return false
    endif
    MTF_Plugin p = ResolvePluginByKey(condKey)
    if p == None
        return false
    endif
    int itemIdx = _condIdxFor(p, _keyItemId(condKey))
    if itemIdx < 0
        return false
    endif
    return p.GetConditionParamMenuOptionCount(itemIdx) > 0 || p.GetConditionParamIsText(itemIdx)
EndFunction

bool Function _condParam2IsMenu(string condKey)
    if condKey == ""
        return false
    endif
    MTF_Plugin p = ResolvePluginByKey(condKey)
    if p == None
        return false
    endif
    int itemIdx = _condIdxFor(p, _keyItemId(condKey))
    if itemIdx < 0
        return false
    endif
    return p.GetConditionParam2MenuOptionCount(itemIdx) > 0 || p.GetConditionParam2IsText(itemIdx)
EndFunction

; v0.4.x: true when a condition's param3 (de)serializes as a STRING. param3 has
; no menu support, so this is just the free-text flag. Save/Load route on it so
; the text content persists instead of coercing to int 0.
bool Function _condParam3IsStr(string condKey)
    if condKey == ""
        return false
    endif
    MTF_Plugin p = ResolvePluginByKey(condKey)
    if p == None
        return false
    endif
    int itemIdx = _condIdxFor(p, _keyItemId(condKey))
    if itemIdx < 0
        return false
    endif
    return p.GetConditionParam3IsText(itemIdx)
EndFunction

; v0.3.x: true when paramN (de)serializes as a STRING — menu (string id) OR
; free-text. Sliders serialize as int. Save/Load/scratch-load route on this
; so text params persist their content instead of being coerced to int 0.
bool Function _effectParamIsStr(string effKey, int n)
    if effKey == "" || n < 1 || n > 5
        return false
    endif
    MTF_Plugin p = ResolvePluginByKey(effKey)
    if p == None
        return false
    endif
    int itemIdx = _effectIdxFor(p, _keyItemId(effKey))
    if itemIdx < 0
        return false
    endif
    return p.GetEffectParamMenuOptionCount(itemIdx, n) > 0 || p.GetEffectParamIsText(itemIdx, n)
EndFunction

; ── Per-slot display name (StorageUtil-backed, v0.2.9) ──────────────────────
; User-authored override for the bare "Default" / "Condition N" labels the MCM
; uses by default. Slot 0 (Default) IS renameable — the engine-side meaning of
; "slot 0 = inheritance source" is unchanged, only the displayed string. Empty
; string = fall back to the canonical label in MCMQuest._slotLabel. Sanitized
; via _sanitizePresetName (cap 32, [A-Za-z0-9_-]) at the MCM input site.
string Function GetCondName(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return ""
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.name." + slot, "")
EndFunction

Function SetCondName(int slot, string name)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if name == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.name." + slot)
    else
        StorageUtil.SetStringValue(None, "mtf.cond.name." + slot, name)
    endif
EndFunction

; ── Slot swap (v0.2.9) ──────────────────────────────────────────────────────
; Permute every cond + effect field between slots a and b, leaving visuals
; (tint/emissive/em.mult/alpha/pulse) tied to the slot index. Rationale:
; today's architecture already decouples visuals from cond content — backend
; slots inherit Default's visuals regardless of what cond lives in them, and
; SavePreset/LoadPreset only write/read layer data when s ≤ mcmCap. Swap
; semantics: cond + effects + cooldown + name move; visuals stay.
;
; Default slot (slot 0) is not swappable — engine code treats slot 0 as the
; inheritance source for backend slots' visuals, so reassigning it would
; reshuffle every backend slot's appearance.
;
; Cooldown timers (cool.until.gt / persist.until.gt) are cleared on the player
; only — NPCs auto-revalidate on next slow tick once the scratch cache is
; dropped via _invalidateScratchCache.
bool Function SwapSlots(string preset, int a, int b)
{Swap the cond definition + effects + cooldown setting + display name between
 slots a and b. Visuals stay tied to slot index. Returns false on invalid
 input (slot 0, out of range, or no preset loaded).}
    if a < 1 || b < 1
        return false   ; slot 0 (Default) is not swappable
    endif
    int maxC = MAX_CONDITIONS_CACHED()
    if a > maxC || b > maxC
        return false
    endif
    if a == b
        return true   ; no-op success
    endif

    ; Snapshot slot a's content into locals
    string aName     = GetCondName(a)
    string aPid      = GetCondPluginId(a)
    int    aPar      = GetCondParam(a)
    int    aPar2     = GetCondParam2(a)
    string aParS     = GetCondParamStr(a)
    string aPar2S    = GetCondParam2Str(a)
    string aPack     = GetCondPackId(a)
    string aEntry    = GetCondEntryId(a)
    int    aPMin     = GetCondPersistMin(a)
    int    aPOvr     = GetCondAllowOverride(a)
    int    aCMin     = _getCoolMin(a)
    int    maxE      = MAX_EFFECTS_PER_SLOT()
    string[] aKeys   = Utility.CreateStringArray(maxE, "")
    int[]    aP1     = Utility.CreateIntArray(maxE, 0)
    int[]    aP2     = Utility.CreateIntArray(maxE, 0)
    int[]    aP3     = Utility.CreateIntArray(maxE, 0)
    int[]    aP4     = Utility.CreateIntArray(maxE, 0)
    int[]    aP5     = Utility.CreateIntArray(maxE, 0)
    string[] aP1S    = Utility.CreateStringArray(maxE, "")
    string[] aP2S    = Utility.CreateStringArray(maxE, "")
    string[] aP3S    = Utility.CreateStringArray(maxE, "")
    string[] aP4S    = Utility.CreateStringArray(maxE, "")
    string[] aP5S    = Utility.CreateStringArray(maxE, "")
    int e = 0
    while e < maxE
        aKeys[e] = _readFxKey(a, e, false)
        aP1[e]   = _readFxParamN(a, e, 1, false)
        aP2[e]   = _readFxParamN(a, e, 2, false)
        aP3[e]   = _readFxParamN(a, e, 3, false)
        aP4[e]   = _readFxParamN(a, e, 4, false)
        aP5[e]   = _readFxParamN(a, e, 5, false)
        aP1S[e]  = _readFxParamNStr(a, e, 1, false)
        aP2S[e]  = _readFxParamNStr(a, e, 2, false)
        aP3S[e]  = _readFxParamNStr(a, e, 3, false)
        aP4S[e]  = _readFxParamNStr(a, e, 4, false)
        aP5S[e]  = _readFxParamNStr(a, e, 5, false)
        e += 1
    endwhile

    ; Copy slot b → slot a
    SetCondName(a,             GetCondName(b))
    SetCondPluginId(a,         GetCondPluginId(b))
    SetCondParam(a,            GetCondParam(b))
    SetCondParam2(a,           GetCondParam2(b))
    SetCondParamStr(a,         GetCondParamStr(b))
    SetCondParam2Str(a,        GetCondParam2Str(b))
    SetCondPackId(a,           GetCondPackId(b))
    SetCondEntryId(a,          GetCondEntryId(b))
    SetCondPersistMin(a,       GetCondPersistMin(b))
    SetCondAllowOverride(a,    GetCondAllowOverride(b))
    _setCoolMin(a,             _getCoolMin(b))
    e = 0
    while e < maxE
        _writeFxKey(a, e, false,    _readFxKey(b, e, false))
        _writeFxParamN(a, e, 1, false, _readFxParamN(b, e, 1, false))
        _writeFxParamN(a, e, 2, false, _readFxParamN(b, e, 2, false))
        _writeFxParamN(a, e, 3, false, _readFxParamN(b, e, 3, false))
        _writeFxParamN(a, e, 4, false, _readFxParamN(b, e, 4, false))
        _writeFxParamN(a, e, 5, false, _readFxParamN(b, e, 5, false))
        _writeFxParamNStr(a, e, 1, false, _readFxParamNStr(b, e, 1, false))
        _writeFxParamNStr(a, e, 2, false, _readFxParamNStr(b, e, 2, false))
        _writeFxParamNStr(a, e, 3, false, _readFxParamNStr(b, e, 3, false))
        _writeFxParamNStr(a, e, 4, false, _readFxParamNStr(b, e, 4, false))
        _writeFxParamNStr(a, e, 5, false, _readFxParamNStr(b, e, 5, false))
        e += 1
    endwhile

    ; Restore snapshot → slot b
    SetCondName(b,             aName)
    SetCondPluginId(b,         aPid)
    SetCondParam(b,            aPar)
    SetCondParam2(b,           aPar2)
    SetCondParamStr(b,         aParS)
    SetCondParam2Str(b,        aPar2S)
    SetCondPackId(b,           aPack)
    SetCondEntryId(b,          aEntry)
    SetCondPersistMin(b,       aPMin)
    SetCondAllowOverride(b,    aPOvr)
    _setCoolMin(b,             aCMin)
    e = 0
    while e < maxE
        _writeFxKey(b, e, false, aKeys[e])
        _writeFxParamN(b, e, 1, false, aP1[e])
        _writeFxParamN(b, e, 2, false, aP2[e])
        _writeFxParamN(b, e, 3, false, aP3[e])
        _writeFxParamN(b, e, 4, false, aP4[e])
        _writeFxParamN(b, e, 5, false, aP5[e])
        _writeFxParamNStr(b, e, 1, false, aP1S[e])
        _writeFxParamNStr(b, e, 2, false, aP2S[e])
        _writeFxParamNStr(b, e, 3, false, aP3S[e])
        _writeFxParamNStr(b, e, 4, false, aP4S[e])
        _writeFxParamNStr(b, e, 5, false, aP5S[e])
        e += 1
    endwhile

    ; Clear player timers for both swapped slots so the next eval doesn't
    ; honor a stale persist window from the now-different content. NPCs
    ; revalidate on next slow tick via the dropped scratch cache below.
    _setCoolUntilGT(a, 0.0)
    _setCoolUntilGT(b, 0.0)
    SetCondPersistUntilGT(a, 0.0)
    SetCondPersistUntilGT(b, 0.0)

    ; Drop the cached scratch for this preset so NPCs reload the swapped
    ; layout on their next slow tick. Limitation: NPCs that were on cooldown
    ; for one of the swapped slots may see one wrong-effect tick before
    ; re-eval catches up — acceptable per design (cosmetic, not data loss).
    if preset != ""
        _invalidateScratchCache(preset)
    endif
    return true
EndFunction

; ── Persist accessors (v0.2.8: now unified across all slots) ────────────────
; Pre-v0.2.8 these were dual-track wrappers around Auto array properties for
; slot ≤ MCM cap and a default-value early-return for backend slots. Now the
; underlying GetCondAllowOverride / GetCondPersistUntilGT accessors are
; StorageUtil-backed and slot-agnostic, so the wrappers are thin delegators
; preserved for backward compatibility with existing callsites.
int Function _getPersistMode(int slot)
    return GetCondAllowOverride(slot)
EndFunction

float Function _getPersistUntilGT(int slot)
    return GetCondPersistUntilGT(slot)
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

; ── String eval-param accessors (v0.2.9) ─────────────────────────────────────
; For menu-typed cond params: evaluateTier sets the id string before calling
; the plugin's checkCondition. The plugin reads it via host.GetEvalParamStr()
; (param) or host.GetEvalParam2Str() (param2). Slider-typed conds still use
; the int param arg + GetEvalParam2 above.
Function _setEvalParamStr(string val)
    StorageUtil.SetStringValue(self, "mtf.evalParam.s", val)
EndFunction
string Function GetEvalParamStr()
    return StorageUtil.GetStringValue(self, "mtf.evalParam.s", "")
EndFunction
Function _setEvalParam2Str(string val)
    StorageUtil.SetStringValue(self, "mtf.evalParam2.s", val)
EndFunction
string Function GetEvalParam2Str()
    return StorageUtil.GetStringValue(self, "mtf.evalParam2.s", "")
EndFunction
; param3 eval-scratch (v0.4.x) — set by _checkOneCond before checkCondition so a
; plugin reads its 3rd value via host.GetEvalParam3() / GetEvalParam3Str().
Function _setEvalParam3(int val)
    StorageUtil.SetIntValue(self, "mtf.evalParam3", val)
EndFunction
int Function GetEvalParam3()
    return StorageUtil.GetIntValue(self, "mtf.evalParam3", 0)
EndFunction
Function _setEvalParam3Str(string val)
    StorageUtil.SetStringValue(self, "mtf.evalParam3.s", val)
EndFunction
string Function GetEvalParam3Str()
    return StorageUtil.GetStringValue(self, "mtf.evalParam3.s", "")
EndFunction

float Function GetCondPulseRate(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0.0
    endif
    return StorageUtil.GetFloatValue(self, "mtf.cond.pulse.rate." + slot, 0.0)
EndFunction

Function SetCondPulseRate(int slot, float v)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    StorageUtil.SetFloatValue(self, "mtf.cond.pulse.rate." + slot, v)
EndFunction

int Function GetCondPulseDepth(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.pulse.depth." + slot, 0)
EndFunction

Function SetCondPulseDepth(int slot, int v)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.pulse.depth." + slot, v)
EndFunction

float Function GetCondPulsePause(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0.0
    endif
    return StorageUtil.GetFloatValue(self, "mtf.pulse.pause." + slot, 0.0)
EndFunction

Function SetCondPulsePause(int slot, float v)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    StorageUtil.SetFloatValue(self, "mtf.pulse.pause." + slot, v)
EndFunction

string Function GetCondWaveform(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return ""
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.pulse.waveform." + slot, "")
EndFunction

Function SetCondWaveform(int slot, string name)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if name == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.pulse.waveform." + slot)
    else
        StorageUtil.SetStringValue(None, "mtf.cond.pulse.waveform." + slot, name)
    endif
EndFunction

; ── Per-slot pack/entry/layer/persist (StorageUtil-backed, v0.2.8) ───────────
; Moved off Auto array properties (condPackId/condEntryId/condLayerTint/
; condLayerEmissive/condLayerEmissiveMult/condLayerAlpha/cooldownMin/
; cooldownMode/cooldownUntilGT) to StorageUtil so all 32 backend slots get
; the same access path as the MCM-cap 8. Old saves are intentionally not
; migrated — fresh saves only. The Auto array property declarations were
; deleted in v0.2.8 after VMAD inspection confirmed they were never CK-
; exposed (no reattach risk per project_vmad_stale_property_reattach).

string Function GetCondPackId(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return ""
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.packid." + slot, "")
EndFunction

Function SetCondPackId(int slot, string val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if val == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.packid." + slot)
    else
        StorageUtil.SetStringValue(None, "mtf.cond.packid." + slot, val)
    endif
EndFunction

string Function GetCondEntryId(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return ""
    endif
    return StorageUtil.GetStringValue(None, "mtf.cond.entryid." + slot, "")
EndFunction

Function SetCondEntryId(int slot, string val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    if val == ""
        StorageUtil.UnsetStringValue(None, "mtf.cond.entryid." + slot)
    else
        StorageUtil.SetStringValue(None, "mtf.cond.entryid." + slot, val)
    endif
EndFunction

int Function GetCondLayerTint(int slot, int L)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || L < 0 || L >= MAX_LAYERS_PER_SLOT()
        return 16777215
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.layer.tint." + slot + "." + L, 16777215)
EndFunction

Function SetCondLayerTint(int slot, int L, int val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || L < 0 || L >= MAX_LAYERS_PER_SLOT()
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.layer.tint." + slot + "." + L, val)
EndFunction

int Function GetCondLayerEmissive(int slot, int L)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || L < 0 || L >= MAX_LAYERS_PER_SLOT()
        return 16777215
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.layer.emissive." + slot + "." + L, 16777215)
EndFunction

Function SetCondLayerEmissive(int slot, int L, int val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || L < 0 || L >= MAX_LAYERS_PER_SLOT()
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.layer.emissive." + slot + "." + L, val)
EndFunction

float Function GetCondLayerEmissiveMult(int slot, int L)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || L < 0 || L >= MAX_LAYERS_PER_SLOT()
        return 0.0
    endif
    return StorageUtil.GetFloatValue(self, "mtf.cond.layer.emult." + slot + "." + L, 0.0)
EndFunction

Function SetCondLayerEmissiveMult(int slot, int L, float val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || L < 0 || L >= MAX_LAYERS_PER_SLOT()
        return
    endif
    StorageUtil.SetFloatValue(self, "mtf.cond.layer.emult." + slot + "." + L, val)
EndFunction

int Function GetCondLayerAlpha(int slot, int L)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || L < 0 || L >= MAX_LAYERS_PER_SLOT()
        return 100
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.layer.alpha." + slot + "." + L, 100)
EndFunction

Function SetCondLayerAlpha(int slot, int L, int val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || L < 0 || L >= MAX_LAYERS_PER_SLOT()
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.layer.alpha." + slot + "." + L, val)
EndFunction


int Function GetCondPersistMin(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.persistmin." + slot, 0)
EndFunction

Function SetCondPersistMin(int slot, int val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.persistmin." + slot, val)
EndFunction

int Function GetCondAllowOverride(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 1
    endif
    return StorageUtil.GetIntValue(self, "mtf.cond.allowoverride." + slot, 1)
EndFunction

Function SetCondAllowOverride(int slot, int val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    StorageUtil.SetIntValue(self, "mtf.cond.allowoverride." + slot, val)
EndFunction

float Function GetCondPersistUntilGT(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return 0.0
    endif
    return StorageUtil.GetFloatValue(self, "mtf.cond.persistgt." + slot, 0.0)
EndFunction

Function SetCondPersistUntilGT(int slot, float val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    StorageUtil.SetFloatValue(self, "mtf.cond.persistgt." + slot, val)
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

; v0.2.1: the legacy `.ex.<name>` keyspace + GetSlotEffectExtra/
; SetSlotEffectExtra / _populateEffectExtrasDefaults / _clearEffectExtras
; collapsed into the uniform paramN scheme below. Params 1 and 2 use
; `mtf.fx.<s>.<e>.paramN`; params 3-5 (former extras) use the same path
; and are now positional (the catalog's order in param3/param4/param5
; defines what each slot means). Plugin behaviour code that used to read
; `GetSlotEffectExtra(slot, eff, "rampms")` now reads
; `GetSlotEffectParam(slot, eff, 3)`.

int Function _maxParamN() global
{Compile-time max for uniform paramN. 1+2 = legacy primary/secondary
 slider; 3-5 = former extras. Bump this and the matching MCM state pool
 if a future effect needs more controls.}
    return 5
EndFunction

; ── Effect dispatch context (v0.1.3 → v0.2.10) ─────────────────────────────
; v0.2.10: dispatch context now flows as explicit FUNCTION PARAMETERS
; (slot/effectIdx/useScratch/baseSlot/area) down through _dispatchActivate /
; plugin.onActivate / its helpers. The earlier StorageUtil-backed
; mtf.dispatch.* keys were race-prone: each cross-script call into a
; plugin function yields the VM, and during that yield a concurrent fiber
; (slow-tick OnUpdate, MCM-driven rebind, NPC dispatch) could rewrite the
; shared keys before the plugin's first read. The plugin would then read
; the WRONG effect's slot/eff/useScratch and silently mis-dispatch
; (skill/resist tests failed at random across F10 runs because of this).
;
; The getters below are kept for ONE remaining caller path: the public
; accessors GetSlotEffectParamN / GetSlotEffectKey / etc. route useScratch
; through _getDispatchUseScratch() for backward-compat with MCM / test
; callers. Since nothing writes the keys anymore, the getters return
; their safe defaults (slot=-1, useScratch=false, baseSlot fallback =
; OverlaySlot, area=0) — exactly what those callers expect from the
; player keyspace. The setter functions are gone (delete-bait if no
; external script restores them).

int Function _getDispatchSlot()
    return StorageUtil.GetIntValue(self, "mtf.dispatch.slot", -1)
EndFunction

int Function _getDispatchEffectIdx()
    return StorageUtil.GetIntValue(self, "mtf.dispatch.effectidx", -1)
EndFunction

int Function _getDispatchBaseSlot()
{Legacy getter (v0.1.3..v0.2.9). Post-v0.2.10 nothing writes the backing
 StorageUtil key, so this always falls back to OverlaySlot — correct for
 the MCM / test read paths that survived the dispatch-context-as-params
 refactor.}
    int v = StorageUtil.GetIntValue(self, "mtf.dispatch.baseslot", -1)
    if v < 0
        return OverlaySlot
    endif
    return v
EndFunction

int Function _getDispatchArea()
{Legacy getter — see _getDispatchBaseSlot. Always returns 0 (Body) now
 that nothing writes the backing key.}
    return StorageUtil.GetIntValue(self, "mtf.dispatch.area", 0)
EndFunction

bool Function _getDispatchUseScratch()
{Legacy getter — see _getDispatchBaseSlot. Always returns false (player
 keyspace) now that nothing writes the backing key. Public accessors
 (GetSlotEffectParamN/etc.) lean on this; MCM and test callers want false.}
    return StorageUtil.GetIntValue(self, "mtf.dispatch.usescratch", 0) != 0
EndFunction

; (v0.2.1: _loadScratchExtra removed — the named-extras storage path it
; populated is gone, replaced by the uniform paramN scratch keys written
; inline in _loadPresetToScratch.)

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
        if _sArraysReady && tier >= 0
            name = _getScratchWaveform(tier)
        endif
    else
        name = GetCondWaveform(tier)
    endif
    return _buildWaveformLUT(name)
EndFunction

bool Function _slotHasPulse(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return false
    endif
    return GetCondPulseRate(slot) > 0.0 && GetCondPulseDepth(slot) > 0
EndFunction

bool Function _slotHasFlashEffect(int slot)
{Returns true if any of the slot's 4 effect rows is bound to the
 mtf.fx:flash.onhit effect. Used by _resyncPulseCache to register a
 (rate=0) roster entry for flash-only tiers — the C++ Tick needs a live
 entry to run the additive flash lane on top of the (no-pulse) ceiling.
 v0.3.9: flash.onhit moved from mtf.base to the mtf.fx module on the split.}
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return false
    endif
    int e = 0
    while e < MAX_EFFECTS_PER_SLOT()
        if GetSlotEffectKey(slot, e) == "mtf.fx:flash.onhit"
            return true
        endif
        e += 1
    endwhile
    return false
EndFunction

Function _resyncPulseCache(int tier)
{Snapshot per-tier overlay context for the fast pulse tick.

 v0.1.28 V4 cross-fade: a roster entry is now installed for ANY tier with
 valid layers, not just tiers with pulse/flash/fade. This lets C++ Tick own
 em/alpha/tint/em-color writes uniformly and drive cross-fades for "purely
 visual" tier changes (different color/alpha/em between tiers, no animation
 lane). Tick handles rate=0 correctly — pulsed=1, em_no_flash=layer_base_em.
 The (tiny) cost of always running Tick for an MCM-base actor is one entry
 worth of skee_bridge writes per frame; trivial compared to the eval/draw
 cost it replaces.}
    _pulseTier = -1
    if tier < 0 || tier > MAX_CONDITIONS_CACHED() || PlayerRef == None
        return
    endif
    string packId  = ResolveSlotPackId(tier)
    string entryId = ResolveSlotEntryId(tier)
    if packId == "" || packId == "<none>" || entryId == ""
        return
    endif
    ; v0.3.7: the active tier's pack determines BOTH the texture and which
    ; area it paints into. Cache that area so _applyPulse installs the C++
    ; roster entry at the right <Area>OverlaySlot — the old code hardcoded
    ; Body, so Face/Hands/Feet MCM-base overlays never got a roster entry,
    ; their alpha/emissive were never driven, and they rendered invisible
    ; (or black when alpha was forced up, since the em=0 floor lives in the
    ; C++ Tick that never ran for them). Area cap must match too.
    string area = GetPackArea(packId)
    int layerN = GetEntryLayerCount(packId, entryId)
    int max = _maxLayerSlots(area)
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
    _pulseArea = area
    _pulseLayerN = layerN
    _pulseTier = tier
    if DebugMode && _sFadeOnDeathEnabled
        Debug.Notification("[MTF fade] cache armed tier=" + tier + " mode=" + _sFadeOnDeathMode + " dur=" + _sFadeOnDeathDurationMs + "ms")
    endif
EndFunction

Function _applyPulse(float forcedTDur = -1.0)
{Hot path. Forwards the player's pulse parameters into the MTFPulse C++
 roster. C++ does the per-frame wave math + NiOverride writes at full
 frame rate via the PlayerCharacter::Update vtable hook in MTFPulse.dll.

 This function still runs at the OnUpdate fast tick (~10 Hz) so MCM
 slider edits to rate / depth / pause / per-layer emissive multiplier
 propagate to the roster within 100 ms.

 v0.1.28 V4 cross-fade: now always uses SetActorPulseWithTransition (the
 plain SetActorPulse entry point is no longer called from here). On
 tier-change the caller passes forcedTDur=_sTransitionDuration; subsequent
 10 Hz refreshes pass forcedTDur=-1 and we compute remaining time as
 max(0, _transitionEndRT - now). Each install captures from-state from
 prev.last_interp, so the slope stays constant across refreshes and the
 lerp lands at the original target time. Once _transitionEndRT has passed
 we pass tDur=0 → C++ runs as a steady ceiling write.

 We also pack per-layer tints/alphas/emissives now (previously only
 emMults) so Tick can cross-fade ALL four interpolatable shader
 properties — em mult, alpha, tint, emissive color — for the MCM-base
 path. Texture binding and falloff are not interpolated; texture inherits
 from Default on shared-pack tier changes, falloff snap is imperceptible.

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
        ; v0.3.7: clear the MCM-base entry in EVERY area (was body-only).
        _clearBaseAreaEntries()
        _pulseTier = -1
        return
    endif
    if _pulseTier < 0 || _pulseLayerN <= 0 || PlayerRef == None
        ; Drop just the MCM-base pulse entries (every area). Stacked presets
        ; sit at their own base_slots above the area base and must keep
        ; pulsing — _clearBaseAreaEntries only touches <Area>OverlaySlot, so
        ; preset entries are untouched.
        _clearBaseAreaEntries()
        return
    endif

    int depthPct = GetCondPulseDepth(_pulseTier)
    float rate   = GetCondPulseRate(_pulseTier)
    float pause  = GetCondPulsePause(_pulseTier)

    ; Per-layer target arrays. MCM slider edits to any of these become
    ; visible on the next 10 Hz refresh.
    Float[] emMults   = Utility.CreateFloatArray(_pulseLayerN)
    Int[]   tints     = Utility.CreateIntArray(_pulseLayerN)
    Int[]   alphas    = Utility.CreateIntArray(_pulseLayerN)
    Int[]   emissives = Utility.CreateIntArray(_pulseLayerN)
    int i = 0
    while i < _pulseLayerN
        ; v0.2.8: route through unified (slot, L) accessors. Per-call cost is
        ; one StorageUtil read (~10 µs) now that MAX_CONDITIONS_CACHED bypasses
        ; the INI lookup that used to dominate this loop. ~0.4-1.6 ms/sec total
        ; at 10 Hz × 2-4 layers — imperceptible.
        emMults[i]   = GetCondLayerEmissiveMult(_pulseTier, i)
        tints[i]     = GetCondLayerTint(_pulseTier, i)
        alphas[i]    = GetCondLayerAlpha(_pulseTier, i)
        emissives[i] = GetCondLayerEmissive(_pulseTier, i)
        ; em=0 black-blob floor lives in skee_bridge::WriteEmissiveMult
        ; (clamps 0→0.001 at the SKEE write boundary). Papyrus sends
        ; user intent unchanged so StorageUtil round-trips em=0 cleanly.
        i += 1
    endwhile

    ; v0.1.29 different-texture cross-blend Phase A: keep OLD texture
    ; (currentTier still points at OLD, so emMults/tints/emissives above
    ; are read from OLD's per-layer arrays). Override target_alpha to 0
    ; so C++ Tick lerps alpha down to fully transparent over the half-
    ; window. At Phase A end, alpha = 0; Phase B swaps the texture
    ; binding then and fades alpha back up — no snap visible because
    ; alpha is 0 at swap time.
    if _crossBlendActive && _crossBlendInPhaseA
        ; Drive BOTH alpha AND em_mult to 0 so the emissive lane doesn't
        ; keep glowing through the (now invisible) texture. Tint/em_color
        ; targets stay at OLD's values (no visible change since
        ; currentTier didn't move); C++ Tick will naturally lerp em_mult
        ; OLD→0 and alpha OLD→0 in parallel over the half-window. Gloss/
        ; spec are derived from em_no_flash in C++ Tick so they drop to 0
        ; alongside em automatically.
        int j = 0
        while j < _pulseLayerN
            alphas[j]   = 0
            emMults[j]  = 0.0
            j += 1
        endwhile
        if DebugMode
            Debug.Trace("[MTF xb] _applyPulse PhaseA override alpha+em=0 layerN=" + _pulseLayerN + " tier=" + _pulseTier + " forcedTDur=" + forcedTDur)
        endif
    endif

    ; Remaining-time pattern. The redraw block primes forcedTDur on the
    ; tier-change edge; every other path leaves it -1 so we compute
    ; remaining = max(0, _transitionEndRT - now). After the window closes
    ; tDur=0 turns subsequent installs into snap-equivalents (still go
    ; through SetActorPulseWithTransition but with no lerp).
    float tDur
    if forcedTDur >= 0.0
        tDur = forcedTDur
    else
        float nowRT = Utility.GetCurrentRealTime()
        if nowRT < _transitionEndRT
            tDur = _transitionEndRT - nowRT
        else
            tDur = 0.0
        endif
    endif

    Float[] lut = _waveformLUTForTier(_pulseTier, false)
    if DebugMode && _crossBlendActive
        Debug.Trace("[MTF xb] _applyPulse sent tier=" + _pulseTier + " area=" + _pulseArea + " layerN=" + _pulseLayerN + " alpha0=" + alphas[0] + " tDur=" + tDur + " phaseA=" + _crossBlendInPhaseA + " endRT=" + _transitionEndRT)
    endif

    ; v0.3.7 multi-area MCM-base: install the roster entry at the active tier's
    ; area (_pulseArea) and CLEAR the other three areas' base entries. Only one
    ; area is ever lit on the MCM-base path (drawOverlayForActor paints exactly
    ; the active tier's area, clearing the rest), so this mirrors the draw: one
    ; install, three clears. Clearing the inactive areas every refresh is what
    ; tears down the OLD area's entry on an area-switch (e.g. a Body tier giving
    ; way to a Face tier) — without it the C++ Tick keeps driving the now-empty
    ; old node. Mirrors _rosterAddOrUpdate's per-area loop. ClearActorAt on a
    ; non-existent entry is a C++ no-op, so over-clearing inactive areas is fine.
    string[] parts = _OVERLAY_PARTS()
    int p = 0
    while p < parts.Length
        string area  = parts[p]
        int areaIdx  = _areaIndex(area)
        int baseSlot = _areaBaseSlot(area)
        if area == _pulseArea
            MTFPulse.SetActorPulseWithTransition(PlayerRef, rate, depthPct, pause, \
                                                 _pulseLayerN, _pulseStartRT, emMults, \
                                                 baseSlot, _pulseIsFemale, lut, \
                                                 tints, alphas, emissives, tDur, areaIdx)
            ; v0.1.4 per-preset fade: re-arm or clear after the roster entry is
            ; up. Idempotent on the C++ side; an in-flight fade isn't disturbed.
            if _sFadeOnDeathEnabled
                MTFPulse.SetActorFade(PlayerRef, baseSlot, _sFadeOnDeathMode, _sFadeOnDeathDurationMs, areaIdx)
            else
                MTFPulse.ClearActorFade(PlayerRef, baseSlot, areaIdx)
            endif
        else
            MTFPulse.ClearActorAt(PlayerRef, baseSlot, areaIdx)
        endif
        p += 1
    endwhile
EndFunction

Function _clearBaseAreaEntries()
{Clear the player MCM-base pulse roster entry in EVERY area
 (Body/Face/Hands/Feet) — each at its <Area>OverlaySlot. Used when the base
 path goes idle (no active tier, or player dead). Stacked presets live at
 base_slots ABOVE the area base, so they are untouched. ClearActorAt on a
 non-existent entry is a C++ no-op.}
    if PlayerRef == None
        return
    endif
    string[] parts = _OVERLAY_PARTS()
    int p = 0
    while p < parts.Length
        MTFPulse.ClearActorAt(PlayerRef, _areaBaseSlot(parts[p]), _areaIndex(parts[p]))
        p += 1
    endwhile
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
    ; v0.3.7: target the active MCM-base area's entry. If no tier is active
    ; the entry doesn't exist and TriggerActorFlash is a C++ no-op.
    MTFPulse.TriggerActorFlash(PlayerRef, _areaBaseSlot(_pulseArea), tag, _areaIndex(_pulseArea))
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

; ── Cast tracking (v0.1.25) ─────────────────────────────────────────────────
; Mirror of the hit-counter helpers but for spell casting. Continuous state
; (not event-counter): MTF_CastListener polls animation variables every 0.1s
; while a cast is held and writes the bool here; combat.casting condition
; reads it back. StorageUtil-backed for the same reason as hit counters
; (post-release Auto property attach gotcha) and so NPC slots default to
; false cleanly.
;
; Detection mechanism is animvar-based (bWantCastLeft / bWantCastRight /
; IsCastingDual / bRitualSpellActive) — the same pattern ZAO Active Overlays
; uses, more reliable than chasing BeginCast*/SpellRelease event pairs
; (which miss interrupts and concentration edge cases). See KNOWLEDGEBASE
; entry "Cast-state detection".
;
; Currently player-only — MTF_CastListener is alias-bound to the player.
; NPCs always read false. Per-actor StorageUtil keying leaves the door open
; for NPC support later without schema migration.

bool Function IsCasting(Actor target)
    if target == None
        return false
    endif
    return StorageUtil.GetIntValue(target, "mtf.casting.active", 0) == 1
EndFunction

Function _setCasting(Actor target, bool active)
    if target == None
        return
    endif
    if active
        StorageUtil.SetIntValue(target, "mtf.casting.active", 1)
    else
        StorageUtil.SetIntValue(target, "mtf.casting.active", 0)
    endif
EndFunction

; Mirror of DispatchFlashHit but for the "cast" tag namespace. Called by
; MTF_CastListener on cast start and on every poll tick while the cast is
; held — the C++ pulse roster's retrigger window keeps the additive
; emissive lane lit between calls.
Function DispatchFlashCast(string tag)
{Public extension hook. External mods can call this with their own tag
 ("cast.fire", "cast.healing", etc.) and any flash.onhit effect bound to
 the matching trigger tag will flash. Built-in CastListener fires the
 plain "cast" tag — flash.onhit with trigger option 128 ("On spell cast")
 registers exactly that.}
    if PlayerRef == None || tag == ""
        return
    endif
    ; v0.3.7: target the active MCM-base area's entry (was body-only).
    MTFPulse.TriggerActorFlash(PlayerRef, _areaBaseSlot(_pulseArea), tag, _areaIndex(_pulseArea))
EndFunction

; ── Presets (PapyrusUtil JsonUtil, cross-save) ──────────────────────────────
; Presets live in TWO sibling folders under
; Data/SKSE/Plugins/StorageUtil/MagicTattoosFramework/:
;   presets/          — USER presets. Writable: SavePreset/DeletePreset only
;                       ever touch this folder. Shown in the MCM picker + the
;                       Apply Tattoo spell.
;   presets_builtin/  — READ-ONLY presets shipped with the framework (load-test
;                       fixtures today; example presets later). Never written by
;                       the mod, so a manual save can't clobber them. Hidden from
;                       the user pickers but still enumerated + loadable by the
;                       test runner (ListPresets includes them; ListVisiblePresets
;                       does not).
; JsonUtil has no native delete, so a deleted USER preset can't be removed — it
; carries a `hidden` int (0/absent = live, 1 = deleted). The file lingers as a
; reclaimable tombstone; re-saving the same name clears the flag. Built-in
; presets are identified by folder, not by any flag.
; Captures slot config (cond + effects + cooldown + visuals) and each
; registered plugin's per-plugin Setting values. Globals (ModActive, etc.)
; are intentionally excluded.

string Function _userPresetFile(string name)
{Path to a USER preset (writable folder). SavePreset/DeletePreset use this.}
    return "MagicTattoosFramework/presets/" + name
EndFunction

string Function _builtinPresetFile(string name)
{Path to a READ-ONLY built-in preset (shipped fixtures/examples).}
    return "MagicTattoosFramework/presets_builtin/" + name
EndFunction

string Function _presetFile(string name)
{Resolver for READS/loads: prefer a user preset of this name, else fall back to
 a built-in. Callers JsonExists-check the result and bail if neither exists.
 WRITES must NOT use this — they target _userPresetFile so they never touch the
 read-only built-in folder.}
    string uf = "MagicTattoosFramework/presets/" + name
    if JsonUtil.JsonExists(uf)
        return uf
    endif
    string bf = "MagicTattoosFramework/presets_builtin/" + name
    if JsonUtil.JsonExists(bf)
        return bf
    endif
    return uf
EndFunction

string Function _stripJsonExt(string raw)
{Strip a trailing ".json" from a JsonInFolder entry. The dot>0 guard keeps the
 PapyrusUtil Substring(s,0,0)=whole-string trap from firing on a leading dot.}
    int dot = StringUtil.Find(raw, ".json")
    if dot > 0
        return StringUtil.Substring(raw, 0, dot)
    endif
    return raw
EndFunction

int Function _indexOfName(string[] arr, int count, string name)
    int i = 0
    while i < count
        if arr[i] == name
            return i
        endif
        i += 1
    endwhile
    return -1
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

string Function _sanitizeSlotName(string raw)
    ; Display-only slot label. Unlike _sanitizePresetName (which sanitizes for a
    ; FILENAME and underscores everything outside [A-Za-z0-9_-]), a slot name is
    ; never a filename or JSON key — it's stored as a string VALUE (.name) and
    ; only rendered in the MCM. So we keep spaces and mixed case, allow common
    ; punctuation, and simply DROP anything JSON/Scaleform-unsafe rather than
    ; underscoring it. Cap at 32 kept chars.
    if raw == ""
        return ""
    endif
    string allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-.,'()&!?:+%"
    string out = ""
    int i = 0
    int maxL = 32
    int rawLen = StringUtil.GetLength(raw)
    while i < rawLen && StringUtil.GetLength(out) < maxL
        string ch = StringUtil.Substring(raw, i, 1)
        if StringUtil.Find(allowed, ch) >= 0
            out += ch
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
    ; A built-in (read-only) preset of this name exists — refuse. SavePreset
    ; only writes the user folder, so saving here would create a user preset
    ; that SHADOWS the built-in in _presetFile's resolver and hide it from the
    ; test runner's by-name loads. Make the user pick another name instead.
    if JsonUtil.JsonExists(_builtinPresetFile(name))
        Notification("MTF: '" + rawName + "' is a reserved built-in preset name — choose another")
        return false
    endif
    string f = _userPresetFile(name)
    JsonUtil.ClearAll(f)
    ; hidden=0 marks this as a live, user-visible preset and clears any prior
    ; deleted-tombstone flag when a previously-deleted name is reclaimed.
    JsonUtil.SetPathIntValue(f,    ".hidden",        0)
    JsonUtil.SetPathStringValue(f, ".displayname",   rawName)
    ; v0.1.24: schema 8 — cooldown rework. cooldown.min/cooldown.mode replaced
    ; by persist.min, persist.allowOverride, cool.min. Old keys are NOT read
    ; on load; existing presets reset to defaults (persist=0, cool=0,
    ; allowOverride=1).
    ; v0.2.9: schema 9 — adds optional .slot[<s>].name (user-authored display
    ; name). v8 presets load cleanly: missing .name reads as empty string and
    ; the MCM falls back to the canonical "Default" / "Condition N" label.
    JsonUtil.SetPathIntValue(f,    ".schemaversion", 9)

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
    int maxC = MAX_CONDITIONS()
    int mcmCap = MAX_CONDITIONS_MCM()
    int s = 0
    while s <= maxC
        ; v0.2.7 perf fast-path: backend slot with no pluginId has nothing
        ; worth serializing. MCM-cap slots (0..mcmCap) always serialize
        ; even when empty so a hand-edited preset JSON keeps the canonical
        ; slot[0..mcmCap] block shape.
        string slotPid = GetCondPluginId(s)
        if s > mcmCap && slotPid == ""
            s += 1
        else
        string sp = ".slot[" + s + "]"
        ; v0.3.1: conditions serialized as an ARRAY (.cond.items[]) + a single
        ; operator (.cond.op: 0=AND, 1=OR). No more special-cased cond[0] /
        ; condx<j> — every condition is items[j], read back via PathCount.
        ; cond[0] reuses the live scalar accessors through the At(s,0)
        ; delegators, so the StorageUtil keyspace is unchanged. Slot is
        ; "configured" iff items[0].pluginid is non-empty (count 0 => no array,
        ; absent on load). _condParamIsMenu routes each param string-vs-int.
        int condN = GetCondCount(s)
        if condN >= 1
            JsonUtil.SetPathIntValue(f, sp + ".cond.op", GetCondOp(s))
            int cjW = 0
            while cjW < condN
                string ipW = sp + ".cond.items[" + cjW + "]"
                string ikeyW = GetCondPluginIdAt(s, cjW)
                JsonUtil.SetPathStringValue(f, ipW + ".pluginid", ikeyW)
                if _condParamIsMenu(ikeyW)
                    JsonUtil.SetPathStringValue(f, ipW + ".param", GetCondParamStrAt(s, cjW))
                else
                    JsonUtil.SetPathIntValue(f, ipW + ".param", GetCondParamAt(s, cjW))
                endif
                if _condParam2IsMenu(ikeyW)
                    JsonUtil.SetPathStringValue(f, ipW + ".param2", GetCondParam2StrAt(s, cjW))
                else
                    JsonUtil.SetPathIntValue(f, ipW + ".param2", GetCondParam2At(s, cjW))
                endif
                if _condParam3IsStr(ikeyW)
                    JsonUtil.SetPathStringValue(f, ipW + ".param3", GetCondParam3StrAt(s, cjW))
                else
                    JsonUtil.SetPathIntValue(f, ipW + ".param3", GetCondParam3At(s, cjW))
                endif
                cjW += 1
            endwhile
        endif
        ; v0.2.9 per-slot display name (sidecar to cond.*). Only emit when
        ; non-empty so untouched presets keep clean JSON. Empty fallback in
        ; MCMQuest._slotLabel handles the missing-field case.
        string slotName = GetCondName(s)
        if slotName != ""
            JsonUtil.SetPathStringValue(f, sp + ".name", slotName)
        endif
        ; v0.2.8: visual/persist serialization unified across all 32 slots
        ; via StorageUtil-backed accessors. Backend slots (> mcmCap) now
        ; round-trip their own pack/entry/persist values; empty backend
        ; slots were already fast-skipped above so default-value emit for
        ; "configured backend slot with no custom visual" is harmless.
        JsonUtil.SetPathStringValue(f, sp + ".cond.packid",            GetCondPackId(s))
        JsonUtil.SetPathStringValue(f, sp + ".cond.entryid",           GetCondEntryId(s))
        JsonUtil.SetPathIntValue(f,    sp + ".persist.min",            GetCondPersistMin(s))
        JsonUtil.SetPathIntValue(f,    sp + ".persist.allowOverride",  GetCondAllowOverride(s))
        JsonUtil.SetPathIntValue(f,    sp + ".cool.min",               _getCoolMin(s))
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
        ; v0.2.8: layer serialization unified across all 32 slots via accessors.
        ; Empty backend slots were fast-skipped above; configured backend slots
        ; emit their per-slot layer values (defaults are fine — white tint /
        ; 100% alpha / 0 emissive mult round-trip cleanly).
        int L = 0
        while L < maxL
            string lp = sp + ".layer[" + L + "]"
            JsonUtil.SetPathStringValue(f, lp + ".tint",         _intToHex(GetCondLayerTint(s, L)))
            JsonUtil.SetPathStringValue(f, lp + ".emissive",     _intToHex(GetCondLayerEmissive(s, L)))
            JsonUtil.SetPathFloatValue(f,  lp + ".emissivemult", GetCondLayerEmissiveMult(s, L))
            JsonUtil.SetPathIntValue(f,    lp + ".alpha",        GetCondLayerAlpha(s, L))
            L += 1
        endwhile
        int e = 0
        while e < maxE
            ; Skip serializing effect rows with empty key — load uses defaults.
            string fxKey = _readFxKey(s, e, false)
            if fxKey != ""
                string ep = sp + ".effect[" + e + "]"
                JsonUtil.SetPathStringValue(f, ep + ".key", fxKey)
                ; v0.2.1: uniform paramN serialization. Walk 1..5 and emit
                ; each value as `paramN`. v0.2.9: probe the catalog per
                ; param — menu params write string id, sliders write int.
                int n = 1
                while n <= 5
                    ; v0.3.x: menu OR text params serialize as string; sliders as int.
                    if _effectParamIsStr(fxKey, n)
                        string sval = _readFxParamNStr(s, e, n, false)
                        if sval != ""
                            JsonUtil.SetPathStringValue(f, ep + ".param" + n, sval)
                        endif
                    else
                        JsonUtil.SetPathIntValue(f, ep + ".param" + n, _readFxParamN(s, e, n, false))
                    endif
                    n += 1
                endwhile
            endif
            e += 1
        endwhile
        s += 1
        endif   ; end of "empty backend slot fast-path"
    endwhile

    ; (v0.2.1: per-plugin settings persistence removed — base class no
    ; longer exposes GetSettingCount/Id/Value. Preset JSON `.setting.*`
    ; paths from older saves are simply ignored on load.)

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
    if JsonUtil.GetPathIntValue(f, ".hidden", 0) == 1
        return false ; deleted tombstone — not loadable (fixtures, hidden==2, still load)
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

    ; v0.2.8: all per-slot fields (cond/persist/layer/pulse) lifted to
    ; StorageUtil-backed accessors. No more local-array workaround for
    ; indexed-write-to-property quirks. Loop is uniform across slots
    ; 0..MAX_CONDITIONS(); empty backend slots get cheap default values
    ; from JSON-missing reads.
    int s = 0
    int maxC = MAX_CONDITIONS()
    int mcmCap = MAX_CONDITIONS_MCM()
    while s <= maxC
        string sp = ".slot[" + s + "]"
        ; v0.3.1: conditions read from the .cond.items[] array. PathCount gives
        ; the count; items[0].pluginid empty / array absent => unconfigured slot.
        ; ClearSlotExtraConds wipes any stale extras (index >= 1) from the prior
        ; preset first, then we repopulate item 0 (live scalar keys via the
        ; At(s,0) delegators) and any extras.
        ClearSlotExtraConds(s)
        int condN = JsonUtil.PathCount(f, sp + ".cond.items")
        if condN < 1
            ; Unconfigured slot — reset item 0 to empty, count 1, op AND.
            SetCondPluginId(s, "")
            SetCondParam(s, 0)
            SetCondParamStr(s, "")
            SetCondParam2(s, 0)
            SetCondParam2Str(s, "")
            SetCondParam3(s, 0)
            SetCondParam3Str(s, "")
            SetCondCount(s, 1)
            SetCondOp(s, 0)
        else
            SetCondOp(s, JsonUtil.GetPathIntValue(f, sp + ".cond.op", 0))
            int cjR = 0
            while cjR < condN
                string ipR = sp + ".cond.items[" + cjR + "]"
                string ikeyR = JsonUtil.GetPathStringValue(f, ipR + ".pluginid", "")
                SetCondPluginIdAt(s, cjR, ikeyR)
                if _condParamIsMenu(ikeyR)
                    SetCondParamStrAt(s, cjR, JsonUtil.GetPathStringValue(f, ipR + ".param", ""))
                    SetCondParamAt(s, cjR, 0)
                else
                    SetCondParamAt(s, cjR, JsonUtil.GetPathIntValue(f, ipR + ".param", 0))
                    SetCondParamStrAt(s, cjR, "")
                endif
                if _condParam2IsMenu(ikeyR)
                    SetCondParam2StrAt(s, cjR, JsonUtil.GetPathStringValue(f, ipR + ".param2", ""))
                    SetCondParam2At(s, cjR, 0)
                else
                    SetCondParam2At(s, cjR, JsonUtil.GetPathIntValue(f, ipR + ".param2", 0))
                    SetCondParam2StrAt(s, cjR, "")
                endif
                if _condParam3IsStr(ikeyR)
                    SetCondParam3StrAt(s, cjR, JsonUtil.GetPathStringValue(f, ipR + ".param3", ""))
                    SetCondParam3At(s, cjR, 0)
                else
                    SetCondParam3At(s, cjR, JsonUtil.GetPathIntValue(f, ipR + ".param3", 0))
                    SetCondParam3StrAt(s, cjR, "")
                endif
                cjR += 1
            endwhile
            SetCondCount(s, condN)
        endif
        ; v0.2.9 per-slot display name. Empty default = use canonical label.
        SetCondName(s,     JsonUtil.GetPathStringValue(f, sp + ".name", ""))
        _setCoolMin(s, JsonUtil.GetPathIntValue(f, sp + ".cool.min", 0))
        ; Clear any active persist/cool timers when loading a preset — slots
        ; start fresh regardless of inherited timer state.
        _setCoolUntilGT(s, 0.0)
        SetCondPersistUntilGT(s, 0.0)
        SetCondPulseRate(s, JsonUtil.GetPathFloatValue(f, sp + ".pulse.rate",  0.0))
        SetCondPulseDepth(s, JsonUtil.GetPathIntValue(f,   sp + ".pulse.depth", 0))
        SetCondPulsePause(s, JsonUtil.GetPathFloatValue(f, sp + ".pulse.pause", 0.0))
        SetCondWaveform(s, JsonUtil.GetPathStringValue(f, sp + ".pulse.waveform", ""))
        SetCondPackId(s,   JsonUtil.GetPathStringValue(f, sp + ".cond.packid",  ""))
        SetCondEntryId(s,  JsonUtil.GetPathStringValue(f, sp + ".cond.entryid", ""))
        ; v0.1.24 cooldown semantics: persist.min, persist.allowOverride.
        ; Default allowOverride=1 (allow higher-priority slot to take over
        ; during persist phase).
        SetCondPersistMin(s,      JsonUtil.GetPathIntValue(f, sp + ".persist.min", 0))
        SetCondAllowOverride(s,   JsonUtil.GetPathIntValue(f, sp + ".persist.allowOverride", 1))
        int L = 0
        while L < maxL
            string lp = sp + ".layer[" + L + "]"
            SetCondLayerTint(s, L,         _readColor(f, lp + ".tint",         16777215))
            SetCondLayerEmissive(s, L,     _readColor(f, lp + ".emissive",     16777215))
            SetCondLayerEmissiveMult(s, L, JsonUtil.GetPathFloatValue(f, lp + ".emissivemult", 0.0))
            SetCondLayerAlpha(s, L,        JsonUtil.GetPathIntValue(f,   lp + ".alpha",        100))
            L += 1
        endwhile
        ; v0.2.7 perf fast-path: backend slots (> mcmCap) with empty
        ; pluginId have no condition to evaluate, so any effect bindings
        ; would be dead anyway. Skip the inner 32-iteration effect loop —
        ; saves ~6 cross-script calls × maxE × (maxC-mcmCap) slots, which
        ; for the default 32/32/7 = ~4800 calls of pure no-op churn that
        ; was hanging the VM thread mid-LoadPreset.
        ;
        ; MCM-cap slots (0..mcmCap) still iterate unconditionally so
        ; stale bindings from a previous preset get cleared even when
        ; the new preset's slot is empty.
        bool runEffectLoop = (s <= mcmCap) || (GetCondPluginId(s) != "")
        int e = 0
        while runEffectLoop && e < maxE
            string ep = sp + ".effect[" + e + "]"
            string newKey = JsonUtil.GetPathStringValue(f, ep + ".key", "")
            _writeFxKey(s, e, false, newKey)
            ; v0.2.1: uniform paramN load. For each n in 1..5: read paramN
            ; from the preset; if missing, fall back to the bound effect's
            ; declared default (so a preset that doesn't override a slider
            ; gets the catalog's intent). Use a sentinel -999999 to detect
            ; absent keys vs explicit 0.
            MTF_Plugin pLoad = ResolvePluginByKey(newKey)
            int itemIdxLoad = -1
            if pLoad != None
                itemIdxLoad = _effectIdxFor(pLoad, _keyItemId(newKey))
            endif
            int n = 1
            while n <= 5
                ; v0.2.9: per-param menu-vs-slider routing on load too. Menu
                ; params read string id (default = catalog's GetEffectParamDefaultId);
                ; sliders read int (default = catalog's GetEffectParamDefault).
                ; v0.3.x: text params also read as string (same path as menus —
                ; GetEffectParamDefaultId returns the catalog's default text).
                bool isStrN = (itemIdxLoad >= 0 && (pLoad.GetEffectParamMenuOptionCount(itemIdxLoad, n) > 0 || pLoad.GetEffectParamIsText(itemIdxLoad, n)))
                if isStrN
                    string svalLoad = JsonUtil.GetPathStringValue(f, ep + ".param" + n, "")
                    if svalLoad == "" && itemIdxLoad >= 0
                        svalLoad = pLoad.GetEffectParamDefaultId(itemIdxLoad, n)
                    endif
                    _writeFxParamNStr(s, e, n, false, svalLoad)
                    _writeFxParamN(s, e, n, false, 0)
                else
                    int sentinel = -999999
                    int v = JsonUtil.GetPathIntValue(f, ep + ".param" + n, sentinel)
                    if v == sentinel
                        if itemIdxLoad >= 0
                            v = pLoad.GetEffectParamDefault(itemIdxLoad, n)
                        else
                            v = 0
                        endif
                    endif
                    _writeFxParamN(s, e, n, false, v)
                    _writeFxParamNStr(s, e, n, false, "")
                endif
                n += 1
            endwhile
            e += 1
        endwhile
        s += 1
    endwhile

    ; v0.2.8: no more bulk array reassign — per-slot accessors wrote directly
    ; to StorageUtil inside the loop. persist timer cleared per-slot via
    ; SetCondPersistUntilGT(s, 0.0) above.

    ; (v0.2.1: per-plugin settings load removed — see save site for context.)

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

    ; v0.2.8: all per-slot fields are StorageUtil-backed now — direct accessor
    ; calls inside the loop, no local-array workaround. Widened to
    ; MAX_CONDITIONS() so backend slots also clear cleanly on "New preset".
    int maxC = MAX_CONDITIONS()
    int s = 0
    while s <= maxC
        SetCondPluginId(s, "")
        SetCondParam(s, 0)
        SetCondParam2(s, 0)
        SetCondName(s, "")
        SetCondPackId(s, "")
        SetCondEntryId(s, "")
        SetCondPersistMin(s, 0)
        SetCondAllowOverride(s, 1)   ; default: allow higher-priority override during persist
        SetCondPersistUntilGT(s, 0.0)
        _setCoolMin(s, 0)
        _setCoolUntilGT(s, 0.0)
        SetCondPulseRate(s, 0.0)
        SetCondPulseDepth(s, 0)
        SetCondPulsePause(s, 0.0)
        SetCondWaveform(s, "")
        int L = 0
        while L < maxL
            SetCondLayerTint(s, L, 16777215)
            SetCondLayerEmissive(s, L, 16777215)
            SetCondLayerEmissiveMult(s, L, 0.0)
            SetCondLayerAlpha(s, L, 100)
            L += 1
        endwhile
        int e = 0
        while e < maxE
            _writeFxKey(s, e, false, "")
            int n = 1
            while n <= 5
                _writeFxParamN(s, e, n, false, 0)
                n += 1
            endwhile
            e += 1
        endwhile
        s += 1
    endwhile

    forceRedraw = true
EndFunction

bool Function DeletePreset(string name)
    ; Only USER presets are deletable; built-ins live in the read-only folder
    ; and aren't selectable in the picker. Target the user file explicitly so a
    ; built-in name can never be tombstoned.
    string f = _userPresetFile(name)
    if !JsonUtil.JsonExists(f)
        return false
    endif
    ; Soft-delete: flag hidden=1 (top-level, via the path API so ListPresets /
    ; LoadPreset actually see it — the old SetIntValue("valid",0) wrote a
    ; different storage slot than the readers used, so deletes never took).
    ; JsonUtil can't remove files; the .json lingers as a reclaimable tombstone.
    JsonUtil.SetPathIntValue(f, ".hidden", 1)
    JsonUtil.Save(f)
    ; Drop any cached scratch buffer for this preset (Plan B v2) — even
    ; though the hidden=1 flag will gate future cold loads, a stale cached
    ; copy would still hit the warm path until invalidated.
    _invalidateScratchCache(name)
    return true
EndFunction

string[] Function ListPresets()
{Fixed-size 64 array of the FULL catalog the test runner enumerates: every
 non-deleted USER preset plus every built-in. Names first, empty strings after.
 For the user-facing pickers use ListVisiblePresets (user, non-deleted only).
 Caller iterates and stops on the first empty string (or use ListPresetsCount).}
    string[] result = new string[64]
    ; Both JsonInFolder reads happen BEFORE any `== None` comparison — a
    ; PapyrusUtil array return followed by a None check corrupts the array
    ; ::temp register and would clobber the second return assignment (KB:
    ; temp1-corruption). result is allocated first for the same reason.
    string[] u = JsonUtil.JsonInFolder("MagicTattoosFramework/presets")
    string[] b = JsonUtil.JsonInFolder("MagicTattoosFramework/presets_builtin")
    int n = 0
    ; User folder: skip deleted (hidden==1).
    int i = 0
    while u != None && i < u.Length && n < 64
        string nm = _stripJsonExt(u[i])
        if JsonUtil.GetPathIntValue(_userPresetFile(nm), ".hidden", 0) != 1
            result[n] = nm
            n += 1
        endif
        i += 1
    endwhile
    ; Built-in folder: include all (skip a name already taken by a user preset).
    i = 0
    while b != None && i < b.Length && n < 64
        string bnm = _stripJsonExt(b[i])
        if _indexOfName(result, n, bnm) < 0
            result[n] = bnm
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

string[] Function ListVisiblePresets()
{The user-facing catalog: USER presets that aren't deleted (hidden!=1). Built-in
 presets are excluded entirely (they live in presets_builtin/ and are runner-
 only). Fixed-size 64 array; names first, empty strings after.}
    string[] result = new string[64]
    string[] u = JsonUtil.JsonInFolder("MagicTattoosFramework/presets")
    int n = 0
    int i = 0
    while u != None && i < u.Length && n < 64
        string nm = _stripJsonExt(u[i])
        if JsonUtil.GetPathIntValue(_userPresetFile(nm), ".hidden", 0) != 1
            result[n] = nm
            n += 1
        endif
        i += 1
    endwhile
    return result
EndFunction

int Function ListVisiblePresetsCount()
    string[] r = ListVisiblePresets()
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

; Plugin-catalog schema version this host understands. Bumped on breaking
; changes to the catalog JSON contract (field renames/removes, semantic
; shifts). When a plugin's catalog declares a different version,
; RegisterPlugin logs a loud warning so users / authors notice that the
; plugin is out of sync with the framework. Additive changes don't need
; a bump — host falls back to defaults for missing optional fields.
;
; History:
;   1 — initial public schema (current). The v0.2.1 paramN refactor and
;       v0.2.5 menu consolidations both happened before any third-party
;       plugin existed, so they don't get version numbers.
int Function PLUGIN_SCHEMA_VERSION() global
{v0.2.9: bumped to 2 -- menu params migrated to id-string dispatch. Old plugin catalogs (schemaversion 1) will register but their menu params will silently read empty defaults and dispatch to no matching branch in the consumer code.}
    return 2
EndFunction

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
    ; Schema version check — warn but don't reject. A wrong-schema catalog
    ; will still half-work (the host falls back to defaults on missing
    ; fields), so it's strictly more useful to register and surface the
    ; mismatch than to silently drop the plugin entirely.
    int catalogVer = JsonUtil.GetPathIntValue(p._catalogFile(), ".schemaversion", PLUGIN_SCHEMA_VERSION())
    int expectedVer = PLUGIN_SCHEMA_VERSION()
    if catalogVer != expectedVer
        string msg
        if catalogVer < expectedVer
            msg = "[MTF] Plugin '" + pid + "' uses catalog schema v" + catalogVer + ", host expects v" + expectedVer + ". Plugin is outdated — fields may be missing or misread."
        else
            msg = "[MTF] Plugin '" + pid + "' uses catalog schema v" + catalogVer + ", host only supports up to v" + expectedVer + ". Update MTF or downgrade the plugin."
        endif
        Trace(msg)
        Debug.Notification(msg)
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
    MTF_Plugin p = FindPlugin(_keyPluginId(key))
    if p != None
        return p
    endif
    ; v0.3.9 back-compat: an un-migrated "mtf.base:<id>" key. The save migrator
    ; (_migrateModuleSplit) only rewrites keys already stored in the cosave; an
    ; OLD preset FILE authored pre-split and loaded fresh still feeds raw
    ; mtf.base keys through here. Map the id to its themed module on the fly so
    ; old presets keep working. Zero cost for normal keys — only reached when
    ; the direct lookup misses AND the key is mtf.base. cond/eff id namespaces
    ; are disjoint, so try both; the bare id passed to checkCondition/onActivate
    ; (via _keyItemId) is already correct regardless of the pluginid.
    if _keyPluginId(key) == "mtf.base"
        string nk = _remapBaseKey(key, "cond:")
        if nk == key
            nk = _remapBaseKey(key, "eff:")
        endif
        if nk != key
            return FindPlugin(_keyPluginId(nk))
        endif
    endif
    return None
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
                string il = p.GetEffectDisplayLabel(globalIdx - seen)
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
                    string il = p.GetEffectDisplayLabel(ei)
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

; v0.2.12: race-free key reader. The NPC snapshot loops in
; _activateSlotEffectsForActor etc. used to read via _readFxKey which goes
; through _scratchLoadedFor. The snapshot loop itself is atomic (SKSE
; natives don't yield), but threading presetName explicitly makes the
; data flow auditable end-to-end — caller passes the preset name it
; intends to read from, no implicit dependency on script-level state.
string Function _readFxKeyForPreset(int slot, int idx, bool useScratch, string presetName)
    if useScratch && presetName != ""
        return StorageUtil.GetStringValue(None, "mtf.fx.scratch." + presetName + "." + slot + "." + idx + ".key", "")
    endif
    return StorageUtil.GetStringValue(None, "mtf.fx." + slot + "." + idx + ".key", "")
EndFunction

; ── Param storage (v0.2.1 uniform paramN) ──────────────────────────────────
; One internal helper family for params 1..5. The legacy _readFxParam /
; _readFxParam2 / _writeFxParam / _writeFxParam2 are now thin n=1/n=2
; convenience aliases — keeps existing call sites compiling unchanged
; while routing all writes through a single unified path.
;
; Storage key shape: `mtf.fx.<slot>.<eff>.paramN`. Scratch namespace:
; `mtf.fx.scratch.<presetName>.<slot>.<eff>.paramN`.

int Function _readFxParamN(int slot, int idx, int n, bool useScratch)
    if useScratch
        return StorageUtil.GetIntValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".param" + n, 0)
    endif
    return StorageUtil.GetIntValue(None, "mtf.fx." + slot + "." + idx + ".param" + n, 0)
EndFunction

; v0.2.12: race-free reader. Path uses the supplied `presetName` directly
; instead of `_scratchLoadedFor` — so a concurrent fiber's _loadPresetToScratch
; can't redirect this read mid-dispatch. The dispatch path passes presetName
; as a stack-local function param through every layer. presetName="" + useScratch=true
; falls back to the live keyspace because empty scratch namespace is never valid.
int Function _readFxParamNForPreset(int slot, int idx, int n, bool useScratch, string presetName)
    if useScratch && presetName != ""
        return StorageUtil.GetIntValue(None, "mtf.fx.scratch." + presetName + "." + slot + "." + idx + ".param" + n, 0)
    endif
    return StorageUtil.GetIntValue(None, "mtf.fx." + slot + "." + idx + ".param" + n, 0)
EndFunction

Function _writeFxParamN(int slot, int idx, int n, bool useScratch, int val)
    if useScratch
        StorageUtil.SetIntValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".param" + n, val)
        return
    endif
    StorageUtil.SetIntValue(None, "mtf.fx." + slot + "." + idx + ".param" + n, val)
EndFunction

; v0.2.12: race-free writer for _loadPresetToScratch's cold-load loop. The
; loop crosses into plugin scripts (pLoadX.GetEffectParamMenuOptionCount)
; which YIELDS the Papyrus VM; a concurrent fiber's _loadPresetToScratch
; can run during the yield and rebind _scratchLoadedFor, redirecting our
; subsequent _writeFxParamN writes to its namespace. Route every write
; inside _loadPresetToScratch's loops through ForPreset variants so writes
; always land under the preset name the load was called with.
Function _writeFxParamNForPreset(int slot, int idx, int n, bool useScratch, string presetName, int val)
    if useScratch && presetName != ""
        StorageUtil.SetIntValue(None, "mtf.fx.scratch." + presetName + "." + slot + "." + idx + ".param" + n, val)
        return
    endif
    StorageUtil.SetIntValue(None, "mtf.fx." + slot + "." + idx + ".param" + n, val)
EndFunction

int Function _readFxParam(int slot, int idx, bool useScratch)
{Legacy convenience for param1. Use _readFxParamN(slot, idx, n, useScratch) directly for new code.}
    return _readFxParamN(slot, idx, 1, useScratch)
EndFunction

int Function _readFxParam2(int slot, int idx, bool useScratch)
{Legacy convenience for param2.}
    return _readFxParamN(slot, idx, 2, useScratch)
EndFunction

Function _writeFxKey(int slot, int idx, bool useScratch, string val)
    if useScratch
        StorageUtil.SetStringValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".key", val)
        return
    endif
    StorageUtil.SetStringValue(None, "mtf.fx." + slot + "." + idx + ".key", val)
EndFunction

; v0.2.12: race-free writer counterpart to _readFxKeyForPreset. Same
; rationale as _writeFxParamNForPreset — used inside _loadPresetToScratch's
; cold-load loop so its writes survive a concurrent fiber's load.
Function _writeFxKeyForPreset(int slot, int idx, bool useScratch, string presetName, string val)
    if useScratch && presetName != ""
        StorageUtil.SetStringValue(None, "mtf.fx.scratch." + presetName + "." + slot + "." + idx + ".key", val)
        return
    endif
    StorageUtil.SetStringValue(None, "mtf.fx." + slot + "." + idx + ".key", val)
EndFunction

Function _writeFxParam(int slot, int idx, bool useScratch, int val)
{Legacy convenience for param1.}
    _writeFxParamN(slot, idx, 1, useScratch, val)
EndFunction

Function _writeFxParam2(int slot, int idx, bool useScratch, int val)
{Legacy convenience for param2.}
    _writeFxParamN(slot, idx, 2, useScratch, val)
EndFunction

; ── String-typed per-effect paramN (v0.2.9) ─────────────────────────────────
; Menu effect params store a stable id string (was int position). Sliders
; keep using _readFxParamN above. Catalog probe `GetEffectParamMenuOptionCount
; (idx, n) > 0` tells the caller which to use.
; Key shape: `mtf.fx.<slot>.<idx>.param<N>.s` (string, new) — distinct from
; the int `mtf.fx.<slot>.<idx>.param<N>` slider key.
string Function _readFxParamNStr(int slot, int idx, int n, bool useScratch)
    if useScratch
        return StorageUtil.GetStringValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".param" + n + ".s", "")
    endif
    return StorageUtil.GetStringValue(None, "mtf.fx." + slot + "." + idx + ".param" + n + ".s", "")
EndFunction

; v0.2.12: race-free string reader. See _readFxParamNForPreset for the
; rationale. The previous _readFxParamNStr — used by every plugin's
; modify.skill/resist/flash/shader/sound string-param read — traversed
; _scratchLoadedFor, which is script-level state any concurrent fiber's
; _loadPresetToScratch can rebind. Read uses the supplied presetName,
; sourced from the plugin entry-point's stack-local `presetName` param.
string Function _readFxParamNStrForPreset(int slot, int idx, int n, bool useScratch, string presetName)
    if useScratch && presetName != ""
        return StorageUtil.GetStringValue(None, "mtf.fx.scratch." + presetName + "." + slot + "." + idx + ".param" + n + ".s", "")
    endif
    return StorageUtil.GetStringValue(None, "mtf.fx." + slot + "." + idx + ".param" + n + ".s", "")
EndFunction

Function _writeFxParamNStr(int slot, int idx, int n, bool useScratch, string val)
    if useScratch
        StorageUtil.SetStringValue(None, "mtf.fx.scratch." + _scratchLoadedFor + "." + slot + "." + idx + ".param" + n + ".s", val)
        return
    endif
    StorageUtil.SetStringValue(None, "mtf.fx." + slot + "." + idx + ".param" + n + ".s", val)
EndFunction

; v0.2.12: race-free string writer. Used in _loadPresetToScratch's cold-load
; loop. Counterpart to _readFxParamNStrForPreset — see that docstring for
; the full race rationale.
Function _writeFxParamNStrForPreset(int slot, int idx, int n, bool useScratch, string presetName, string val)
    if useScratch && presetName != ""
        StorageUtil.SetStringValue(None, "mtf.fx.scratch." + presetName + "." + slot + "." + idx + ".param" + n + ".s", val)
        return
    endif
    StorageUtil.SetStringValue(None, "mtf.fx." + slot + "." + idx + ".param" + n + ".s", val)
EndFunction

; ── Public accessors for menu effect params (v0.2.9) ────────────────────────
; Mirrors GetSlotEffectParamN / SetSlotEffectParamN but for string-typed
; (menu) effect params. Plugin behaviour code consumes via
; host.GetSlotEffectParamNStr(slot, eff, n) inside its menu-dispatch branches.
;
; v0.2.10: slot bounds widened to MAX_CONDITIONS_CACHED() so backend slots
; (8..31 by default) read/write through the public API — previously the
; hardcoded `slot >= 8` returned "" / 0 / no-op for any backend dispatch,
; silently breaking menu-typed effects on backend slots. Same widening
; applied to GetSlotEffectParamN / SetSlotEffectParamN below.
;
; v0.2.10: useScratch is now read from the dispatch context flag
; (_getDispatchUseScratch) rather than hardcoded false. Plugins firing
; on NPCs or stacked-preset paths read from the scratch namespace
; (mtf.fx.scratch.<preset>.<slot>.<idx>.paramN.s) instead of the player's
; live keyspace. Setters mirror the same flag so MCM-edits to the
; player's live row don't accidentally bleed into the scratch namespace
; mid-dispatch.
string Function GetSlotEffectParamNStr(int slot, int effectIdx, int n)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT() || n < 1 || n > 5
        return ""
    endif
    return _readFxParamNStr(slot, effectIdx, n, _getDispatchUseScratch())
EndFunction

; v0.2.10: explicit-useScratch overload. Dispatch hot paths now receive the
; flag as a stack-local function param and pass it through here, so the
; read is immune to the shared-StorageUtil dispatch-context clobber the
; non-Ex variant suffers when a concurrent fiber rewrites usescratch during
; the cross-script yield. Non-Ex accessor still works for MCM / test
; callers — they read with dispatch context unset (= useScratch=false),
; which is correct because they target the player's persistent keyspace.
string Function GetSlotEffectParamNStrEx(int slot, int effectIdx, int n, bool useScratch)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT() || n < 1 || n > 5
        return ""
    endif
    return _readFxParamNStr(slot, effectIdx, n, useScratch)
EndFunction

; v0.2.12: race-free overload for string-typed paramN reads. See
; GetSlotEffectParamNExForPreset for the full rationale — same race, same
; fix. Plugins MUST use this variant inside onActivate/onDeactivate/onTick/
; onGameTime; the Ex variant traverses _scratchLoadedFor and is no longer
; safe for mid-dispatch reads when a concurrent fiber might rebind it.
string Function GetSlotEffectParamNStrExForPreset(int slot, int effectIdx, int n, bool useScratch, string presetName)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT() || n < 1 || n > 5
        return ""
    endif
    return _readFxParamNStrForPreset(slot, effectIdx, n, useScratch, presetName)
EndFunction

Function SetSlotEffectParamNStr(int slot, int effectIdx, int n, string val)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT() || n < 1 || n > 5
        return
    endif
    _writeFxParamNStr(slot, effectIdx, n, _getDispatchUseScratch(), val)
EndFunction

; ── Per-slot effect-list helpers ─────────────────────────────────────────────
;
; v0.2.10: slot bounds widened to MAX_CONDITIONS_CACHED() (default 32) so
; backend slots reach the public API; useScratch routed through the
; dispatch context. See the comment on GetSlotEffectParamNStr above for
; the full rationale — same fix, same shape.

string Function GetSlotEffectKey(int slot, int effectIdx)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return ""
    endif
    return _readFxKey(slot, effectIdx, _getDispatchUseScratch())
EndFunction

int Function GetSlotEffectParamN(int slot, int effectIdx, int n)
{Unified accessor for paramN (n=1..5). Used by MCM / test callers — they
 read outside of dispatch, where _getDispatchUseScratch() = false (the
 player's persistent keyspace). Plugin behaviour code should call
 GetSlotEffectParamNEx with the explicit useScratch from its entry-point
 params instead — see the Ex variant's docstring for the race rationale.}
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT() || n < 1 || n > 5
        return 0
    endif
    return _readFxParamN(slot, effectIdx, n, _getDispatchUseScratch())
EndFunction

; v0.2.10: explicit-useScratch overload — see GetSlotEffectParamNStrEx for
; the full rationale.
int Function GetSlotEffectParamNEx(int slot, int effectIdx, int n, bool useScratch)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT() || n < 1 || n > 5
        return 0
    endif
    return _readFxParamN(slot, effectIdx, n, useScratch)
EndFunction

; v0.2.12: race-free overload. The Ex variant (above) still depends on
; _scratchLoadedFor inside _readFxParamN — a concurrent fiber's
; _loadPresetToScratch will rebind it during the cross-script yield from
; plugin onActivate back to this host call, redirecting the read to the
; wrong preset's scratch namespace. The ForPreset variant takes presetName
; as a stack-local param threaded from the dispatcher and bypasses
; _scratchLoadedFor entirely. Plugins MUST use this variant for any
; mid-dispatch read; the Ex variant is kept only for the MCM / test
; callers that read outside of dispatch.
int Function GetSlotEffectParamNExForPreset(int slot, int effectIdx, int n, bool useScratch, string presetName)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT() || n < 1 || n > 5
        return 0
    endif
    return _readFxParamNForPreset(slot, effectIdx, n, useScratch, presetName)
EndFunction

Function SetSlotEffectParamN(int slot, int effectIdx, int n, int val)
{Unified setter for paramN.}
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT() || n < 1 || n > 5
        return
    endif
    _writeFxParamN(slot, effectIdx, n, _getDispatchUseScratch(), val)
EndFunction

int Function GetSlotEffectParam(int slot, int effectIdx)
{Legacy 2-arg convenience for param1. New code should call GetSlotEffectParamN(slot, eff, 1).}
    return GetSlotEffectParamN(slot, effectIdx, 1)
EndFunction

int Function GetSlotEffectParam2(int slot, int effectIdx)
{Legacy 2-arg convenience for param2.}
    return GetSlotEffectParamN(slot, effectIdx, 2)
EndFunction

Function SetSlotEffect(int slot, int effectIdx, string key, int param)
{Legacy 4-arg setter — preserves existing param2.}
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
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
{Sets key + param1 + param2 at once. Params 3-5 are written separately
 via SetSlotEffectParamN where needed; when a new effect is bound, params
 3-5 are stamped to the catalog defaults for any declared paramN slot.}
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    bool live = (slot == currentTier)
    if live
        _deactivateSingleEffect(slot, effectIdx)
    endif
    _writeFxKey(slot, effectIdx, false, key)
    _writeFxParamN(slot, effectIdx, 1, false, param)
    _writeFxParamN(slot, effectIdx, 2, false, param2)
    ; v0.2.10: stamp catalog defaults onto BOTH int params 3-5 AND string
    ; params 1-5 (paramN.s) when rebinding. Previously only ints 3-5 were
    ; stamped — string params were left at their stale value from the
    ; previous binding (or empty on first bind), which made menu-typed
    ; effects (modify.skill, flash.onhit, shader.play, sound.play,
    ; sexlab.cum.*, etc.) silently no-op after a fresh MCM bind because
    ; the live auto-activate below dispatched with an empty/stale id.
    ;
    ; String defaults are stamped CONDITIONALLY:
    ;   - If the existing string is already a valid menu option for the
    ;     new effect's paramN, preserve it. Lets callers (e.g. test runner)
    ;     pre-write a specific id via SetSlotEffectParamNStr before this
    ;     call without it being clobbered.
    ;   - Otherwise stamp the catalog default. Covers fresh-bind (empty
    ;     string), stale-from-different-effect (id belonged to another
    ;     effect's menu domain), and effect-switch cases.
    MTF_Plugin pNew = ResolvePluginByKey(key)
    if pNew != None
        int itemIdxNew = _effectIdxFor(pNew, _keyItemId(key))
        if itemIdxNew >= 0
            int n = 1
            while n <= 5
                ; Int default for declared paramN n=3..5 (n=1/2 already
                ; set from the call args above).
                if n >= 3
                    if pNew.GetEffectParamLabel(itemIdxNew, n) != ""
                        _writeFxParamN(slot, effectIdx, n, false, pNew.GetEffectParamDefault(itemIdxNew, n))
                    else
                        _writeFxParamN(slot, effectIdx, n, false, 0)
                    endif
                endif
                ; String default for menu-typed paramN — preserve current
                ; value if it's already in the new effect's menu domain.
                int menuN = pNew.GetEffectParamMenuOptionCount(itemIdxNew, n)
                if menuN > 0
                    string curId = _readFxParamNStr(slot, effectIdx, n, false)
                    bool isValidForNewMenu = false
                    if curId != ""
                        int oi = 0
                        while oi < menuN && !isValidForNewMenu
                            if pNew.GetEffectParamMenuOptionId(itemIdxNew, n, oi) == curId
                                isValidForNewMenu = true
                            endif
                            oi += 1
                        endwhile
                    endif
                    if !isValidForNewMenu
                        _writeFxParamNStr(slot, effectIdx, n, false, pNew.GetEffectParamDefaultId(itemIdxNew, n))
                    endif
                else
                    ; Non-menu paramN — clear any stale string left over
                    ; from a previous menu-typed binding on this slot.
                    _writeFxParamNStr(slot, effectIdx, n, false, "")
                endif
                n += 1
            endwhile
        else
            ; Effect id not in catalog — clear all of paramN[3..5] and
            ; paramN.s[1..5] to leave no stale state behind.
            _writeFxParamN(slot, effectIdx, 3, false, 0)
            _writeFxParamN(slot, effectIdx, 4, false, 0)
            _writeFxParamN(slot, effectIdx, 5, false, 0)
            int nx = 1
            while nx <= 5
                _writeFxParamNStr(slot, effectIdx, nx, false, "")
                nx += 1
            endwhile
        endif
    else
        ; Empty key (slot cleared) OR plugin not resolved. Wipe all
        ; lingering params so the next bind starts clean.
        _writeFxParamN(slot, effectIdx, 3, false, 0)
        _writeFxParamN(slot, effectIdx, 4, false, 0)
        _writeFxParamN(slot, effectIdx, 5, false, 0)
        int ny = 1
        while ny <= 5
            _writeFxParamNStr(slot, effectIdx, ny, false, "")
            ny += 1
        endwhile
    endif
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

 Walks front-to-back. Each iteration reads from src = i+1, copies into
 dst = i, then blanks src. After SetSlotEffectFull resets params 3-5 to
 the new key's catalog defaults, we re-stamp the snapshot values so
 user-tuned params don't get clobbered.

 Stops early at the first empty src — nothing beyond a gap to compact.}
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || fromIdx < 0 || fromIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    int maxE = MAX_EFFECTS_PER_SLOT()
    int i = fromIdx
    while i < maxE - 1
        string srcKey = _readFxKey(slot, i + 1, false)
        if srcKey == ""
            return
        endif
        ; Snapshot all 5 src params before SetSlotEffectFull rewrites dst.
        int[] srcParams = Utility.CreateIntArray(5, 0)
        int sn = 1
        while sn <= 5
            srcParams[sn - 1] = _readFxParamN(slot, i + 1, sn, false)
            sn += 1
        endwhile
        ; Move src → dst.
        SetSlotEffectFull(slot, i, srcKey, srcParams[0], srcParams[1])
        ; Re-stamp params 3-5 (SetSlotEffectFull reset them to defaults).
        int sn2 = 3
        while sn2 <= 5
            _writeFxParamN(slot, i, sn2, false, srcParams[sn2 - 1])
            sn2 += 1
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
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
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
        ; v0.2.10: dispatch context is passed as explicit params — see
        ; _dispatchDeactivate's docstring for the race rationale. Player
        ; single-preset path: useScratch=false, baseSlot=OverlaySlot, area=0.
        _dispatchDeactivate(p, itemIdx, PlayerRef, slot, effectIdx, false, OverlaySlot, 0, _readFxParam(slot, effectIdx, false), _readFxParam2(slot, effectIdx, false), "")
        _emitEffectDeactivated(PlayerRef, key, slot)
    endif
EndFunction

Function _activateSingleEffect(int slot, int effectIdx)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
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
        _dispatchActivate(p, itemIdx, PlayerRef, slot, effectIdx, false, OverlaySlot, 0, _readFxParam(slot, effectIdx, false), _readFxParam2(slot, effectIdx, false), "")
        _emitEffectActivated(PlayerRef, key, slot)
    endif
EndFunction

Function SetSlotEffectParam2(int slot, int effectIdx, int param2)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED() || effectIdx < 0 || effectIdx >= MAX_EFFECTS_PER_SLOT()
        return
    endif
    _writeFxParam2(slot, effectIdx, false, param2)
EndFunction

; ── Priority evaluation (v0.1.24 rework) ────────────────────────────────────
; State machine per slot:
;   - In COOL phase (now < coolUntilGT[i])  → skip (can't re-arm)
;   - In PERSIST phase (now < persistUntilGT[i]):
;       - If !allowOverride: SLOT LOCKED — short-circuits the whole eval and
;         returns i regardless of higher-priority slot conditions.
;       - If allowOverride:  slot still wins via persistence at i, but
;         higher-priority slots (lower i) can take over if their condition fires.
;   - Else: NORMAL eval — check condition; if met, return i.
;
; Lowest-index slot wins (priority 1 highest, 7 lowest). The two-pass shape
; (pre-scan for !allowOverride lock, then normal eval) is what enforces
; "block higher" semantics: once we find a locked slot at index i, we return
; immediately without giving slots 1..i-1 a chance to fire.
; ── Multi-condition evaluation core (v0.3.0) ────────────────────────────────
; _checkOneCond resolves a single condition's plugin + item and runs it,
; setting the eval-param channel the plugin reads via host.GetEvalParam*.
; Shared by the player-live, JSON-peek, and scratch eval paths so the
; resolve/eval-param/checkCondition dance lives in exactly one place.
bool Function _checkOneCond(Actor target, string key, int paramInt, int param2Int, int param3Int, string paramStr, string param2Str, string param3Str)
    if key == ""
        return false
    endif
    MTF_Plugin p = ResolvePluginByKey(key)
    if p == None
        return false
    endif
    int itemIdx = _condIdxFor(p, _keyItemId(key))
    if itemIdx < 0
        return false
    endif
    _setEvalParam2(param2Int)
    _setEvalParam3(param3Int)
    _setEvalParamStr(paramStr)
    _setEvalParam2Str(param2Str)
    _setEvalParam3Str(param3Str)
    return p.checkCondition(target, paramInt, p.GetConditionId(itemIdx))
EndFunction

; Evaluate ALL conditions of a player-live slot (StorageUtil-backed), combined
; by the slot's operator. op 0 = AND (every cond must pass), op 1 = OR (any).
; Short-circuits. Empty slot (count 0) => false.
bool Function _slotCondsMetLive(Actor target, int slot)
    int n = GetCondCount(slot)
    if n <= 0
        return false
    endif
    int op = GetCondOp(slot)
    int j = 0
    while j < n
        bool met = _checkOneCond(target, GetCondPluginIdAt(slot, j), GetCondParamAt(slot, j), GetCondParam2At(slot, j), GetCondParam3At(slot, j), GetCondParamStrAt(slot, j), GetCondParam2StrAt(slot, j), GetCondParam3StrAt(slot, j))
        if op == 0 && !met
            return false
        endif
        if op == 1 && met
            return true
        endif
        j += 1
    endwhile
    return op == 0
EndFunction

; Evaluate ALL conditions of a slot straight from a JSON preset file, combined
; by the slot's operator. Used by the NPC/scratch + peek paths (the JSON file
; is the source of truth for those). cond[0] lives at .cond.*; extras at
; .cond.x.<j>.* (object keys, j>=1); op at .cond.op; count at .cond.count.
; param2 int is not carried on these paths (matches prior behaviour) — only
; the player-live path threads param2.
bool Function _slotCondsMetJson(Actor target, string f, int slot)
    string sp = ".slot[" + slot + "]"
    ; v0.3.1: conditions live in the .cond.items[] array. PathCount == 0 means
    ; an unconfigured slot. op 0 = AND (all must pass), 1 = OR (any). Short-
    ; circuits. v0.4.x: param2/param3 ints are now read straight from JSON here
    ; too (was hardcoded 0), so numeric 2nd/3rd params work for NPC presets.
    int n = JsonUtil.PathCount(f, sp + ".cond.items")
    if n < 1
        return false
    endif
    int op = JsonUtil.GetPathIntValue(f, sp + ".cond.op", 0)
    int j = 0
    while j < n
        string ip = sp + ".cond.items[" + j + "]"
        string key = JsonUtil.GetPathStringValue(f, ip + ".pluginid", "")
        int pInt = JsonUtil.GetPathIntValue(f, ip + ".param", 0)
        int p2Int = JsonUtil.GetPathIntValue(f, ip + ".param2", 0)
        int p3Int = JsonUtil.GetPathIntValue(f, ip + ".param3", 0)
        string pStr = JsonUtil.GetPathStringValue(f, ip + ".param", "")
        string p2Str = JsonUtil.GetPathStringValue(f, ip + ".param2", "")
        string p3Str = JsonUtil.GetPathStringValue(f, ip + ".param3", "")
        bool met = _checkOneCond(target, key, pInt, p2Int, p3Int, pStr, p2Str, p3Str)
        if op == 0 && !met
            return false
        endif
        if op == 1 && met
            return true
        endif
        j += 1
    endwhile
    return op == 0
EndFunction

int Function evaluateTier()
    if !_arraysReady
        return 0
    endif
    float now = Utility.GetCurrentGameTime()

    int maxC = MAX_CONDITIONS_CACHED()

    ; Pre-scan: lowest-index slot in PERSIST with !allowOverride wins outright.
    int i = 1
    while i <= maxC
        if GetCondPluginId(i) != "" && _getPersistMode(i) == 0 && now < _getPersistUntilGT(i)
            return i
        endif
        i += 1
    endwhile

    ; Normal eval, with persist passthrough for allowOverride==1 slots.
    i = 1
    while i <= maxC
        string key = GetCondPluginId(i)
        if key != ""
            float coolEnd = _getCoolUntilGT(i)
            bool inCool = (now < coolEnd)
            if !inCool
                bool inPersist = (now < _getPersistUntilGT(i))
                if inPersist
                    ; allowOverride==1 here (else pre-scan would've caught it).
                    ; Persistence keeps slot winning.
                    return i
                endif
                ; v0.3.0: evaluate all conditions in the slot (AND/OR).
                if _slotCondsMetLive(PlayerRef, i)
                    return i
                endif
            endif
        endif
        i += 1
    endwhile
    return 0
EndFunction

Function _armPersistTimer(int slot)
{Sets persistUntilGT[slot] = now + persistMin[slot] minutes. Called on the
 activation edge (prev→new transition) only when persistMin > 0. Indexed
 writes to Auto array properties silently no-op
 (project_papyrus_property_array_writes), so we do whole-array reassign.}
    if slot <= 0 || slot > MAX_CONDITIONS_CACHED() || !_arraysReady
        return
    endif
    int mins = GetCondPersistMin(slot)
    if mins <= 0
        return
    endif
    SetCondPersistUntilGT(slot, Utility.GetCurrentGameTime() + (mins as float) / 1440.0)
EndFunction

Function _armCoolTimer(int slot)
{Sets coolUntilGT[slot] = now + coolMin[slot] minutes. Called on the
 deactivation edge (prev→new transition where prev is this slot) only when
 coolMin > 0. cool[] storage is StorageUtil-backed (see _setCoolUntilGT).}
    if slot <= 0 || slot > MAX_CONDITIONS_CACHED() || !_arraysReady
        return
    endif
    int mins = _getCoolMin(slot)
    if mins <= 0
        return
    endif
    _setCoolUntilGT(slot, Utility.GetCurrentGameTime() + (mins as float) / 1440.0)
EndFunction

; ── Defensive lifecycle audit (debug-mode opt-in) ───────────────────────────
; Plugin authors who mutate persistent state in onActivate (ModActorValue,
; AddSpell, SetNthEffectMagnitude, persistent shaders, etc.) MUST balance
; in onDeactivate. The framework can't statically detect a forgotten
; cleanup; the bug presents as "removed the tattoo but the buff is still
; applied," potentially many sessions later. This audit catches it.
;
; How it works: when DebugMode is on, every continuous-kind dispatch
; (re-)balances a per-(actor, pluginId, effectIdx) counter. onActivate
; increments; onDeactivate decrements. A balanced lifecycle ends at 0.
; Burst effects are skipped (they can't leak — no rolling state).
;
; Storage: `mtf.audit.<pluginId>.<idx>` on the target actor via
; StorageUtil. Survives save/load (so cross-session leaks are visible).
; AdjustIntValue is SKSE-native ~5µs; total overhead is ~negligible vs
; the cross-script onActivate call we're wrapping.
;
; To inspect: call DumpLifecycleAudit() from console / MCM. The dump
; walks the player plus every actor in mtf.tracked, prints non-zero
; counters. (Continuous effects you currently have ACTIVE will show up
; as +1 — that's expected. Positive counts on effects that should be
; OFF are the bug signal.)
;
; To reset: call ResetLifecycleAudit() to clear all counters (or just
; toggle DebugMode off to stop incrementing).

; v0.2.10: dispatch context (slot/effectIdx/useScratch/baseSlot/area) is
; passed as stack-local params now, not via the shared StorageUtil dispatch
; context. The shared context races against concurrent fibers during the
; cross-script yield on p.onActivate. See the plugin entry-point docstring
; in MTF_Plugin.psc for the full story.
Function _dispatchActivate(MTF_Plugin p, int itemIdx, Actor target, int slot, int eff, bool useScratch, int baseSlot, int area, int param, int param2, string presetName)
    string eid = p.GetEffectId(itemIdx)
    p.onActivate(target, param, param2, eid, slot, eff, useScratch, baseSlot, area, presetName)
    if !DebugMode
        return
    endif
    if p.GetEffectKind(itemIdx) == "burst"
        return
    endif
    StorageUtil.AdjustIntValue(target, "mtf.audit." + p.GetPluginId() + "." + eid, 1)
EndFunction

Function _dispatchDeactivate(MTF_Plugin p, int itemIdx, Actor target, int slot, int eff, bool useScratch, int baseSlot, int area, int param, int param2, string presetName)
    string eid = p.GetEffectId(itemIdx)
    p.onDeactivate(target, param, param2, eid, slot, eff, useScratch, baseSlot, area, presetName)
    if !DebugMode
        return
    endif
    if p.GetEffectKind(itemIdx) == "burst"
        return
    endif
    StorageUtil.AdjustIntValue(target, "mtf.audit." + p.GetPluginId() + "." + eid, -1)
EndFunction

Function DumpLifecycleAudit()
{Scan player + every tracked actor × every registered plugin's effects.
 Log any non-zero counters. Run from MCM Debug or console:
   cqf MTF_MainQuest DumpLifecycleAudit}
    Debug.Trace("[MTF audit] === Lifecycle imbalance scan ===")
    Debug.Notification("[MTF] Lifecycle audit dumped to log")
    int leakedRows = 0
    int actorIdx = -1
    int trackedN = StorageUtil.FormListCount(self, "mtf.tracked")
    while actorIdx < trackedN
        Actor a
        if actorIdx < 0
            a = PlayerRef
        else
            a = StorageUtil.FormListGet(self, "mtf.tracked", actorIdx) as Actor
        endif
        if a != None
            int pi = 0
            while pi < pluginCount
                MTF_Plugin p = GetPluginAt(pi)
                if p != None
                    string pid = p.GetPluginId()
                    int eCount = p.GetEffectCount()
                    int ei = 0
                    while ei < eCount
                        string eid = p.GetEffectId(ei)
                        int n = StorageUtil.GetIntValue(a, "mtf.audit." + pid + "." + eid, 0)
                        if n != 0
                            string actorName = a.GetDisplayName()
                            Debug.Trace("[MTF audit]   " + actorName + "  " + pid + "." + eid + "  " + n)
                            leakedRows += 1
                        endif
                        ei += 1
                    endwhile
                endif
                pi += 1
            endwhile
        endif
        actorIdx += 1
    endwhile
    if leakedRows == 0
        Debug.Trace("[MTF audit]   (all clean)")
    else
        Debug.Trace("[MTF audit] " + leakedRows + " imbalance(s) — see lines above")
    endif
    Debug.Trace("[MTF audit] === end ===")
EndFunction

Function ResetLifecycleAudit()
{Clear every per-actor audit counter. Use after fixing a leak so the
 next DumpLifecycleAudit starts from a clean baseline. Walks the player
 + every tracked actor × every registered plugin's effects.}
    int actorIdx = -1
    int trackedN = StorageUtil.FormListCount(self, "mtf.tracked")
    while actorIdx < trackedN
        Actor a
        if actorIdx < 0
            a = PlayerRef
        else
            a = StorageUtil.FormListGet(self, "mtf.tracked", actorIdx) as Actor
        endif
        if a != None
            int pi = 0
            while pi < pluginCount
                MTF_Plugin p = GetPluginAt(pi)
                if p != None
                    string pid = p.GetPluginId()
                    int eCount = p.GetEffectCount()
                    int ei = 0
                    while ei < eCount
                        StorageUtil.UnsetIntValue(a, "mtf.audit." + pid + "." + p.GetEffectId(ei))
                        ei += 1
                    endwhile
                endif
                pi += 1
            endwhile
        endif
        actorIdx += 1
    endwhile
    Debug.Notification("[MTF] Lifecycle audit counters reset")
EndFunction

; ── Effect lifecycle dispatch ────────────────────────────────────────────────
; Player single-preset path. The base overlay slot is the MCM-managed
; OverlaySlot — for NPCs and stacked player presets, the parallel ForActor
; variants pass a per-preset base.
;
; v0.2.10: dispatch context (slot/effectIdx/useScratch/baseSlot/area) is
; passed as stack-local params straight into _dispatchActivate / onTick / …
; rather than stashed in StorageUtil. The shared StorageUtil context races
; against concurrent fibers during the cross-script yield on the plugin
; call — see _dispatchActivate / plugin entry-point docstrings.
Function _activateSlotEffects(int slot)
    ; v0.2.7: widened from slot < 8 to MAX_CONDITIONS() so backend-only
    ; slots (8..MAX_CONDITIONS) dispatch their effects when evaluateTier
    ; picks them. Storage is in StorageUtil (mtf.fx.<slot>.<e>.*) which has
    ; no inherent per-slot cap.
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _dispatchActivate(p, itemIdx, PlayerRef, slot, e, false, OverlaySlot, 0, _readFxParam(slot, e, false), _readFxParam2(slot, e, false), "")
                    _emitEffectActivated(PlayerRef, key, slot)
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _deactivateSlotEffects(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    _dispatchDeactivate(p, itemIdx, PlayerRef, slot, e, false, OverlaySlot, 0, _readFxParam(slot, e, false), _readFxParam2(slot, e, false), "")
                    _emitEffectDeactivated(PlayerRef, key, slot)
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _tickSlotEffects(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onTick(PlayerRef, _readFxParam(slot, e, false), _readFxParam2(slot, e, false), p.GetEffectId(itemIdx), slot, e, false, OverlaySlot, 0, "")
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _gameTickSlotEffects(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    int e = 0
    int maxE = MAX_EFFECTS_PER_SLOT()
    while e < maxE
        string key = _readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onGameTime(PlayerRef, _readFxParam(slot, e, false), _readFxParam2(slot, e, false), p.GetEffectId(itemIdx), slot, e, false, OverlaySlot, 0, "")
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

bool Function _slotHasEffects(int slot)
    if slot < 0 || slot > MAX_CONDITIONS_CACHED()
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
                    msg += " - " + p.GetEffectDisplayLabel(itemIdx) + " " + _readFxParam(tier, e, useScratch)
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
                    msg += " - " + p.GetEffectDisplayLabel(itemIdx) + " " + _readFxParam(tier, e, false)
                endif
            endif
        endif
        e += 1
    endwhile
    Notification(msg)
EndFunction

; ── Slow-tick re-arm ───────────────────────────────────────────────────────
; Re-enter the update-loop state to force OnBeginState, which re-arms the
; RegisterForSingleUpdate timer that drives the loop. Saves persist the STATE
; but not pending timers, so after a load the loop would otherwise never
; re-fire. Cycling through the empty state guarantees OnBeginState runs even
; when we're already in checkingAroused. Defined on self so Caprica can
; validate the state name — external callers (HitListener, MCMQuest) invoke
; Rearm() rather than a cross-script GotoState the compiler can't verify (W4003).
Function Rearm()
    GotoState("")
    GotoState("checkingAroused")
EndFunction

; ── Update loop (state) ───────────────────────────────────────────────────────
; NOTE: "checkingAroused" is a vestigial name from the mod's LewdMarks arousal
; origins. It is now the generic condition-evaluation + effect-tick loop, not
; arousal-specific. Not renamed: the state name is stored in saves, so a rename
; would strand in-flight saves mid-loop.
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
            ; v0.1.29 different-texture cross-blend phase advancement.
            ; If we're mid-cross-blend, check whether we've crossed the
            ; midpoint (transition Phase A → Phase B) or the end (clear
            ; cross-blend state). Phase B is treated as a synthetic tier
            ; change to _crossBlendNewTier below; the eval lock holds
            ; newTier at currentTier for the whole window otherwise.
            bool phaseBStarting = false
            if _crossBlendActive
                ; v0.1.29 dead-zone hold (0.1s) between Phase A end and
                ; Phase B start. During the hold, alpha+em stay at 0 (Phase A
                ; override keeps firing). Reasons:
                ;   - Guarantees C++ Tick has settled last_interp_alpha to 0
                ;     before Phase B install captures it. Without this, the
                ;     InstallLocked snap heuristic (from_alpha < 0.01) misses
                ;     and tint visibly lerps OLD→NEW as alpha rises.
                ;   - Visually imperceptible (player already sees nothing).
                ; Total visible cross-blend = _crossBlendDuration + 0.1s.
                if _crossBlendInPhaseA && now >= _crossBlendStartRT + _crossBlendDuration / 2.0 + 0.1
                    _crossBlendInPhaseA = false
                    phaseBStarting = true
                    if DebugMode
                        Debug.Trace("[MTF xb] PhaseA→B at now=" + now + " startRT=" + _crossBlendStartRT + " dur=" + _crossBlendDuration + " newTier=" + _crossBlendNewTier)
                    endif
                elseif !_crossBlendInPhaseA && now >= _crossBlendStartRT + _crossBlendDuration + 0.1
                    _crossBlendActive = false
                    if DebugMode
                        Debug.Trace("[MTF xb] PhaseB end at now=" + now)
                    endif
                endif
            endif

            int newTier
            if _crossBlendActive
                ; Eval lock: condition re-eval suspended for the full
                ; tDur window so a flapping condition can't restart the
                ; fade mid-flight. Phase B starting case is handled by
                ; the phaseBStarting override below.
                newTier = currentTier
            else
                newTier = evaluateTier()
            endif
            if phaseBStarting
                ; Synthetic tier-change for Phase B: jump straight to the
                ; NEW tier we captured when Phase A started.
                newTier = _crossBlendNewTier
            endif
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

            ; Capture before the clear below — the same-texture skip path
            ; needs to know whether this pass was a forced full redraw (live
            ; shader torn down, must re-stamp) vs a pure tier change (texture
            ; unchanged, C++ Tick owns the visual delta).
            bool wasForceRedraw = forceRedraw
            if forceRedraw || tierChanged
                forceRedraw = false
                if tierChanged && currentTier >= 0
                    _deactivateSlotEffects(currentTier)
                    ; v0.1.24: on the deactivation edge, clear the slot's
                    ; persist timer (any leftover time is discarded — slot
                    ; was either overridden, lost its condition past persist,
                    ; or was just released). Then arm cool if coolMin > 0
                    ; so re-arm is blocked. Without the persist clear, a
                    ; stale persistUntilGT could fool the pre-scan into
                    ; treating the slot as locked-in-persist on the next tick.
                    if currentTier > 0 && _arraysReady
                        ; Whole-array reassign — indexed writes to Auto
                        ; v0.2.8: persistUntilGT is now StorageUtil-backed per
                        ; slot, slot-agnostic — single setter call, no bounds
                        ; check needed (accessor early-returns on bad index).
                        SetCondPersistUntilGT(currentTier, 0.0)
                        _armCoolTimer(currentTier)
                    endif
                endif
                ; v0.1.29 different-texture cross-blend detection. We
                ; route to Phase A (fade OLD alpha → 0, keep texture) when
                ; ALL of:
                ;   - This is a real tier change (not a forceRedraw refresh)
                ;   - We're NOT already starting Phase B (which is itself a
                ;     synthetic tier change for the cross-blend)
                ;   - We have a prev tier's (pack, entry) to compare against
                ;   - The resolved (pack, entry) of NEW differs from OLD
                ;   - tDur > 0
                ; Phase B and same-texture changes go through the existing
                ; in-place V4 cross-fade path.
                string newPackId  = ResolveSlotPackId(newTier)
                string newEntryId = ResolveSlotEntryId(newTier)
                bool diffTexture = (newPackId != _prevPackId) || (newEntryId != _prevEntryId)
                bool useCrossBlend = tierChanged && !phaseBStarting \
                    && _prevPackId != "" && diffTexture \
                    && _sTransitionDuration > 0.0

                if DebugMode
                    Debug.Trace("[MTF xb] decide tch=" + tierChanged + " phB=" + phaseBStarting + " prevPk='" + _prevPackId + "' newPk='" + newPackId + "' prevEn='" + _prevEntryId + "' newEn='" + newEntryId + "' diff=" + diffTexture + " tDur=" + _sTransitionDuration + " useXB=" + useCrossBlend + " curT=" + currentTier + " newT=" + newTier)
                endif
                if useCrossBlend
                    ; Phase A: hold OLD texture in store (don't drawOverlay),
                    ; keep currentTier=OLD (don't update), push C++ with
                    ; alphas overridden to 0 so Tick lerps alpha down over
                    ; tDur/2. Eval lock for the full window so a flapping
                    ; condition can't restart mid-fade.
                    _crossBlendActive    = true
                    _crossBlendInPhaseA  = true
                    _crossBlendStartRT   = now
                    _crossBlendDuration  = _sTransitionDuration
                    _crossBlendNewTier   = newTier
                    ; v0.1.29 fix: Phase A lerp ends at MIDPOINT, not at
                    ; full duration. With endRT=full, 10Hz reinstalls
                    ; compute tDur=remaining-to-full, halving the slope
                    ; after the first install — alpha would only reach
                    ; ~50% by midpoint instead of 0. After midpoint
                    ; reinstalls see tDur=0 (steady-state snap to 0)
                    ; which is what we want for the 0.1s hold.
                    _transitionEndRT     = now + _sTransitionDuration / 2.0
                    if DebugMode
                        Debug.Trace("[MTF xb] PhaseA START now=" + now + " curTier=" + currentTier + " newTier=" + newTier + " dur=" + _sTransitionDuration + " _pulseTier=" + _pulseTier + " _pulseLayerN=" + _pulseLayerN)
                    endif
                    ; _pulseTier was already set by the prior drawOverlay
                    ; for OLD; _applyPulse reads condLayerEmissiveMult etc.
                    ; for _pulseTier=OLD and overrides alpha→0 because
                    ; _crossBlendInPhaseA is now true.
                    _applyPulse(_sTransitionDuration / 2.0)
                    ; Don't drawOverlay, don't deactivate/activate effects,
                    ; don't update _prevPackId/_prevEntryId. All deferred
                    ; until Phase B starts.
                else
                    currentTier = newTier
                    ; v0.3.x same-texture flash fix. When the new tier resolves
                    ; to the SAME (pack, entry) as the previous draw, the
                    ; overlay's TEXTURE binding is unchanged — only the
                    ; C++-owned shader properties (em_mult/alpha/tint/emissive)
                    ; differ between tiers. Re-running drawOverlay +
                    ; ApplyNodeOverrides rebuilds the live shader from the
                    ; override store, which (post-V4) no longer holds those
                    ; properties NOR gloss/spec, producing a one-frame reset
                    ; (white/black flash) before the next C++ Tick re-asserts
                    ; them. Writing AFTER the Apply (RepushLiveNow) can't win
                    ; that race — the render thread samples the reset frame
                    ; between the Apply and the Papyrus re-push. So we SKIP the
                    ; visual redraw entirely: there is nothing for
                    ; ApplyNodeOverrides to do when the texture is identical,
                    ; and the C++ roster transitions (or snaps, tDur=0) the
                    ; colors with no reset window. forceRedraw still takes the
                    ; full path — there the live shader was genuinely torn down
                    ; (armor swap / 3D rebuild) and must be re-stamped.
                    bool sameTexSkip = tierChanged && !diffTexture \
                        && !wasForceRedraw && _prevPackId != ""
                    if sameTexSkip
                        ; Update the pulse cache for the new tier (drawOverlay
                        ; would normally do this via _resyncPulseCache) without
                        ; touching the override store or issuing an Apply.
                        _resyncPulseCache(currentTier)
                    else
                        drawOverlay(PlayerRef, currentTier, true)
                        needPlayerApply = true
                    endif
                    ; Reset pulse phase so the new tier starts cleanly at sin(0)=0.
                    _pulseStartRT = now
                    if tierChanged
                        ; v0.1.28 V4 cross-fade: arm the transition window
                        ; BEFORE the priming _applyPulse so the install captures
                        ; from-state and runs the lerp over the full duration.
                        ; Without the window, _applyPulse would compute
                        ; tDur=0 (no transition in flight) and snap.
                        ; For Phase B start, reset _transitionEndRT to the
                        ; Phase B half-window endpoint so subsequent 10Hz
                        ; _applyPulse reinstalls compute correct remaining
                        ; tDur (Phase A set endRT to its OWN midpoint, which
                        ; has already passed by now).
                        float pulseDur
                        if phaseBStarting
                            pulseDur = _crossBlendDuration / 2.0
                            _transitionEndRT = now + _crossBlendDuration / 2.0
                        else
                            if _sTransitionDuration > 0.0
                                _transitionEndRT = now + _sTransitionDuration
                            else
                                _transitionEndRT = 0.0
                            endif
                            pulseDur = _sTransitionDuration
                        endif
                        ; Push the pulse roster entry BEFORE activating effects.
                        ; v0.1.3 flash.onhit's onActivate calls MTFPulse.SetActorFlash,
                        ; which silently no-ops unless a (actor, base_slot) entry
                        ; already exists. _applyPulse runs anyway at the bottom of
                        ; OnUpdate at 10Hz, but the first SetActorFlash on tier
                        ; activation would miss without this priming call.
                        _applyPulse(pulseDur)
                        _activateSlotEffects(currentTier)
                        ; v0.1.24: arm persist timer on activation edge (any new > 0
                        ; with persistMin > 0). Slot will keep winning the eval for
                        ; the persist window regardless of condition.
                        if currentTier > 0 && _arraysReady
                            _armPersistTimer(currentTier)
                        endif
                        _notifyTierChange(currentTier)
                        ; v0.1.20: external-integration broadcast. After the
                        ; activation pass so SkyrimNet decorators called from
                        ; the listener see the new state's effects already on.
                        _emitTierChanged(PlayerRef, "player", "", prevTierForEmit, currentTier)
                    endif
                    ; v0.1.29: always refresh _prevPackId/_prevEntryId after
                    ; a non-cross-blend draw — even on forceRedraw refreshes
                    ; that don't change the tier. This lets the FIRST tier
                    ; change after a save load (where _prevPackId starts
                    ; empty) detect different-texture correctly. Otherwise
                    ; we'd snap on the very first transition.
                    _prevPackId  = newPackId
                    _prevEntryId = newEntryId
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

Function _setAreaBaseSlot(string area, int value)
{Mirror writer for the MCM-driven TARGET base slot (OverlaySlot etc.),
 companion of _setAreaCurrentBaseSlot. Routed through here so every base
 change goes via the one guarded SetOverlaySlot path.}
    if area == "Body"
        OverlaySlot = value
    elseif area == "Face"
        FaceOverlaySlot = value
    elseif area == "Hands"
        HandOverlaySlot = value
    elseif area == "Feet"
        FeetOverlaySlot = value
    endif
EndFunction

Function SetOverlaySlot(string area, int newBase)
{Safe single entry point for changing an area's MCM base overlay slot.
 Clears the range we ACTUALLY painted FIRST (via the Current<Area> mirror),
 so nothing is stranded in the SKEE store when the base moves, THEN sets the
 new base and forces a redraw.

 The pre-clear is keyed off the painted mirror (Current<Area>), not the
 OverlaySlot property — so it is correct even when the new base equals the
 property's current value in a single pass. That is exactly the v0.4.x
 ghost-tattoo bug: a reset wrote base==current together, the slow-tick
 mismatch detector never fired, and "Body [ovl16]" stayed painted with no
 live driver (renders white/B&W). Idempotent — a true no-op still refreshes.}
    if _areaCurrentBaseSlot(area) != newBase
        ; Same clear the slow-tick detector uses; keyed off Current<Area>
        ; (where we really painted). Safe to call before the base changes.
        removeOverlay(PlayerRef)
    endif
    _setAreaBaseSlot(area, newBase)
    setRedraw()
EndFunction

; ── TEST-ONLY slot-ghost levers (driven by MTF_TestRunner's HOME-key menu) ───
; Reproduce / verify the v0.4.x ghost-tattoo bug. Remove before ship.
Function DebugClobberSlot()
{TEST: reproduce the bug. Raw-writes base==current in one pass (what the old
 update wipe did) — bypasses SetOverlaySlot's pre-clear, so whatever is
 painted at the old Current slot is orphaned (renders white). No heal: the
 slow-tick detector sees Current==Overlay and stays silent.}
    OverlaySlot        = 2
    CurrentOverlaySlot = 2
    setRedraw()
    Debug.Notification("MTF TEST: raw clobber -> ghost expected at old slot")
EndFunction

Function DebugClearBodyPool()
{TEST: clear the WHOLE body overlay pool (ovl0..iNumOverlays) on the player
 and Apply — a clean slate between test iterations. Destructive to any other
 mod's body overlays too; test characters only.}
    bool isFemale = PlayerRef.GetLeveledActorBase().GetSex() as bool
    int n = _numOverlays("Body")
    int i = 0
    while i < n
        clearOverlay(PlayerRef, isFemale, "Body", i)
        i += 1
    endwhile
    NiOverride.ApplyNodeOverrides(PlayerRef)
    MTFPulse.ClearActor(PlayerRef)
    Debug.Notification("MTF TEST: cleared body overlay pool 0.." + (n - 1))
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
    while s <= MAX_CONDITIONS_CACHED()
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
    while s <= MAX_CONDITIONS_CACHED()
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
    ; v0.2.7: widened from idx>=8 to MAX_CONDITIONS() so backend slots
    ; (8..MAX_CONDITIONS) can still resolve their visual via Default-
    ; inheritance in _g_resolvePackId/_g_resolveEntryId. The clear-overlay
    ; branch now only fires for truly out-of-range tiers.
    if idx < 0 || idx > MAX_CONDITIONS_CACHED()
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
 have been done by the caller (we don't repeat the check per layer).

 v0.1.28 V4 cross-fade: em mult (1), alpha (8), tint (7), and emissive
 color (0) are NO LONGER written here. C++ Tick owns those four properties
 exclusively via skee_bridge::SetNodeProperty (immediate writes, bypass
 the override store). V4 _resyncPulseCache guarantees a roster entry
 exists for every tier with layers, so Tick always runs to drive them.
 Stacked-preset paths get their roster entry via _rosterAddOrUpdate.

 Writing these to the store before would push target values to live on
 ApplyNodeOverrides, causing a visible 1-frame target flash before Tick's
 first lerped frame wrote the from-state. Removing the writes lets Tick
 own the live shader uninterrupted; the lerp starts cleanly from prev's
 last_interp values.

 Texture binding (9) is written here. Glossiness (2) and specular strength
 (3) are ALSO written here as of v0.3.x — but keyed off ALPHA (visibility),
 NOT off emissive intensity. History: gloss/spec used to flip based on
 Intensity > 0, which fired INSTANTLY at tier change while Tick was still
 lerping em_mult high->0, producing a "high em + zero gloss" combo that
 rendered black for the whole transition. V4 removed them entirely and let
 Tick own them. But that reopened a DIFFERENT black flash: on a draw where
 the texture is APPEARING (none->tattoo) or changing, ApplyNodeOverrides
 re-derives the live shader from the store; with no gloss in the store the
 reset frame paints the new texture at gloss 0, so the near-black ink
 diffuse renders as a black smudge for the one frame until the next C++
 Tick writes gloss. Writing gloss/spec to the STORE here (keyed off alpha,
 matching Tick's current sheen_vis logic) makes the Apply frame paint a
 visible layer with sheen instead of black; the store and Tick agree
 because both key off alpha, so there is no high-em/zero-gloss combo. Tick
 keeps owning gloss/spec live every frame after the Apply. A cleared slot
 (alpha 0) still gets gloss 0 via _clearOverlayDeferred.

 em mult (1), alpha (8), tint (7), emissive color (0) remain Tick-owned and
 are NOT written here (writing them would reintroduce the 1-frame target
 flash V4 fixed). Tint/Intensity/Emissive params unused; Alpha is consulted.}
    string Node = Area + " [ovl" + Slot + "]"
    NiOverride.AddNodeOverrideString(Target, isFemale, Node, 9, 0, Texture, true)
    ; Sheen floor for the ApplyNodeOverrides reset frame (see docstring).
    ; Visible layer (alpha>0) -> gloss 5 / spec 1 so the ink diffuse renders;
    ; matches Tick's gloss=5*sheen_vis, spec=1*sheen_vis with sheen_vis=alpha.
    float sheen = 0.0
    if Alpha > 0.0
        sheen = 1.0
    endif
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 2, -1, 5.0 * sheen, true)
    NiOverride.AddNodeOverrideFloat(Target, isFemale, Node, 3, -1, 1.0 * sheen, true)
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

    ; v0.3.x early post-load draw. setRedraw() only sets the flag; the actual
    ; drawOverlay -> ApplyNodeOverrides (which pushes the restored override
    ; store -- texture + the v0.3.x gloss/spec sheen floor -- onto the live
    ; shader) otherwise waits for the ~5s post-load freeze to expire, so the
    ; tattoo visibly lags several seconds behind the load. currentTier is a
    ; persisted script var holding the resting tier at save time, so we can
    ; draw the MCM-base immediately here (we run at ~0.5s, during the freeze).
    ; This is safe alongside the freeze: eval is still suspended, so nothing
    ; competes; the freeze-gated slow-tick redraw remains the backstop that
    ; re-evaluates and corrects the tier once condition sources have settled.
    ; Skipped when currentTier < 0 (no base tattoo to draw). All draws below
    ; pass deferApply=true and are collapsed into a SINGLE ApplyNodeOverrides
    ; at the end -- N+1 separate Applies (base + one per stacked preset) would
    ; each rebuild the live shader and cascade-flash on load.
    bool needApply = false
    if currentTier >= 0
        drawOverlay(PlayerRef, currentTier, true)
        needApply = true
    endif

    float rtNow = Utility.GetCurrentRealTime()
    int n = GetActorPresetCount(PlayerRef)
    int i = 0
    while i < n
        string nm = GetActorPresetAt(PlayerRef, i)
        if nm != "" && _loadPresetToScratch(nm)
            int storedTier = _getActorPresetTier(PlayerRef, nm)
            if storedTier >= 0
                ; Early visual draw for stacked presets too, mirroring the
                ; MCM-base draw above -- otherwise they wait out the freeze.
                _drawPresetOnActor(PlayerRef, nm, storedTier, true)
                needApply = true
                ; snapNow=true: fresh post-load entries must restore their
                ; resting visual instantly, not fade in over transition.duration.
                _rosterAddOrUpdate(PlayerRef, nm, storedTier, rtNow, true)
            endif
        endif
        i += 1
    endwhile

    if needApply
        NiOverride.ApplyNodeOverrides(PlayerRef)
    endif
EndFunction

; ── NiOverride wrappers ───────────────────────────────────────────────────────

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

; ── SPID-style NPC preset distribution (optional addon trigger) ───────────────
; Rules in distribution/<pack>.json map a filter -> preset(s). The optional
; MTF_SPID_Distributor addon delivers a self-deleting ability to NPCs via SPID;
; that ability's effect calls DistributeToActor(akTarget) then RemoveSpell(self).
; ALL selection is MTF-owned JSON — SPID is purely the per-NPC trigger (matching
; how SlaveTats-SPID / Overlay-Distribution-Framework do it: the mapping never
; lives in the distributed form). Mirrors the .cond.items[] reader idiom.
;
; Rules parse ONCE into StorageUtil caches (form refs resolved to forms at load;
; eval touches only cheap engine calls + FormListGet/HasKeyword, never JsonUtil
; per actor — the task-queued-native perf rule). mtf.distr.ver is the cache
; sentinel, written LAST so a crash mid-parse forces a clean re-parse. Per-actor
; mtf.distr.done makes evaluation one-shot. All form filters are 0xID~plugin
; refs (npcs/factions/races/formlists/keywords) — uniform, avoids the fragile
; keyword-editorID->form resolution.
int Function DIST_SCHEMA() global
    return 1
EndFunction

; "0xID~plugin.esp" -> Form (None on parse failure). GetFormFromFile masks the
; load-order byte, so an 8-digit (00xxxxxx) or 6-digit id both resolve.
Form Function _distRefToForm(string ref)
    int tilde = StringUtil.Find(ref, "~")
    if tilde <= 0
        return None
    endif
    string idHex = StringUtil.Substring(ref, 0, tilde)
    string plugin = StringUtil.Substring(ref, tilde + 1)
    if StringUtil.Find(idHex, "0x") == 0 || StringUtil.Find(idHex, "0X") == 0
        idHex = StringUtil.Substring(idHex, 2)
    endif
    int len = StringUtil.GetLength(idHex)
    if len < 1 || plugin == ""
        return None
    endif
    int result = 0
    int i = 0
    while i < len
        int d = _hexCharToInt(StringUtil.Substring(idHex, i, 1))
        if d < 0
            return None
        endif
        result = result * 16 + d
        i += 1
    endwhile
    return Game.GetFormFromFile(result, plugin)
EndFunction

Function _distClearRuleSlot(int ruleIdx)
    string b = "mtf.distr." + ruleIdx + "."
    StorageUtil.StringListClear(self, b + "presets")
    StorageUtil.IntListClear(self, b + "weights")
    StorageUtil.FormListClear(self, b + "npcs")
    StorageUtil.FormListClear(self, b + "factions")
    StorageUtil.FormListClear(self, b + "races")
    StorageUtil.FormListClear(self, b + "formlists")
    StorageUtil.FormListClear(self, b + "keywords")
    StorageUtil.FormListClear(self, b + "kwexclude")
EndFunction

Function _distLoadFormList(string f, string jsonArrPath, string cacheKey, int ruleIdx)
    int n = JsonUtil.PathCount(f, jsonArrPath)
    int j = 0
    while j < n
        string ref = JsonUtil.GetPathStringValue(f, jsonArrPath + "[" + j + "]", "")
        Form fm = _distRefToForm(ref)
        if fm != None
            StorageUtil.FormListAdd(self, "mtf.distr." + ruleIdx + "." + cacheKey, fm)
        endif
        j += 1
    endwhile
EndFunction

; Load rule r of file f into cache slot ruleIdx. Returns false (slot left clean)
; if the rule names no preset — caller does NOT advance ruleIdx then.
bool Function _distLoadRule(string f, int r, int ruleIdx)
    string rp = ".rules[" + r + "]"
    string b = "mtf.distr." + ruleIdx + "."
    _distClearRuleSlot(ruleIdx)   ; clean slot so a prior skipped rule can't bleed in
    ; presets: array "presets" (+ optional parallel "weights"), else single "preset"
    int pn = JsonUtil.PathCount(f, rp + ".presets")
    if pn > 0
        int j = 0
        while j < pn
            string nm = JsonUtil.GetPathStringValue(f, rp + ".presets[" + j + "]", "")
            if nm != ""
                StorageUtil.StringListAdd(self, b + "presets", nm)
            endif
            j += 1
        endwhile
        int wn = JsonUtil.PathCount(f, rp + ".weights")
        int w = 0
        while w < wn
            StorageUtil.IntListAdd(self, b + "weights", JsonUtil.GetPathIntValue(f, rp + ".weights[" + w + "]", 1))
            w += 1
        endwhile
    else
        string single = JsonUtil.GetPathStringValue(f, rp + ".preset", "")
        if single != ""
            StorageUtil.StringListAdd(self, b + "presets", single)
        endif
    endif
    if StorageUtil.StringListCount(self, b + "presets") < 1
        return false
    endif
    _distLoadFormList(f, rp + ".npcs",             "npcs",      ruleIdx)
    _distLoadFormList(f, rp + ".factions",         "factions",  ruleIdx)
    _distLoadFormList(f, rp + ".races",            "races",     ruleIdx)
    _distLoadFormList(f, rp + ".formlists",        "formlists", ruleIdx)
    _distLoadFormList(f, rp + ".keywords",         "keywords",  ruleIdx)
    _distLoadFormList(f, rp + ".keywords_exclude", "kwexclude", ruleIdx)
    StorageUtil.SetIntValue(self, b + "chance",   JsonUtil.GetPathIntValue(f, rp + ".chance", 100))
    StorageUtil.SetIntValue(self, b + "levelmin", JsonUtil.GetPathIntValue(f, rp + ".level_min", 0))
    StorageUtil.SetIntValue(self, b + "levelmax", JsonUtil.GetPathIntValue(f, rp + ".level_max", 0))
    string sx = JsonUtil.GetPathStringValue(f, rp + ".sex", "any")
    int sxi = 0
    if sx == "male" || sx == "m"
        sxi = 1
    elseif sx == "female" || sx == "f"
        sxi = 2
    endif
    StorageUtil.SetIntValue(self, b + "sex", sxi)
    return true
EndFunction

; Parse all distribution/*.json into the rule cache once (schema-versioned).
Function _distEnsureLoaded()
    if StorageUtil.GetIntValue(self, "mtf.distr.ver", 0) == DIST_SCHEMA()
        return
    endif
    int oldN = StorageUtil.GetIntValue(self, "mtf.distr.count", 0)
    int c = 0
    while c < oldN
        _distClearRuleSlot(c)
        c += 1
    endwhile
    int ruleIdx = 0
    string[] files = JsonUtil.JsonInFolder("MagicTattoosFramework/distribution")
    if files != None
        int fi = 0
        while fi < files.Length
            string f = "MagicTattoosFramework/distribution/" + files[fi]
            int rn = JsonUtil.PathCount(f, ".rules")
            int r = 0
            while r < rn
                if _distLoadRule(f, r, ruleIdx)
                    ruleIdx += 1
                endif
                r += 1
            endwhile
            fi += 1
        endwhile
    endif
    StorageUtil.SetIntValue(self, "mtf.distr.count", ruleIdx)
    StorageUtil.SetIntValue(self, "mtf.distr.ver", DIST_SCHEMA())   ; sentinel LAST
EndFunction

bool Function _distRuleMatches(Actor target, int i)
    string b = "mtf.distr." + i + "."
    ActorBase ab = target.GetActorBase()
    ; npcs: actor's base must be one of the listed base forms
    if StorageUtil.FormListCount(self, b + "npcs") > 0 && !StorageUtil.FormListHas(self, b + "npcs", ab)
        return false
    endif
    ; factions: in any listed faction
    int fc = StorageUtil.FormListCount(self, b + "factions")
    if fc > 0
        bool ok = false
        int j = 0
        while j < fc && !ok
            ok = target.IsInFaction(StorageUtil.FormListGet(self, b + "factions", j) as Faction)
            j += 1
        endwhile
        if !ok
            return false
        endif
    endif
    ; races: current race in the list
    if StorageUtil.FormListCount(self, b + "races") > 0 && !StorageUtil.FormListHas(self, b + "races", target.GetRace())
        return false
    endif
    ; formlists: actor base contained in any listed FormList
    int lc = StorageUtil.FormListCount(self, b + "formlists")
    if lc > 0
        bool ok2 = false
        int k = 0
        while k < lc && !ok2
            FormList fl = StorageUtil.FormListGet(self, b + "formlists", k) as FormList
            ok2 = fl != None && fl.HasForm(ab)
            k += 1
        endwhile
        if !ok2
            return false
        endif
    endif
    ; keywords: has any listed keyword
    int kc = StorageUtil.FormListCount(self, b + "keywords")
    if kc > 0
        bool ok3 = false
        int m = 0
        while m < kc && !ok3
            ok3 = target.HasKeyword(StorageUtil.FormListGet(self, b + "keywords", m) as Keyword)
            m += 1
        endwhile
        if !ok3
            return false
        endif
    endif
    ; keywords_exclude: has NONE of these
    int xc = StorageUtil.FormListCount(self, b + "kwexclude")
    int x = 0
    while x < xc
        if target.HasKeyword(StorageUtil.FormListGet(self, b + "kwexclude", x) as Keyword)
            return false
        endif
        x += 1
    endwhile
    ; sex: 0 any / 1 male / 2 female
    int sex = StorageUtil.GetIntValue(self, b + "sex", 0)
    if sex > 0
        int aSex = ab.GetSex()   ; 0 male, 1 female
        if (sex == 1 && aSex != 0) || (sex == 2 && aSex != 1)
            return false
        endif
    endif
    ; level range (0 bound = open)
    int lmin = StorageUtil.GetIntValue(self, b + "levelmin", 0)
    int lmax = StorageUtil.GetIntValue(self, b + "levelmax", 0)
    int lvl = target.GetLevel()
    if (lmin > 0 && lvl < lmin) || (lmax > 0 && lvl > lmax)
        return false
    endif
    return true
EndFunction

; Weighted pick from the rule's preset list (equal odds when no weights).
string Function _distPickPreset(int i)
    string b = "mtf.distr." + i + "."
    int pc = StorageUtil.StringListCount(self, b + "presets")
    if pc < 1
        return ""
    endif
    if pc == 1
        return StorageUtil.StringListGet(self, b + "presets", 0)
    endif
    int wc = StorageUtil.IntListCount(self, b + "weights")
    int total = 0
    int j = 0
    while j < pc
        int w = 1
        if j < wc
            w = StorageUtil.IntListGet(self, b + "weights", j)
            if w < 0
                w = 0
            endif
        endif
        total += w
        j += 1
    endwhile
    if total <= 0
        return StorageUtil.StringListGet(self, b + "presets", Utility.RandomInt(0, pc - 1))
    endif
    int roll = Utility.RandomInt(1, total)
    int acc = 0
    int k = 0
    while k < pc
        int w2 = 1
        if k < wc
            w2 = StorageUtil.IntListGet(self, b + "weights", k)
            if w2 < 0
                w2 = 0
            endif
        endif
        acc += w2
        if roll <= acc
            return StorageUtil.StringListGet(self, b + "presets", k)
        endif
        k += 1
    endwhile
    return StorageUtil.StringListGet(self, b + "presets", pc - 1)
EndFunction

; Public entry the optional SPID addon calls on each delivered NPC. One-shot per
; actor. Returns the AddAppliedPreset code, 0 if no rule matched / already done,
; -2 None, -8 player (distribution is NPC-only).
int Function DistributeToActor(Actor target)
    if target == None
        return -2
    endif
    if target == PlayerRef
        return -8
    endif
    if StorageUtil.GetIntValue(target, "mtf.distr.done", 0) == 1
        return 0
    endif
    ; Mark done BEFORE the suspending AddAppliedPreset so a concurrent re-fire
    ; (e.g. fast re-load) early-outs (KB: write storage before suspending calls).
    StorageUtil.SetIntValue(target, "mtf.distr.done", 1)
    _distEnsureLoaded()
    int n = StorageUtil.GetIntValue(self, "mtf.distr.count", 0)
    int i = 0
    while i < n
        if _distRuleMatches(target, i)
            int chance = StorageUtil.GetIntValue(self, "mtf.distr." + i + ".chance", 100)
            if chance >= 100 || Utility.RandomInt(1, 100) <= chance
                string preset = _distPickPreset(i)
                if preset != ""
                    return AddAppliedPreset(target, preset)
                endif
            endif
            return 0   ; first matching rule wins
        endif
        i += 1
    endwhile
    return 0
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
    ; Broadcast removal as a tier transition (prevTier -> -1). The bridge
    ; uses this to invalidate per-actor caches (e.g. the SkyrimNet bridge's
    ; pre-rendered StorageUtil bio string) — without it the bio would show
    ; the preset until the next unrelated tier change happened to refresh.
    ; Fired AFTER compact so listeners see the actor in its post-removal state.
    if prevTier >= 0
        _emitTierChanged(target, "preset", name, prevTier, -1)
    endif
EndFunction

Function RemoveTrackedActor(Actor target)
{Untrack an NPC entirely: deactivate effects for every applied preset,
 clear their overlay ranges, drop tracking state.}
    if target == None || !IsTrackedActor(target)
        return
    endif
    int n = GetActorPresetCount(target)
    ; Snapshot (name,tier) pairs for the post-cleanup emit pass. We can't
    ; emit during the deactivate loop — the bridge would call
    ; _rebuildRenderedFor which iterates mtf.presets while we're still
    ; mutating it. Defer to after _clearAllActorState wipes everything,
    ; then emit prevTier->-1 for each so the bridge rebuilds once on an
    ; empty preset list (producing the empty "no Magic Tattoos" bio).
    string[] snapNames = Utility.CreateStringArray(n, "")
    int[] snapTiers = Utility.CreateIntArray(n, -1)
    int i = n - 1
    while i >= 0
        string nm = GetActorPresetAt(target, i)
        if nm != ""
            int tier = _getActorPresetTier(target, nm)
            snapNames[i] = nm
            snapTiers[i] = tier
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
    ; Broadcast removal per-preset AFTER state is wiped. The bridge's
    ; HandleTierChange will call _rebuildRenderedFor and find an empty
    ; mtf.presets list, writing "" to the bio string. Multiple emits in
    ; quick succession are fine — the rebuild is idempotent and the final
    ; one wins (each writes the same empty result).
    if snapNames != None
        int j = 0
        while j < snapNames.Length
            if snapNames[j] != "" && snapTiers[j] >= 0
                _emitTierChanged(target, "preset", snapNames[j], snapTiers[j], -1)
            endif
            j += 1
        endwhile
    endif
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

; v0.1.24: split cooldown into persist (slot stays active) + cool (re-arm
; lockout). Old `.cd.<slot>` key is no longer read or written — existing
; saves' stale .cd values become orphaned StorageUtil entries (harmless).
; Per user direction: preset migration "resets to defaults", so any active
; cooldown timer from before the upgrade is simply dropped.
float Function _getActorPresetPersistUntil(Actor target, string name, int slot)
    if target == None || name == ""
        return 0.0
    endif
    return StorageUtil.GetFloatValue(target, "mtf.preset." + name + ".persist." + slot, 0.0)
EndFunction
Function _setActorPresetPersistUntil(Actor target, string name, int slot, float gameTime)
    if target != None && name != ""
        StorageUtil.SetFloatValue(target, "mtf.preset." + name + ".persist." + slot, gameTime)
    endif
EndFunction

float Function _getActorPresetCoolUntil(Actor target, string name, int slot)
    if target == None || name == ""
        return 0.0
    endif
    return StorageUtil.GetFloatValue(target, "mtf.preset." + name + ".cool." + slot, 0.0)
EndFunction
Function _setActorPresetCoolUntil(Actor target, string name, int slot, float gameTime)
    if target != None && name != ""
        StorageUtil.SetFloatValue(target, "mtf.preset." + name + ".cool." + slot, gameTime)
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
    ; v0.2.7: widen to MAX_CONDITIONS() so backend-slot timers don't leak.
    int slotMax = MAX_CONDITIONS()
    int s = 0
    while s <= slotMax
        ; v0.1.24: persist + cool replaced the old single .cd timer. Drop
        ; the legacy key too in case it was set by a pre-upgrade save.
        StorageUtil.UnsetFloatValue(target, "mtf.preset." + name + ".cd." + s)
        StorageUtil.UnsetFloatValue(target, "mtf.preset." + name + ".persist." + s)
        StorageUtil.UnsetFloatValue(target, "mtf.preset." + name + ".cool." + s)
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
    ;
    ; v0.2.6: _sArraysReady bool gates this so the inner `== None` check
    ; runs at most ONCE per session (previously ran ~23×/preset eval and
    ; each call logged "Cannot cast from None to String[]" per memory
    ; project_papyrus_array_none_cast_noise). The == None check itself
    ; is kept in the slow path so old saves where the arrays survived
    ; from a pre-fix session don't re-allocate over their cached data.
    ;
    ; v0.2.7: kept at 8 elements for MCM slots only. Earlier attempt to
    ; widen these to 33 crashed PapyrusUtil — "Cannot create an array
    ; into a non-array variable" on existing saves (analogue of the
    ; bulk-var-add quirk applied to array reassignment of already-
    ; attached script vars). Backend slot cond data instead lives in
    ; per-slot StorageUtil keys (mtf.scratch.cond.{pluginid,param}.<name>.<slot>);
    ; see _getScratchCondPluginId / _setScratchCondPluginId and the
    ; _g_condPluginId scratch branch.
    if _sArraysReady
        return
    endif
    ; v6: nothing to allocate — all per-slot scratch lives in per-preset
    ; StorageUtil keys now (see _getScratch* / _setScratch*). The flag just
    ; records that the scratch subsystem is live so _g_* readers don't early-out.
    _sArraysReady = true
EndFunction

; ── v0.2.7 backend-slot scratch cond storage ────────────────────────────────
; Mirrors the player-path SetCondPluginId/GetCondPluginId pattern (which uses
; StorageUtil instead of Auto arrays) so the apply-via-spell flow can hold
; cond bindings for slots beyond the MCM cap. Per-preset namespaced by
; _scratchLoadedFor so swapping between presets doesn't blend backend slots.
; Existing saves don't have these keys yet; GetStringValue returns "" which
; reads as "empty slot" and evaluateTierForActor skips them safely.
string Function _getScratchCondPluginId(int slot)
    return StorageUtil.GetStringValue(None, "mtf.scratch.cond.pluginid." + _scratchLoadedFor + "." + slot, "")
EndFunction
Function _setScratchCondPluginId(int slot, string v)
    StorageUtil.SetStringValue(None, "mtf.scratch.cond.pluginid." + _scratchLoadedFor + "." + slot, v)
EndFunction
int Function _getScratchCondParam(int slot)
    return StorageUtil.GetIntValue(None, "mtf.scratch.cond.param." + _scratchLoadedFor + "." + slot, 0)
EndFunction
Function _setScratchCondParam(int slot, int v)
    StorageUtil.SetIntValue(None, "mtf.scratch.cond.param." + _scratchLoadedFor + "." + slot, v)
EndFunction
; v0.2.9 string-id scratch accessors for menu cond params. Per-preset namespaced
; just like the int variants above. Read at eval time before calling
; plugin.checkCondition via _setEvalParamStr.
string Function _getScratchCondParamStr(int slot)
    return StorageUtil.GetStringValue(None, "mtf.scratch.cond.param." + _scratchLoadedFor + "." + slot + ".s", "")
EndFunction
Function _setScratchCondParamStr(int slot, string v)
    StorageUtil.SetStringValue(None, "mtf.scratch.cond.param." + _scratchLoadedFor + "." + slot + ".s", v)
EndFunction
string Function _getScratchCondParam2Str(int slot)
    return StorageUtil.GetStringValue(None, "mtf.scratch.cond.param2." + _scratchLoadedFor + "." + slot + ".s", "")
EndFunction
Function _setScratchCondParam2Str(int slot, string v)
    StorageUtil.SetStringValue(None, "mtf.scratch.cond.param2." + _scratchLoadedFor + "." + slot + ".s", v)
EndFunction
; v0.2.9 per-slot display name (scratch path). Mirrors the cond.pluginid pattern;
; namespaced by _scratchLoadedFor so each preset keeps its own slot names. Read
; via _g_condName below (currently MCM-only consumer); written by cold load.
string Function _getScratchCondName(int slot)
    return StorageUtil.GetStringValue(None, "mtf.scratch.cond.name." + _scratchLoadedFor + "." + slot, "")
EndFunction
Function _setScratchCondName(int slot, string v)
    StorageUtil.SetStringValue(None, "mtf.scratch.cond.name." + _scratchLoadedFor + "." + slot, v)
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
 with the plugin-driven path.

 v3: cooldown rework. _sCooldownMin/_sCooldownMode are semantically
 persistMin/allowOverride (default flip — allowOverride defaults to 1,
 was 0 under old "after-deactivate" mode). New `cool.min` key written
 per-preset under the namespaced scratch key. v2 caches won't have the
 new cool.min keys; bumping invalidates them so cold load reads the
 new schema 8 JSON keys.

 v4: backend-slot support. The _s arrays stay length 8 (avoiding the
 bulk-var-add crash on existing saves), but cold load now ALSO writes
 backend slot cond pluginid/param to per-preset StorageUtil keys via
 _setScratchCondPluginId / _setScratchCondParam. v3 caches were
 produced WITHOUT those backend writes; a cache hit on a v3 entry
 would skip the cold-load path and leave backend slots empty, so the
 apply-via-spell flow couldn't evaluate slot >= 8 conditions. Bumping
 forces a one-shot cold rebuild for every cached preset on first
 access under the new code.

 v5: per-slot display name (3a slot rename + swap). Cold load now also
 writes mtf.scratch.cond.name.<preset>.<slot> via _setScratchCondName
 for every slot 0..maxC. v4 caches were produced WITHOUT those name
 writes; a cache hit on a v4 entry would skip cold load and the MCM
 slot dropdown would render canonical labels even when the preset
 stored custom names. Bumping forces a one-shot cold rebuild.

 v6: full StorageUtil migration. The _s* scratch arrays were removed; cold
 load now writes per-slot cond/layer/pulse/persist for EVERY slot 0..maxC to
 per-preset namespaced scalar keys (not the old length-8 cache lists). v5
 caches predate those scalar keys, so a v5 hit would read empty per-slot
 scratch — bumping forces a one-shot cold rebuild on first access.}
    return 6
EndFunction

; v0.1.24 scratch-namespaced cool.min accessors. Per-preset (preset name
; embedded in the key), mirroring _set/_getScratchPulsePause. _scratchLoadedFor
; is the active scratch preset name; cold loads + cache hits set it before
; calling these.
int Function _getScratchCoolMin(int slot)
    return StorageUtil.GetIntValue(self, "mtf.scratch.cool.min." + _scratchLoadedFor + "." + slot, 0)
EndFunction
Function _setScratchCoolMin(int slot, int v)
    StorageUtil.SetIntValue(self, "mtf.scratch.cool.min." + _scratchLoadedFor + "." + slot, v)
EndFunction

; ── v6 full-StorageUtil scratch migration ──────────────────────────────────
; The remaining per-slot scratch fields (cond packid/entryid, persistMin,
; allowOverride, pulse rate/depth/waveform, layer tint/emissive/emult/alpha)
; moved off the fixed-length _s* arrays onto per-preset namespaced StorageUtil
; keys — same pattern as the cond.pluginid / pulse.pause accessors above. This
; removes the length-8 visual/pulse/persist cap on the scratch (NPC) path so
; every slot up to MAX_CONDITIONS() carries its own visual, pulse and persist.
; Layer keys carry a trailing .<L> for the per-slot layer index (0..maxL-1).
string Function _getScratchCondPackId(int slot)
    return StorageUtil.GetStringValue(None, "mtf.scratch.cond.packid." + _scratchLoadedFor + "." + slot, "")
EndFunction
Function _setScratchCondPackId(int slot, string v)
    StorageUtil.SetStringValue(None, "mtf.scratch.cond.packid." + _scratchLoadedFor + "." + slot, v)
EndFunction
string Function _getScratchCondEntryId(int slot)
    return StorageUtil.GetStringValue(None, "mtf.scratch.cond.entryid." + _scratchLoadedFor + "." + slot, "")
EndFunction
Function _setScratchCondEntryId(int slot, string v)
    StorageUtil.SetStringValue(None, "mtf.scratch.cond.entryid." + _scratchLoadedFor + "." + slot, v)
EndFunction
int Function _getScratchPersistMin(int slot)
    return StorageUtil.GetIntValue(None, "mtf.scratch.persistmin." + _scratchLoadedFor + "." + slot, 0)
EndFunction
Function _setScratchPersistMin(int slot, int v)
    StorageUtil.SetIntValue(None, "mtf.scratch.persistmin." + _scratchLoadedFor + "." + slot, v)
EndFunction
int Function _getScratchAllowOverride(int slot)
    return StorageUtil.GetIntValue(None, "mtf.scratch.allowoverride." + _scratchLoadedFor + "." + slot, 1)
EndFunction
Function _setScratchAllowOverride(int slot, int v)
    StorageUtil.SetIntValue(None, "mtf.scratch.allowoverride." + _scratchLoadedFor + "." + slot, v)
EndFunction
float Function _getScratchPulseRate(int slot)
    return StorageUtil.GetFloatValue(None, "mtf.scratch.pulse.rate." + _scratchLoadedFor + "." + slot, 0.0)
EndFunction
Function _setScratchPulseRate(int slot, float v)
    StorageUtil.SetFloatValue(None, "mtf.scratch.pulse.rate." + _scratchLoadedFor + "." + slot, v)
EndFunction
int Function _getScratchPulseDepth(int slot)
    return StorageUtil.GetIntValue(None, "mtf.scratch.pulse.depth." + _scratchLoadedFor + "." + slot, 0)
EndFunction
Function _setScratchPulseDepth(int slot, int v)
    StorageUtil.SetIntValue(None, "mtf.scratch.pulse.depth." + _scratchLoadedFor + "." + slot, v)
EndFunction
string Function _getScratchWaveform(int slot)
    return StorageUtil.GetStringValue(None, "mtf.scratch.pulse.waveform." + _scratchLoadedFor + "." + slot, "")
EndFunction
Function _setScratchWaveform(int slot, string v)
    StorageUtil.SetStringValue(None, "mtf.scratch.pulse.waveform." + _scratchLoadedFor + "." + slot, v)
EndFunction
int Function _getScratchLayerTint(int slot, int L)
    return StorageUtil.GetIntValue(None, "mtf.scratch.layer.tint." + _scratchLoadedFor + "." + slot + "." + L, 16777215)
EndFunction
Function _setScratchLayerTint(int slot, int L, int v)
    StorageUtil.SetIntValue(None, "mtf.scratch.layer.tint." + _scratchLoadedFor + "." + slot + "." + L, v)
EndFunction
int Function _getScratchLayerEmissive(int slot, int L)
    return StorageUtil.GetIntValue(None, "mtf.scratch.layer.emissive." + _scratchLoadedFor + "." + slot + "." + L, 16777215)
EndFunction
Function _setScratchLayerEmissive(int slot, int L, int v)
    StorageUtil.SetIntValue(None, "mtf.scratch.layer.emissive." + _scratchLoadedFor + "." + slot + "." + L, v)
EndFunction
float Function _getScratchLayerEmissiveMult(int slot, int L)
    return StorageUtil.GetFloatValue(None, "mtf.scratch.layer.emult." + _scratchLoadedFor + "." + slot + "." + L, 0.0)
EndFunction
Function _setScratchLayerEmissiveMult(int slot, int L, float v)
    StorageUtil.SetFloatValue(None, "mtf.scratch.layer.emult." + _scratchLoadedFor + "." + slot + "." + L, v)
EndFunction
int Function _getScratchLayerAlpha(int slot, int L)
    return StorageUtil.GetIntValue(None, "mtf.scratch.layer.alpha." + _scratchLoadedFor + "." + slot + "." + L, 100)
EndFunction
Function _setScratchLayerAlpha(int slot, int L, int v)
    StorageUtil.SetIntValue(None, "mtf.scratch.layer.alpha." + _scratchLoadedFor + "." + slot + "." + L, v)
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
    ; v6: per-slot scratch (cond/layer/pulse/persist) lives in per-preset
    ; namespaced StorageUtil scalar keys written during cold load; they persist
    ; across preset swaps, so a warm hit has nothing per-slot to restore. Only
    ; the preset-scoped transition / fade-on-death scalars are read back below.
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
    ; v6: per-slot scratch already persisted to per-preset namespaced scalar
    ; keys during the cold-load loop; only the preset-scoped scalars + version
    ; stamp are written here.
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
    ; v6: also require the scratch to be cached under the CURRENT version. On a
    ; mod-version upgrade _scratchLoadedFor survives in the save but the new
    ; per-slot scalar keys don't exist yet; gating on _isScratchCached forces a
    ; one-time cold rebuild instead of fast-returning onto empty scratch.
    if name == _scratchLoadedFor && _isScratchCached(name)
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
    if JsonUtil.GetPathIntValue(f, ".hidden", 0) == 1
        return false ; deleted tombstone — not loadable (fixtures, hidden==2, still load)
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
    int maxC = MAX_CONDITIONS()
    int mcmCap = MAX_CONDITIONS_MCM()
    ; v6: unified cold-load loop over EVERY slot 0..maxC. All per-slot scratch
    ; state — cond pre-scan mirror, layer visual, pulse, persist — writes through
    ; per-preset namespaced StorageUtil accessors (_setScratch*). The fixed
    ; length-8 _s* arrays are gone, so there is no MCM-cap / backend-cap split:
    ; every slot carries its own visual, pulse and persist up to MAX_CONDITIONS().
    ; Effect rows use the namespaced FX scratch keyspace (already slot-indexed,
    ; any slot), written through the ForPreset variants so a VM yield mid-write
    ; can't rebind the namespace (the v0.2.12 race that motivated them).
    int s = 0
    while s <= maxC
        string sp = ".slot[" + s + "]"
        ; v0.3.1: condition 0 lives at .cond.items[0]; this scratch mirror only
        ; feeds the evaluateTierForActor pre-scan gate. The real multi-condition
        ; AND/OR eval reads the full .cond.items[] array via _slotCondsMetJson.
        string slotCondKey = JsonUtil.GetPathStringValue(f, sp + ".cond.items[0].pluginid", "")
        _setScratchCondPluginId(s, slotCondKey)
        if _condParamIsMenu(slotCondKey)
            _setScratchCondParamStr(s, JsonUtil.GetPathStringValue(f, sp + ".cond.items[0].param", ""))
            _setScratchCondParam(s, 0)
        else
            _setScratchCondParam(s, JsonUtil.GetPathIntValue(f, sp + ".cond.items[0].param", 0))
            _setScratchCondParamStr(s, "")
        endif
        if _condParam2IsMenu(slotCondKey)
            _setScratchCondParam2Str(s, JsonUtil.GetPathStringValue(f, sp + ".cond.items[0].param2", ""))
        else
            _setScratchCondParam2Str(s, "")
        endif
        _setScratchCondPackId(s,  JsonUtil.GetPathStringValue(f, sp + ".cond.packid",  ""))
        _setScratchCondEntryId(s, JsonUtil.GetPathStringValue(f, sp + ".cond.entryid", ""))
        ; v0.2.9 per-slot display name (MCM consumer only; uniform across slots).
        _setScratchCondName(s,    JsonUtil.GetPathStringValue(f, sp + ".name", ""))
        ; v0.1.24 cooldown rework — persist.min / persist.allowOverride / cool.min.
        ; Defaults: persistMin=0, allowOverride=1, cool=0.
        _setScratchPersistMin(s,    JsonUtil.GetPathIntValue(f, sp + ".persist.min", 0))
        _setScratchAllowOverride(s, JsonUtil.GetPathIntValue(f, sp + ".persist.allowOverride", 1))
        _setScratchCoolMin(s,       JsonUtil.GetPathIntValue(f, sp + ".cool.min", 0))
        _setScratchPulseRate(s,  JsonUtil.GetPathFloatValue(f,  sp + ".pulse.rate",   0.0))
        _setScratchPulseDepth(s, JsonUtil.GetPathIntValue(f,    sp + ".pulse.depth",  0))
        _setScratchWaveform(s,   JsonUtil.GetPathStringValue(f, sp + ".pulse.waveform", ""))
        _setScratchPulsePause(s, JsonUtil.GetPathFloatValue(f,  sp + ".pulse.pause",  0.0))
        int L = 0
        while L < maxL
            string lp = sp + ".layer[" + L + "]"
            _setScratchLayerTint(s, L,         _readColor(f, lp + ".tint",         16777215))
            _setScratchLayerEmissive(s, L,     _readColor(f, lp + ".emissive",     16777215))
            _setScratchLayerEmissiveMult(s, L, JsonUtil.GetPathFloatValue(f, lp + ".emissivemult", 0.0))
            _setScratchLayerAlpha(s, L,        JsonUtil.GetPathIntValue(f,   lp + ".alpha",        100))
            L += 1
        endwhile
        ; v0.2.7 perf fast-path: a slot past the MCM cap with an empty pluginId
        ; has no condition to evaluate, so its effect bindings are dead — skip
        ; the inner effect loop. MCM-cap slots (0..mcmCap) iterate unconditionally
        ; so stale bindings from a previously-loaded preset get cleared.
        bool runEffectLoop = (s <= mcmCap) || (slotCondKey != "")
        int e = 0
        while runEffectLoop && e < maxE
            string ep = sp + ".effect[" + e + "]"
            string effKey = JsonUtil.GetPathStringValue(f, ep + ".key", "")
            _writeFxKeyForPreset(s, e, true, name, effKey)
            ; v0.2.1: uniform paramN load. Walk 1..5, fall back to the bound
            ; effect's declared default when the preset omits a paramN key.
            ; v0.2.9/v0.3.x: menu + text params read as string, sliders as int.
            MTF_Plugin pLoadX = None
            int itemIdxX = -1
            if effKey != ""
                pLoadX = ResolvePluginByKey(effKey)
                if pLoadX != None
                    itemIdxX = _effectIdxFor(pLoadX, _keyItemId(effKey))
                endif
            endif
            int sn = 1
            while sn <= 5
                bool isStrSn = (itemIdxX >= 0 && (pLoadX.GetEffectParamMenuOptionCount(itemIdxX, sn) > 0 || pLoadX.GetEffectParamIsText(itemIdxX, sn)))
                if isStrSn
                    string snStr = JsonUtil.GetPathStringValue(f, ep + ".param" + sn, "")
                    if snStr == "" && itemIdxX >= 0
                        snStr = pLoadX.GetEffectParamDefaultId(itemIdxX, sn)
                    endif
                    _writeFxParamNStrForPreset(s, e, sn, true, name, snStr)
                    _writeFxParamNForPreset(s, e, sn, true, name, 0)
                else
                    int sentinel = -999999
                    int v = JsonUtil.GetPathIntValue(f, ep + ".param" + sn, sentinel)
                    if v == sentinel
                        if itemIdxX >= 0
                            v = pLoadX.GetEffectParamDefault(itemIdxX, sn)
                        else
                            v = 0
                        endif
                    endif
                    _writeFxParamNForPreset(s, e, sn, true, name, v)
                    _writeFxParamNStrForPreset(s, e, sn, true, name, "")
                endif
                sn += 1
            endwhile
            e += 1
        endwhile
        s += 1
    endwhile

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
        if !_sArraysReady
            return ""
        endif
        if slot < 0
            return ""
        endif
        ; v6: every slot reads from per-preset StorageUtil keys.
        return _getScratchCondPluginId(slot)
    endif
    ; Player path: StorageUtil-backed, all slots up to MAX_CONDITIONS().
    return GetCondPluginId(slot)
EndFunction

int Function _g_condParam(int slot, bool useScratch)
    if useScratch
        if !_sArraysReady
            return 0
        endif
        if slot < 0
            return 0
        endif
        return _getScratchCondParam(slot)
    endif
    return GetCondParam(slot)
EndFunction

; v0.1.24: legacy _g_cooldownMode / _g_cooldownMin replaced by semantic
; accessors _g_allowOverride / _g_persistMin. Physical storage unchanged
; (still backed by cooldownMode / cooldownMin or _sCooldownMode / _sCooldownMin).
; New _g_coolMin reads StorageUtil per the cool-phase rework.

int Function _g_allowOverride(int slot, bool useScratch)
    if useScratch
        if !_sArraysReady
            return 1   ; safe default: allow override when scratch not loaded
        endif
        if slot < 0
            return 1
        endif
        return _getScratchAllowOverride(slot)
    endif
    return GetCondAllowOverride(slot)
EndFunction

int Function _g_persistMin(int slot, bool useScratch)
    if useScratch
        if !_sArraysReady
            return 0
        endif
        if slot < 0
            return 0
        endif
        return _getScratchPersistMin(slot)
    endif
    return GetCondPersistMin(slot)
EndFunction

int Function _g_coolMin(int slot, bool useScratch)
    if useScratch
        return _getScratchCoolMin(slot)
    endif
    return _getCoolMin(slot)
EndFunction

float Function _g_pulseRate(int slot, bool useScratch)
    if useScratch
        if !_sArraysReady
            return 0.0
        endif
        if slot < 0
            return 0.0
        endif
        return _getScratchPulseRate(slot)
    endif
    return GetCondPulseRate(slot)
EndFunction

int Function _g_pulseDepth(int slot, bool useScratch)
    if useScratch
        if !_sArraysReady
            return 0
        endif
        if slot < 0
            return 0
        endif
        return _getScratchPulseDepth(slot)
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
    if !_sArraysReady
        return ""
    endif
    if slot < 0
        return _getScratchCondPackId(0)
    endif
    ; v6: empty packId on a non-Default slot still inherits slot 0's pack.
    string pid = _getScratchCondPackId(slot)
    if pid == "" && slot > 0
        return _getScratchCondPackId(0)
    endif
    return pid
EndFunction

string Function _g_resolveEntryId(int slot, bool useScratch)
    if !useScratch
        return ResolveSlotEntryId(slot)
    endif
    if !_sArraysReady
        return ""
    endif
    if slot < 0
        return _getScratchCondEntryId(0)
    endif
    if slot > 0 && _getScratchCondPackId(slot) == ""
        return _getScratchCondEntryId(0)
    endif
    return _getScratchCondEntryId(slot)
EndFunction

; v0.2.8: _safeLayerIdx retired — the StorageUtil-backed accessors return
; sensible defaults for any (slot, L) pair, no wrap-around needed. Player-
; side _g_layer* functions decompose flat lidx → (slot, L) and call the
; unified accessors. Scratch path still reads the NPC _s* arrays directly
; (slot 0..7 only; backend NPC slots have no per-slot visuals).
int Function _g_layerTint(int lidx, bool useScratch)
    if useScratch
        if !_sArraysReady || lidx < 0
            return 16777215
        endif
        int maxLs = MAX_LAYERS_PER_SLOT()
        return _getScratchLayerTint(lidx / maxLs, lidx % maxLs)
    endif
    int maxL = MAX_LAYERS_PER_SLOT()
    return GetCondLayerTint(lidx / maxL, lidx % maxL)
EndFunction
int Function _g_layerEmissive(int lidx, bool useScratch)
    if useScratch
        if !_sArraysReady || lidx < 0
            return 16777215
        endif
        int maxLs = MAX_LAYERS_PER_SLOT()
        return _getScratchLayerEmissive(lidx / maxLs, lidx % maxLs)
    endif
    int maxL = MAX_LAYERS_PER_SLOT()
    return GetCondLayerEmissive(lidx / maxL, lidx % maxL)
EndFunction
float Function _g_layerEmissiveMult(int lidx, bool useScratch)
    if useScratch
        if !_sArraysReady || lidx < 0
            return 0.0
        endif
        int maxLs = MAX_LAYERS_PER_SLOT()
        return _getScratchLayerEmissiveMult(lidx / maxLs, lidx % maxLs)
    endif
    int maxL = MAX_LAYERS_PER_SLOT()
    return GetCondLayerEmissiveMult(lidx / maxL, lidx % maxL)
EndFunction
int Function _g_layerAlpha(int lidx, bool useScratch)
    if useScratch
        if !_sArraysReady || lidx < 0
            return 100
        endif
        int maxLs = MAX_LAYERS_PER_SLOT()
        return _getScratchLayerAlpha(lidx / maxLs, lidx % maxLs)
    endif
    int maxL = MAX_LAYERS_PER_SLOT()
    return GetCondLayerAlpha(lidx / maxL, lidx % maxL)
EndFunction

; _g_effectKey/Param/Param2 removed in v0.1.5 — effect storage moved to
; StorageUtil. Call sites now use _readFxKey/Param/Param2(slot, idx, useScratch)
; directly with the natural (slot, idx) shape instead of a flat fxIdx.

; ── Generalized eval + effect dispatch ──────────────────────────────────────
int Function _quickEvalCondsFromJson(Actor target, string presetName)
{Fast scratch-free tier evaluator. Reads cond.pluginid / cond.param /
 persist.* / cool.* directly from the preset JSON, dispatches
 checkCondition, and returns the winning slot — same semantics as
 evaluateTierForActor(target, presetName, true) but without the
 ~480ms _loadPresetToScratch round-trip. Used by the slow-tick pre-eval
 pass to capture every loaded preset's target tier atomically before any
 apply work runs, so multi-preset cross-fades don't staircase because
 slot 2's eval saw an AV that already shifted during slot 1's apply.

 Always uses the scratch-path evalParam2 = 0 convention (stacked presets
 don't carry param2). Persist + cool timers are read via the per-(actor,
 preset, slot) StorageUtil helpers (_getActorPresetPersistUntil /
 _getActorPresetCoolUntil). Returns 0 on any failure path (no preset
 file, killed actor, no matching slot).

 v0.1.24 state machine: pre-scan for !allowOverride locked slot, then
 normal eval per slot — see evaluateTier for the canonical comment.}
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

    ; v0.2.7: scan up to MAX_CONDITIONS() instead of the old MCM-cap hardcode.
    ; Backend slots (s > MAX_CONDITIONS_MCM) live in the JSON beyond the
    ; MCM-rendered range and must be evaluated here — otherwise the slow-tick
    ; pre-eval pass returns 0 for a backend-slot-only preset and immediately
    ; reverts the apply path's tier transition within the same tick. Symptom:
    ; "applied" → "Tier N - <effect>" (apply dispatch) → "condition cleared"
    ; (slow-tick reversion), all within ~1 second.
    int maxC = MAX_CONDITIONS_CACHED()

    ; Pre-scan: lowest-i slot in persist with !allowOverride wins outright.
    int i = 1
    while i <= maxC
        string sp1 = ".slot[" + i + "]"
        string k1 = JsonUtil.GetPathStringValue(f, sp1 + ".cond.items[0].pluginid", "")
        if k1 != ""
            int allowOver = JsonUtil.GetPathIntValue(f, sp1 + ".persist.allowOverride", 1)
            float persistEnd = _getActorPresetPersistUntil(target, presetName, i)
            if allowOver == 0 && now < persistEnd
                return i
            endif
        endif
        i += 1
    endwhile

    ; Normal eval with persist passthrough.
    i = 1
    while i <= maxC
        string sp = ".slot[" + i + "]"
        string key = JsonUtil.GetPathStringValue(f, sp + ".cond.items[0].pluginid", "")
        if key != ""
            float coolEnd = _getActorPresetCoolUntil(target, presetName, i)
            if now >= coolEnd
                float persistEnd2 = _getActorPresetPersistUntil(target, presetName, i)
                if now < persistEnd2
                    return i  ; persistence wins (allowOverride==1 since pre-scan didn't catch)
                endif
                ; v0.3.0: evaluate all conditions in the slot (AND/OR) from JSON.
                if _slotCondsMetJson(target, f, i)
                    return i
                endif
            endif
        endif
        i += 1
    endwhile
    return 0
EndFunction

int Function evaluateTierForActor(Actor target, string presetName, bool useScratch)
{Evaluate the winning condition slot for `target`. When useScratch is true,
 the per-(actor, preset, slot) persist + cool timers are consulted via
 presetName; when false, the player's own cooldownUntilGT array (= persist)
 and StorageUtil cool keys are consulted (presetName is ignored).

 v0.1.24 state machine: pre-scan for !allowOverride locked slot, then
 normal eval per slot — see evaluateTier for the canonical comment.}
    if target == None
        return 0
    endif
    if _getActorKilled(target)
        return 0
    endif
    float now = Utility.GetCurrentGameTime()

    ; v0.2.7: scratch path now scans backend slots too (was MCM-capped).
    ; Scratch _s* cond arrays widened to 33 in _ensureScratchArrays so
    ; the apply-via-spell flow can dispatch slot 9+ effects. Clamp to
    ; array bounds for safety if user bumps iMaxConditions past 32.
    int maxC = MAX_CONDITIONS_CACHED()
    if useScratch && maxC > 32
        maxC = 32
    endif

    ; Pre-scan: lowest-i slot in persist with !allowOverride wins outright.
    int i = 1
    while i <= maxC
        if _g_condPluginId(i, useScratch) != "" && _g_allowOverride(i, useScratch) == 0
            float persistEndA
            if useScratch
                persistEndA = _getActorPresetPersistUntil(target, presetName, i)
            else
                persistEndA = _getPersistUntilGT(i)
            endif
            if now < persistEndA
                return i
            endif
        endif
        i += 1
    endwhile

    ; Normal eval with persist passthrough.
    i = 1
    while i <= maxC
        string key = _g_condPluginId(i, useScratch)
        if key != ""
            float coolEnd
            float persistEnd
            if useScratch
                coolEnd = _getActorPresetCoolUntil(target, presetName, i)
                persistEnd = _getActorPresetPersistUntil(target, presetName, i)
            else
                coolEnd = _getCoolUntilGT(i)
                persistEnd = _getPersistUntilGT(i)
            endif
            if now >= coolEnd
                if now < persistEnd
                    return i  ; persistence wins (allowOverride==1)
                endif
                ; v0.3.0: evaluate all conditions in the slot (AND/OR). Scratch
                ; (NPC tracked subjects) reads from the preset JSON — its source
                ; of truth, loaded into scratch from the same file; player-live
                ; (non-scratch) reads StorageUtil and threads param2.
                if useScratch
                    if _slotCondsMetJson(target, _presetFile(presetName), i)
                        return i
                    endif
                else
                    if _slotCondsMetLive(target, i)
                        return i
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
 every other case. Empty string falls back to OverlaySlot.

 v0.2.10: dispatch context (slot/eff/useScratch/baseSlot/area) is passed
 as explicit params straight into _dispatchActivate, not stashed in the
 shared StorageUtil dispatch context. See _dispatchActivate / plugin
 entry-point docstrings for the full race rationale.}
    if target == None || slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    int baseSlot = _resolveDispatchBaseSlot(target, presetName)
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
        keys[e]    = _readFxKeyForPreset(slot, e, useScratch, presetName)
        params[e]  = _readFxParamNForPreset(slot, e, 1, useScratch, presetName)
        params2[e] = _readFxParamNForPreset(slot, e, 2, useScratch, presetName)
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
                    _dispatchActivate(p, itemIdx, target, slot, e, useScratch, baseSlot, 0, params[e], params2[e], presetName)
                    _emitEffectActivated(target, key, slot)
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _deactivateSlotEffectsForActor(Actor target, int slot, bool useScratch, string presetName = "")
    if target == None || slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    int baseSlot = _resolveDispatchBaseSlot(target, presetName)
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
        keys[e]    = _readFxKeyForPreset(slot, e, useScratch, presetName)
        params[e]  = _readFxParamNForPreset(slot, e, 1, useScratch, presetName)
        params2[e] = _readFxParamNForPreset(slot, e, 2, useScratch, presetName)
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
                    _dispatchDeactivate(p, itemIdx, target, slot, e, useScratch, baseSlot, 0, params[e], params2[e], presetName)
                    _emitEffectDeactivated(target, key, slot)
                endif
            endif
        endif
        e += 1
    endwhile
EndFunction

Function _tickSlotEffectsForActor(Actor target, int slot, bool useScratch, string presetName = "")
    if target == None || slot < 0 || slot > MAX_CONDITIONS_CACHED()
        return
    endif
    int baseSlot = _resolveDispatchBaseSlot(target, presetName)
    int maxE = MAX_EFFECTS_PER_SLOT()
    ; SNAPSHOT before dispatch — see _deactivateSlotEffectsForActor for
    ; the race-rationale. _scratchLoadedFor gets clobbered by interleaved
    ; _loadPresetToScratch calls during suspending p.onTick dispatches.
    string[] keys    = Utility.CreateStringArray(maxE, "")
    int[]    params  = Utility.CreateIntArray(maxE, 0)
    int[]    params2 = Utility.CreateIntArray(maxE, 0)
    int e = 0
    while e < maxE
        keys[e]    = _readFxKeyForPreset(slot, e, useScratch, presetName)
        params[e]  = _readFxParamNForPreset(slot, e, 1, useScratch, presetName)
        params2[e] = _readFxParamNForPreset(slot, e, 2, useScratch, presetName)
        e += 1
    endwhile
    e = 0
    while e < maxE
        ; v0.2.13 race fix: re-verify the preset is still tracked on this
        ; actor BEFORE each yielding p.onTick. The slow-tick snapshot of
        ; mtf.presets happens once at the top of OnUpdate; by the time we
        ; reach effect e, a concurrent RemoveAppliedPreset on another fiber
        ; could have already dropped the preset from mtf.presets and run
        ; its deactivate loop (which UnsetFloatValue'd `mtf.shift.modify.*`
        ; and ModActorValue'd back to baseline). If we then call p.onTick
        ; here, _recomputeSkillShift reads prev=0 (the just-unset tracker)
        ; → sees prev != amt → ModActorValue's the buff BACK ON. AV stays
        ; stuck at +delta after the apparent revert.
        ;
        ; The membership re-check is a single StorageUtil read (atomic SKSE
        ; native, no yield) — costs nothing per iteration and closes the
        ; in-flight stale-snapshot race that prior `drop from mtf.presets
        ; FIRST` ordering can't address (it stops NEW tick snapshots from
        ; including the preset, but in-flight ticks already past the
        ; snapshot read continue iterating).
        if useScratch && presetName != "" && _findActorPresetIdx(target, presetName) < 0
            return
        endif
        string key = keys[e]
        if key != ""
            MTF_Plugin p = ResolvePluginByKey(key)
            if p != None
                int itemIdx = _effectIdxFor(p, _keyItemId(key))
                if itemIdx >= 0
                    p.onTick(target, params[e], params2[e], p.GetEffectId(itemIdx), slot, e, useScratch, baseSlot, 0, presetName)
                endif
            endif
        endif
        e += 1
    endwhile
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
            ; v0.1.24: on the deactivation edge, clear the slot's persist
            ; timer (any leftover time is discarded) and arm cool if
            ; coolMin > 0. Mirrors the player path in OnUpdate; the persist
            ; clear is necessary to keep the pre-scan from treating a
            ; just-overridden slot as still-locked.
            if prev > 0
                _setActorPresetPersistUntil(target, name, prev, 0.0)
                int coolMins = _g_coolMin(prev, true)
                if coolMins > 0
                    _setActorPresetCoolUntil(target, name, prev, Utility.GetCurrentGameTime() + (coolMins as float) / 1440.0)
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
            ; v0.1.24: arm persist timer on the activation edge (now > 0
            ; with persistMin > 0). Slot will keep winning the per-actor
            ; eval for the persist window regardless of condition.
            if now > 0
                int persistMins = _g_persistMin(now, true)
                if persistMins > 0
                    _setActorPresetPersistUntil(target, name, now, Utility.GetCurrentGameTime() + (persistMins as float) / 1440.0)
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

Function _rosterAddOrUpdate(Actor a, string name, int tier, float startRT, bool snapNow = false)
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
    if a == None || name == "" || tier < 0 || tier > MAX_CONDITIONS_CACHED()
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
    if snapNow
        tDur = 0.0
    endif
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

; ══════════════════════════════════════════════════════════════════════════
; PRESET EVENT API (v0.1.22)
; ══════════════════════════════════════════════════════════════════════════
; Inbound mod-event surface that lets ANY external mod apply or remove
; saved presets without a hard Papyrus dependency on MTF. Companion to the
; outbound MTF_TierChanged / MTF_EffectActivated etc. events above.
;
; The receiver lives on MTF_AliasPresetApi (a ReferenceAlias attached to
; this Quest, filled with PlayerRef). Quest scripts can't RegisterForModEvent
; so the alias dispatches inbound events into Api* functions here.
;
; ── INBOUND EVENTS ──
;
;   MTF_ApplyPreset
;     str  = "<presetName>"            internal name (not the displayname)
;     num  = (ignored / reserved)
;     sender = target Actor (or None → defaults to PlayerRef)
;
;   MTF_RemovePreset
;     str  = "<presetName>"
;     sender = target Actor (or None → PlayerRef)
;     Removes ONLY if the preset is in this actor's mtf.api.applied list
;     (i.e. the API previously applied it). User-applied presets won't be
;     touched.
;
;   MTF_RemoveAllPresets
;     str  = (ignored)
;     sender = target Actor (or None → PlayerRef)
;     Removes every preset the API ever applied to this actor.
;
; ── OUTBOUND CONFIRMATIONS ──
;
;   MTF_ApplyPresetResult
;     str  = "<presetName>|<rc>"       rc passed through from AddAppliedPreset
;     num  = rc as float
;     sender = target Actor
;     rc codes: 1=applied, 0=already-applied (NOT tracked by API), -2=None
;     target, -3=tracked-cap (NPC), -4=empty name, -5=invalid preset,
;     -6=no overlay slots, -7=would render truncated.
;
;   MTF_RemovePresetResult
;     str  = "<presetName>|<status>"
;     num  = 1.0 if removed, 0.0 otherwise
;     sender = target Actor
;     Status strings: "removed", "not-tracked-by-api", "no-target", "no-name".
;
;   MTF_RemoveAllPresetsResult
;     str  = "<count>"
;     num  = count as float
;     sender = target Actor
;
; ── EXAMPLE CALLER ──
;
;   int h = ModEvent.Create("MTF_ApplyPreset")
;   ModEvent.PushString(h, "MyPreset")
;   ModEvent.PushForm(h, Game.GetPlayer() as Form)
;   ModEvent.Send(h)
;
; ── TRACKING ──
;
; Per-actor StringList mtf.api.applied stores the names of presets the API
; applied. The list is the sole source of truth for whether the API can
; remove a preset; the host's mtf.presets list (user + API combined) is
; never used as the API's "is this mine" check.

Function ApiApplyPreset(Actor target, string presetName)
{Inbound MTF_ApplyPreset dispatch. Calls AddAppliedPreset, emits result
 event with the rc, tracks the preset under mtf.api.applied on success.}
    if target == None
        target = PlayerRef
    endif
    if target == None
        _apiEmitApplyResult(None, presetName, -2)
        return
    endif
    int rc = AddAppliedPreset(target, presetName)
    if rc == 1
        ; Only track presets the API actually applied. rc=0 means the user
        ; (or another caller) already had it on; we must NOT track it
        ; because we don't own that lifecycle.
        _apiTrackingAdd(target, presetName)
    endif
    _apiEmitApplyResult(target, presetName, rc)
EndFunction

Function StopAllMtfShadersOn(Actor target)
{Recovery: brute-force Stop every vanilla EffectShader MTF can Play on `target`
 and reset alpha. Clears an actor left invisible/shaded by a leaked Duration-0
 shader.play whose paired Stop() was dropped (VM saturation, or a .pex rebuild
 mid-save). Stop() on a non-playing shader and SetAlpha(1) on a visible actor
 are both no-ops, so calling this on the wrong target is harmless. Reached from
 the MCM "Clear stuck FX" button and the MTF_StopAllShaders mod event.}
    if target == None
        return
    endif
    ; Keep in sync with MTF_Plugin_Base._shaderFormIdById (22 vanilla shaders).
    _stopMtfFx(target, 0x0002acd8) ; fire_cloak
    _stopMtfFx(target, 0x0001b212) ; fire_burst
    _stopMtfFx(target, 0x0001f03a) ; frost
    _stopMtfFx(target, 0x0010a043) ; frost_chillrend
    _stopMtfFx(target, 0x00057c67) ; shock
    _stopMtfFx(target, 0x0003bf79) ; shock_storm
    _stopMtfFx(target, 0x00094161) ; stoneflesh
    _stopMtfFx(target, 0x00094162) ; ebonyflesh
    _stopMtfFx(target, 0x000e9ac8) ; dragonhide
    _stopMtfFx(target, 0x000506d7) ; soul_trap
    _stopMtfFx(target, 0x0003b6cb) ; ghost_ethereal
    _stopMtfFx(target, 0x000fe68c) ; ghost_red
    _stopMtfFx(target, 0x0002df92) ; invisibility
    _stopMtfFx(target, 0x000bcf25) ; muffle
    _stopMtfFx(target, 0x0001c858) ; ward_shield
    _stopMtfFx(target, 0x00075272) ; reanimate
    _stopMtfFx(target, 0x000e7557) ; turn_undead_flames
    _stopMtfFx(target, 0x00012fd9) ; heal
    _stopMtfFx(target, 0x000abeff) ; absorb_health
    _stopMtfFx(target, 0x000fd804) ; vampire_change
    _stopMtfFx(target, 0x000ebec5) ; werewolf_transform
    _stopMtfFx(target, 0x00000146) ; detect_life
    target.SetAlpha(1.0)
EndFunction

Function _stopMtfFx(Actor t, int fid)
    EffectShader es = Game.GetFormFromFile(fid, "Skyrim.esm") as EffectShader
    if es
        es.Stop(t)
    endif
EndFunction

Function ApiRemovePreset(Actor target, string presetName)
{Inbound MTF_RemovePreset dispatch. Refuses to remove if the API didn't
 apply this preset to this actor; otherwise calls RemoveAppliedPreset and
 cleans up tracking.}
    if target == None
        target = PlayerRef
    endif
    if target == None
        _apiEmitRemoveResult(None, presetName, "no-target", false)
        return
    endif
    if presetName == ""
        _apiEmitRemoveResult(target, presetName, "no-name", false)
        return
    endif
    if !_apiTrackingHas(target, presetName)
        _apiEmitRemoveResult(target, presetName, "not-tracked-by-api", false)
        return
    endif
    ; Tracking says it's ours. Clean tracking first so a concurrent
    ; ApiRemovePreset can't double-remove if RemoveAppliedPreset suspends.
    _apiTrackingRemove(target, presetName)
    RemoveAppliedPreset(target, presetName)
    _apiEmitRemoveResult(target, presetName, "removed", true)
EndFunction

Function ApiRemoveAllPresets(Actor target)
{Inbound MTF_RemoveAllPresets dispatch. Iterates mtf.api.applied for this
 actor and removes each preset. Emits a single result with the count.}
    if target == None
        target = PlayerRef
    endif
    if target == None
        _apiEmitRemoveAllResult(None, 0)
        return
    endif
    int removed = 0
    ; Snapshot the list first — RemoveAppliedPreset suspends, and the
    ; tracking removal during the loop would shift indices.
    int n = _apiTrackingCount(target)
    string[] snapshot = Utility.CreateStringArray(n, "")
    int i = 0
    while i < n
        snapshot[i] = _apiTrackingAt(target, i)
        i += 1
    endwhile
    i = 0
    while i < n
        string nm = snapshot[i]
        if nm != ""
            ; Remove tracking FIRST so a re-entry can't double-pop.
            _apiTrackingRemove(target, nm)
            RemoveAppliedPreset(target, nm)
            removed += 1
        endif
        i += 1
    endwhile
    _apiEmitRemoveAllResult(target, removed)
EndFunction

; ── Public API tracking accessors ──────────────────────────────────────────
; Read-only introspection of which presets the event API has applied to an
; actor. Useful for callers that want to UI-render "currently active via
; this integration" lists, or for test harnesses verifying API state.

int Function ApiTrackingCount(Actor target)
{Number of presets the event API currently has applied to `target`.}
    return _apiTrackingCount(target)
EndFunction

string Function ApiTrackingAt(Actor target, int idx)
{Internal preset name at index `idx` of the API tracking list for `target`.}
    return _apiTrackingAt(target, idx)
EndFunction

bool Function ApiHasTracked(Actor target, string name)
{Whether the event API applied preset `name` to `target` (and hasn't
 since removed it). Returns false for user-applied presets even when
 they're currently on the actor.}
    return _apiTrackingHas(target, name)
EndFunction

; ── API tracking storage (per-actor StringList mtf.api.applied) ─────────────

bool Function _apiTrackingHas(Actor target, string name)
    if target == None || name == ""
        return false
    endif
    return StorageUtil.StringListHas(target, "mtf.api.applied", name)
EndFunction

Function _apiTrackingAdd(Actor target, string name)
    if target == None || name == ""
        return
    endif
    ; StringListAdd with allowDuplicate=false dedupes for us.
    StorageUtil.StringListAdd(target, "mtf.api.applied", name, false)
EndFunction

Function _apiTrackingRemove(Actor target, string name)
    if target == None || name == ""
        return
    endif
    StorageUtil.StringListRemove(target, "mtf.api.applied", name, true)
EndFunction

int Function _apiTrackingCount(Actor target)
    if target == None
        return 0
    endif
    return StorageUtil.StringListCount(target, "mtf.api.applied")
EndFunction

string Function _apiTrackingAt(Actor target, int idx)
    if target == None
        return ""
    endif
    return StorageUtil.StringListGet(target, "mtf.api.applied", idx)
EndFunction

; ── Outbound result emitters ────────────────────────────────────────────────

Function _apiEmitApplyResult(Actor target, string presetName, int rc)
    int h = ModEvent.Create("MTF_ApplyPresetResult")
    if h == 0
        return
    endif
    ModEvent.PushString(h, presetName + "|" + rc)
    ModEvent.PushFloat(h, rc as float)
    if target != None
        ModEvent.PushForm(h, target as Form)
    else
        ModEvent.PushForm(h, None)
    endif
    ModEvent.Send(h)
EndFunction

Function _apiEmitRemoveResult(Actor target, string presetName, string status, bool removed)
    int h = ModEvent.Create("MTF_RemovePresetResult")
    if h == 0
        return
    endif
    ModEvent.PushString(h, presetName + "|" + status)
    float num = 0.0
    if removed
        num = 1.0
    endif
    ModEvent.PushFloat(h, num)
    if target != None
        ModEvent.PushForm(h, target as Form)
    else
        ModEvent.PushForm(h, None)
    endif
    ModEvent.Send(h)
EndFunction

Function _apiEmitRemoveAllResult(Actor target, int count)
    int h = ModEvent.Create("MTF_RemoveAllPresetsResult")
    if h == 0
        return
    endif
    ModEvent.PushString(h, "" + count)
    ModEvent.PushFloat(h, count as float)
    if target != None
        ModEvent.PushForm(h, target as Form)
    else
        ModEvent.PushForm(h, None)
    endif
    ModEvent.Send(h)
EndFunction
