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

| Mod | ESP | Required | Provides |
|-----|-----|----------|----------|
| **Magic Tattoos Framework** | `MagicTattoosFramework.esp` (ESL) | base | core engine, MCM, built-in conditions (magicka/stamina/combat/hits), built-in effects (drains, stagger, magic cost penalty) |
| **MTF Plugin — FMR** | `MTF_Plugin_FMR.esp` (ESL) | optional | pregnancy / ovulation conditions from Fertility Mode |
| **MTF Plugin — SLA** | `MTF_Plugin_SLA.esp` (ESL) | optional | arousal condition + exposure/aura effects from SexLab Aroused |
| **MTF Content — LewdMarks** | — (no ESP) | optional | example pack: JSON catalogs for LewdMarks RaceMenu / SlaveTats textures |

All three framework ESPs are flagged ESL — zero regular-plugin slots consumed.
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

## Distribution

A FOMOD installer that bundles base MTF + the 5 integration plugins +
JSON-only texture-pack adapters + optional extras (NPC overlays helper,
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
