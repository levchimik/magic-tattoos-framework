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

## Heritage

Originated as `LewdMarks Effects`, based on LewdMarks Aroused by SavageDomain.
Generalised in v0.0.23 into a content-agnostic framework; FMR/SLA plugins
split into separate ESL addons in v0.0.24.
