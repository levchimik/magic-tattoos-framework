# Changelog

All notable changes to Magic Tattoos Framework are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/);
versions are the Nexus release tags.

## [v0.3.0] — 2026-05-29

Rolls up 21 commits since v0.2.8,
including two on-disk schema bumps (menu-param **string ids, catalog
schema v2**; **preset schema 9**), a reworked emissive/sheen render path,
the dispatch-context race fix, the form-string persistence fix, a
built-in/user preset split, and several new content-pack adapters.
Existing saves migrate transparently; a new save is still recommended for
first-time setup.

### Added

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
