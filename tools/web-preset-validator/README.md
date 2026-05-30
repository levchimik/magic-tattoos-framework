# MTF Preset Validator (web)

A single-page, pure-browser tool that validates a
[Magic Tattoos Framework](https://github.com/levchimik/magic-tattoos-framework)
preset JSON against the in-game `LoadPreset` schema and, on success,
packages it into a ready-to-install ZIP.

**Live:** https://levchimik.github.io/magic-tattoos-framework/preset-validator/

## What it does

1. Paste or drop a `.json` preset file.
2. The tool runs the same shape/range/typo checks the in-game
   `MTF_MainQuest.SavePreset` / `LoadPreset` pair enforces — schema version,
   exactly 8 slots, per-slot `cond` / `persist` / `cool` / `pulse` /
   `layer[0..4]` / `effect[0..32]`, color hex format, range bounds, effect
   `key` shape (`pluginid:effectid`), and unknown-field typo catching.
3. Errors block the download. Warnings flag legacy fields that the loader
   silently ignores (e.g. pre-schema-8 `cooldown` block, pre-v0.2.1
   `extras` block) — fine to install, but cruft.
4. On `0 errors`, click **Download installable ZIP**: you get
   `MTF-Preset-<sanitized-displayname>.zip` containing one file at
   `SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/<name>.json`.
5. Drop the ZIP into MO2 / Vortex's "Install from archive". The preset
   appears in the in-game MTF MCM list on next save / load.

## Filename derivation

The output filename inside the ZIP comes from `displayname`, sanitized
the same way the in-game `_sanitizePresetName` does it: anything outside
`A-Z a-z 0-9 _ -` becomes `_`, capped at 32 characters. So
`"My Cycle Preset (v2)"` → `My_Cycle_Preset__v2_.json`. The displayname
in the JSON itself is left untouched — only the filename is sanitized.

## Schema reference

The validator targets schema version `8` (current as of v0.2.x). It still
accepts presets from schema 4..7 with a warning, since the in-game loader
does too. Anything older fails. The full source-of-truth schema lives in
[`source/scripts/MTF_MainQuest.psc`](../../source/scripts/MTF_MainQuest.psc) —
search for `SavePreset` / `LoadPreset`.

## Local development

```bash
firefox tools/web-preset-validator/index.html
# or, to avoid file:// quirks:
cd tools/web-preset-validator && python -m http.server 8000
```

JSZip 3.10.1 is vendored under `vendor/jszip.min.js` and is the only
runtime dependency.

## Layout

```
tools/web-preset-validator/
├── index.html              ← page shell (paste box + drop zone + report)
├── app.js                  ← ES module: validator + ZIP packager
├── style.css               ← matches the pack-builder's dark UI
├── vendor/jszip.min.js     ← JSZip 3.10.1
└── README.md               ← this file
```

## Deploy

GitHub Pages auto-deploys this directory on every push to `main` via
[`.github/workflows/pages.yml`](../../.github/workflows/pages.yml).
The pack-builder lives at the site root; this validator lives at
`/preset-validator/`.
