# MTF Texture Pack Adapters

JSON-only catalogs that wire MTF onto overlay textures provided by **other
authors' mods**. We do not redistribute the .dds assets — the user must
install the source mod separately.

(Folder is `content-packs/` for historical reasons; user-facing terminology
is "texture pack adapters" — they adapt MTF's catalog format onto external
texture packs.)

The FOMOD installer (`tools/fomod/build_fomod.sh`) pulls these JSON files
into its "Texture Pack Adapters" step. Each adapter's description in the
installer explicitly names the source mod the user must have installed for
the catalog's texture paths to resolve.

| Adapter folder | Catalog | Source mod (user must install) | Area |
|---|---|---|---|
| `lewdmarks/` | `mtf.lewdmarks-racemenu.json`, `mtf.lewdmarks-slavetats.json` | LewdMarks (by SavageDomain) — RaceMenu + SlaveTats variants | Body |
| `rx-overlays/` | `mtf.rx-overlays.json` | RX Overlays (texture pack) | Body |
| `bardle-nail-polish/` | `mtf.bardle-nail-polish.json` | Bard's Nail Overlays (by Bardledorf) | Hands |

The `skyrimnet-bridge/` folder also lives here but is NOT a texture-pack
adapter — it ships a SkyrimNet prompt template (`character_bio/0350_mtf_tattoos.prompt`)
that the FOMOD bundles with the `MTF_Plugin_SkyrimNet.esp` step, not as a
content-pack option. See `tools/fomod/README.md`.

## Adding a new adapter

1. Create a new folder: `content-packs/<pack-id>/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/`
2. Drop the catalog JSON there.
3. Add an entry to the table above and to `tools/fomod/templates/ModuleConfig.xml`
   (Texture Pack Adapters step).
4. Rebuild the FOMOD: `bash tools/fomod/build_fomod.sh`.

Texture paths in catalogs must match exactly where the source mod ships
its .dds files. If the user picks an adapter in the installer without the
source mod installed, MTF will fail to apply the overlay silently (NiOverride
takes the path but the texture won't render).
