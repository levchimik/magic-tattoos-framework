# MTF Content Pack Builder (web)

A single-page, pure-browser tool that converts a Skyrim texture mod ZIP
into a [Magic Tattoos Framework](https://github.com/levchimik/magic-tattoos-framework)-ready
content pack ZIP.

**Live:** https://levchimik.github.io/magic-tattoos-framework/

## What it does

1. You fill in three fields: `packId`, display label, area (`Body` /
   `Face` / `Hands` / `Feet`).
2. You drop a Skyrim mod ZIP — the kind that has `textures/...*.dds`
   at the root (same shape as any Nexus download).
3. The tool walks every `.dds` it finds, generates an MTF catalog JSON,
   and emits a new ZIP containing the original textures unchanged plus
   the catalog at the right path:
   ```
   SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/<packid>.json
   ```
4. You drag the output ZIP into MO2 / Vortex's "Install from archive"
   the same way you'd install any mod.

100% client-side via [JSZip](https://stuk.github.io/jszip/). No upload,
no server, no telemetry.

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
firefox tools/web-pack-builder/index.html

# Or serve over HTTP (avoids file:// drag-drop weirdness on some browsers):
cd tools/web-pack-builder
python -m http.server 8000
# → http://localhost:8000/
```

## Layout

```
tools/web-pack-builder/
├── index.html               ← page shell + form + drop zone
├── app.js                   ← ZIP parse, catalog build, output ZIP compose
├── style.css                ← dark UI, minimal
├── vendor/
│   └── jszip.min.js         ← JSZip 3.10.1 (MIT/GPLv3 dual-licensed)
└── README.md                ← this file
```

## Deploy

GitHub Pages auto-deploys this directory on every push to `main` via
[`.github/workflows/pages.yml`](../../.github/workflows/pages.yml).
Local edits land at https://levchimik.github.io/magic-tattoos-framework/
within ~1 minute of `git push`.

## Updating JSZip

JSZip is pinned at v3.10.1 (vendored). To bump:

```bash
curl -sL https://cdn.jsdelivr.net/npm/jszip@<NEW>/dist/jszip.min.js \
    -o tools/web-pack-builder/vendor/jszip.min.js
```

Smoke-test by dropping a known pack ZIP and confirming the JSON output
matches the existing catalog format (compare against
`content-packs/community-overlays-1-face/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/mtf.community-overlays-1-face.json`).
