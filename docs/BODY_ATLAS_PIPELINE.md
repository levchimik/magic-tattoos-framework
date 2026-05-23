# Body Atlas Pipeline

A one-time calibration that maps every UV region of the CBBE/3BA body texture to
its anatomical location. Once built, the lookup resolves any future tattoo's
alpha-centroid into "left buttock", "right collarbone", "lower abdomen below
navel", etc. — automatically and across all body-overlay content packs (RX,
Obi, LewdMarks, and any future pack on the same body UV).

This document captures the data and tools so any future session (or anyone
inheriting this project) can use the atlas without redoing the calibration.

## What this solves

Body-overlay textures (.dds files registered via SlaveTats or RaceMenu) paint
onto the body via the CBBE/3BA body UV unwrap. Each tattoo's design lives at
some (x, y) position in a 4096×4096 canvas, which maps to *some* anatomical
location on the body — but the mapping isn't visible from the texture alone:

- The body UV is non-trivial (front + back + arms + legs all packed into
  one 4K texture with separate UV islands).
- L/R sides of the body are at different canvas positions (not mirrored).
- Some canvas regions don't map to body at all (hand UV ends up at unrelated
  texture coordinates if the body atlas is applied).

Pre-atlas, every placement string was hand-authored from label-based guesses
and the front-only CBBE diffuse render. **The Boob Dragons / Butt Butterflies /
Butt Cat session showed those guesses were systematically wrong** — we had
"across both X" descriptions for what were really single-spot designs, and
got L/R sides flipped on multiple entries.

With the atlas calibrated, every entry can be auto-checked: feed its layer
texture into the resolver, get back the anatomical region + confidence.

## How it works

1. **Calibration texture** — a 4096×4096 RGBA with a 5×5 grid of distinctly
   colored, labeled cells (A1–E5). Subdivided cells (D3 chest, A3 buttocks,
   E3 lower abdomen, D1 right thigh-fold, D5 left thigh-fold) get 2×2
   sub-cells (a/b/c/d). Total: 40 distinct regions.

2. **Apply in-game** — registered as a SlaveTats entry under "MTF Calibration".
   When applied to the player character, the colored patchwork covers the body,
   each cell visibly landing on a specific anatomical region.

3. **Photograph** — front / back / left / right screenshots (plus close-ups
   of subdivided regions) capture which cell maps to which body part. Each
   cell has its label baked into the texture so identification is unambiguous
   even at partial visibility.

4. **Build lookup** — `cells_to_anatomy.json` records the 4096-canvas bbox of
   each cell + sub-cell with its anatomical region and L/R side.

5. **Resolve** — `mtf_atlas_resolver.py` takes a tattoo's layer PNG, finds the
   largest connected ink cluster, computes its alpha-weighted centroid, and
   looks up the matching cell. Returns the anatomy + flags multi-cluster or
   off-body-UV cases.

6. **Diff report** — `mtf_atlas_diff_report.py <packId>` runs the resolver
   over every entry in a pack JSON, compares to the current placement string,
   and surfaces mismatches.

## File locations

### In the MTF repo (committed)
- `docs/BODY_ATLAS_PIPELINE.md` — this document
- `docs/VISUAL_REFS_PIPELINE.md` — companion doc for the per-tattoo combined
  render pipeline
- `docs/atlas/cells_to_anatomy.json` — **canonical backup of the lookup**
  (the working copy under `tools/mtf-vision-cache/` is gitignored; if the
  cache is wiped, restore from here)
- `docs/atlas/atlas_5x5_sub_legend.json` — programmatic cell→color map
- `docs/atlas/atlas_5x5_sub_legend.png` — small visual reference grid

### In the Skyrim modding workspace (`F:/stuff/Skyrim modding/`)
- `tools/build_anatomy_atlas.py` — generates the calibration PNG + legend
- `tools/mtf_atlas_resolver.py` — alpha-cluster → anatomy lookup
- `tools/mtf_atlas_diff_report.py` — pack-level placement audit
- `tools/mtf-vision-cache/atlas/` — cache outputs (gitignored)
  - `anatomy_atlas_5x5_sub.png` (4096×4096 source)
  - `anatomy_atlas_5x5_sub.dds` (BC3, deployed copy)
  - `atlas_5x5_sub_legend.png` (small reference grid)
  - `atlas_5x5_sub_legend.json` (programmatic cell→color map)
  - `cells_to_anatomy.json` — **the authoritative lookup**

### In the MO2 modlist (deployed for in-game use)
- `mods/Magic Tattoos Framework/Textures/Actors/Character/slavetats/calibration/anatomy_atlas_5x5_sub.dds`
- `mods/Magic Tattoos Framework/Textures/Actors/Character/slavetats/calibration.json`
  — registers the atlas as a SlaveTats entry under "MTF Calibration"

## The cell → anatomy lookup (snapshot of `cells_to_anatomy.json`)

40 regions total. Subdivided cells: **D3** (central chest), **A3** (buttocks),
**E3** (lower abdomen), **D1** (right thigh-fold), **D5** (left thigh-fold).
**Logical-only** sub-cells (no separate color, just bbox in JSON): **C3-left** /
**C3-right** for L/R shoulder blade disambiguation.

Key anatomical anchors:

| Cell | Region | Side |
|---|---|---|
| A3a | sacrum / lumbar right side | right |
| A3b | sacrum / lumbar left side | left |
| A3c | **right buttock** | right |
| A3d | **left buttock** | left |
| A4 | lumbar / lower-back centerline | centered |
| B3 | upper-back center / between shoulder blades | centered |
| C3-right | right shoulder area (front collarbone OR back blade) | right |
| C3-left | left shoulder area (front collarbone OR back blade) | left |
| D1a–D1d | right buttock-fold + right outer thigh (vertical slices) | right |
| D3a | upper chest above **right** nipple / right collarbone | right |
| D3b | upper chest above **left** nipple / left collarbone | left |
| D3c | **right breast** / right under-breast | right |
| D3d | **left breast** / left under-breast | left |
| D2 | non-body UV region (hand back; off-body) | n/a |
| D4 | front of left thigh / outer left thigh | left |
| D5a–D5d | left buttock-fold + left outer thigh (vertical slices) | left |
| E2 | right upper-outer thigh / right hip-thigh junction | right |
| E3a | lower abdomen just below navel, right side | right |
| E3b | lower abdomen just below navel, left side | left |
| E3c | pubic mound / right hip / very low abdomen | right |
| E3d | pubic mound / left hip / very low abdomen | left |
| E5 | left upper-outer thigh / left hip-thigh junction | left |

## Calibration rules discovered

These are non-obvious facts the calibration revealed; if the atlas is ever
rebuilt from scratch, expect to rediscover them:

- **Canvas-X mapping**: low canvas X → character's RIGHT anatomy; high
  canvas X → character's LEFT. Holds across A3/D3/E3/D1/D5 — consistent
  with how the body UV mirrors the two halves.
- **Navel sits at the D3 / E3 boundary** (y = 3277). All of E3 is *below*
  the navel; E3a/E3b are just below the navel, E3c/E3d are at the pubic mound.
- **Nipples sit at the D3 horizontal midline** (y = 2867). A tattoo "around
  the nipple" has its bbox straddling D3a↔D3c (right) or D3b↔D3d (left).
- **Back UV is vertically inverted relative to the front**: canvas-A row
  (y = 0–819) = lower back / buttocks; canvas-C row (y = 1638–2458) = upper
  back / shoulder blades / nape. So canvas-up ≠ body-up for the back half.
- **C3 wraps the shoulder ring**: includes both front-of-shoulder (collarbone,
  upper chest near shoulder) AND back-of-shoulder (shoulder blade, nape).
  Found while debugging Chest StarsLeft.
- **D1 / D5 are dual-region cells**: each spans both lower-buttock fold and
  upper outer thigh on its side. Use the 2×2 sub-cells to disambiguate.
- **D2 is off-body UV**: the canvas position for D2 maps to the hand UV
  (verified via Hand Stars). Tattoos whose centroids land here are likely
  hand-only designs or multi-cluster artifacts.
- **Filename L/R labels are unreliable — trust the atlas, not the file
  name.** Many pack authors label files by *viewer-perspective when looking
  at the texture in their editor* ("R" = right side of the canvas image),
  which corresponds to the character's **anatomical LEFT** once the UV is
  wrapped on the model. Confirmed via Lyru / Bitchcraft packs where the
  resolver consistently inverted the filename's L/R; in-game verification
  agreed with the atlas. Example: `LyruRoseThighL` — filename says left,
  but the design (centroid at canvas (1010, 2948), fallback → D1d) lands on
  the character's anatomical **right** thigh in-game, matching the atlas.
  Rule for any audit: when filename and resolver disagree on side,
  **the resolver wins**.
- **Some "lateral" designs land at D2 with body-mapped overlap** — Side /
  outer-thigh / lateral-hip designs sometimes have their alpha centroid fall
  inside the off-body D2 cell because their ink occupies the canvas gap
  between body UV islands but their bbox extends into adjacent body cells.
  The resolver's `_is_off_body` fallback promotes the largest body-mapped
  overlap to primary with an `[centroid off-body — placement inferred from
  overlap]` flag. LyruRoseThighL confirms this fallback works: centroid in
  D2, but the D1b/D1d (right outer thigh) overlap matched the in-game
  rendering. Treat flag-bearing entries as "atlas best-effort"; visual
  verification is still wise but the fallback is usually correct.

## Re-running

To rebuild the atlas (if cells_to_anatomy.json is lost or needs refinement):

```bash
# Generate the calibration PNG + legend
cd "F:/stuff/Skyrim modding"
python tools/build_anatomy_atlas.py

# Convert PNG → BC3 DDS
tools/texconv/texconv.exe -ft dds -y -f BC3_UNORM \
  -o tools/mtf-vision-cache/atlas \
  tools/mtf-vision-cache/atlas/anatomy_atlas_5x5_sub.png

# Deploy DDS into the SlaveTats-readable path on MO2
cp tools/mtf-vision-cache/atlas/anatomy_atlas_5x5_sub.dds \
   "F:/Modlists/Modding Essentials/mods/Magic Tattoos Framework/Textures/Actors/Character/slavetats/calibration/"

# Full Skyrim restart required if calibration.json wasn't already registered.
# Then in-game: SlaveTats MCM → Body Tattoos → Section 1 → MTF Calibration.
```

## To verify a pack

```bash
python tools/mtf_atlas_diff_report.py mtf.rx-overlays   # 41 entries
python tools/mtf_atlas_diff_report.py mtf.obi-tattoos   # 18 entries
python tools/mtf_atlas_diff_report.py mtf.lewdmarks-slavetats  # 96 entries
```

Output is markdown. "MISMATCH" rows are the actionable cases (placement string
disagrees with resolver's anatomy category). "?" rows have multi-cluster ink
that the resolver flags as ambiguous.

## To resolve a single tattoo

```python
import sys
sys.path.insert(0, 'tools')
from mtf_atlas_resolver import resolve_layer, summarize

result = resolve_layer('tools/mtf-vision-cache/render-by-id/mtf.rx-overlays/_layers/Boob_Dragons__L0.png')
print(summarize(result))
# → centroid=D3a: upper chest / right collarbone (above right nipple) [right]
#   | overlaps=D3a, D3c, D2
```

## What's NOT covered

- **Hands UV** (Bardle nail polish) — different unwrap, needs its own atlas
- **Face UV** — likely useful eventually
- **Feet UV** — no current pack uses it
- **Body 3D mesh deformation** (large body sliders) — the atlas was calibrated
  on default CBBE proportions; extreme sliders may shift UV samples slightly
  but the anatomical mapping is stable enough for placement descriptions.

## Historical note

This pipeline was built in a single session (2026-05-22). The atlas calibration
data is irrecoverable without re-running the in-game screenshot workflow, so
preserving `cells_to_anatomy.json` is the highest priority. If that file is
ever lost, rebuild via: deploy DDS → apply in-game → screenshot front/back/
left/right + close-ups of subdivided regions → manually transcribe back into
the JSON.
