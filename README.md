# Magic Tattoos Framework

**State-reactive tattoo overlays with gameplay effects for Skyrim SE/AE.**

Magic Tattoos Framework (MTF) turns body tattoos into living things.
Instead of static decals, your tattoos fade in based on what your
character is doing, feeling, or wearing — and they can *do something*
while they're visible. A glowing sigil that brightens as your magicka
drains. A frost rune that pulses during combat. A mark that blooms at
night and fades by day. Pack authors define the art, the triggers, and
the gameplay effects; the framework handles the layering, fading,
persistence, and integration with the rest of your mod list.

It ships with no tattoos of its own — it's the engine. Drop in a content
pack (or several), pick which slots are active in MCM, and your
character starts wearing a reactive canvas.

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Components](#components)
- [SkyrimNet integration](#skyrimnet-integration)
- [For authors: building content packs](#for-authors-building-content-packs)
- [Building from source](#building-from-source)
- [Repository layout](#repository-layout)
- [Credits](#credits)
- [License](#license)
- [Heritage](#heritage)

---

## Features

- **Layered, fading visuals.** Tattoos render through SKEE / NiOverride
  overlay slots, fade smoothly between tiers, and survive armor swaps,
  body 3D rebuilds, and BodyGen.
- **Reactive conditions out of the box.** The base framework ships with
  triggers for health / magicka / stamina percentage, combat state,
  sneaking, mounted, swimming, time of day, weather, location type,
  worn armor, carry weight, current weapon, and more — composable per
  tier.
- **In-game effects out of the box.** Tiers can apply effects while
  visible: scale spell cost across all magic schools, modify actor
  values and skills, grant abilities and resistances, adjust speed and
  carry weight, trigger one-shot bursts (stagger, flash on hit), play
  shaders and sounds, and more.
- **Integrates with your other mods.** MTF auto-detects supported mods
  at runtime and exposes their state as additional conditions and
  effects — no INI toggles, no hard masters, no extra setup. Without
  these mods MTF still works fully; with them, pack authors get a much
  richer trigger palette.
- **Per-slot preset library.** Pack authors can ship multiple looks per
  tattoo; users can mix, override, and save their own from the MCM.
- **Cooldown state machine.** Each tier has a *persist* phase (tattoo
  stays for N minutes after activation, with optional override-lock)
  and a *cool* phase (next activation blocked for N minutes). Both
  range from seconds to a full in-game week.
- **SkyrimNet bridge.** If [SkyrimNet] is installed, MTF exposes every
  visible tattoo (with rendered condition and effect descriptions) into
  the LLM character-bio prompt, so AI companions actually notice what's
  on your skin. NPC reactions and player narration ride SkyrimNet's
  Event Configuration UI.
- **NPC-tracked subjects.** Apply MTF presets to specific NPCs via a
  console-driven path (or other mod integrations); they evaluate
  independently from the player.
- **MCM-driven.** Everything is configurable in-game — per-slot
  opacity, tier thresholds, preset selection, integration toggles,
  cooldown timers.

[SkyrimNet]: https://www.nexusmods.com/skyrimspecialedition/mods/130000

---

## Requirements

### Hard dependencies (required)

- SKSE64 (matching your Skyrim version)
- Address Library for SKSE Plugins
- PapyrusUtil SE
- RaceMenu (includes SKEE / NiOverride)
- SkyUI

### Soft dependencies (optional — auto-detected, no setup)

| Mod | Provides |
|-----|----------|
| Fertility Mode Reloaded (FMR) | pregnancy / ovulation conditions |
| SexLab Aroused (SLA) / OSL Aroused | arousal condition + exposure / aura effects |
| SexLab Framework SE | scene / animation / orgasm conditions |
| OStim Standalone | scene / excitement conditions |
| Beeing Female NG | pregnancy / cycle conditions |
| SlaveTats | bidirectional bridge — MTF tattoos appear in SlaveTats's polling API |
| SkyrimNet | LLM-readable tattoo descriptions in character-bio prompts |

Built for Skyrim Special Edition / Anniversary Edition. VR
compatibility is best-effort — overlays render fine, but VR-specific
quirks (skeleton, camera) are not specifically tested.

---

## Installation

1. Install all **hard requirements** above first. Launch the game once
   to confirm they work.
2. Install **Magic Tattoos Framework** with your mod manager (Vortex /
   MO2). Place it after RaceMenu in your load order.
3. Install one or more **MTF content packs** (e.g. *LewdMarks*,
   *RX Overlays*). Packs are standalone mods that depend on MTF.
4. *(Optional)* Install any of the supported integration mods listed
   above — MTF will auto-detect them at runtime; no manual switches.
5. Launch a **new save** (recommended) or load an existing one. Open
   **MCM → Magic Tattoos Framework** to assign slots, browse presets,
   and configure SkyrimNet output if you use it.

All framework ESPs are flagged ESL — zero regular-plugin slots
consumed.

---

## Components

### Framework plugins

| Mod | ESP | Required | Provides |
|-----|-----|----------|----------|
| **Magic Tattoos Framework** | `MagicTattoosFramework.esp` (ESL) | base | core engine, MCM, built-in conditions (magicka / stamina / combat / hits / location / weather / etc.), built-in effects (drains, stagger, magic cost penalty, shader play, sound play, flash on hit, skill / AV / resist modifiers) |
| **MTF Plugin — FMR** | `MTF_Plugin_FMR.esp` (ESL) | optional | pregnancy / ovulation conditions from Fertility Mode Reloaded |
| **MTF Plugin — SLA** | `MTF_Plugin_SLA.esp` (ESL) | optional | arousal condition + exposure / aura effects from SexLab Aroused |
| **MTF Plugin — SexLab** | `MTF_Plugin_SexLab.esp` (ESL) | optional | scene / animation / orgasm conditions from SexLab Framework |
| **MTF Plugin — OStim** | `MTF_Plugin_OStim.esp` (ESL) | optional | scene / excitement conditions from OStim Standalone |
| **MTF Plugin — BFNG** | `MTF_Plugin_BFNG.esp` (ESL) | optional | pregnancy / cycle conditions from Beeing Female NG |
| **MTF Plugin — SlaveTats Bridge** | `MTF_Plugin_SlaveTats.esp` (ESL) | optional | ghost-writes MTF tattoos into SlaveTats's state store so polling consumers (`has_tattoo` / `query_applied_tattoos`) see them |
| **MTF Plugin — SkyrimNet** | `MTF_Plugin_SkyrimNet.esp` (ESL) | optional | LLM-readable tattoo descriptions: registers `mtf_active_tattoos` decorator + fires `mtf_tattoo_change` events on tier transitions |

### Texture pack adapters (JSON-only — source textures installed separately)

| Adapter | Source mod (user must install) | Area |
|---|---|---|
| **MTF Content — LewdMarks** | LewdMarks (RaceMenu + SlaveTats variants) by SavageDomain | Body |
| **MTF Content — Obi Tattoos** | Obi's Tattoos for RaceMenu by Obi | Body |
| **MTF Content — RX Overlays** | RX Overlays (texture pack) | Body |
| **MTF Content — Bardle Nail Polish** | Bard's Nail Overlays by Bardledorf | Hands |
| **MTF Content — Community Overlays 1 Face** | Community Overlays 1 — Female Face Overlays | Face |

The base mod ships with no content; install at least one adapter (or
run effects-only by picking *"(no texture)"* per slot in the MCM).

See [`content-packs/README.md`](content-packs/README.md) for adapter
internals and the wrapping recipe.

---

## SkyrimNet integration

When `MTF_Plugin_SkyrimNet.esp` is loaded alongside SkyrimNet, MTF:

- **Exposes tattoos to the LLM.** Every currently-visible tattoo is
  rendered into the `mtf_active_tattoos` decorator (visible in
  SkyrimNet's character-bio prompts), with anatomy-aware placement
  labels (e.g. "right buttock", "collarbone") and rendered condition /
  effect descriptions.
- **Fires `mtf_tattoo_change` events on tier transitions.** Both
  player and NPC events fire. The events are routed through
  SkyrimNet's short-lived event queue with the tattoo bearer as
  `sourceActor`. NPC reactions and player narration are enabled /
  cooldowned via SkyrimNet's standard **Event Configuration** page
  (the event auto-uses SkyrimNet's global reaction defaults).
- **Live updates.** The decorator content is pre-rendered to
  StorageUtil on every mutation (apply / remove / tier shift) and
  re-read by the prompt on each warmup, bypassing SkyrimNet's
  decorator cache.

The prompt template ships at
`SKSE/Plugins/SkyrimNet/prompts/submodules/character_bio/0350_mtf_tattoos.prompt`
via the FOMOD's SkyrimNet step.

---

## For authors: building content packs

A **texture pack adapter** is a JSON catalog under
`Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/` that
points MTF at textures provided by another mod. No ESP, no plugin slot.

See [`content-packs/README.md`](content-packs/README.md) for the layout
and [`docs/tattoo_packs.md`](docs/tattoo_packs.md) for the wrapping
recipe (install source mod → identify texture root → generate catalog →
package as MO2 mod).

For **gameplay-effect presets** (curated combinations of tattoo +
conditions + effects), the preset format lives at
`Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/`.
Example presets live under [`test-pack/`](test-pack/) — including
multi-area, multi-tier, pulse, and integration-driven presets.

For **new integration plugins** (binding MTF onto a new soft-master
mod's API), see the existing `source/scripts/MTF_Plugin_*.psc` files
as templates. Each integration soft-probes a sentinel form ID from its
master ESP at runtime; if the master isn't loaded the plugin skips
registration.

---

## Building from source

### Papyrus scripts

```bash
bash tools/build_scripts.sh
```

Compiles all `source/scripts/*.psc` with Caprica into
`source/scripts/*.pex`, deploying compiled `.pex` files into the dev
MO2 mods folder. Vanilla Skyrim script headers used as compile-time
references live in `_deps/`.

### C++ SKSE companion plugin (optional)

The `cpp-plugin/` subproject contains **MTFPulse**, an SKSE plugin
that owns the per-frame pulse animation loop (offloaded from Papyrus
for performance with many tracked actors). Built via xmake / vcpkg /
CommonLibSSE-NG. See [`cpp-plugin/README.md`](cpp-plugin/README.md)
for build details.

### FOMOD installer

```bash
bash tools/fomod/build_fomod.sh
```

Output: `_build/MagicTattoosFramework-FOMOD-<version>.7z`. Bundles
base MTF + all 7 integration plugins + texture pack adapters + the
SkyrimNet prompt template + optional extras (NPC overlays helper, test
pack). See [`tools/fomod/README.md`](tools/fomod/README.md) for the
layout and how to add new integrations.

---

## Repository layout

```
.
├── MagicTattoosFramework.esp      ← base mod
├── MTF_Plugin_*.esp               ← integration plugins (7 ESLs)
├── source/scripts/                ← Papyrus source (.psc)
├── data/SKSE/Plugins/             ← shipped MCM config, waveform JSONs
├── content-packs/                 ← texture pack adapters (JSON-only)
├── cpp-plugin/                    ← MTFPulse SKSE plugin (C++)
├── test-pack/                     ← smoke-test presets
├── docs/                          ← user-facing docs
│   └── internal/                  ← dev-facing notes (CLAUDE.md, IDEAS.md, NEXUS draft)
├── tools/                         ← build scripts, FOMOD assembler
├── _deps/                         ← vanilla Skyrim script headers (compile refs)
└── _build/                        ← build outputs (gitignored)
```

---

## Credits

- **expired6978** — RaceMenu and SKEE / NiOverride, the overlay
  backbone everything renders through.
- **Exiledviper & meh321** — PapyrusUtil, without which none of the
  per-actor state persistence would be sane.
- **schlangster & the SkyUI team** — MCM, still the gold standard.
- **Ousnius & Caliente** — BodySlide / OutfitStudio and the BHUNP /
  CBBE ecosystems that make body overlays possible.
- **Mutagen team (Spriggit), MatortheEternal (xEdit / xEditLib),
  Orvid (Caprica), Orvid / Centurion (Champollion)** — the modding
  toolchain that made authoring this mod tractable.
- The authors of **Beeing Female NG, Fertility Mode Reloaded, OStim
  Standalone, SexLab, SexLab Aroused, SlaveTats, and SkyrimNet** —
  for stable, scriptable APIs that made integration a matter of
  soft-probing a form ID rather than reverse-engineering anything.
- **SavageDomain** — original LewdMarks content; MTF originated as
  LewdMarks Effects before being generalized.
- Everyone in the LL and Nexus modding threads who answered "why does
  my overlay disappear after armor swap" patiently enough times that
  the answer made it into this framework.

---

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE).

---

## Heritage

Originated as **LewdMarks Effects**, based on LewdMarks Aroused by
SavageDomain. Generalized in v0.0.23 into a content-agnostic framework;
FMR / SLA plugins split into separate ESL addons in v0.0.24. Multi-area
overlays (Face / Hands / Feet) landed in v0.1.17. SlaveTats bidirectional
bridge in v0.1.19. SkyrimNet LLM integration in v0.1.20.
