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
;   baseOverlaySlot — NiOverride body overlay base index (typically 0 or 2).
;   isFemale    — sex flag for NiOverride node lookups.
;   waveLUT     — 64-entry [0,1]→[0,1] waveform sampled across one cycle.
;                 Empty or wrong-length array → C++ falls back to cosine.
Function SetActorPulse(Actor aktor, Float rate, Int depthPct, Float pause, \
                       Int layerCount, Float startTime, Float[] emMults, \
                       Int baseOverlaySlot, Bool isFemale, Float[] waveLUT) Global Native

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
                                     Float transitionDuration) Global Native

; Remove EVERY entry the actor owns (all base_slots).
; Use on death / unload / total teardown.
Function ClearActor(Actor aktor) Global Native

; Remove ONE entry by (actor, baseOverlaySlot). Use when a single preset on
; an actor with several stacked presets becomes inactive.
Function ClearActorAt(Actor aktor, Int baseOverlaySlot) Global Native

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
                       Int retriggerMs, String tagsCsv) Global Native

; Empty the tag set on (aktor, baseOverlaySlot). Any in-flight intensity
; eases out naturally on the next frames. Use on tier-deactivate.
Function ClearActorFlash(Actor aktor, Int baseOverlaySlot) Global Native

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
Function TriggerActorFlash(Actor aktor, Int baseOverlaySlot, String tag) Global Native
