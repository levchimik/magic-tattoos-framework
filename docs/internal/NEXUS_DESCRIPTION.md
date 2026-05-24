# Magic Tattoos Framework

## Description

Magic Tattoos Framework (MTF) turns body tattoos into living things. Instead of static decals, your tattoos can fade in based on what your character is doing, feeling, or wearing — and they can do something while they're visible. A glowing sigil that brightens as your magicka drains. A frost rune that pulses during combat. A mark that blooms at night and fades by day. Pack authors define the art, the triggers, and the gameplay effects; the framework handles the layering, fading, persistence, and integration with the rest of your mod list.

It ships with no tattoos of its own — it's the engine. Drop in a content pack (or several), pick which slots are active in MCM, and your character starts wearing a reactive canvas.

## Installation Instructions

1. Install **all hard requirements** below first (SKSE64, Address Library, PapyrusUtil, RaceMenu/SKEE, SkyUI). Launch the game once to confirm they work.
2. Install **Magic Tattoos Framework** with your mod manager (Vortex / MO2). Place it after RaceMenu in your load order.
3. Install one or more **MTF content packs** (e.g. *LewdMarks*). Packs are standalone mods that depend on MTF.
4. *(Optional)* Install any of the supported integration mods listed under Requirements — MTF will auto-detect them at runtime; no manual switches needed.
5. Launch a **new save** (recommended) or load an existing one. Open MCM → Magic Tattoos Framework to assign slots, browse presets, and configure SkyrimNet output if you use it.

## Main Features

- **Layered, fading visuals.** Tattoos render through SKEE/NiOverride overlay slots, fade smoothly between tiers, and survive armor swaps, body 3D rebuilds, and BodyGen.
- **Reactive conditions out of the box.** The base framework ships with triggers for health/magicka/stamina percentage, combat state, sneaking, mounted, swimming, time of day, weather, location type, worn armor, carry weight, current weapon, and more — composable per tier.
- **In-game effects out of the box.** Tiers can apply effects while visible: scale spell cost across all magic schools, modify actor values and skills, grant abilities and resistances, adjust speed and carry weight, and more.
- **Integrates with your other mods.** MTF auto-detects supported mods at runtime and exposes their state as additional conditions and effects — no INI toggles, no hard masters, no extra setup. Without these mods MTF still works fully; with them, pack authors get a much richer trigger palette.
- **Stacked presets.** Per-slot preset library lets pack authors ship multiple looks per tattoo; users can mix, override, and save their own in MCM.
- **SkyrimNet bridge.** If SkyrimNet is installed, MTF exposes every visible tattoo (with rendered condition and effect descriptions) to the LLM prompt, so AI companions actually notice what's on your skin.
- **MCM-driven.** Everything is configurable in-game: per-slot opacity, tier thresholds, preset selection, and integration toggles.

## Requirements

**Hard dependencies (required):**
- SKSE64 (matching your Skyrim version)
- Address Library for SKSE Plugins
- PapyrusUtil SE
- RaceMenu (includes SKEE/NiOverride)
- SkyUI

**Soft dependencies (optional — auto-detected, no setup):**
- BeeingFemale NG
- Fertility Mode Redux
- OStim Standalone
- SexLab Framework SE
- SexLab Aroused (SLA)
- SlaveTats
- SkyrimNet

Built for Skyrim Special Edition / Anniversary Edition. VR compatibility is best-effort — overlays render fine, but VR-specific quirks (skeleton, camera) are not specifically tested.

## Shout Outs

- **expired6978** — RaceMenu and SKEE/NiOverride, the overlay backbone everything renders through.
- **Exiledviper & meh321** — PapyrusUtil, without which none of the per-actor state persistence would be sane.
- **schlangster & the SkyUI team** — MCM, still the gold standard.
- **Ousnius & Caliente** — BodySlide/OutfitStudio and the BHUNP/CBBE ecosystems that make body overlays possible.
- **Murilo Hoffmann (Spriggit), MatortheEternal (xEdit/xEditLib), Orvid (Caprica), Orvid/Centurion (Champollion)** — the modding toolchain that made authoring this mod tractable.
- The authors of **BeeingFemale NG, Fertility Mode Redux, OStim Standalone, SexLab, SexLab Aroused, SlaveTats, and SkyrimNet** — for stable, scriptable APIs that made integration a matter of soft-probing a form ID rather than reverse-engineering anything.
- Everyone in the LL and Nexus modding threads who answered "why does my overlay disappear after armor swap" patiently enough times that the answer made it into this framework.
