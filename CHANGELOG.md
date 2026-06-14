# Changelog

All notable changes to Magic Tattoos Framework are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/);
versions are the Nexus release tags.

## [v0.4.3] — 2026-06-14

A bug fix plus new Fertility Mode condition options. Drop-in over v0.4.2; no
schema or save changes — the new conditions are additive, so existing presets
are untouched.

### Fixed

- **Overlay base-slot change left a white "ghost" tattoo.** Changing the body
  overlay base slot — e.g. an MCM-config reset on update — wrote `OverlaySlot`
  and `CurrentOverlaySlot` together in a single pass, which slipped past the
  slow-tick mismatch detector that clears the old slot. The previously painted
  `Body [ovlN]` overlay was then orphaned in the SKEE co-save with no live
  colour driver: it rendered as an untinted white/grey mark and fought the real
  overlay. All base-slot changes now route through one `SetOverlaySlot` that
  clears the previously painted range first (keyed off where it actually
  painted), and the version-update wipe no longer clobbers a configured slot.
  An already-stranded ghost can be cleared by setting that RaceMenu body-paint
  slot back to Default once.

### Added

- **Fertility Mode (Reloaded) — new conditions.**
  - **Cycle phase** — one condition with a Menstruation / Follicular /
    Ovulation / Luteal picker.
  - **Postpartum recovery** — fires during post-birth recovery, with a
    minimum-recovery-% threshold.
  - **Inseminated** — fires while the actor is carrying sperm, with a minimum
    amount threshold.
  - **Children** — fires when the player has at least N tracked children.
  - The standalone **Ovulation** condition is kept alongside the new picker.

### Changed

- **SkyrimNet bio phrasing.** Condition and label text on the fertility and
  arousal adapters (Fertility Mode, Beeing Female, OStim, SexLab, SexLab
  Aroused) was reworded to read naturally under the bearer's name in the
  generated bio — dropping the "the actor" subject prefix and internal/mechanical
  notes — so a triggered tattoo renders e.g. "Triggered by: **Pregnancy** — is
  pregnant and at least 50% through the pregnancy."

## [v0.4.2] — 2026-06-08

A compatibility and packaging fix. Drop-in over v0.4.1; no schema or save changes.

### Fixed

- **Tattoos invisible on RaceMenu 0.4.19.x (old SKEE).** `MTFPulse.dll` drives
  the overlay's shader properties (alpha, emissive colour/multiple, tint) through
  SKEE's `Override` interface. It required interface **v2** — the "wrapper"
  ABI introduced by RaceMenu 0.4.20.0 — and rejected older RaceMenu (0.4.19.x),
  which exposes the pre-wrapper **v1** interface. With the bridge dead, every
  shader write silently no-opped: the overlay applied (texture in the store via
  Papyrus/NiOverride) but rendered invisible, even though *manually* set RaceMenu
  overlays worked. The bridge now detects the interface version and, on v1, drives
  SKEE's legacy concrete `OverrideInterface` vtable directly — `SetNodeProperty`
  at vtable slot 14, with the property key/index packed inside an `OverrideVariant`
  and the node name passed as a `BSFixedString`. Pulse and visuals now work on
  RaceMenu 0.4.19.x as well as 0.4.20.0+. The call stays SEH-guarded, so a vtable
  mismatch disables the bridge rather than crashing.

- **Ambient Light effect (`toggle.ambientLight`) never worked from a FOMOD
  install.** The effect's magic effect (MGEF `0x924`, Light archetype → LIGH
  `0x928`) attaches its light via a HitEffectArt art object (ARTO `0x929`) whose
  model is `meshes\MTF\MTF_AmbientLightAttach.nif`. That mesh — the only one MTF
  ships — was never staged by `tools/fomod/build_fomod.sh`, which copied scripts,
  the ESP, the DLL, INIs and catalogs but not the `meshes/` tree. So every FOMOD
  install lacked the attach carrier and the light had nothing to parent to. The
  build now stages `data/meshes/` into `00_base` and lists the NIF in the
  release prereq check, so a future missing mesh fails the build loudly instead
  of shipping a broken effect.

- **Several effects silently dead on FOMOD installs — SkyrimNet `rp.text`, the
  spell-cast emissive flash, the preset API, and SPID-distributed tattoos.** The
  build never staged the files these features depend on. The SkyrimNet plugin
  catalog (`mtf.skyrimnet.json`) was omitted, so its `rp.text` effect reported
  `-1`/unregistered and presets binding it resolved to nothing. And four scripts
  the ESPs attach via VMAD were never shipped — `MTF_CastListener` (the
  `BeginCast*` → emissive flash trigger), `MTF_AliasPresetApi`, `MTF_AliasSkyrimNet`,
  and `MTF_SpidApply` (the SPID-distribution MGEF script) — so each alias/MGEF
  attachment bound to a missing `.pex` and silently no-op'd at runtime. All are
  now staged (`mtf.skyrimnet.json` + the four scripts).

### Changed

- **Build hardening — packaging-omission gates.** `tools/fomod/build_fomod.sh`
  now runs two coverage gates after staging and fails the build loudly on a gap:
  a source→stage check (every git-tracked file under `data/` and `content-packs/`
  must be staged or explicitly excluded) and a VMAD check (every script an ESP
  binds must have its `.pex` staged). Together they close the class of
  silent-omission bug behind every "never staged" fix above.

## [v0.4.1] — 2026-06-07

A compatibility fix. Drop-in over v0.4.0; no schema or save changes.

### Fixed

- **Fertility Mode (original / non-Reloaded) pregnancy & ovulation conditions.**
  The Fertility Mode adapter's `pregnancy` and `ovulation` conditions only fired
  on Fertility Mode *Reloaded* (which encodes the fertility state in an
  `ImmersiveEffectsFaction` rank); on the original Fertility Mode, which has no
  such faction, they silently never fired. They now read the same state directly
  off Fertility Mode's `_JSW_BB_Storage` arrays — pregnancy progress from
  `LastConception` / `PregnancyDuration`, a viable egg from `LastOvulation`
  (egg age) vs `EggLife` — matching FM 3.x's own logic. Reloaded is unchanged.

### Changed

- FOMOD: the Fertility Mode option is relabeled from "Fertility Mode Reloaded"
  to "Fertility Mode" (original or Reloaded — both supported).

## [v0.4.0] — 2026-06-06

The biggest feature wave since launch: the effect catalog is now split into
toggleable themed modules, a Dragonborn fantasy pack lands, and a new
actor-attached ambient light, on-hit retaliation, and vitals-drain effects
join the roster. Drop-in over the v0.3.x line — existing presets and saves
migrate automatically (the old `mtf.base:<id>` keys are rewritten to the new
themed-module keys on load).

### Added

- **Themed module split.** The monolithic `mtf.base` catalog is now five
  self-registering core modules — **Attributes**, **Combat**, **Magic**,
  **World**, and **FX** — each its own toggleable pack. Mix and match the
  thematic groups you want without touching the rest.
- **Dragonborn module.** A new themeable pack of Thu'um / dragon-soul
  reactive conditions you can toggle on its own: *Voice on Cooldown*,
  *Shout Equipped*, *Shout Learned*, *Word of Power Unlocked*, *Unspent
  Dragon Souls*, and *Dragon Soul Absorbed* (fires for a window right after
  a soul lands).
- **Ambient light effect.** *Ambient Light* (FX module) attaches an
  invisible, flicker-free light that follows the actor — no visible orb,
  smooth movement. Radius, brightness, and **colour** are tunable per tier
  (colour via a new MCM colour-picker control). Light tuning is a soft
  dependency on **po3's Papyrus Extender** — the effect still toggles
  without it, just at the base light's fixed radius/colour.
- **On-hit retaliation effects** (Combat): *Ragdoll on Hit* and *Fire /
  Frost / Shock Damage on Hit* strike back at attackers when the actor is
  struck (player-only).
- **Vitals drain effects** (Attributes): *Drain Health / Magicka / Stamina*
  continuously bleed a current attribute while the tier is active, with a
  menu/sleep/load-pause guard so paused time isn't billed as play time.
- **SPID distributor add-on.** An optional plugin that auto-distributes MTF
  content via Spell Perk Item Distributor.
- **Community Overlays 1 (Body) adapter.** FOMOD now wires in a catalog for
  Community Overlays 1 body overlays.

### Internal / dev

- Self-test battery expanded to **76/104** automated F10 checks (was mostly
  skipped): drain dt-cap regression, ambient-light signature, burst damage,
  on-hit flag roundtrip, `time.range`, `shout.equipped`, and a spawn-based
  combat/follower trio.

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

[v0.4.3]: https://www.nexusmods.com/skyrimspecialedition/mods/180775
[v0.4.2]: https://www.nexusmods.com/skyrimspecialedition/mods/180775
[v0.4.1]: https://www.nexusmods.com/skyrimspecialedition/mods/180775
[v0.4.0]: https://www.nexusmods.com/skyrimspecialedition/mods/180775
[v0.3.0]: https://www.nexusmods.com/skyrimspecialedition/mods/180775
