# Visual References Pipeline

How the per-entry PNGs under `docs/visual-refs/<packId>/` are generated. These
images are the ground truth that drives every `tags`/`description` field in
the `visuals/*.json` pack files — without them, descriptions devolve into
label-based speculation that doesn't survive in-game inspection.

`docs/visual-refs/` is gitignored (large binary churn) but is rebuildable
from this pipeline at any time.

## What each PNG shows

Side-by-side combined view per tattoo entry:

```
┌──────────────────────────────┬──────────────────────────────┐
│ PLACEMENT (body)             │ DESIGN (stencil)             │
│                              │                              │
│   CBBE femalebody_1 diffuse  │   Alpha-union → black ink    │
│   with the entry's alpha     │   on white, cropped to the   │
│   painted on as red (#E51E2A)│   ink bbox + 8% padding,     │
│   at ~85% opacity            │   gamma-boosted (0.35) so    │
│                              │   thin lines pop solid.      │
│   "Where it lands on a body" │   "What the design is"       │
└──────────────────────────────┴──────────────────────────────┘
```

Both panes share the same source texture; the left pane uses the body
diffuse as a UV-aware backdrop, and the right pane is a flat stencil at the
design's native aspect ratio.

## Pipeline

```
┌────────────────────┐   texconv     ┌────────────────────┐   PIL
│  .dds (overlay     │ ────────────► │  .png  (alpha-     │ ──────►  combined PNG
│   texture, 1K–4K)  │  -ft png -y   │   preserved RGBA,  │  composite
│                    │  -w 2048      │   2048×2048)       │  --mode combined
└────────────────────┘  -h 2048      └────────────────────┘
                                                          ▲
                                                          │
                                          ┌───────────────┴──────────────┐
                                          │  Body reference PNG          │
                                          │  (femalebody_1 or            │
                                          │   femalehands_1 for nails)   │
                                          └──────────────────────────────┘
```

Stage 1 — **texconv** (`tools/texconv/texconv.exe`, Microsoft DirectXTex)
- Reads the source `.dds` (BC3_UNORM / BC7_UNORM, original 4096×4096 for most
  packs, 1024×1024 for Bardle nails)
- Forces output to 2048×2048 PNG with `-w 2048 -h 2048` so the stencil pane
  has enough pixels to render fine linework crisply
- Alpha channel preserved (RGBA PNG)

Stage 2 — **PIL composite** (`tools/mtf_vision_composite.py`, `--mode combined`)
- Loads all layers for the entry (some LewdMarks entries have two: base + glow)
- Unions the alpha channels across layers (`ImageChops.lighter`)
- Left pane: brightens body diffuse by 1.45×, contrast by 1.10×, stamps the
  alpha-union as red ink at ~85% opacity over the body
- Right pane: applies gamma 0.35 to the alpha-union (boosts low-alpha thin
  lines toward solid), stamps black through it on a white sheet, crops to
  bbox + 8% padding, resizes height to match body pane (native aspect ratio
  preserved — no width cap, so wide RX overlays stay sharp)
- Joins with a 4-px grey divider, burns in `PLACEMENT (body)` / `DESIGN
  (stencil)` labels in the top-left of each pane

Stage 3 — **driver** (`tools/mtf_vision_render_by_id.py`)
- Walks every `content-packs/*/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/*.json`
- For each entry: resolves the texture path (case-insensitive fs walk)
  against `SOURCE_ROOTS[packId]`, runs texconv per layer, then composite
- Writes `OUT_ROOT/<packId>/combined/<safeId>.png` + an
  `OUT_ROOT/<packId>/index.json` mapping entry id → filename so downstream
  tools (writer subagents, the apply-patches script) iterate without
  re-inferring filenames
- `safeId = re.sub(r'[^A-Za-z0-9._-]', '_', id)` — RX uses spaces in ids
  (e.g. `"ArmL Turtle"`) which become `ArmL_Turtle` on disk

The current `OUT_ROOT` is `tools/mtf-vision-cache/render-by-id/` (anchored
on the script's own location via `Path(__file__).parent`; no hardcoded user
or temp paths). The whole `tools/mtf-vision-cache/` tree is gitignored.
After rendering, the `<packId>/combined/` subtree is copied into
`docs/visual-refs/<packId>/`.

## Inputs

### Source textures (`SOURCE_ROOTS` in `mtf_vision_render_by_id.py`)

| Pack | Source |
|------|--------|
| `mtf.lewdmarks-slavetats`, `mtf.lewdmarks-racemenu` | BSA-extracted into `tools/mtf-vision-cache/lewdmarks-extracted/textures` (one-time `AutoMod archive extract`) |
| `mtf.obi-tattoos` | `F:/Modlists/Modding Essentials/mods/Obi's Tattoos 3BA 4K/textures` (loose .dds) |
| `mtf.rx-overlays` | `F:/Modlists/Modding Essentials/mods/RX'Overlays - Racemenu Tattoo and Overlays for 3BA/textures` (loose .dds) |
| `mtf.bardle-nail-polish` | `F:/Modlists/Modding Essentials/mods/Bard's Nail Overlays/textures` (loose .dds) |

### Body-UV references (`BODY_REF` in `mtf_vision_render_by_id.py`)

| Pack | Reference |
|------|-----------|
| LewdMarks, Obi, RX | `tools/mtf-vision-cache/png/body/femalebody_1.png` — vanilla CBBE diffuse |
| Bardle nails | `tools/mtf-vision-cache/png/body/femalehands_1.png` — vanilla CBBE hands diffuse |

**Known limitation:** the body diffuse used in the left pane only shows the
front of the body in CBBE/vanilla UV layout. Tattoos that land on the back,
arms, or legs may not be readable from the body pane alone — for those, the
right (design) pane plus the stencil's position within the full 2048-px UV
canvas is the only reliable placement signal. When in doubt, defer to the
mod author's intended placement (Nexus page screenshots) rather than the
body pane.

## Re-running

To rebuild everything:

```bash
# 1. (one-time) extract LewdMarks BSAs into the cache
#    Skip if already done.
bash tools/automod-cli.sh archive extract \
  "F:/Modlists/Modding Essentials/mods/MTF Content - LewdMarks/LewdMarks.bsa" \
  --output "F:/stuff/Skyrim modding/tools/mtf-vision-cache/lewdmarks-extracted" --json

# 2. (one-time) extract a CBBE body diffuse to use as the UV reference.
#    Any femalebody_1.png from a CBBE/3BA mod will do.

# 3. Drive the renderer. Optional positional args skip listed packs.
python tools/mtf_vision_render_by_id.py
# or to skip the heavy LewdMarks pass:
python tools/mtf_vision_render_by_id.py mtf.lewdmarks-slavetats mtf.lewdmarks-racemenu

# 4. Copy the freshly rendered combined PNGs into docs/visual-refs/.
for pack in mtf.lewdmarks-slavetats mtf.lewdmarks-racemenu mtf.obi-tattoos mtf.rx-overlays mtf.bardle-nail-polish; do
  mkdir -p "F:/stuff/MagicTattoosFramework/docs/visual-refs/$pack"
  cp "F:/stuff/Skyrim modding/tools/mtf-vision-cache/render-by-id/$pack/combined/"*.png \
     "F:/stuff/MagicTattoosFramework/docs/visual-refs/$pack/"
done
```

To re-render a single pack's textures after a mod update, delete the
relevant `OUT_ROOT/<packId>/_layers/*.png` so texconv re-runs against the
fresh .dds, then re-execute the driver.

## File counts (snapshot)

| Pack | Entries | Combined PNGs |
|------|--------:|--------------:|
| `mtf.lewdmarks-slavetats` | 96 | 96 |
| `mtf.lewdmarks-racemenu`  | 96 | 96 (mirror of slavetats — same source textures) |
| `mtf.obi-tattoos`         | 18 | 18 |
| `mtf.rx-overlays`         | 42 | 42 |
| `mtf.bardle-nail-polish`  | 16 | 16 |
| **Total** | **268** | **268** |

## Why this matters

The `tags` and `description` fields in each `visuals/*.json` are served to
SkyrimNet via the `MTF_Plugin_SkyrimNet` bridge, where they become in-scene
context for NPC dialogue. Wrong descriptions become wrong NPC reactions in
RP scenes. Without the visual-refs pipeline, descriptions are guesswork
from label strings like "Mark 073" or "ArmL Turtle" — names alone don't
carry the design content.

## Related scripts

- `tools/mtf_vision_composite.py` — PIL compositor (flat / stencil / body / combined modes)
- `tools/mtf_vision_render_by_id.py` — driver: walks pack JSONs and runs texconv + composite
- `tools/mtf_vision_batch_render.sh` — older bash batch script (1024-px, legacy; superseded by the by-id driver)
- `tools/mtf_vision_apply_patches.py` — reads `patches/<packId>.json` produced by writer subagents and injects tags+description into the pack JSONs
- `tools/mtf_vision_regen_doc.py` — rebuilds `docs/DESCRIPTIONS_REVIEW.md` from current pack JSON state
