# Multi-Area Overlay Support (Body / Face / Hand / Feet)

Plan for extending MTF beyond body-only overlays to also drive NiOverride's
Face, Hand, and Feet overlay slot pools. Drafted 2026-05-21.

## Goal

Tattoo packs declaring `"area": "Face"`, `"area": "Hand"`, or `"area": "Feet"`
in their visual catalog JSON should:

- Render onto the matching NiOverride node pool (`Face [ovlN]` etc.)
- Stack independently of body overlays (face slot 0 + body slot 0 = distinct)
- Pulse, cross-fade, and flash like body overlays do today
- Have their own MCM player-base slider so the user can pick the starting
  slot per area (same UX as today's body `OverlaySlot`)

User decisions locked in 2026-05-21:
- **Scope**: All three phases.
- **Base slot**: Per-area MCM sliders (`FaceOverlaySlot` etc.) in General page.
- **Pack area granularity**: Pack-level (one pack = one area). Mixed-area
  packs would require entry-level metadata and a heavier refactor — defer
  unless a real pack demands it.

## Current state

The framework was largely **pre-wired** for this. These layers already accept
an `area` parameter and format node names as `area + " [ovl" + N + "]"`:

- `_numOverlays(area)` — switches Body/Face/Hand/Feet, calls the matching
  `NiOverride.GetNum<Area>Overlays`
- `_findFirstFreeOverlaySlotNPC(target, area)`
- `_drawOverlayForActorAt(actor, idx, useScratch, area, baseSlot, reservedLayers, deferApply)`
- `_applyOverlayDeferred / _clearOverlayDeferred`
- `_drawPresetOnActor` loops `_OVERLAY_PARTS()`
- `_clearPresetOverlayForActor` loops `_OVERLAY_PARTS()`
- `_compactAppliedPresets` loops `_OVERLAY_PARTS()`
- `_getActorPresetBase(target, name, area) / _getActorPresetLayers(target, name, area)` — storage already keyed by area
- Pack JSON already declares `"area": "Body"` in v3 schema

What's still body-locked:

1. `_OVERLAY_PARTS()` returns just `["Body"]`
2. `_playerBaseLayers(area)` early-returns 0 for non-Body
3. `_computePresetReservedLayers(area, useScratch)` early-returns 0 for non-Body
4. Pack-JSON loader doesn't read `"area"` — no `GetPackArea(packId)` accessor
5. `OverlaySlot` is a single int — no Face/Hand/Feet equivalents
6. `drawOverlayForActor` (legacy player path) hard-locked to area="Body"
7. C++ `pulse_roster.cpp` snprintf's `"Body [ovl%d]"` in 3 spots
8. `PulseEntry` keyed by `(actor_formID, base_slot)` — area collisions possible
9. MCM has no per-area exposure for player-base slot

## Phase 1 — apply-time multi-area (NPC + stacked presets only)

Lets users APPLY face/hand/feet packs via the Apply Tattoo spell. Static
visuals only (no pulse on non-body). MCM Conditions sub-tab stays body-only.
Smallest change that lights up Tier 3 face packs from `plans/tattoo_packs.md`.

### Changes

1. **Pack-JSON loader reads `area`.** Where the catalog file is parsed
   (search for the function that registers `packIds` + entries), also read
   `.area` (default "Body"). Cache it in a parallel StringList keyed by
   packId.
2. **New accessor:** `string Function GetPackArea(string packId)` returning
   the cached area for `packId` (or "Body" for unknown/legacy).
3. **`_OVERLAY_PARTS()`** returns `["Body", "Face", "Hand", "Feet"]`.
4. **`AddAppliedPreset` per-area reservation.** Replace the single
   "compute body floor + reserve" path with: scan the preset's 8 slot
   entries → group by `GetPackArea(slot.packId)` → compute per-area max
   layer count → reserve a slot range per area at that area's floor.
   Floor = `_findFirstFreeOverlaySlotNPC(target, area)` for NPCs;
   `<Area>OverlaySlot + _playerBaseLayers(area)` for player (Phase 2 wires
   the player-base term — Phase 1 it's just `_findFirstFreeOverlaySlotNPC`
   for the player too, so applied presets stack above whatever the
   body-only MCM base is using).
5. **`_drawPresetOnActor`** — already loops `_OVERLAY_PARTS()`; works
   automatically once non-Body reservations exist.
6. **`_computePresetReservedLayers(area, useScratch)`** — generalize like
   `_playerBaseLayers` (see Phase 2).

### Verification (Phase 1)

- Install one Tier 3 face pack (e.g. Hellblade Senua's Warpaints)
- Add `"area": "Face"` to its catalog JSON
- Save a preset with slot 0 = the face pack's "warpaint A" entry
- Cast Apply Tattoo on self → NotificationLog shows "applied"
- Verify the warpaint renders on the face, not the chest
- Apply a second body-area preset → both should render independently
- Remove face preset → face clears, body remains
- Remove body preset → body clears, face remains (if not already removed)

## Phase 2 — MCM player-base sliders + legacy draw path

Lets the MCM Conditions sub-tab control non-body conditions. Player can
have a face condition-slot ladder, independent body condition-slot ladder, etc.

### Changes

1. **New `MTF_MainQuest` properties:**
   ```papyrus
   int Property FaceOverlaySlot = 0 Auto
   int Property HandOverlaySlot = 0 Auto
   int Property FeetOverlaySlot = 0 Auto
   int Property CurrentFaceOverlaySlot = 0 Auto
   int Property CurrentHandOverlaySlot = 0 Auto
   int Property CurrentFeetOverlaySlot = 0 Auto
   ```
2. **General-page MCM sliders** in `MTF_MCMQuest.psc`: three new int
   sliders next to the existing `OverlaySlot` slider. Step 1, min 0,
   max = `_numOverlays(area) - 1`.
3. **`_playerBaseLayers(area)`** — drop the `if area != "Body" return 0`
   guard; the body-only `_g_resolvePackId` walk already returns per-slot
   pack IDs that are area-aware once Phase 1's `GetPackArea` resolves
   each slot's area. Add the area filter: only include a slot in the
   max if its picked entry's pack area matches the requested area.
4. **`_computePresetReservedLayers(area, useScratch)`** — same generalization.
5. **`drawOverlayForActor` (legacy player path)** — was a single-area
   wrapper. Replace with a loop over `_OVERLAY_PARTS()`, calling
   `_drawOverlayForActorAt` per area with that area's
   `<Area>OverlaySlot` + `_playerBaseLayers(area)`.
6. **`removeOverlay(akTarget)`** — clear all 4 areas, not just Body.
7. **`CurrentOverlaySlot` parity** — update each `Current<Area>OverlaySlot`
   in lockstep so the slow-tick's "base changed → wipe and redraw"
   detection works per area.
8. **`_resolveBaseForPulse(area)`** — already used by pulse cache; pick
   the right `<Area>OverlaySlot` based on the preset's primary area.
9. **MCM "Reload visual packs"** — bump menu cache invalidation to include
   per-area pack listings.

### Verification (Phase 2)

- Set `FaceOverlaySlot = 0` in MCM
- Pick a face pack entry in Conditions slot 0 (Default)
- Confirm warpaint applies on tier 0
- Bind a face-condition (e.g. `mtf.sla:arousal >= 50`) to slot 1, point at
  a different face entry; raise arousal → face warpaint swaps cleanly
- Confirm body conditions still drive body overlays independently

## Phase 3 — Pulse / cross-fade / flash for non-body

Lets face/hand/feet tattoos pulse, cross-fade between tiers, and flash on
hit just like body overlays. Requires a DLL rebuild and a save-state-safe
migration.

### Changes

#### C++ side (`pulse_roster.h/.cpp`, `papyrus.cpp`)

1. **`PulseEntry` adds `area` field** as `std::uint8_t` (kBody=0, kFace=1,
   kHand=2, kFeet=3). Use uint8 not std::string — millions of Tick frames
   shouldn't pay for a string compare.
2. **Hash key becomes `(formID, area, base_slot)`** — `FindLocked` adds
   area param; `kCapacity = 128` stays; eviction policy unchanged.
3. **Node-name format** — replace the 3 hard-coded `"Body [ovl%d]"`
   snprintfs with a helper:
   ```cpp
   static const char* AreaName(std::uint8_t a) {
       switch (a) {
       case 1:  return "Face";
       case 2:  return "Hand";
       case 3:  return "Feet";
       default: return "Body";
       }
   }
   // ...
   std::snprintf(node, sizeof(node), "%s [ovl%d]",
                 AreaName(e.area), static_cast<int>(e.base_slot + li));
   ```
4. **Native signature changes** for `SetActorPulse*`, `ClearActorAt`,
   `SetActorFlash`, `ClearActorFlash`, `TriggerActorFlash`, `SetActorFade`,
   `ClearActorFade`, `TriggerActorFade`. Add `Int area` after
   `baseOverlaySlot` in each. To preserve back-compat for any third-party
   callers, keep the OLD signature as a wrapper that calls the new one
   with `area = 0` (Body) — same trick MTFPulse already does for
   `SetActorPulse` vs `SetActorPulseWithTransition`.
5. **Death sink** — `TriggerFadeAllSlotsForActor` already walks all
   entries for an actor; no change beyond the struct field.
6. **Hit sink** — `TriggerFlashAllSlotsForActor` ditto.

#### Papyrus side (`MTFPulse.psc`, `MTF_MainQuest.psc`)

1. **`MTFPulse.psc`** — new native shapes:
   ```papyrus
   Function SetActorPulseWithTransitionAt(Actor a, ..., Int baseOverlaySlot, Int area, ...) Global Native
   Function ClearActorAt(Actor a, Int baseOverlaySlot, Int area) Global Native
   ; ... etc
   ```
   Keep old-shape natives as deprecation stubs that call through with
   `area = 0`. Mark in comments which is current.
2. **`_resolveBaseForPulse` and `_rosterAddOrUpdate`** — accept area
   string, translate to int (0/1/2/3), pass through to the natives.
3. **`_applyPulse` (MCM-base path)** — loop `_OVERLAY_PARTS()`, for each
   area that has a base reservation, push a roster entry for that area's
   `(base, layerCount)`.
4. **Stacked presets** — `_rosterAddOrUpdate(target, presetName, tier, rt)`
   already loops over `_OVERLAY_PARTS()` in `_drawPresetOnActor`; the
   roster push currently writes one entry per preset (body only). Change
   to write one entry per (preset, area-with-reservation).

#### Save-state migration

Roster is in-memory, lost on save/load. The post-load redraw
(`postLoadRedrawNow`) already rebuilds the roster from applied-preset
metadata. As long as `_rosterAddOrUpdate` covers all 4 areas in Phase 3,
the post-load path picks up multi-area pulse automatically.

### Verification (Phase 3)

- Face pack with `pulse.rate > 0` configured on Default slot
- Confirm face warpaint pulses
- Body pack pulsing simultaneously — independent rates render correctly
- Tier transition with face + body presets — both cross-fade in lockstep
  (BeginTransitionBatch / EndTransitionBatch already coordinates this)
- Save → reload → both pulse animations resume after the post-load redraw
- Death triggers fade animation on face + body together

## Implementation order

Order matters because Phase 1 enables packs to load, Phase 2 reuses Phase
1's `GetPackArea`, and Phase 3 is the most surgical. Each phase ends with
build + deploy + user in-game verify before moving on.

```
[Phase 1]
  ├─ Pack-JSON loader reads "area"
  ├─ GetPackArea accessor + cache
  ├─ _OVERLAY_PARTS() → 4 areas
  ├─ AddAppliedPreset per-area reservation
  ├─ _computePresetReservedLayers generalization
  ├─ BUILD + DEPLOY
  └─ USER VERIFIES face pack applies + renders → commit

[Phase 2]
  ├─ Face/Hand/Feet OverlaySlot properties
  ├─ MCM General sliders
  ├─ _playerBaseLayers area filter
  ├─ drawOverlayForActor area loop
  ├─ removeOverlay 4-area sweep
  ├─ Current<Area>OverlaySlot tracking
  ├─ BUILD + DEPLOY
  └─ USER VERIFIES MCM-driven face conditions → commit

[Phase 3]
  ├─ PulseEntry.area field + Find by 3-tuple
  ├─ Node-name format helper
  ├─ Native signature additions
  ├─ MTFPulse.psc deprecation stubs
  ├─ _applyPulse + _rosterAddOrUpdate area expansion
  ├─ BUILD DLL + DEPLOY
  ├─ BUILD scripts + DEPLOY
  └─ USER VERIFIES face pulse + post-load roster → commit
```

## Open considerations

- **Hand overlay node naming**: NiOverride uses `Hand [ovlN]` (singular)
  not `Hands` — verify at first phase-1 test. Same for `Feet` (already
  plural).
- **SkyUI MCM state pool cap (127)**: Phase 2 adds 3 sliders + 3 hidden
  `Current<Area>OverlaySlot` properties. Check current MCM page state-block
  budget before wiring — might need to demote some legacy diagnostic
  rows.
- **`MTF NPC Overlays`** mod folder — already installed but unverified
  what it does. Should not block Phase 1; address before Phase 3 if it
  turns out to be a pack rather than an unrelated mod.
- **First Tier 3 pack for verification**: pick the smallest in `D:\Skyrim
  mods` — Daymarr Yokuda (2.2 MB) or Niohoggr Warpaints AIO (118 MB,
  face+body). Niohoggr is more useful because it exercises both areas at
  once; install Niohoggr instead of one of the Tier 1 picks if Phase 1
  needs a face pack to test against.

## Status

- [ ] Phase 1: pack JSON area + apply-time multi-area
- [ ] Phase 1 in-game verify (face pack applies + renders)
- [ ] Phase 1 commit
- [ ] Phase 2: MCM sliders + legacy player draw path
- [ ] Phase 2 in-game verify
- [ ] Phase 2 commit
- [ ] Phase 3: C++ pulse roster area key + node-name format
- [ ] Phase 3 in-game verify
- [ ] Phase 3 commit
- [ ] Update `plans/tattoo_packs.md` — mark Tier 3 as unlocked
- [ ] README.md — document multi-area support
