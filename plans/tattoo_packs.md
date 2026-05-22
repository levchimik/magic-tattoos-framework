# Tattoo / Overlay Content Pack Roadmap

Plan for expanding MTF's content-pack lineup beyond the current three
(`MTF Content - LewdMarks`, `MTF Content - RX Overlays`, `MTF Content - Obi's Tattoos`).
Drafted 2026-05-21 after surveying `D:\Skyrim mods`.

## Tooling gap

The existing generator at `tools/gen_visual_catalogs.js` is hardcoded to
the LewdMarks numeric naming scheme (`001.dds`–`096.dds`, both base + glow
layer per index). It can't be reused for packs with arbitrary filenames
(e.g. `RX Abs Butterfly.dds`).

**Pre-req task:** generalize the generator so it accepts:
- `--source <texture-dir>` — root to scan recursively for `.dds`
- `--packid <id>` — `mtf.<author>.<name>`
- `--label <display>` — user-facing pack label
- `--prefix <texture-root>` — `actors\character\overlays\<sub>\` portion to
  strip from each path before emitting (texture paths stored in JSON are
  relative to `Data/textures/`)
- `--area Body|Face` (default Body)
- (optional) `--glow-suffix <s>` to pair `<name>.dds` + `<name><s>.dds`
  for 2-layer LewdMarks-style packs

Walk the texture dir, generate one entry per `.dds` with `id`/`label`
derived from the filename (sans `.dds`, sans pack prefix).

## Wrapping recipe (per pack)

1. **Install the source mod** via MO2 (drop archive in Downloads, click Install).
2. **Identify the texture root** — usually `textures/actors/character/overlays/<sub>/`.
3. **Run generalized generator** → produces `mtf.<pack>.json`.
4. **Create `MTF Content - <PackName>` mod folder** in MO2's `mods/` with
   layout:
   ```
   MTF Content - <PackName>/
     SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/
       mtf.<pack>.json
   ```
5. **Add to modlist.txt** (enabled).
6. **No ESP** — content packs are JSON-only, no plugin slot consumed.

For SlaveTats packs (Tier 4 below), the texture root is `textures/actors/character/slavetats/<sub>/`
instead, and the JSON catalog references the SlaveTats path the same way
`mtf.lewdmarks-slavetats.json` does — same wrapping shape, different
texture-root prefix.

## Candidate packs (ranked)

### Tier 1 — flagship body tattoo packs (recommended starter set)

Both sexes covered, broad design variety, widely-used quality content.

| Pack | Archive(s) | Size | Notes |
|---|---|---|---|
| Community Overlays 1 (CBBE 2K + 4K + Face) | `(3) Community Overlays 1 - Main - CBBE 2K`, `(4) Community Overlays 1 - Main - CBBE 4K`, `(7) Community Overlays 1 - Female Face Overlays`, `(Q) Community Overlays 1 - Bugfix Patch` | 14 + 49 + 16 + 0.05 MB | De-facto general pack. Pick 2K **or** 4K, not both. |
| Community Overlays 2 | `(2) Community Overlays 2 - Main - CBBE`, `(4) Community Overlays 2 - Main - CBBE and Male` | 76 / 149 MB | Newer continuation. Pick the AIO (option 4) for male coverage. |
| Community Overlays 3 | `(2) Community Overlays 3 - Main - CBBE`, `(4) Community Overlays 3 - Main - CBBE and Male` | 119 / 220 MB | Latest, largest. Same AIO pick. |
| Barbarian Bodypaints (CBBE + Male) | `(2)Barbarian Bodypaints - CBBE`, `(3)Barbarian Bodypaints - Male` | 272 + 244 MB | Tribal, high quality, two installs for both sexes. |
| Yyvengar Bodypaints (CBBE + M/F) | `Yyvengar Bodypaints - Female (CBBE)`, `Yyvengar Bodypaints - Female and Male (CBBE)` | 62 + 133 MB | Viking-themed. Pick AIO for male too. |
| Ziovendian Bodypaints | `Ziovendian Bodypaints - Female and Male (CBBE)` | 52 MB | Compact, both sexes in one. |
| WNB — Weathered Nordic Bodypaints | `WNB - Weathered Nordic Bodypaints SE - 2K`, `WNB -Weathered Nordic Bodypaints SE- 4K` | 50 / 154 MB | Nordic classic. Pick 2K or 4K. |

### Tier 2 — focused / themed packs

| Pack | Archive | Size | Notes |
|---|---|---|---|
| Niohoggr Warpaints AIO | `Niohoggr Warpaints - All in one` | 118 MB | Face + body. |
| Lyru's Tattoo Pack collection | `Lyru's Tattoo pack collection 2`, `Lyru's Tattoo pack collection-75222` | 8-11 + 5 MB | Smaller, well-designed. |
| CBBE AIO SE Port Tattoo Pack ESL | `CBBE AIO SE Port Tattoo Pack ESL 2-0` | 20 MB | Older packs combined. May overlap with Community Overlays. |
| Zhizhen Tattoo (4K / 8K) | `Zhizhen Tattoo 4K`, `Zhizhen Tattoo 8K` | 8 / 28 MB | High-res body. Pick one resolution. |
| Sheps Tattoo Collection SE + Male | `Sheps Tattoo Collection SE`, `Sheps Male Tattoo Collection SE` | 7 + 7 MB | Classic, both sexes. |
| TRX Spider Web Tattoo Pack | `TRX Spider Web Tattoo Pack ESL` | 5.6 MB | Themed. |
| Body Highlight Tattoos | `Body Highlight Tattoos` | 7.4 MB | Anatomy lines. |
| ZMD's Gothic Tattoos | `ZMD'S Gothic Tattoos Race Menu CBBE v1 SE` | 3.7 MB | Themed. |
| Unholy Tattoos for Racemenu | `Unholy Tattoos for Racemenu` | 5.1 MB | Demonic/occult. |
| Miggyluv's Tattoos for Men | `Miggyluv's Tattoos for Men` | 3.6 MB | Male-focused. |
| Sunstarved Tanlines | `(2) Sunstarved Tanlines - CBBE`, `ODF - Sunstarved Tanlines` | 26 + ? MB | Tanlines, not tattoos. Subtle effect. |
| SBP — Simple Belly Paints | `(2) SBP SE - Simple Belly Paints - 4K`, `(3) SBP - CBBE Adjustments` | 6 + 8 MB | Belly only — pairs well with pregnancy plugins. |

### Tier 3 — face-only

| Pack | Archive | Size | Notes |
|---|---|---|---|
| Hellblade — Senua's Warpaints | `Hellblade - Senua's Warpaints for Racemenu` | 6.5 MB | Face. |
| Corrupted Warpaints — RM Overlays | `Corrupted Warpaints - RM Overlays` | 3.3 MB | Face. |
| LDD Modular Warpaints — HPH 4K | `LDD - Modular Warpaints - HPH 4K` | 26 MB | High Poly Head face warpaints. |
| Daymarr Yokuda — Tribal Racemenu Tattoos | `Daymarr Yokuda - Tribal Racemenu Tattoos` | 2.2 MB | Face tribal. |
| Dalish Vallaslin Face Tattoos | `Dalish Vallaslin Face Tattoo's for Racemenu` | 20 MB | DA-inspired face. |
| Neith Team Warpaints | `Neith Team Warpaints Set 50 warpaint` | 3.8 MB | Face. |
| RutahWarpaints | `RutahWarpaints 2K` | 3.6 MB | Face. |
| Ravens Warpaint SE | `Ravens Warpaint SE` | 12.5 MB | Face. |
| Xara's Makeup and Warpaints | `Xara's Makeup and Warpaints 1.4 - FOMOD` | 2 MB | Face. |

### Tier 4 — SlaveTats packs (use SlaveTats wrapping path)

| Pack | Archive | Size | Notes |
|---|---|---|---|
| Alpia Slavetats general | `Alpia Slavetats SE` | 52 MB | Generic SlaveTats set. |
| Alpia Slavetats Orc | `Alpia Slavetats Orc SE-LE` | 20 MB | Orc race-specific. |
| Alpia Slavetats Riek | `Alpia Slavetats Riek SE-LE` | 3 MB | Riek race-specific. |
| Sexy Supplemental Slavetats | `Sexy Supplemental Slavetats 1.17` | 16 MB | SlaveTats addon. |
| SlaveTats CumTextures Remake | `SlaveTats CumTextures Remake v1.2.5` | 1.9 MB | Themed. |
| BS-TheHags Body Tattoo (CBBE) | `BS-TheHags Body Tattoo(CBBE)` | 2.3 MB | Hag-themed body. |
| BS-TheHags Wartattoos | `BS-TheHags Wartattoos` | 0.3 MB | Face wartattoos. |
| slavetats_spanked | `slavetats_spanked_1.0` | 0.3 MB | Themed. |

## Skip list

| Pack | Why skip |
|---|---|
| Vanilla Warpaints Absolution / VWA | Replaces vanilla face slots (not RaceMenu overlay) |
| Painterly_HighResVanillaWarpaint | Vanilla face replacer, not overlay |
| BRB BeastRaceBodypaints | Race texture replacer for beast races, not RaceMenu overlay |
| Ashtoreth Barbarian Armor / RB's Barbarian Set | Armor, not tattoos (keyword false-positive on "barbarian") |
| Barbarian Dual Hammer / Lockpicking for Barbarians | Weapon / perk overhaul (keyword false-positive) |
| Brynjolf Tattoo Patch | Single-NPC retexture, not for player |
| Kaidan — a visual replacer — Tattoo 3 | Single-NPC |
| Dovahnique's Kaidan — Full Body Tattoo | Single-NPC |
| Miggyluv's Female Nord — Aela (warpaint) | Single-NPC |
| Fade Tattoos Continued | 0 KB local archive — looks broken |
| Warpaint 1 | 0.2 MB, ambiguous content |
| Flamebringer Tattoo-Sleeve | Single-design themed tattoo, low impact |
| Alchemy Tattoos — 4K | Niche, likely overlap with Community Overlays |
| Am Barbarian — 3ba Bodyslide Preset | Bodyslide preset, not overlay |

## Recommended starter batch (Tier 1)

Pick from these to keep first wrapping pass tractable:

1. **Community Overlays 1 (4K) + bugfix patch** — flagship general pack
2. **Community Overlays 2 (CBBE and Male)** — continuation, both sexes
3. **Community Overlays 3 (CBBE and Male)** — latest
4. **Barbarian Bodypaints CBBE + Male** — tribal, both sexes
5. **Yyvengar Bodypaints (Female and Male)** — viking-themed, both sexes

Total: ~5 wrapped packs, ~1000+ textures, ~750 MB on disk.

## Implementation order

1. **Generalize `tools/gen_visual_catalogs.js`** (or write a sibling `gen_pack_catalog.js`)
2. **Install Tier 1 pack #1** (Community Overlays 1 4K) in MO2
3. **Run generator** against the new mod folder → emit catalog JSON
4. **Create `MTF Content - Community Overlays 1` mod folder**, drop the JSON in
5. **Add to modlist.txt** (enabled, near other `MTF Content` entries)
6. **In-game verification**: MCM → Magic Tattoos Framework → General → "Reload visual packs" count should bump. Pick the new pack in the Default slot's pack picker, choose any entry, confirm overlay renders.
7. **Repeat steps 2-6** for each remaining Tier 1 pack.
8. **Update `README.md`** Components table with the new packs once verified.

## Open questions

- **Face overlay support**: MTF's overlay slot system writes to NiOverride. Face overlays go to a different slot pool than body. Need to check whether MTF's existing `OverlaySlot` MCM option supports the face-overlay-slot range, or if it's body-only. If body-only, Tier 3 packs need a feature-gate first (add `OverlaySlot.Face` setting + dispatch to NiOverride face APIs).
- **Resolution selection** for packs that ship 2K + 4K variants — generator should be told the resolution choice; the JSON itself doesn't care, since texture paths are identical between resolutions. The mod manager picks which file ships.
- **Pack overlap**: Community Overlays 1+2+3 + CBBE AIO + Sheps may have overlapping content (older designs absorbed into newer packs). May warrant a one-time dedup audit by texture-hash.
- **`MTF NPC Overlays`** (already installed) — this is a *different* concept (per-NPC override data, not a tattoo pack). Confirm by inspection what it actually does, before treating it as a content pack.

## Status

- [ ] Generalize catalog generator
- [ ] Install + wrap Community Overlays 1
- [ ] Install + wrap Community Overlays 2
- [ ] Install + wrap Community Overlays 3
- [ ] Install + wrap Barbarian Bodypaints
- [ ] Install + wrap Yyvengar Bodypaints
- [ ] In-game verify all 5
- [ ] README.md Components table update
- [ ] (Stretch) Tier 2 batch
- [ ] (Stretch) Face overlay slot support → unlocks Tier 3
- [ ] (Stretch) SlaveTats wrapper helper → unlocks Tier 4 batch
