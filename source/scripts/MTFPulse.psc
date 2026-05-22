Scriptname MTFPulse Native Hidden

; SKSE C++ plugin native bindings.
; Implementation lives in cpp-plugin/src/papyrus.cpp.
; The plugin (MTFPulse.dll) registers these on kDataLoaded; if the DLL is
; absent or failed to load, calls below raise a Papyrus runtime warning
; ("function MTFPulse.X not found") and return defaults (0 / void).

; Set or refresh the pulse parameters for one actor.
;   rate        — cycles per second (>0 to engage, <=0 to clear).
;   depthPct    — 0..100 trough depth (0 = no pulse, 100 = full off→on).
;   pause       — seconds the wave holds at the trough between cycles.
;   layerCount  — number of overlay layers to drive (max 4).
;   startTime   — real-time epoch in seconds, anchoring the wave phase.
;   emMults     — per-layer ceiling emissive multipliers (length == layerCount).
;   baseOverlaySlot — NiOverride overlay base index (typically 0 or 2).
;   isFemale    — sex flag for NiOverride node lookups.
;   waveLUT     — 64-entry [0,1]→[0,1] waveform sampled across one cycle.
;                 Empty or wrong-length array → C++ falls back to cosine.
;   area        — v0.1.17 Phase 3 (multi-area): which NiOverride node pool
;                 to paint into. 0=Body, 1=Face, 2=Hand, 3=Feet. Identity is
;                 (actor, area, baseOverlaySlot) — same actor can hold a
;                 Body[ovl0] and a Face[ovl0] entry without collision.
Function SetActorPulse(Actor aktor, Float rate, Int depthPct, Float pause, \
                       Int layerCount, Float startTime, Float[] emMults, \
                       Int baseOverlaySlot, Bool isFemale, Float[] waveLUT, \
                       Int area) Global Native

; Set pulse + cross-fade transition in one call. Identical to SetActorPulse
; except the caller additionally passes:
;   tintRGBs            — per-layer target tint colors (packed 0x00RRGGBB)
;   alphasPct           — per-layer target alpha as 0..100 percent
;   transitionDuration  — seconds to fade emissive ceiling, alpha, and tint
;                         from the prior entry's last-rendered state to the
;                         new target values. <=0 behaves identically to
;                         SetActorPulse (instant snap, no cross-fade).
; The C++ side snapshots the prior entry's last interpolated values at
; Set() time, so chained transitions don't snap back to the previous tier.
; For fresh entries (first apply on this actor/base_slot), the from-state
; defaults to the target → no visible fade on initial apply; per-tier
; transitions on already-applied presets are where the smoothing happens.
Function SetActorPulseWithTransition(Actor aktor, Float rate, Int depthPct, Float pause, \
                                     Int layerCount, Float startTime, Float[] emMults, \
                                     Int baseOverlaySlot, Bool isFemale, Float[] waveLUT, \
                                     Int[] tintRGBs, Int[] alphasPct, Int[] emissiveRGBs, \
                                     Float transitionDuration, Int area) Global Native

; Same as SetActorPulseWithTransition, plus the caller pins the cross-fade
; anchor by passing `transitionStartRT` (Utility.GetCurrentRealTime() — the
; same clock the C++ side reads via NowSec()). When >0 the C++ roster stores
; this as transition_start instead of capturing its own NowSec() per Set
; call; when <=0 it falls back to the legacy NowSec path (identical to
; SetActorPulseWithTransition). Callers batching several Set()s in one
; Papyrus tick should snapshot ONE anchor (typically a few tens of ms in
; the future so all bursts land before the anchor) and pass it to every
; Set so all entries lerp in lockstep — without this the per-call NowSec()
; capture made the first-frame alpha writes visibly staircase the "tattoos
; pop on" moment across stacked presets. Forward anchors are safe; back-
; dated anchors past (anchor + transitionDuration) snap and skip the
; alpha/tint write — callers must keep the anchor at now-or-near-future.
Function SetActorPulseWithTransitionAt(Actor aktor, Float rate, Int depthPct, Float pause, \
                                       Int layerCount, Float startTime, Float[] emMults, \
                                       Int baseOverlaySlot, Bool isFemale, Float[] waveLUT, \
                                       Int[] tintRGBs, Int[] alphasPct, Int[] emissiveRGBs, \
                                       Float transitionDuration, Float transitionStartRT, \
                                       Int area) Global Native

; The C++ clock Tick() reads and Roster::Set() stores into transition_start
; (steady_clock since DLL init). Sample this — NOT Utility.GetCurrentRealTime
; (which counts from Skyrim launch, a different epoch) — when pinning a
; shared transition anchor across a batch of SetActorPulseWithTransitionAt
; calls. Mixing the two clocks leaves Tick's `tt = now - transition_start`
; computation hugely negative and the cross-fade stuck at eased=0 forever
; (tattoos paint at from-state, never reach target).
Float Function GetNowSec() Global Native

; Transition batching (v0.1.7). Wrap any Papyrus loop that pushes several
; roster updates in BeginTransitionBatch / EndTransitionBatch and the C++
; side will queue every intervening SetActorPulse* call, then install all
; queued entries atomically at EndTransitionBatch with one shared
; transition_start — so stacked-preset cross-fades lerp in lockstep
; regardless of how long the Papyrus burst between them takes. Without
; batching, each Set() captured its own NowSec and later entries either
; jumped past earlier ones mid-lerp or hit the snap path (when the burst
; exceeded transition_duration). Nested Begin is logged and ignored;
; End without Begin is a safe no-op. Set() calls OUTSIDE a batch keep
; the legacy "install immediately at NowSec" behavior.
Function BeginTransitionBatch() Global Native
Function EndTransitionBatch() Global Native

; Remove EVERY entry the actor owns (all base_slots).
; Use on death / unload / total teardown.
Function ClearActor(Actor aktor) Global Native

; Remove ONE entry by (actor, baseOverlaySlot, area). Use when a single preset
; on an actor with several stacked presets becomes inactive.
; v0.1.17 Phase 3 (multi-area): area param added (0=Body, 1=Face, 2=Hand, 3=Feet).
Function ClearActorAt(Actor aktor, Int baseOverlaySlot, Int area) Global Native

; Empty the entire roster (e.g. on full plugin reset).
Function ClearAll() Global Native

; Master enable. When false, Tick() short-circuits without touching any
; NiOverride state — useful for MCM "pause pulse" toggles.
Function SetEnabled(Bool on) Global Native

; Current roster population (for diagnostics).
Int Function Size() Global Native

; ── Flash on event (v0.1.3, string-tag dispatch) ────────────────────────────
; Transient additive emissive lane on top of the steady pulse. Requires a
; steady roster entry to already exist for (aktor, baseOverlaySlot) — call
; SetActorPulse or SetActorPulseWithTransition first (rate=0/depth=0 is OK).
;
; Push flash params on tier-becomes-active:
;   peakEmissivePct — additive amount at intensity=1 expressed as percent of
;                     1.0 emissive. 0 disables the lane, 100 = "+1.0", 500 =
;                     "+5.0" (very bright spike). Range 0..1000.
;   rampMs / decayMs — envelope shape; ramp covers 0→1 from a cold start,
;                     decay covers 1→0 after retrigger window expires.
;   retriggerMs     — while the gap since the last accepted event stays
;                     inside this window, intensity targets 1.0 (held bright
;                     by sustained streams like Flames). Past the window,
;                     target snaps to 0 and decay runs.
;   tagsCsv         — comma-separated list of event tags this entry reacts
;                     to. "*" is the wildcard (any incoming tag). Tags are
;                     case-insensitive ASCII; "" disables the lane. Built-in
;                     combat tags from MTF_HitListener: "blunt", "bladed",
;                     "ranged", "fire", "frost", "shock". External mods can
;                     introduce their own dotted tags like "sla.aroused.over80".
;                     Examples: "blunt,bladed" (melee), "fire,frost,shock"
;                     (magic), "*" (any event).
Function SetActorFlash(Actor aktor, Int baseOverlaySlot, \
                       Int peakEmissivePct, Int rampMs, Int decayMs, \
                       Int retriggerMs, String tagsCsv, Int area) Global Native

; Empty the tag set on (aktor, baseOverlaySlot, area). Any in-flight intensity
; eases out naturally on the next frames. Use on tier-deactivate.
Function ClearActorFlash(Actor aktor, Int baseOverlaySlot, Int area) Global Native

; Stamp an event on (aktor, baseOverlaySlot). `tag` is a short ASCII
; identifier (case-insensitive); "blunt", "fire", "sla.aroused.over80", etc.
; Cheap — no SKEE writes, just records the tag + timestamp so the next Tick
; picks it up. No-op if no roster entry, no flash configured, or the tag
; doesn't match the entry's tag set (or the "*" wildcard).
;
; This is the public extension hook for external mods: any third-party
; Papyrus code can call MTFPulse.TriggerActorFlash(player, slot, "mytag")
; from its own event handlers (arousal changes, location enter, custom
; OnHit handling, etc.). MTF tiers binding flash.onhit with tagsCsv
; including "mytag" — or with the "*" wildcard — will flash on the event.
Function TriggerActorFlash(Actor aktor, Int baseOverlaySlot, String tag, Int area) Global Native

; ── Fade on death (v0.1.4, one-shot animation) ──────────────────────────────
; Arms a one-shot fade animation that fires when the actor dies. Like
; SetActorFlash, requires a pre-existing roster entry — call SetActorPulse
; or SetActorPulseWithTransition first (rate=0 / depth=0 is fine for
; fade-only presets).
;
;   mode        — 0 = overlay   (em→0, alpha→0; corpse has invisible tattoo)
;                 1 = emissive  (em→1.0 baseline; texture stays visible)
;                 2 = inverted  (em dips to 0 then back; flicker effect)
;                 Out-of-range values clamp to overlay.
;   durationMs  — total animation length in milliseconds (>=1).
;                 For mode=2 the dip + recover each take durationMs/2.
;
; The actual fade fires automatically when the C++ TESDeathEvent sink
; sees this actor die — no per-frame tick needed on the Papyrus side.
; After the animation completes the roster entry is dropped (one-shot;
; we stop spending CPU on the corpse). The last-written em/alpha values
; persist on the NiOverride node, so the visible end state holds.
Function SetActorFade(Actor aktor, Int baseOverlaySlot, \
                      Int mode, Int durationMs, Int area) Global Native

; Disarm fade on (aktor, baseOverlaySlot, area). Cancels an in-flight fade
; in place if one was running — last interpolated em/alpha values stick on
; the node. Use on tier-deactivate.
Function ClearActorFade(Actor aktor, Int baseOverlaySlot, Int area) Global Native

; Manual one-shot trigger of an armed fade. Normally the C++ death sink
; fires this automatically; this native exists for unit tests, custom
; triggers (e.g. a non-death "dramatic effect" event), or external mods
; that want fade-on-event semantics without subclassing the death sink.
;
; No-op if no entry, not armed, or fade already in flight.
Function TriggerActorFade(Actor aktor, Int baseOverlaySlot, Int area) Global Native

; ── Runtime config (v0.1.5) ─────────────────────────────────────────────────
; Read an int from Data/SKSE/Plugins/MagicTattoosFramework.ini. The DLL
; resolves the path next to itself, then reads via Win32
; GetPrivateProfileInt (Win32 maintains its own in-process file cache, so
; repeated calls don't hit disk). INI edits take effect on Skyrim restart.
;
;   key           — bare name (resolved against the [General] section) or
;                   "section.name" form for non-default sections. Bethesda
;                   convention: type-prefix the name (iFoo / fFoo / bFoo).
;   defaultValue  — returned when the INI file is absent, the key is
;                   missing, or the C++ plugin failed to load (the
;                   "function MTFPulse.GetConfigInt not found" path falls
;                   through to the caller's own default).
Int Function GetConfigInt(String key, Int defaultValue) Global Native
