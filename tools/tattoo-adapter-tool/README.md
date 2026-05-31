# MTF Tattoo Adapter Tool (web)

A single-page, pure-browser tool that converts a Skyrim overlay mod
archive into a [Magic Tattoos Framework](https://github.com/levchimik/magic-tattoos-framework)-ready
adapter ZIP (a thin pointer pack — the textures stay in the source mod).

**Live:** https://levchimik.github.io/magic-tattoos-framework/

## What it does

1. You drop a Skyrim mod archive — `.zip`, `.7z`, `.rar`, `.tar`, or
   `.tar.gz`/`.xz`/`.bz2`. The tool auto-fills the form by parsing the
   filename: `ZAO Active Overlays 0.3 SE-39407-…7z` →
   label `ZAO Active Overlays`, packId `mtf.zao-active-overlays`.
2. (Optional) Tweak `packId`, display label, or area (`Body` / `Face`
   / `Hands` / `Feet`) — area defaults to Body.
3. The tool lists every `.dds` under `textures/` (auto-detecting
   `Data/textures/…` and arbitrary wrapper directories like
   `ZAO Pack/Data/Textures/…`), generates an MTF catalog JSON.
4. You click download and get a thin **ZIP** containing just one file:
   ```
   SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/<packid>.json
   ```
5. Drag the ZIP into MO2 / Vortex's "Install from archive". End users
   need both this pack AND the original texture mod active — MTF reads
   textures by their `Data/textures/...` path, not from inside the
   pack ZIP itself.

This pointer-only model matches every shipping pack under the
framework's [`content-packs/`](../../content-packs/) directory and
sidesteps redistribution / permission concerns.

**Read** is via [libarchive.js](https://github.com/nika-begiashvili/libarchivejs)
(a WASM port of libarchive — same C library 7-Zip ports use). **Write**
is via [JSZip](https://stuk.github.io/jszip/). 100% client-side, no
upload, no telemetry.

## What it doesn't do (yet)

- **No preview.** Browsers can't render `.dds` natively; the tool
  doesn't try. Test in-game.
- **No auto-pair for multi-layer packs.** Packs like LewdMarks ship a
  base directory + a parallel `-glow/` directory; the tool emits one
  entry per DDS. Open the generated JSON and merge layers manually
  (just nest the second `{ "texture": "..." }` object inside the same
  entry's `layers` array — see [CONTENT_PACKS.md](../../docs/CONTENT_PACKS.md)).
- **No label prettifier.** Entry labels default to the bare filename
  stem (`001.dds` → `"001"`). Open the JSON and edit if you want
  prettier MCM display names.
- **No description / placement / style tags.** Those are pack-author
  metadata and the tool intentionally stays out of authorship decisions.
  See the [content pack schema](../../docs/CONTENT_PACKS.md) for the
  full set of optional fields you can add by hand.

## Local development

It's a single static page with one dependency vendored under
`vendor/jszip.min.js`. No build step.

```bash
# Just open the file:
firefox tools/tattoo-adapter-tool/index.html

# Or serve over HTTP (avoids file:// drag-drop weirdness on some browsers):
cd tools/tattoo-adapter-tool
python -m http.server 8000
# → http://localhost:8000/
```

## Layout

```
tools/tattoo-adapter-tool/
├── index.html                       ← page shell + form + drop zone
├── app.js                           ← ES module: archive read, catalog build,
│                                     output ZIP compose
├── style.css                        ← dark UI, minimal
├── vendor/
│   ├── jszip.min.js                 ← JSZip 3.10.1 (output ZIP writer)
│   └── libarchive/
│       ├── libarchive.js            ← v2.0.2 ES module entry (Archive class)
│       ├── worker-bundle.js         ← Web Worker that runs libarchive
│       └── libarchive.wasm          ← 1 MB WASM port of libarchive
└── README.md                        ← this file
```

The four files under `vendor/libarchive/` must stay together — the
worker resolves `libarchive.wasm` relative to its own URL, and
`libarchive.js` resolves the worker the same way.

## Deploy

GitHub Pages auto-deploys this directory on every push to `main` via
[`.github/workflows/pages.yml`](../../.github/workflows/pages.yml).
Local edits land at https://levchimik.github.io/magic-tattoos-framework/
within ~1 minute of `git push`.

## Updating vendored dependencies

JSZip 3.10.1:
```bash
curl -sL https://cdn.jsdelivr.net/npm/jszip@<NEW>/dist/jszip.min.js \
    -o tools/tattoo-adapter-tool/vendor/jszip.min.js
```

libarchive.js 2.0.2 — all four files together:
```bash
V=<NEW>
D=tools/tattoo-adapter-tool/vendor/libarchive
curl -sL "https://cdn.jsdelivr.net/npm/libarchive.js@${V}/dist/libarchive.js"       -o "$D/libarchive.js"
curl -sL "https://cdn.jsdelivr.net/npm/libarchive.js@${V}/dist/worker-bundle.js"    -o "$D/worker-bundle.js"
curl -sL "https://cdn.jsdelivr.net/npm/libarchive.js@${V}/dist/libarchive.wasm"     -o "$D/libarchive.wasm"
```

Smoke-test by dropping at least one ZIP and one 7z and confirming the
JSON output matches the existing catalog format (compare against
`content-packs/community-overlays-1-face/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/mtf.community-overlays-1-face.json`).
