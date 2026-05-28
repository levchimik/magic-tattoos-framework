# MTF FOMOD installer

Generates a Nexus-ready FOMOD archive that bundles base MTF (which now
ships the `bPlayerOnly=0` skee64.ini override by default), all integration
plugins, the JSON-only texture pack adapters, and the test pack as an
optional extra.

## Quick rebuild

```bash
bash tools/fomod/build_fomod.sh
```

Output: `_build/MagicTattoosFramework-FOMOD-<version>.7z` (+ a `_build/fomod-stage/`
folder you can drag into MO2's "Install from folder" if you want to test
without re-zipping).

The script calls `bash tools/build_esps.sh` first to rebuild all 8 ESPs
from their Spriggit YAML mirrors (`spriggit/<PluginName>/`) into
`_build/esps/*.esp`. Binary `.esp` files are not committed to git —
only the YAML.

Version comes from the latest commit subject (e.g. `v0.1.x`), or `MTF_VERSION` env override:

```bash
MTF_VERSION=v0.1.x bash tools/fomod/build_fomod.sh
```

## Layout

```
tools/fomod/
├── README.md               ← this file
├── build_fomod.sh          ← assembler script
├── templates/
│   ├── info.xml            ← FOMOD metadata; @MTF_VERSION@ substituted at build
│   └── ModuleConfig.xml    ← FOMOD installer logic (validated against ModConfig5.0.xsd)
├── static/
│   ├── 00_base/            ← skee64.ini override (bPlayerOnly=0); layered into 00_base stage
│   └── _diagnostics/       ← loose-file probe marker (installed by <conditionalFileInstalls>)
└── images/                 ← optional header / per-option images (auto-copied if present)
```

## What the installer ships

All ESPs below come from `_build/esps/*.esp` (deserialized from
`spriggit/<PluginName>/` by the build script). `.pex` files come from
`source/scripts/`.

| Folder in stage | Source in repo | Always installed? |
|---|---|---|
| `00_base/` | `MagicTattoosFramework.esp` + base `*.pex` + `data/SKSE/Plugins/{MagicTattoosFramework.ini,MTFPulse.dll,StorageUtilData/.../waveforms/*.json}` + `tools/fomod/static/00_base/SKSE/Plugins/skee64.ini` (bPlayerOnly=0 override) | Yes (Required) |
| `10_plugin_fmr/` | `MTF_Plugin_FMR.esp` + `MTF_Plugin_FMR.pex` | Auto-recommend if `Fertility Mode.esm` active |
| `11_plugin_sla/` | `MTF_Plugin_SLA.esp` + `MTF_Plugin_SLA.pex` | Auto-recommend if `SexLabAroused.esm` active |
| `12_plugin_sexlab/` | `MTF_Plugin_SexLab.esp` + `.pex` | Auto-recommend if `SexLab.esm` active |
| `13_plugin_ostim/` | `MTF_Plugin_OStim.esp` + `.pex` | Auto-recommend if `OStim.esp` active |
| `14_plugin_bfng/` | `MTF_Plugin_BFNG.esp` + `.pex` | Auto-recommend if `BeeingFemale.esm` active |
| `15_plugin_slavetats/` | `MTF_Plugin_SlaveTats.esp` + `.pex` | Auto-recommend if `SlaveTats.esp` active. Universal bridge — works for all pack roots, not just slavetats-prefixed ones (see `source/scripts/MTF_Plugin_SlaveTats.psc` docstring). |
| `16_plugin_skyrimnet/` | `MTF_Plugin_SkyrimNet.esp` + `.pex` + `SKSE/Plugins/SkyrimNet/prompts/submodules/character_bio/0350_mtf_tattoos.prompt` | Auto-recommend if `SkyrimNet.esp` active. Registers `mtf_active_tattoos` decorator + listens for `MTF_TierChanged`; surfaces visible tattoos in LLM character_bio context. |
| `20_content_lewdmarks/` … `29_content_co2/` | `content-packs/<pack>/` | Optional, manual checkbox |
| `31_test_pack/` | `test-pack/SKSE/...` | Optional, manual checkbox |

Integration plugins are always installable. When the master plugin is
active they're auto-checked (Recommended via `dependencyType` pattern);
when it's missing they fall back to the default `Optional` type, so the
user can still install them (handy if you plan to add the integration
mod later without re-running FOMOD). The BFNG ESP carries a hard
`BeeingFemale.esm` master, so installing without it will produce a
Skyrim load-time error — the option description warns about this.

Texture pack adapter auto-detection: adapters whose source mod ships an
ESP get pre-recommended too — LewdMarks (`LewdMarks.esp` OR
`LewdMarksSlaveTats.esp`), RX (`RXOverlays.esp`), Lyru-1 (`LyruTat.esp`),
Lyru-2 (`LyruTat2.esp`), Bitchcraft (`Bitchcraft Tats.esp`),
Community Overlays 2 (`CommunityOverlays2_31T50.esp`), Community Overlays 3
(`CommunityOverlays3.esp`). Bardle Nail Polish and Community Overlays 1 Face
stay manual (their source mods are texture-only with no plugin file to detect).

The "Texture Pack Adapters" picklist in the installer is ordered alphabetically
by display name (Bard's → Bitchcraft → CO1 → CO2 → CO3 → LewdMarks → Lyru-1
→ Lyru-2 → RX). Folder numbering (20-29) is historical — UI order is set by
the `<plugins order="Explicit">` sequence in `templates/ModuleConfig.xml`.

### Loose-file path detection probe

The installer ships a `<conditionalFileInstalls>` block that drops
`MTF_FOMOD_DIAGNOSTIC_loose_file_check_works.txt` into the installed mod
folder IFF the FOMOD installer reports `SKSE/Plugins/PapyrusUtil.dll`
with `state="Active"`. The FOMOD spec says `<fileDependency>` is plugin-only
(`.esp`/`.esm`/`.esl`), but some installer implementations may extend it
to loose paths. This probe is harmless either way — if the file shows up
post-install, future FOMOD versions can use the same mechanism as a real
hard-requirement check; if not, we know to stick with plugin-file proxies
for everything.

## Hard requirements (NOT auto-checked)

Neither the FOMOD installer nor any Skyrim mod manager can detect loose
DLLs reliably. The installer's main description names them, but
ultimately the user must have:

- RaceMenu / SKEE (NiOverride)
- PapyrusUtil SE
- SKSE 64
- Skyrim SE 1.5.97 or Skyrim AE 1.6.x (the bundled MTFPulse.dll uses
  CommonLibSSE-NG which covers both)

## Editing

- **Adding an integration**: append a `<plugin>` to the "Integration Plugins"
  group in `templates/ModuleConfig.xml`, plus a `stage_plugin "1N_plugin_xxx" ...`
  call in `build_fomod.sh`. Folder number convention: 10–19 = integration plugins.
- **Adding a texture pack adapter**: drop a new folder under `content-packs/<id>/`
  (mirroring `SKSE/Plugins/...`; folder kept as `content-packs/` for historical
  reasons), add a `<plugin>` to the "Texture Pack Adapters" group, add a
  `stage_content "2N_content_xxx" "<id>"` line. Folder number convention: 20–29.
- **Adding an extras option**: drop files under `tools/fomod/static/3N_xxx/`,
  add the `<plugin>` under the Extras group, add a copy line in the script.
  Folder number convention: 30–39.

After editing `ModuleConfig.xml`, validate before committing:

```bash
curl -sSL -o /tmp/fomod.xsd "https://raw.githubusercontent.com/dh-nunes/fomod-schema/master/ModuleConfig.xsd"
sed -i 's/" xs:string"/"xs:string"/g; s/" xs:int"/"xs:int"/g; s/" xs:boolean"/"xs:boolean"/g' /tmp/fomod.xsd
xmllint --noout --schema /tmp/fomod.xsd _build/fomod-stage/fomod/ModuleConfig.xml
```

The XSD on GitHub has whitespace bugs in a few attribute declarations —
the `sed` line patches them before xmllint loads the schema.

## Testing the installer

1. `bash tools/fomod/build_fomod.sh`
2. In MO2: **+ → Install a new mod from an archive**, point at `_build/MagicTattoosFramework-FOMOD-vX.Y.Z.7z`.
3. Step through the installer pages, verify:
   - Integrations whose master is active are pre-ticked
   - Integrations whose master is missing are unticked but still installable
   - Texture pack adapters whose source ESP is active are pre-ticked
   - Texture pack adapters with no detectable source mod (Bardle, CommOv1 Face) are unticked
   - Extras are all unticked by default
4. Confirm the resulting MO2 mod folder contains only the files you ticked,
   and that `SKSE/Plugins/skee64.ini` is present in the base install.
