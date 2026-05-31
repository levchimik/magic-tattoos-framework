# Changelog

All notable changes to Magic Tattoos Framework are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/);
versions are the Nexus release tags.

## [v0.3.6] — 2026-05-31

A packaging fix. No script, schema, or save changes; drop-in over v0.3.5.

### Changed

- **NPC-overlay override now ships as `skee64_custom.ini`.** The base FOMOD
  previously bundled a full copy of RaceMenu's `skee64.ini` just to flip
  `[Overlays] bPlayerOnly=0` (the key that lets MTF apply tattoos to tracked
  NPCs, not only the player). That copy created a loose-file conflict with
  RaceMenu's own ini — it had to load *after* RaceMenu or NPC tattoos
  silently broke, and it overwrote any user customizations in the file. MTF
  now ships a minimal `skee64_custom.ini` (RaceMenu's official per-section
  override mechanism) that changes only the one key, conflicts with nothing,
  and is load-order independent. The in-game effect is identical.

## [v0.3.5] — 2026-05-31

A visual-polish release for the cross-fade render path. No schema or save
changes; drop-in over v0.3.4.

### Fixed

- **Same-texture tier-swap flash.** Switching between two tiers that share
  the same overlay texture no longer flashes dark for a frame. The swap
  used to re-run `drawOverlay → ApplyNodeOverrides`, which re-derives the
  live shader from the override store; glossiness/specular aren't stored
  there, so they reset to mesh defaults for one frame. MTF now skips the
  redraw entirely when the texture is unchanged — the C++ pulse Tick
  already owns em_mult / alpha / tint / emissive, so only the pulse cache
  is resynced.
- **Black blink when a tattoo first appears.** Going from no tattoo to a
  tattoo (e.g. a condition turning on) no longer blinks black on the first
  painted frame. Glossiness and specular strength are now written into the
  override store keyed off alpha, so the `ApplyNodeOverrides` frame paints
  with sheen instead of mesh-default flat black.
- **Fresh tattoos fade in.** A newly-appearing tattoo now cross-fades from
  alpha/emissive 0 instead of popping in at full strength, matching the
  fade already used on tier changes.
- **Faster post-load reappearance.** After loading a save the tattoo
  redraws via an early batched draw, and the post-load freeze window was
  trimmed (5s → 3s, snapping the repopulation), cutting the visible delay
  from ~5s toward the SKEE async override-store restore floor (~1–3s).

### Changed

- **Pulse survives `tfc` (free camera).** The per-frame pulse Tick moved
  off the player-actor update hook — which `tfc` suspends — onto a main
  game-loop call-site hook (the canonical per-frame hook used by e.g. True
  Directional Movement). Glow/pulse and live tier color changes now keep
  running in free camera. A full game-pausing menu still halts the loop;
  its own 3D rebuild repaints on close.

## [v0.3.4] — 2026-05-30

### Added

- **SLA NPC aura gender targeting.** The "NPC Arousal Rate" effect
  (`arousal.rate.npc`) gains a third parameter — *Affects: Both / Females
  only / Males only* — so a pheromone-aura tattoo can be oriented. The
  game-time tick filters nearby actors by `GetActorBase().GetSex()` before
  applying the exposure delta. Existing presets default to "Both".

### Changed

- **SLA "Arousal Locked" condition simplified.** Collapsed the
  Unlocked/Locked dropdown to a single parameterless condition that fires
  when the actor's arousal is locked. Old presets that stored a lock-state
  id are read harmlessly (the id is ignored).
- **Wider parameter ranges** for several base effects, sized to their stat:
  carry-weight shift ±100 → **±1000** (step 10); max magicka / max stamina
  shift ±100 → **±500** (step 5); magicka / stamina / health regen-rate
  shift max 100 → **300** (step 5).
- **Finer emission-strength control.** The per-layer *Emission strength*
  slider now steps by **0.25** (was 0.5) for precise tuning in the low
  glow band.

## [v0.3.3] — 2026-05-30

### Changed

- **Plain-language condition/effect descriptions.** Rewrote every
  SkyrimNet bio description (base, SLA, OStim, SexLab, FMR, BFNG) into
  plain, in-world, third-person prose — dropping mod/engine jargon
  (mod names, "exposure", "tier", "Burst —") that no character would
  know, while keeping real terms (ovulation, arousal) and all
  `{paramN}` placeholders. Bare predicate phrasing fixes a
  double-"Triggered"/double-period artifact in the rendered bio.

### Fixed

- **Multi-condition bio narration.** The SkyrimNet bio now narrates
  *all* conditions on a slot, joined by the slot's AND/OR operator —
  previously only the first condition was described.

## [v0.3.2] — 2026-05-30

### Added

- **OStim scene conditions.** `scene.action` (act type the actor is
  giving/receiving) and `scene.partner` (in a scene with a named actor).
- **SexLab scene partner condition** (`scene.partner`).

### Removed

- **SexLab cum conditions/effects** and the OStim `has.schlong` /
  SexLab `has.strapon` equipment conditions, dropped as out-of-scope.

## [v0.3.1] — 2026-05-30

### Changed

- **Conditions serialized as an array.** Per-slot conditions moved to a
  `cond.items[]` array with a single `cond.op` operator (hard cutover
  from the legacy scalar `cond` + indexed `condx<j>` keys). Presets and
  live state round-trip the array, count, and operator.

## [v0.3.0] — 2026-05-30

Rolls up 22 commits since v0.2.8,
including two on-disk schema bumps (menu-param **string ids, catalog
schema v2**; **preset schema 9**), per-slot **multi-condition AND/OR**, a
reworked emissive/sheen render path, the dispatch-context race fix, the
form-string persistence fix, a built-in/user preset split, and several new
content-pack adapters. Existing saves migrate transparently; a new save is
still recommended for first-time setup.

### Added

- **Per-slot multi-condition logic (AND/OR).** A condition slot can now
  hold more than one condition combined by a single operator — **AND**
  (all must pass) or **OR** (any passes). The MCM exposes up to two
  conditions per slot with a *Match mode* toggle; the backend supports
  more (`MAX_CONDS_PER_SLOT`). Fully back-compatible: legacy
  single-condition slots evaluate bit-identically, a slot with no explicit
  count reports 1, and old saves/presets are untouched. All four
  evaluation paths (player-live and NPC scratch/quick-eval) honor the
  operator via shared helpers, and presets round-trip the operator, count,
  and extra conditions.
- **SkyrimNet — free-text "Special" effect.** New `rp.text` effect
  surfaces roleplayer-authored copy directly in the actor's rendered bio.
  The framework gained a generic **text** parameter type alongside
  menu/slider, editable from the MCM.
- **SkyrimNet — live bio + bearer-only effects.** The bio now refreshes on
  MCM close, so edits to effect/condition params, layer colors, and pulse
  rates reflect immediately (previously only on a tier transition). Effect
  descriptions are now **bearer-only** — observers can see the tattoo
  (placement, color, pulse, condition) but not what it does.
- **MCM — slot rename + slot swap.** Name any condition slot; swap a
  slot's condition/effects/cooldown/name with another. Visuals stay tied
  to slot index. (Preset schema → 9.)
- **Built-in vs user presets.** Presets now live in two folders:
  user-saved presets (shown in the MCM picker and the Apply Tattoo spell)
  and read-only built-in presets (shipped fixtures, hidden from the
  pickers). Saving can no longer overwrite a built-in, and a reserved
  built-in name is refused at save time.
- **Catalog — stable string ids for menu params** (schema v2). Menu
  options now carry a reorder-stable `id` string instead of a positional
  int, so reordering or growing a catalog no longer shifts existing
  bindings.
- **New content-pack adapters:** Lyru 1, Lyru 2, Bitchcraft, Community
  Overlays 2, and Community Overlays 3.
- **FOMOD:** ships plugin catalogs and an optional F10 console test
  runner; NPC-overlays INI enabled by default; integration plugins may
  install without their soft master present.

### Fixed

- **Visual — emissive-0 layers no longer render black or invisible.** The
  ink diffuse is near-black and is only made visible by its specular
  sheen, but the C++ pulse tick had coupled gloss/spec to the emissive
  ceiling — so a matte layer (emissive 0, e.g. the base mark) collapsed to
  a black blob or vanished entirely. Gloss/spec are now driven by the
  layer's **alpha** (visibility), fully decoupled from emissive; emissive
  controls glow only. (Supersedes the earlier em→0.001 floor band-aid,
  which targeted the wrong knob and never fixed the smudge.)
- **Pulse — tier swaps no longer pop to full brightness.** A tier change
  now lands at the pulse *trough* with phase pinned to 0, so a deep /
  heartbeat pulse resumes from its natural low point instead of flashing
  to the ceiling on every transition.
- **Preset delete actually works now.** Deletion wrote `int.valid` while
  every reader checked the top-level `.valid` path — two different
  PapyrusUtil storage slots — so "deleted" presets silently lingered in
  the picker and stayed loadable. Delete now flags the file correctly;
  the name can be reclaimed by saving over it.
- **Persistence — MCM slot config no longer vanishes on save/reload.**
  PapyrusUtil silently drops single form-attached strings on ESL-flagged
  Quest forms across the cosave round-trip. The seven affected string
  families (pack/entry/condition plugin id/params/name/waveform) plus the
  per-actor skill/resist revert keys are now routed through None-attached
  storage with the FormID baked into the key.
- **Concurrency — stuck buff after a tier change.** A dispatch-context
  race could let the slow tick clobber the active (slot, effect) while a
  plugin's deactivate was suspended mid-call, leaving a skill or resist
  buff applied with no handle to remove it. Dispatch context now flows as
  explicit function parameters, snapshotted once at entry — no shared
  StorageUtil keys.
- **Startup — visual-catalog load no longer spams the Papyrus log.** The
  catalog loader emitted a 3-error array cascade (~3× per launch) from a
  PapyrusUtil array-return / None-comparison ordering bug; the load
  succeeded anyway but each error wrote a sync-disk stack trace. Fixed by
  allocating before the guard.
- **Fade-on-death** now arms fade parameters eagerly from cache on actor
  death, so the fade plays even if the actor's roster entry was evicted.
- **Post-string-id polish:** menu defaults are stamped onto string params
  on a fresh MCM bind; scratch routing and a residual F10 race fixed.

### Changed

- **Debug mode now defaults off.** Tier-change toasts and lifecycle audit
  output are opt-in via MCM ▸ General ▸ Debug mode (was force-enabled as a
  dev convenience). Leftover `[MTFwipe]` diagnostics removed.

### Internal / dev

- **FOMOD build is now a one-command release pipeline.** `build_fomod.sh`
  rebuilds the MTFPulse.dll SKSE plugin, stages all components, and runs a
  static release gate (`release_check.sh`) that aborts before archiving on
  any shipping defect (forced debug, leftover scaffolding, test artifacts
  in the base step, stale `.pex`, catalog drift, version mislabel).
- **Build scripts are path-portable.** Repo root auto-derives from each
  script's location; MO2 deploy + toolchain paths are env-overridable
  (`MTF_PROJ`, `MTF_MO2_MODS`, `MTF_CAPRICA`, `MTF_FLAGS`).
- Visual stress runner (End key) — 4 stacked tattoos × N NPCs.
- N-fiber concurrency stress runner (PgDn) with a UIListMenu picker.

[v0.3.0]: https://www.nexusmods.com/skyrimspecialedition/mods/180775
