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

**Download:** [Magic Tattoos Framework on Nexus Mods][nexus]

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Components](#components)
- [SkyrimNet integration](#skyrimnet-integration)
- [Extending MTF](#extending-mtf)
- [Building from source](#building-from-source)
- [Repository layout](#repository-layout)
- [Credits](#credits)
- [License](#license)
- [Heritage](#heritage)

---

## Features

- **Layered, fading visuals.** Tattoos render through RaceMenu's overlay
  system, fade smoothly between states, and survive armor changes, body
  swaps, and BodyGen rebuilds.
- **Reactive conditions out of the box.** The base framework ships with
  triggers for health / magicka / stamina percentage, combat state,
  sneaking, mounted, swimming, time of day, weather, location type,
  worn armor, carry weight, current weapon, and more. Each slot can
  combine **multiple conditions** with an **AND** (all must pass) or
  **OR** (any passes) match mode.
- **In-game effects out of the box.** While a tattoo is visible, it can
  apply effects: scale spell costs, modify stats and skills, grant
  abilities and resistances, adjust speed and carry weight, trigger
  one-shot bursts (stagger, flash on hit), play shaders and sounds, and
  more.
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
- **SkyrimNet bridge.** If [SkyrimNet] is installed, MTF tells it about
  every visible tattoo — what it looks like, when it appears, and what
  it does — so AI-driven characters actually notice and can comment on
  what's on your skin. NPC reactions and player narration ride
  SkyrimNet's Event Configuration UI.
- **Works on NPCs too.** A Papyrus API (`MTF_AliasPresetApi`) lets other
  mods apply MTF presets to specific NPCs; each NPC's tattoos react to
  their own state, independently of the player.
- **MCM-driven.** Everything is configurable in-game — per-slot
  transparency, trigger thresholds, preset selection, integration
  toggles, cooldown timers.

---

## Requirements

### Hard dependencies (required)

- [SKSE64][skse] (matching your Skyrim version)
- [Address Library for SKSE Plugins][addrlib]
- [PapyrusUtil SE][papyrusutil]
- [RaceMenu][racemenu] (includes SKEE / NiOverride)
- [SkyUI][skyui]

### Soft dependencies (optional — auto-detected, no setup)

| Mod | Provides |
|-----|----------|
| [Fertility Mode Reloaded][fmr] (FMR) | pregnancy / ovulation conditions |
| [OSL Aroused][osla] | arousal condition + exposure / aura effects |
| [SexLab Framework SE][sexlab] | scene / animation / orgasm conditions |
| [OStim Standalone][ostim] | scene / excitement conditions |
| [Beeing Female NG][bfng] | pregnancy / cycle conditions |
| [SlaveTats][slavetats] | bidirectional bridge — MTF tattoos appear in SlaveTats's polling API |
| [SkyrimNet][skyrimnet] | LLM-readable tattoo descriptions in character-bio prompts |

Built for Skyrim Special Edition / Anniversary Edition. VR
compatibility is best-effort — overlays render fine, but VR-specific
quirks (skeleton, camera) are not specifically tested.

---

## Installation

1. Install all **hard requirements** above first. Launch the game once
   to confirm they work.
2. Install **[Magic Tattoos Framework][nexus]** with your mod manager
   (Vortex / MO2). Place it after RaceMenu in your load order.
3. Install one or more **MTF content packs** (e.g. *[LewdMarks][lewdmarks]*,
   *[RX'Overlays][rxoverlays]*). Packs are standalone mods that depend on MTF.
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
| **MTF Plugin — FMR** | `MTF_Plugin_FMR.esp` (ESL) | optional | pregnancy / ovulation conditions from [Fertility Mode Reloaded][fmr] |
| **MTF Plugin — SLA** | `MTF_Plugin_SLA.esp` (ESL) | optional | arousal condition + exposure / aura effects from [OSL Aroused][osla] (ESP keeps the `SLA` name for back-compat) |
| **MTF Plugin — SexLab** | `MTF_Plugin_SexLab.esp` (ESL) | optional | scene / animation / orgasm conditions from [SexLab Framework SE][sexlab] |
| **MTF Plugin — OStim** | `MTF_Plugin_OStim.esp` (ESL) | optional | scene / excitement conditions from [OStim Standalone][ostim] |
| **MTF Plugin — BFNG** | `MTF_Plugin_BFNG.esp` (ESL) | optional | pregnancy / cycle conditions from [Beeing Female NG][bfng] |
| **MTF Plugin — SlaveTats Bridge** | `MTF_Plugin_SlaveTats.esp` (ESL) | optional | ghost-writes MTF tattoos into [SlaveTats][slavetats]'s state store so polling consumers (`has_tattoo` / `query_applied_tattoos`) see them |
| **MTF Plugin — SkyrimNet** | `MTF_Plugin_SkyrimNet.esp` (ESL) | optional | LLM-readable tattoo descriptions: writes each actor's visible-tattoo bio block to StorageUtil for the character-bio prompt + fires `mtf_tattoo_change` events on tier transitions ([SkyrimNet][skyrimnet]) |

### Texture pack adapters (JSON-only — source textures installed separately)

| Adapter | Source mod (user must install) | Area |
|---|---|---|
| **MTF Content — LewdMarks** | [LewdMarks][lewdmarks] (RaceMenu + SlaveTats variants) by SavageDomain | Body |
| **MTF Content — RX Overlays** | [RX'Overlays][rxoverlays] (texture pack) | Body |
| **MTF Content — Bardle Nail Polish** | [Bard's Nail Overlays][bardnails] by BinkBoink | Hands |
| **MTF Content — Community Overlays 1 Face** | [Community Overlays 1][commover1] — Female Face Overlays | Face |

The base mod ships with no content; install at least one adapter (or
run effects-only by picking *"(no texture)"* per slot in the MCM).

See [`content-packs/README.md`](content-packs/README.md) for adapter
internals and the wrapping recipe.

---

## SkyrimNet integration

When `MTF_Plugin_SkyrimNet.esp` is loaded alongside SkyrimNet, MTF:

- **Exposes tattoos to the LLM.** Every currently-visible tattoo is
  rendered into the actor's character-bio prompt, with anatomy-aware
  placement labels (e.g. "right buttock", "collarbone") and rendered
  condition / effect descriptions. The bio block is pre-rendered to
  StorageUtil and read back by the prompt template each warmup
  (bypassing SkyrimNet's decorator cache so mid-session changes show).
- **Fires `mtf_tattoo_change` events on tier transitions.** Both
  player and NPC events fire. The events are routed through
  SkyrimNet's short-lived event queue with the tattoo bearer as
  `sourceActor`. NPC reactions and player narration are enabled /
  cooldowned via SkyrimNet's standard **Event Configuration** page
  (the event auto-uses SkyrimNet's global reaction defaults).
- **Live updates.** The bio block is refreshed on every mutation
  (apply / remove / tier shift), so what the LLM reads always matches
  the tattoos currently on the actor.

The prompt template ships at
`SKSE/Plugins/SkyrimNet/prompts/submodules/character_bio/0350_mtf_tattoos.prompt`
via the FOMOD's SkyrimNet step.

---

## Extending MTF

Three ways to extend the framework, in order of how much you have to
write:

### 1. Author a gameplay-effect preset (no code, JSON only)

A **preset** is a curated combination of tattoo + conditions + effects
saved to JSON under
`Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/`.
Users pick presets from the MCM dropdown; pack authors can ship
multiple looks per tattoo for users to remix.

Build them in-game via the MCM preset editor (recommended), or hand-
author the JSON directly. Example presets covering multi-area,
multi-tier, pulse, and integration-driven flows live under
[`test-pack/`](test-pack/) — read those for the schema.

### 2. Wrap a new texture pack as a content pack (no code, JSON only)

A **texture pack adapter** is a JSON catalog that points MTF at
overlay textures from another mod (RaceMenu overlays, SlaveTats packs,
nail / face overlays). No ESP, no plugin slot, no scripting.

**Quick path — [Web Pack Builder][packbuilder]** (recommended for
single-layer packs): drop a Skyrim mod archive (`.zip` / `.7z` / `.rar`
/ `.tar`), fill in three fields, get back an MO2-ready ZIP with the
catalog wired up. 100% client-side, no upload. Best for Community
Overlays / SlaveTats / nail overlay packs.

**→ Full guide: [`docs/CONTENT_PACKS.md`](docs/CONTENT_PACKS.md)**

Covers the JSON schema, MO2 mod layout, FOMOD bundling, in-game
testing, multi-layer packs (base + glow), and the optional
description / placement / style tag fields the LLM bridge consumes.

### 3. Write an integration plugin (Papyrus + tiny ESP)

An **integration plugin** binds MTF onto another mod's runtime state,
exposing it as conditions (e.g. "when arousal > 50") and effects (e.g.
"boost arousal", "grant a buff"). This is how MTF integrates with FMR,
SLA, SexLab, OStim, BFNG, SlaveTats, and SkyrimNet today.

**→ Full guide: [`docs/INTEGRATION_PLUGINS.md`](docs/INTEGRATION_PLUGINS.md)**

Covers the plugin lifecycle, soft-master pattern, complete vtable
reference for conditions / effects / extras / settings, ESP setup,
common pitfalls (the `onDeactivate` footgun, the suspending-call race,
the post-release Auto-property trap), testing, and links to every
existing plugin as a working reference.

---

## Building from source

### ESPs

```bash
bash tools/build_esps.sh
```

Binary `.esp` files are **not committed to git** — only Spriggit YAML
mirrors under [`spriggit/`](spriggit/). This script deserializes every
plugin folder under `spriggit/<PluginName>/` back into a real `.esp`
binary under `_build/esps/`. The FOMOD build runs it automatically;
run it manually before testing in-game if you're working from a fresh
clone (you'll also need to copy the `.esp` files out of `_build/esps/`
into your MO2 / Vortex mod folder, or symlink them).

Requires [Spriggit][spriggit] CLI (`dotnet tool install -g Spriggit.CLI`).

To edit an ESP record, do **not** open the binary in CK. Instead, edit
the YAML directly (e.g. `spriggit/MagicTattoosFramework/Quests/MTF_MainQuest - 000803_MagicTattoosFramework.esp.yaml`),
then re-run `bash tools/build_esps.sh` to regenerate the binary. Diffs
stay human-readable and review-friendly.

### Papyrus scripts

```bash
bash tools/build_scripts.sh
```

Compiles all `source/scripts/*.psc` with [Caprica][caprica] into
`source/scripts/*.pex`, deploying compiled `.pex` files into the dev
MO2 mods folder. Vanilla Skyrim script headers used as compile-time
references live in `_deps/`.

### C++ SKSE companion plugin (optional)

The `cpp-plugin/` subproject contains **MTFPulse**, an SKSE plugin
that owns the per-frame pulse animation loop (offloaded from Papyrus
for performance with many tracked actors). Built via CMake / vcpkg /
CommonLibSSE-NG. See [`cpp-plugin/README.md`](cpp-plugin/README.md)
for build details.

### FOMOD installer

```bash
MTF_VERSION=v0.3.0 bash tools/fomod/build_fomod.sh
```

This is the full release pipeline: it rebuilds the ESPs **and** the
MTFPulse.dll, stages every component, runs the `release_check.sh`
pre-ship gate (aborts before archiving on any shipping defect), and
writes `_build/MagicTattoosFramework-FOMOD-<version>.7z`. Bundles base
MTF + all 7 integration plugins + texture pack adapters + the SkyrimNet
prompt template + optional extras (NPC overlays helper, test pack). See
[`tools/fomod/README.md`](tools/fomod/README.md) for the layout and how
to add new integrations.

### Portable paths

The build scripts auto-derive the repo root from their own location, so
no editing is needed if you move the repo. Machine-specific locations
are environment-overridable:

| Var | Default | Purpose |
|-----|---------|---------|
| `MTF_PROJ` | auto-derived | repo root |
| `MTF_MO2_MODS` | dev modlist | MO2 `mods` folder (deploy target) |
| `MTF_CAPRICA` | bundled path | `Caprica.exe` (Papyrus compiler) |
| `MTF_FLAGS` | game path | Papyrus `.flg` flags file |
| `MTF_VERSION` | latest commit/tag | FOMOD version label |
| `MTF_SKIP_DLL` | unset | `=1` reuse existing DLL (skip C++ build) |
| `MTF_SKIP_CHECK` | unset | `=1` skip the release_check gate |

---

## Repository layout

```
.
├── spriggit/                      ← Spriggit YAML mirrors of every ESP
│   ├── MagicTattoosFramework/     ← base mod records (MGEFs, Spells, Quests, …)
│   └── MTF_Plugin_*/              ← integration-plugin Quest shells (7 ESLs)
├── source/scripts/                ← Papyrus source (.psc)
├── data/SKSE/Plugins/             ← shipped MCM config, waveform JSONs
├── content-packs/                 ← texture pack adapters (JSON-only)
├── cpp-plugin/                    ← MTFPulse SKSE plugin (C++)
├── test-pack/                     ← smoke-test presets
├── docs/                          ← user-facing docs
│   └── internal/                  ← dev-facing notes (CLAUDE.md, IDEAS.md, NEXUS draft)
├── tools/                         ← build scripts (build_esps.sh, build_scripts.sh), FOMOD assembler
├── _deps/                         ← vanilla Skyrim script headers (compile refs)
└── _build/                        ← build outputs incl. _build/esps/*.esp (gitignored)
```

---

## Credits

- **expired6978** — [RaceMenu][racemenu] and SKEE / NiOverride, the
  overlay backbone everything renders through.
- **Exiledviper & meh321** — [PapyrusUtil][papyrusutil], without which
  none of the per-actor state persistence would be sane.
- **schlangster & the SkyUI team** — [SkyUI][skyui] / MCM, still the
  gold standard.
- **Ousnius & Caliente** — [BodySlide / Outfit Studio][bodyslide] and
  the BHUNP / CBBE ecosystems that make body overlays possible.
- **Mutagen team ([Spriggit][spriggit]), MatortheEternal
  ([xEdit][xedit] / [xEditLib][xeditlib]), Orvid ([Caprica][caprica]),
  Orvid / Centurion ([Champollion][champollion])** — the modding
  toolchain that made authoring this mod tractable.
- The authors of **[Beeing Female NG][bfng], [Fertility Mode
  Reloaded][fmr], [OStim Standalone][ostim], [SexLab][sexlab],
  [OSL Aroused][osla], [SlaveTats][slavetats], and
  [SkyrimNet][skyrimnet]** — for stable, scriptable APIs that made
  integration a matter of soft-probing a form ID rather than
  reverse-engineering anything.
- **SavageDomain** — original [LewdMarks][lewdmarks] content; MTF
  originated as LewdMarks Effects before being generalized.
- Everyone in the LL and Nexus modding threads who answered "why does
  my overlay disappear after armor swap" patiently enough times that
  the answer made it into this framework.

---

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE).

---

## Heritage

Originated as **LewdMarks Effects**, based on [LewdMarks Aroused][lewdmarksaroused]
by SavageDomain. Generalized in v0.0.23 into a content-agnostic
framework; FMR / SLA plugins split into separate ESL addons in v0.0.24.
Multi-area overlays (Face / Hands / Feet) landed in v0.1.17. SlaveTats
bidirectional bridge in v0.1.19. SkyrimNet LLM integration in v0.1.20.

---

<!-- Reference-style link definitions -->

[nexus]: https://www.nexusmods.com/skyrimspecialedition/mods/180775
[packbuilder]: https://levchimik.github.io/magic-tattoos-framework/

[skse]: https://skse.silverlock.org/
[addrlib]: https://www.nexusmods.com/skyrimspecialedition/mods/32444
[papyrusutil]: https://www.nexusmods.com/skyrimspecialedition/mods/13048
[racemenu]: https://www.nexusmods.com/skyrimspecialedition/mods/19080
[skyui]: https://www.nexusmods.com/skyrimspecialedition/mods/12604

[fmr]: https://www.nexusmods.com/skyrimspecialedition/mods/165569
[osla]: https://www.nexusmods.com/skyrimspecialedition/mods/65454
[sexlab]: https://www.loverslab.com/files/file/5868-sexlab-framework-se-164b/
[ostim]: https://www.nexusmods.com/skyrimspecialedition/mods/98163
[bfng]: https://www.nexusmods.com/skyrimspecialedition/mods/168434
[slavetats]: https://www.loverslab.com/files/file/383-slavetats/
[skyrimnet]: https://github.com/MinLL/SkyrimNet-GamePlugin

[lewdmarks]: https://www.nexusmods.com/skyrimspecialedition/mods/83786
[lewdmarksaroused]: https://www.nexusmods.com/skyrimspecialedition/mods/83794
[rxoverlays]: https://www.nexusmods.com/skyrimspecialedition/mods/166670
[bardnails]: https://www.nexusmods.com/skyrimspecialedition/mods/126211
[commover1]: https://www.nexusmods.com/skyrimspecialedition/mods/22487

[bodyslide]: https://www.nexusmods.com/skyrimspecialedition/mods/201
[xedit]: https://www.nexusmods.com/skyrimspecialedition/mods/164
[xeditlib]: https://github.com/matortheeternal/xedit-lib
[spriggit]: https://github.com/Mutagen-Modding/Spriggit
[caprica]: https://github.com/Orvid/Caprica
[champollion]: https://github.com/Orvid/Champollion
