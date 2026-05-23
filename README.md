# Magic Tattoos Framework

Skyrim SE/AE framework for dynamic, condition-driven tattoo overlays with
gameplay effects.

Pack authors ship a JSON catalog of tattoos (under
`Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/`); the
framework renders them via NiOverride with per-layer tint/emissive/alpha,
switches them based on configurable conditions, and dispatches gameplay
effects per slot.

Up to 7 condition slots + 1 default slot. Each slot has its own pack/entry,
per-layer visuals, condition trigger, cooldown, and up to 4 effects with
per-effect parameters.

## Components

### Plugins

| Mod | ESP | Required | Provides |
|-----|-----|----------|----------|
| **Magic Tattoos Framework** | `MagicTattoosFramework.esp` (ESL) | base | core engine, MCM, built-in conditions (magicka/stamina/combat/hits), built-in effects (drains, stagger, magic cost penalty, shader.play, sound.play, flash.onhit, skill modifiers) |
| **MTF Plugin — FMR** | `MTF_Plugin_FMR.esp` (ESL) | optional | pregnancy / ovulation conditions from Fertility Mode |
| **MTF Plugin — SLA** | `MTF_Plugin_SLA.esp` (ESL) | optional | arousal condition + exposure/aura effects from SexLab Aroused |
| **MTF Plugin — SexLab** | `MTF_Plugin_SexLab.esp` (ESL) | optional | scene/animation/orgasm conditions from SexLab Framework |
| **MTF Plugin — OStim** | `MTF_Plugin_OStim.esp` (ESL) | optional | scene/excitement conditions from OStim |
| **MTF Plugin — BFNG** | `MTF_Plugin_BFNG.esp` (ESL) | optional | pregnancy / cycle conditions from Beeing Female |
| **MTF Plugin — SlaveTats Bridge** | `MTF_Plugin_SlaveTats.esp` (ESL) | optional | ghost-writes MTF tattoos into SlaveTats's state store so polling consumers (`has_tattoo` / `query_applied_tattoos`) see them. Universal — works for all pack roots; safety relies on SlaveTats's own `external_slots` detection and a one-time `.SlaveTats.version` preset to dodge `upgrade_tattoos`' first-touch wipe |
| **MTF Plugin — SkyrimNet** | `MTF_Plugin_SkyrimNet.esp` (ESL) | optional | LLM-readable tattoo descriptions: registers `mtf_active_tattoos` decorator, surfaces visible tattoos in SkyrimNet character_bio prompts |

### Texture-pack adapters (JSON only — source textures installed separately)

| Adapter | Source mod | Provides |
|---|---|---|
| **MTF Content — LewdMarks** | LewdMarks (RaceMenu + SlaveTats) by SavageDomain | example pack; the original LewdMarks content extracted into a JSON catalog |
| **MTF Content — Bardle Nail Polish** | Bardle Nail Polish (texture-only) | nail polish overlays |
| **MTF Content — Obi Tattoos** | Obi Tattoos | extra body tattoo set |
| **MTF Content — RX Overlays** | RX Overlays | extra body tattoo set |
| **MTF Content — Community Overlays 1 Face** | Community Overlays 1 Face | face-area overlays |

All framework ESPs are flagged ESL — zero regular-plugin slots consumed.
The base mod ships with no content; install at least one content pack (or
run effects-only by picking "(no texture)" per slot in the MCM).

## Requirements

**Base mod:**
- RaceMenu / SKEE (NiOverride)
- PapyrusUtil (StorageUtil + JsonUtil)
- (Optional) A tattoo content pack. "MTF Content — LewdMarks" ships
  separately and references LewdMarks RaceMenu/SlaveTats textures by
  SavageDomain. Without any pack the framework still runs — pick
  "(no texture)" per slot to use it as an effects-only condition driver.

**Optional addons:**
- Fertility Mode Reloaded (for `MTF_Plugin_FMR.esp`)
- SexLab Aroused / OSL Aroused (for `MTF_Plugin_SLA.esp`)
- SexLab Framework (for `MTF_Plugin_SexLab.esp`)
- OStim (for `MTF_Plugin_OStim.esp`)
- Beeing Female (for `MTF_Plugin_BFNG.esp`)
- SlaveTats (for `MTF_Plugin_SlaveTats.esp` bridge)
- SkyrimNet (for `MTF_Plugin_SkyrimNet.esp` LLM integration)

## Distribution

A FOMOD installer that bundles base MTF + the 7 integration plugins +
5 JSON-only texture-pack adapters + optional extras (NPC overlays helper,
test pack) lives at `tools/fomod/`. Rebuild with:

```bash
bash tools/fomod/build_fomod.sh
```

Output is `_build/MagicTattoosFramework-FOMOD-<version>.7z`. The installer
auto-detects each integration's master plugin (`SexLab.esm`, `OStim.esp`, etc.)
and pre-recommends only the addons whose dependencies are present. See
`tools/fomod/README.md` for the layout and how to add new integrations.

Texture pack adapters ship JSON catalogs only — the source mods (LewdMarks,
Bard's Nail Overlays, Community Overlays 1 Face, etc.) provide the .dds
textures and must be installed separately.

## Heritage

Originated as `LewdMarks Effects`, based on LewdMarks Aroused by SavageDomain.
Generalised in v0.0.23 into a content-agnostic framework; FMR/SLA plugins
split into separate ESL addons in v0.0.24.
