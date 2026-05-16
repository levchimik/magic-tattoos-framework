# Magic Tattoos Framework

Skyrim SE/AE framework for dynamic, condition-driven tattoo overlays with gameplay effects.

Pack authors ship a JSON catalog of tattoos (under
`Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/`); the
framework renders them with per-layer tint/emissive/alpha, switches them based
on configurable conditions, and can attach gameplay effects to each slot.

Up to 7 condition slots + 1 default slot, each with its own pack/entry/visual
configuration. Built-in condition plugins: Arousal (SLA), Pregnancy (FMR),
Ovulation (FMR), Magicka %, active Magic Effects, weapon-class hits.

## Requirements
- RaceMenu / SKEE (NiOverride) — required
- PapyrusUtil (StorageUtil + JsonUtil) — required
- Tattoo content pack of your choice (LewdMarks pack bundled as example)
- SexLab Aroused (optional, for Arousal condition)
- Fertility Mode Reloaded (optional, for Pregnancy/Ovulation conditions)

## Heritage

Originated as `LewdMarks Effects`, based on LewdMarks Aroused by SavageDomain.
Generalised in v0.0.23 into a content-agnostic framework.
