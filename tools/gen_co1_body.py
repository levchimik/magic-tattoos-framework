#!/usr/bin/env python3
"""Generate the Community Overlays 1 BODY adapter catalog (was the missing
half — only the Face pack existed). One pointer entry per '* Body*.dds',
matching the format of the shipping CO2/CO3 body catalogs.

Source textures: Community Overlays 1 by DomainWolf. Pointer-only — textures
stay in the source mod. tags/description left empty for a later vision pass
(mtf-describe-pack), same as a freshly-built pack.
"""
import json, os, re

# Texture dir of an installed CO1 (used only to ENUMERATE filenames; nothing
# is copied). The catalog references the in-game Data-relative path.
SRC = r"F:/Modlists/N.Y.A/mods/Community Overlays 1 (0-30) Bodypaints Warpaints Tattoos and more made for the Community (Special Edition)/textures/actors/character/Overlays/Community Overlays"
PATH_PREFIX = "actors\\character\\Overlays\\Community Overlays\\"   # matches CO1-face catalog
OUT = "content-packs/community-overlays-1-body/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/mtf.community-overlays-1-body.json"

files = sorted(f for f in os.listdir(SRC)
               if f.lower().endswith(".dds") and re.search(r"\bbody\b", f, re.I))

def entry(fname):
    stem = fname[:-4]                      # drop .dds
    return {
        "id": stem,
        "label": re.sub(r"\s+", " ", stem).strip(),
        "layers": [{"texture": PATH_PREFIX + fname}],
        "tags": {"subject": "", "style": "", "placement": ""},
        "description": "",
    }

catalog = {
    "schemaVersion": 3,
    "packId": "mtf.community-overlays-1-body",
    "label": "Community Overlays 1 (Body)",
    "area": "Body",
    "entries": [entry(f) for f in files],
}

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as fh:
    json.dump(catalog, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(f"wrote {OUT}")
print(f"  {len(catalog['entries'])} body entries")
print("  sample:", catalog["entries"][0]["id"], "->", catalog["entries"][0]["layers"][0]["texture"])
