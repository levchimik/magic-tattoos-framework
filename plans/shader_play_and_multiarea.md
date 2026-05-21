# Plan: EffectShader playback + multi-area overlay support

Inspired by Nexus 37275 (RaceMenu Animated Overlays). Two independent phases — Phase 1 is the quick win, Phase 2 is more invasive.

## Phase 1 — `shader.play` effect type (~80 lines, ~1-2 hours, low risk)

Add a new effect type that plays a vanilla `EffectShader` on the target for a configurable duration. This is the "magic glow" everyone wants without committing to multi-area overlays.

### ESP changes
- Backup: `cp MagicTattoosFramework.esp MagicTattoosFramework.esp.bak-pre-shader-list`
- Spriggit serialize → add new FormList `MTF_VanillaShaderList` containing ~30 vanilla `EffectShader` FormIDs (frost cloak, fire cloak, ghost, soultrap, candlelight, etc.) → deserialize back
- The FormList index corresponds to the `param` value stored on the effect.

### Script changes — `MTF_Plugin_Base.psc`
- New idx **55** = `shader.play`
  - **param** = shader index into `MTF_VanillaShaderList` (dropdown in MCM)
  - **param2** = duration in whole seconds (0 = infinite while bound, slider 0-60)
- `onActivate(target, param, param2)`:
  - `EffectShader es = MTF_VanillaShaderList.GetAt(param) as EffectShader`
  - `es.Play(target, param2)` if param2 > 0 else `es.Play(target, -1.0)`
- `onDeactivate(target, param, param2)`:
  - `es.Stop(target)` always (idempotent on vanilla EffectShader)
- `onTick(...)` no-op for shader.play

### Lookup table updates
- `GetEffectCount()`: 55 → 56
- `_effectIdHigh()` / `_effectLabelHigh()`: add entry for idx 55
- `GetEffectMode(idx)`: return mode for the new idx
- `_avNameForHigh(idx)`: no AV for idx 55 (shader doesn't touch AVs)
- New helper `GetShaderName(idx)` returning a short pretty name for the dropdown

### MCM
- Effect type dropdown gets the new entry
- When `shader.play` is selected, param dropdown shows shader names (via `GetShaderName`), param2 slider is "Duration (s)" 0-60

### Test preset
- `presets/Test_Shaders.json` headless preset with a few shader effects bound to default & one condition

### Verification
- Apply preset in-game, watch the visual; toggle condition; remove preset → shader stops

---

## Phase 2 — multi-area overlay support (~300-500 lines, ~4-6 hours, more invasive)

Currently only Body overlays work. RAO supports Face/Hand/Feet too. Extend MTF to all 4 areas. Roll out in stages with verification between each.

### Stage A — JSON `area` field
- Pack entries get optional `area: "Body"|"Face"|"Hand"|"Feet"` (default `"Body"` for backcompat)
- New helper `GetEntryArea(packId, entryId)` reads it lowercase

### Stage B — area-aware reservation
- `_computePresetReservedLayers` already MAXes across slots; now it must MAX **per area** because Face/Hand/Feet have separate slot pools
- Returns max overlays per area: `int[] reserved = [bodyMax, faceMax, handMax, feetMax]`
- `AddAppliedPreset` reserves slots in each area separately, with the same truncation hard-reject logic per area

### Stage C — `_OVERLAY_PARTS()` expansion
- Return all 4 area names from `_OVERLAY_PARTS()`
- Audit every call site to ensure they iterate areas rather than assume Body

### Stage D — fix hardcoded "Body"
- Known sites (must re-verify line numbers before edit): ~2991, 2993, 3209, 3223, 3635, 4892
- Some are intentional (pulse roster, see Stage F); rest must use the entry's area

### Stage E — MCM split
- OverlaySlot binding sub-page goes from one block to four (Body/Face/Hand/Feet)
- Or keep one block but show only the entry's area's free slots

### Stage F — pulse roster stays Body-only in v1
- `MTFPulse.dll` ties per-actor base_slot to Body; Face/Hand/Feet pulse needs a roster refactor
- Leave a `; TODO multi-area pulse` comment at the relevant lines; non-Body areas get no pulse animation yet

### Verification gates between stages
- A: load existing presets without `area` — they still apply as Body
- B: artificial preset with Body + Face entries — both reserve correctly
- C+D: apply Face-only preset to player — face overlay renders, body untouched
- E: MCM shows Face/Hand/Feet bindings in the right places
- F: confirm Body preset still pulses; Face preset doesn't break anything

### Rollout
- 3-4 commits, each one in-game verified before the next
- Phase 2 in a separate session; do NOT bundle with Phase 1
