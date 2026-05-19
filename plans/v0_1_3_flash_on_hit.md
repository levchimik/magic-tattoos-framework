# v0.1.3 — Flash on Hit

Transient additive emissive lane that responds to combat. Sits on top of the
steady pulse / cross-fade pipeline already in `MTFPulse` C++.

Player-only for v1 (NPC flash deferred — needs per-NPC hit listeners).

---

## Open question: data-model placement

The user-facing pitch was "Flash is one more entry in the slot's effect list,
same as pulse". But re-reading the code, **pulse is NOT an entry in the effect
list** — it's a dedicated per-tier block (`_sCondPulseRate[slot]`, JSON
`slot[i].pulse.{rate,depth,pause,waveform}`, MCM "Pulse" header). The
effect-list (`effectKey[]`) is for *gameplay lifecycle* things (drains,
spells, bursts).

The effect framework also gives only 2 int params per binding (`param`,
`param2`). Flash has 7 settings. So if we go "effect list", we'd need to
either hardcode params or hack StorageUtil for the extras.

**Three options:**

### A. Sibling to Pulse (RECOMMENDED)
Flash becomes its own per-tier block. JSON: `slot[i].flash.{class,minDmg,
retriggerWindow,rampMs,decayMs,peakEmissive,peakAlpha}`. MCM: dedicated
"Flash" header under each tier with 7 sliders. Per-slot scalars live in
StorageUtil (post-release-safe).

Pros: clean conceptually (flash is visual, like pulse); no 2-param crowbar;
no plugin-registry plumbing for a player-only effect; consistent with how
pulse is authored.
Cons: contradicts what I said in chat earlier; one more dedicated block.

### B. Effect-list entry with hardcoded shape
Flash registered as `mtf.base:flash.onhit`. `param` = class filter (0-6),
`param2` = peak emissive (50-500%). Ramp/decay/retrigger_window/min_damage/
peak_alpha hardcoded as constants.

Pros: matches earlier description; appears in the existing effects UI for
free.
Cons: not authorable; can't have one tier's flash be longer/slower than
another's.

### C. Effect-list entry + StorageUtil sidecar
Flash registered as `mtf.base:flash.onhit`. `param`/`param2` show whatever
two settings make sense in the standard slider UI. Remaining 5 settings live
in StorageUtil keyed by `mtf.fxslot.flash.<slot>.<effectIdx>.<field>`, with
their own custom MCM rows.

Pros: full authorability AND fits the "effect list" mental model.
Cons: hybrid storage is unusual — every other effect lives entirely in the
two params; debugging would have to know to look in two places.

**Recommendation: A.** Flash is a visual feature like pulse, not a gameplay
effect like the drains. Matches the surrounding code's mental model.

---

## C++ side (`cpp-plugin/src/`)

Changes assume Option A or B (the C++ math is the same either way; only the
Papyrus-side caller differs).

### `pulse_roster.h` — extend `PulseEntry`
```cpp
// Flash state (v0.1.3) — transient additive emissive lane.
// Authored per-tier. When `flash_peak_emissive > 1.0f` AND a hit has
// stamped `flash_last_hit`, Tick eases `flash_intensity` toward target
// and multiplies final_mult by (1 + (flash_peak_emissive-1) * intensity).
//
// `flash_class_mask` is a bitmask over the 7-class enum from HitListener:
//   bit 0 = ANY, 1 = BLUNT, 2 = BLADED, 3 = RANGED, 4 = FIRE, 5 = FROST, 6 = SHOCK
// Triggers only when (hit_class_bit & flash_class_mask) != 0. ANY=bit0
// means "any hit triggers"; the others are stricter filters.
float        flash_peak_emissive   { 1.0f };  // 1.0 = disabled
float        flash_peak_alpha      { 0.0f };  // additive on top of target_alpha; 0 disables
float        flash_ramp_ms         { 80.0f };
float        flash_decay_ms        { 350.0f };
float        flash_retrigger_ms    { 150.0f };
std::int32_t flash_min_damage      { 0 };
std::uint32_t flash_class_mask     { 0u };    // 0 = disabled

// Hot state (mutated by TriggerFlash + Tick)
float        flash_last_hit        { -1.0e6f };  // NowSec() at last qualifying hit; very negative = never
float        flash_intensity       { 0.0f };     // [0,1]; eased per frame
float        flash_last_tick       { 0.0f };     // for dt computation
```

### `pulse_roster.cpp` — `Tick()` patch
After computing `pulsed` and `ceiling`, before `WriteEmissiveMult`:
```cpp
// Flash envelope
float flash_mult = 1.0f;
float flash_alpha_add = 0.0f;
if (e.flash_class_mask != 0u && e.flash_peak_emissive > 1.0f) {
    const float dt = (e.flash_last_tick > 0.0f) ? (now - e.flash_last_tick) : 0.0f;
    const float target = ((now - e.flash_last_hit) < (e.flash_retrigger_ms * 0.001f)) ? 1.0f : 0.0f;
    if (e.flash_intensity < target) {
        e.flash_intensity = std::min(target, e.flash_intensity + dt * 1000.0f / e.flash_ramp_ms);
    } else if (e.flash_intensity > target) {
        e.flash_intensity = std::max(target, e.flash_intensity - dt * 1000.0f / e.flash_decay_ms);
    }
    flash_mult = 1.0f + (e.flash_peak_emissive - 1.0f) * e.flash_intensity;
    flash_alpha_add = e.flash_peak_alpha * e.flash_intensity;
}
e.flash_last_tick = now;

const float final_mult = pulsed * ceiling * flash_mult;
```

For alpha: when transitioning, the existing transition-lerp already writes
alpha each frame; we add `+flash_alpha_add` to it (clamped to 1). When NOT
transitioning, alpha isn't written each frame today — but if flash is active
AND has peak_alpha > 0, we must write alpha each frame the flash is running
(and zero it on the post-flash frame to release control back to the
persisted store). v1 keeps flash_alpha = 0 by default to dodge this — only
implement the alpha path if needed.

### `papyrus.h/.cpp` — new natives
```cpp
void SetActorFlash(
    Actor target,
    int base_slot,
    int peak_emissive_pct,     // 100-500; 100 = disabled
    int peak_alpha_pct,        // 0-100; 0 = no alpha component
    int ramp_ms,
    int decay_ms,
    int retrigger_ms,
    int min_damage,
    int class_mask);           // bitmask, 0 = disabled

void ClearActorFlash(Actor target, int base_slot);

void TriggerFlash(
    Actor target,
    int base_slot,
    int hit_class,             // single class index 0..6 from HitListener
    int damage);               // engine-reported damage; 0 if unknown
```

`SetActorFlash` finds (actor, base_slot) in roster, writes flash params, or
no-op if no entry exists yet. Called from Papyrus on tier-becomes-active.

`TriggerFlash` finds the entry, checks `class_mask & (1u << hit_class) != 0`
and `damage >= min_damage`, stamps `flash_last_hit = NowSec()`. Cheap.

`ClearActorFlash` zeroes flash_class_mask on the entry. Called when tier
deactivates (so the next tier's flash params take over cleanly).

---

## Papyrus side

### Schema bump (`MTF_MainQuest.SchemaVersion()` → 6)
Migration in `LoadPreset`: if reading schemaversion < 6, flash blocks are
absent → flash settings default to disabled.

### `MTF_MainQuest.psc` — new per-slot scalar accessors (StorageUtil-backed)
```papyrus
int   Function GetCondFlashClassMask(int slot)
Function SetCondFlashClassMask(int slot, int v)
int   Function GetCondFlashPeakEmissive(int slot)   ; 100-500 percent
Function SetCondFlashPeakEmissive(int slot, int v)
int   Function GetCondFlashPeakAlpha(int slot)      ; 0-100
Function SetCondFlashPeakAlpha(int slot, int v)
int   Function GetCondFlashRampMs(int slot)
Function SetCondFlashRampMs(int slot, int v)
int   Function GetCondFlashDecayMs(int slot)
Function SetCondFlashDecayMs(int slot, int v)
int   Function GetCondFlashRetriggerMs(int slot)
Function SetCondFlashRetriggerMs(int slot, int v)
int   Function GetCondFlashMinDamage(int slot)
Function SetCondFlashMinDamage(int slot, int v)
```
All StorageUtil-backed under `mtf.cond.flash.<field>.<slot>`.

### `_slotHasFlash(int slot)` helper
```papyrus
bool Function _slotHasFlash(int slot)
    return GetCondFlashClassMask(slot) != 0 && GetCondFlashPeakEmissive(slot) > 100
EndFunction
```

### Tier-change wiring (in `_applyTier` / `_applyTierEffects`)
After the existing `_resyncPulseCache` + `_applyPulse` call, push flash
params to the C++ roster:
```papyrus
if _slotHasFlash(tier)
    MTFPulse.SetActorFlash(
        PlayerRef, OverlaySlot,
        GetCondFlashPeakEmissive(tier),
        GetCondFlashPeakAlpha(tier),
        GetCondFlashRampMs(tier),
        GetCondFlashDecayMs(tier),
        GetCondFlashRetriggerMs(tier),
        GetCondFlashMinDamage(tier),
        GetCondFlashClassMask(tier))
else
    MTFPulse.ClearActorFlash(PlayerRef, OverlaySlot)
endif
```

**Wrinkle**: SetActorFlash requires a roster entry to exist. Currently
the roster only gets one when there's a pulse OR an in-flight transition.
Fix: extend `_applyPulse` (or add `_ensureRosterEntry`) to register a rate=0/
depth=0 entry whenever the active tier has flash configured, even without
a pulse. Costs one no-op SKEE write per frame but is simplest.

### `MTF_HitListener._classify` + `OnHit`
Already classifies hit source. Extend OnHit to also call MTF_MainQuest's
flash dispatcher:
```papyrus
Event OnHit(...)
    ...
    int cls = _classify(akSource)
    MTF_Plugin_Base p = ...  ; existing
    if p != None
        p._onHit(cls)        ; existing (for combat.hit.* conditions)
    endif
    MTF_MainQuest h = _host()
    if h != None
        h._dispatchFlash(cls, /*damage estimate*/ 0)
    endif
EndEvent
```
Damage isn't a parameter of vanilla OnHit; we'd have to derive it (delta
HP since last frame, or just pass 0 = "trigger always"). v1 passes 0 and
`min_damage = 0` default means it triggers; authors who want filtering set
min_damage > 0 only when they have a reliable damage source.

→ Realistically: drop the damage filter from v1. Saves a parameter and
removes the awkward "we don't know the damage" question. Add later if a
real damage source materializes.

### `MTF_MainQuest._dispatchFlash(cls, damage)`
```papyrus
Function _dispatchFlash(int cls, int damage)
    int s = 0
    while s < 8
        if currentTier_perSlot[s] >= 0 && _slotHasFlash(currentTier_perSlot[s])
            MTFPulse.TriggerFlash(PlayerRef, OverlaySlotForStack(s),
                                  cls, damage)
        endif
        s += 1
    endwhile
EndFunction
```
(Adjust for actual slot/tier tracking — the codebase has both single-active-
tier and stacked-presets paths.)

### `SavePreset` / `LoadPreset` JSON I/O
```
slot[i].flash.classMask      (int)
slot[i].flash.peakEmissive   (int, 100-500)
slot[i].flash.peakAlpha      (int, 0-100)
slot[i].flash.rampMs         (int)
slot[i].flash.decayMs        (int)
slot[i].flash.retriggerMs    (int)
```
Pattern matches the existing `slot[i].pulse.{rate,depth,pause}` block.

---

## MCM (`MTF_MCMQuest.psc`)

### Schema version
`GetVersion()` 21 → 22. `OnVersionUpdate` ml=35 block: no rewrite needed
(no Pages change, no Auto property add). Just bump for safety.

### New right-column block under each tier
After "Cooldown" header, before "Effects" header, add a "Flash" header with:
- "On hit" — multi-class-mask picker (or 7 toggles)
- "Peak brightness" — slider 100-500%, format "{0}%"
- "Peak alpha boost" — slider 0-100%, default 0
- "Ramp up" — slider 10-500 ms, format "{0} ms"
- "Decay" — slider 50-2000 ms, format "{0} ms"
- "Retrigger window" — slider 50-1000 ms, format "{0} ms"

(Drop "Min damage" from MCM if we're dropping it from runtime.)

### Class-mask picker
Easiest: 7 toggle rows ("Any", "Blunt", "Bladed", "Ranged", "Fire", "Frost",
"Shock"). Set bit on toggle. "Any" overrides others for clarity (or treat
ANY as "if no specific class matched, still fire"). Probably simpler: only
ANY OR specifics, never both. If user toggles a specific class, clear ANY.

### State blocks (per slider)
~14 new state blocks: `FLASH_CLASS_ANY`, `FLASH_CLASS_BLUNT`, ... ×7 toggles
+ `FLASH_PEAK_EMISSIVE`, `FLASH_PEAK_ALPHA`, `FLASH_RAMP`, `FLASH_DECAY`,
`FLASH_RETRIG`, all reading/writing the selected condition.

---

## Migration

Schema bump 5→6. Existing presets load with all flash fields = disabled
(class_mask = 0). User opts in by configuring flash on a tier and saving.

No StorageUtil migration needed — defaults read as zero.

---

## Test plan

1. **Pulse-less tier with flash**: Default slot (no pulse, no transition).
   Add `state.weaponDrawn` condition, enable flash on it (class=ANY,
   peak=300%, ramp=80, decay=350). Draw weapon, take a hit from a guard.
   Expect: visible brightness spike on the tattoo, decays back over ~400ms.
2. **Pulse + flash**: T2 below-50%-HP with pulse + flash. Drop HP via
   `player.damageav health 60`. Tattoo should pulse normally. Take a
   sword hit. Expect: pulse continues unbroken, but with a transient
   brightness spike layered on top.
3. **Magic beam sustain**: Set flash with class=FIRE only. Have a NPC
   cast Flames on the player. Expect: tattoo holds bright while beam is
   on, decays once beam stops.
4. **Class filter exclusion**: Set flash class=FIRE only. Get hit by a
   sword. Expect: no flash (no class match).
5. **Mid-flash tier transition**: Configure flash on T0 default AND T2
   low-HP. Trigger T2 mid-flash (drop HP from above 50% to below).
   Expect: cross-fade transitions colour, flash decays naturally on T0,
   T2's flash params take over for the next hit.
6. **Save/load round-trip**: Save preset with flash → reload → reopen
   MCM. Flash params should round-trip identically.

---

## Implementation order

1. C++: PulseEntry fields + Tick patch + 3 new natives. Build, deploy DLL.
2. Papyrus: StorageUtil accessors on MTF_MainQuest.
3. Papyrus: SavePreset/LoadPreset JSON I/O.
4. Papyrus: tier-change wiring + HitListener dispatch.
5. Papyrus: schema bump.
6. MCM: Flash block in preset-editor right column.
7. MCM: schema bump + migration block.
8. In-game test (scenario 1 first — simplest).

Each step builds and is independently testable.

---

## Out of scope (v2 candidates)

- Per-layer flash mask (layer 0 flashes, layer 1 doesn't)
- Tint override (white flash on top of red tattoo, or coloured flash)
- Curve shape (linear / ease / exp)
- Power-attack / sneak / blocked filters
- Damage threshold (needs reliable damage source)
- Other triggers: `flash.oncast`, `flash.onkill`, `flash.ondodge`
- NPC flash (needs per-NPC hit listeners — alias forced onto each
  tracked NPC, or PO3 OnObjectHit global event)
