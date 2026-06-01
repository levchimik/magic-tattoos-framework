# Writing an MTF Content Pack

How to wrap an existing texture-overlay mod (RaceMenu overlays,
SlaveTats packs, face/hand/nail overlays) into a Magic Tattoos
Framework content pack so its tattoos can be picked in MCM, layered
with effects, faded between tiers, and dispatched as gameplay
triggers.

A content pack is **a single JSON file** plus a thin MO2 mod folder.
**No ESP, no plugin slot consumed, no scripting required.**

---

## Contents

- [What a content pack is](#what-a-content-pack-is)
- [JSON schema](#json-schema)
- [Mod folder layout](#mod-folder-layout)
- [Walkthrough: wrapping a real pack](#walkthrough-wrapping-a-real-pack)
- [Testing in-game](#testing-in-game)
- [Shipping](#shipping)
- [Troubleshooting](#troubleshooting)
- [Reference: existing adapters](#reference-existing-adapters)

---

## What a content pack is

MTF doesn't ship any of its own textures. It's a framework: the
visuals come from texture packs that other authors made — LewdMarks,
Community Overlays, RX'Overlays, Bard's Nail Overlays, etc.

A **content pack** (also called a **texture pack adapter**) is the
metadata file that tells MTF:

- Where the textures live in `Data/textures/...`
- Which textures form each named entry (a single tattoo is usually
  one or more layered .dds files — a base + an emissive/glow layer)
- Which body area each entry targets (Body, Face, Hands, Feet)
- A user-facing label, an LLM-readable description, and freeform
  tags for each entry

The textures themselves are **never** redistributed in the content
pack. The user must install the source mod separately. If you don't
have the source author's permission to ship a wrapper, keep it
local-only (gitignored) — see `.gitignore` in the project root for
the pattern.

---

## JSON schema

A content pack is a single JSON file at this path inside its MO2
mod folder:

```
SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/mtf.<packid>.json
```

The file's top level:

```json
{
  "schemaVersion": 3,
  "packId": "mtf.<short-pack-id>",
  "label": "Human-Readable Pack Name",
  "area": "Body",
  "entries": [ ... ]
}
```

### Top-level fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `schemaVersion` | int | yes | Current schema version is **3**. MTF rejects unknown versions. |
| `packId` | string | yes | Globally unique pack id. Convention: `mtf.<short-name>` (e.g. `mtf.lewdmarks-racemenu`). Must match the filename's `mtf.<packid>.json` portion. |
| `label` | string | yes | Display name shown in MCM's pack picker dropdown. |
| `area` | string | yes | One of `Body`, `Hands`, `Feet`. (`Face` is **not supported** — see the warning below.) Determines which NiOverride overlay-slot pool MTF writes to. Mixing areas in one pack is not supported — split into multiple packs. |
| `entries` | array | yes | One element per tattoo / overlay in the pack. |

> ### ⚠️ Face / facepaint / warpaint is NOT supported
>
> **MTF cannot drive face paint, war paint, or any `area: "Face"` content. Do not author Face packs.**
>
> Two independent engine walls make the face unusable, and we verified both empirically (2026-05-31):
>
> 1. **Face overlay textures must be transparent-background alpha masks** (DXT5/BC7 with a real alpha channel), exactly like body overlays. The common "head"/warpaint textures (e.g. Community Overlays 1's `## Head M.dds`) are **opaque DXT1 luminance masks** (white design on solid black, no alpha). Painted onto the NiOverride face overlay node they render as a **solid black face** — and SKEE exposes no blend mode to treat black as transparent.
>
> 2. **The vanilla tint-mask path can't be driven either.** Routing those luminance masks through Skyrim's warpaint *tint masks* (`Game.SetNthTintMaskColor` / `SetTintMaskTexturePath` / `UpdateTintMaskColors`) *does* render — but **`UpdateTintMaskColors` only fully re-composites the face from the input-handling phase** (e.g. an `OnKeyDown` keypress). From every automatic context MTF actually runs in — the OnUpdate tick, `RegisterForSingleUpdate`, or a mod-event handler — it re-composites **only when a tint slot's texture pointer changes**. So a tier-driven **color change on the same design is silently ignored**, and there is no way to trigger the input phase from automatic logic. Deferring via a mod-event hop and alternating tint slots were both tried; neither works.
>
> **Net:** the only face content that could ever render is alpha-channel overlays, and even then condition-driven recolouring is unreliable. Face is therefore out of scope. Use `Body` / `Hands` / `Feet` with proper alpha textures. All `*-warpaint` content packs (Community Overlays 1/2/3) have been removed for this reason.

### Per-entry fields

```json
{
  "id": "001",
  "label": "Mark 001",
  "layers": [
    { "texture": "actors\\character\\overlays\\lewdmarks\\001.dds" },
    { "texture": "actors\\character\\overlays\\lewdmarks-glow\\001.dds" }
  ],
  "tags": {
    "subject": "fertility sigil, central heart, curling fallopian arms",
    "style":   "tribal linework, bilateral symmetry",
    "placement": "lower abdomen above the pubic mound"
  },
  "description": "A tribal fertility sigil with a solid heart at the center..."
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Stable per-pack id. Used in preset JSON and StorageUtil keys. **Lowercase ASCII, no spaces, no colons.** Renaming an id breaks any existing preset that references it. |
| `label` | string | yes | Shown in MCM's per-entry picker. |
| `layers` | array | yes | One or more layer objects. Each layer renders as a separate NiOverride overlay (z-ordered), letting MTF independently tint / fade / pulse the base vs. emissive layers. Most packs have 1-2 layers. |
| `layers[].texture` | string | yes | Path **relative to `Data/textures/`** (so `actors\\character\\overlays\\foo\\001.dds`, not `textures\\actors\\character\\overlays\\foo\\001.dds`). Use `\\` (double-backslash) in JSON; the engine accepts both `/` and `\\`. |
| `tags.subject` / `tags.style` / `tags.placement` | string | recommended | Freeform tag fields consumed by the SkyrimNet bridge and bio renderers. Plain English, comma-separated phrases. |
| `description` | string | recommended | Full prose description (1-3 sentences) for LLM consumption. The SkyrimNet bridge surfaces this in NPC bio prompts so AI companions can react to specific tattoos by content, not just by name. |

### Optional per-entry fields

| Field | Type | Notes |
|---|---|---|
| `defaultTint` | string | Hex color (e.g. `"#FFAA00"`) applied to layer 0 if the preset doesn't specify a tint. Default white. |
| `defaultEmissive` | string | Hex color for the emissive layer (typically layer 1). |
| `defaultEmissiveMult` | float | 0.0–1.0 default emissive intensity. |
| `defaultAlpha` | int | 0–100 default alpha for layer 0. Default 100. |

These defaults only fire when the preset doesn't bind a value — they
let a pack ship a sensible look without requiring every preset to
specify color/alpha. They're useful for packs that have a strong
intended palette (e.g. neon glow tattoos).

---

## Mod folder layout

Once you have your JSON, package it as a standalone MO2 mod:

```
MTF Content - <Pack Name>/
└── SKSE/
    └── Plugins/
        └── StorageUtilData/
            └── MagicTattoosFramework/
                └── visuals/
                    └── mtf.<packid>.json
```

That's the entire mod. No ESP. No textures (those come from the
source mod the user installs separately). One JSON file at one path.

The filename and the `packId` field **must match** — if your JSON
says `"packId": "mtf.foo"`, the file must be `mtf.foo.json`. MTF
discovers packs by scanning the `visuals/` directory at startup; the
two paths feed into the same lookup.

---

## Walkthrough: wrapping a real pack

End-to-end example using a generic body-overlay mod called
"AcmeOverlays" with 24 .dds files at
`textures/actors/character/overlays/acme/acme_01.dds` ... `acme_24.dds`.

### 1. Install the source mod

Drop the source mod archive into MO2's Downloads, install, enable.
Confirm in MO2's right pane that the .dds files land at
`Data/textures/actors/character/overlays/acme/*.dds`.

### 2. Identify the texture root

`textures/actors/character/overlays/acme/` — note the path **without**
the `textures/` prefix (you'll strip that in the JSON).

### 3. Author the catalog JSON

```json
{
  "schemaVersion": 3,
  "packId": "mtf.acme-overlays",
  "label": "Acme Overlays",
  "area": "Body",
  "entries": [
    {
      "id": "acme_01",
      "label": "Acme 01",
      "layers": [
        { "texture": "actors\\character\\overlays\\acme\\acme_01.dds" }
      ],
      "tags": {
        "subject": "geometric tribal sleeve",
        "style":   "bold linework",
        "placement": "upper arm wrapping"
      },
      "description": "A bold geometric tribal sleeve wrapping the upper arm."
    },
    // ... 23 more entries
  ]
}
```

For 24 entries, hand-authoring is feasible. For 100+, a tiny script
that walks the texture directory and emits the JSON is faster — see
`docs/VISUAL_REFS_PIPELINE.md` for the visual-reference pipeline
existing adapters use, and `docs/internal/content_pack_backlog.md`
for notes on the ad-hoc per-pack generators we've used.

### 4. Create the MO2 mod folder

In MO2's mods directory:

```
MTF Content - Acme Overlays/
└── SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/
    └── mtf.acme-overlays.json
```

Add it to MO2's left pane, enable it, save the profile.

### 5. Verify the pack appears in MCM

In game:
1. Open MCM → Magic Tattoos Framework → General → "Reload visual packs"
2. Open the preset editor for any slot
3. Open the texture pack dropdown — `Acme Overlays` should appear
4. Pick it, then pick `Acme 01` as the entry
5. Save the preset and bind it to a tier
6. Trigger the tier in-game — the overlay should render

---

## Testing in-game

Verify via the MCM preset editor — covers the whole stack: pack
discovery → MCM rendering → preset authoring → tier evaluation →
effect activation.

1. Open MCM → Magic Tattoos Framework → General → **"Reload visual
   packs"**. The post-reload pack count should bump by 1.
2. Open the preset editor for any slot.
3. Open the texture pack dropdown — your pack's `label` should
   appear.
4. Pick it; the entry dropdown should populate from `entries[]`.
5. Pick an entry, save the preset, bind it to a tier with a
   condition you can trigger easily (e.g. magicka % threshold).
6. Trigger the condition in-game — the overlay should render within
   ~2 s (the eval tick interval).

### Programmatic regression presets

The [`test-pack/`](../test-pack/) folder holds preset JSONs that
exercise the framework end-to-end (multi-area, multi-tier, pulse,
cooldown, integration-driven flows). Copy one as a template for
your pack's smoke-test preset, then enable the test pack in MO2
alongside yours.

### When the overlay doesn't render

| Check | How |
|---|---|
| Pack discovered? | MCM → General → "Reload visual packs" — count should increment after install. If not, JSON filename ≠ `packId`, the path is wrong, or the JSON is malformed (validate with `jq . file.json`). |
| Entry list populated? | Pick the pack in MCM. If dropdown is empty, `entries[]` is empty or the JSON is malformed past the header. |
| Texture path exists on disk? | Manually browse to `Data/textures/<path-from-json>`. Typos and missing sub-folders are the #1 cause of silent non-rendering — NiOverride accepts the path but writes nothing. |
| SKSE / NiOverride errors? | Tail `Documents/My Games/Skyrim Special Edition/SKSE/skse64.log` while triggering the tier condition. Look for `NiOverride` or `MTF` lines. |
| Stale overlay after JSON edit? | Force a fresh eval + redraw from the console: `cqf MTF_MainQuest EvalAndDrawActor <ref>` (use `player` for self; click an NPC to get their reference). Iterates every applied preset on the target and re-renders. |

---

## Shipping

### Standalone Nexus / LL release

Pack the MO2 mod folder into a .7z, upload to Nexus/LL as a
separate mod page that depends on:
1. The source mod (textures)
2. Magic Tattoos Framework (the engine)

Use the mod page description to make the dependency chain obvious to
the user.

### Bundle into MTF's FOMOD installer

For first-party adapters, drop the folder into MTF's
`content-packs/<packid>/` directory and add a Texture Pack Adapters
step entry to `tools/fomod/templates/ModuleConfig.xml`. Run
`bash tools/fomod/build_fomod.sh` to rebuild. See
`tools/fomod/README.md` for the assembler details.

### Local-only (personal use)

If you don't have the source author's permission to redistribute a
wrapper, keep the folder in `content-packs/<packid>/` on your local
disk and add the path to `.gitignore`. The pack still works locally;
nothing gets pushed or shipped.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Pack doesn't appear in MCM's pack dropdown | JSON filename doesn't match `packId`, or file isn't at the right path, or JSON is malformed (run it through `jq . file.json` to validate). |
| Pack appears but entry list is empty | `entries` array is empty or the JSON is malformed past the header — MTF parses lazily. |
| Pack appears but overlay doesn't render | Texture path in JSON doesn't match where the source mod actually installs (typos, wrong sub-folder, missing `\\` escape). Verify with a file manager. |
| Overlay renders but tint/alpha is wrong | Preset's per-layer override has zero alpha or `#000000` tint. Check the preset, not the pack. |
| Overlay renders briefly then disappears after armor swap | Known SKEE issue — MTF handles this for ITS overlays via the redraw-on-3D-rebuild pipeline. If you're seeing it consistently, the texture might be in a slot conflicting with what your body mod (CBBE/UNP) reserves. |

---

## Reference: existing adapters

| Pack | Folder | Source mod | Notes |
|---|---|---|---|
| LewdMarks (RaceMenu) | `content-packs/lewdmarks/` | LewdMarks Aroused by SavageDomain | RaceMenu-overlay variant; 96 entries with both base and glow layers |
| LewdMarks (SlaveTats) | `content-packs/lewdmarks/` | LewdMarks (SlaveTats variant) | Same 96 entries pointed at SlaveTats paths instead |
| RX'Overlays | `content-packs/rx-overlays/` | RX'Overlays texture pack | 41 entries, body |
| Bard's Nail Overlays | `content-packs/bardle-nail-polish/` | Bard's Nail Overlays by BinkBoink | 16 entries, hands |
| Community Overlays 1 — Body | `content-packs/community-overlays-1-body/` | Community Overlays 1 by DomainWolf | 57 entries, body. Descriptions/tags vision-grounded |

Read the actual JSONs under each folder to see real-world examples
of every schema field in use.
