#!/usr/bin/env python3
"""Render 2-panel placement+design refs for the CO1 body pack, matching the
CO2/CO3 visual-ref format.

  LEFT  "PLACEMENT" — the tattoo's alpha tinted red, composited over the CBBE
                      body diffuse (same 4K UV), so you see WHERE on the body
                      the ink lands.
  RIGHT "DESIGN"    — the raw alpha on light grey, so you see the design clean.

Pointer-only inputs (textures read from the installed mods, nothing copied).
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

DIFFUSE = r"F:/Modlists/Modding Essentials/mods/Caliente's Beautiful Bodies Enhancer -CBBE-/textures/actors/character/female/femalebody_1.dds"
OVL_DIR = r"F:/Modlists/Modding Essentials/mods/(4) Community Overlays 1 - Main - CBBE 4K/textures/actors/character/Overlays/Community Overlays"
CAT = "content-packs/community-overlays-1-body/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/mtf.community-overlays-1-body.json"
OUT = "docs/visual-refs/mtf.community-overlays-1-body"
PANEL = 1024                     # each panel side, px (2048x1024 total)
RED = (220, 30, 30)

os.makedirs(OUT, exist_ok=True)
bs = chr(92)
cat = json.load(open(CAT, encoding="utf-8"))

# Body diffuse at full panel resolution (no darkening — keep skin bright so the
# anatomy reads clearly; the red ink already contrasts against it).
_diff_panel = Image.open(DIFFUSE).convert("RGB").resize((PANEL, PANEL), Image.LANCZOS)
def diffuse_panel():
    return _diff_panel.copy()

try:
    FONT = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", 40)
except Exception:
    FONT = ImageFont.load_default()

def render(entry, only=None):
    eid = entry["id"]
    if only and eid != only:
        return None
    fn = entry["layers"][0]["texture"].split(bs)[-1]
    src = os.path.join(OVL_DIR, fn)
    if not os.path.exists(src):
        print("  MISSING texture:", fn); return None
    ov = Image.open(src).convert("RGBA")
    alpha = ov.split()[3]

    # LEFT: red ink over body diffuse, in UV space.
    left = diffuse_panel().convert("RGBA")
    a_small = alpha.resize((PANEL, PANEL), Image.LANCZOS)
    red_layer = Image.new("RGBA", (PANEL, PANEL), RED + (0,))
    red_layer.putalpha(a_small)
    left = Image.alpha_composite(left, red_layer).convert("RGB")

    # RIGHT: raw alpha as black ink on light grey.
    right = Image.new("RGB", (PANEL, PANEL), (200, 200, 200))
    a_small2 = alpha.resize((PANEL, PANEL), Image.LANCZOS)
    ink = Image.new("RGBA", (PANEL, PANEL), (20, 20, 20, 0))
    ink.putalpha(a_small2)
    right = Image.alpha_composite(right.convert("RGBA"), ink).convert("RGB")

    canvas = Image.new("RGB", (PANEL * 2, PANEL), (0, 0, 0))
    canvas.paste(left, (0, 0))
    canvas.paste(right, (PANEL, 0))
    d = ImageDraw.Draw(canvas)
    d.text((6, 4), "PLACEMENT", fill=(255, 255, 0), font=FONT)
    d.text((PANEL + 6, 4), "DESIGN", fill=(40, 40, 40), font=FONT)
    out = os.path.join(OUT, eid.replace(" ", "_") + ".png")
    canvas.save(out)
    return out

if __name__ == "__main__":
    only = sys.argv[1] if len(sys.argv) > 1 else None
    n = 0
    for e in cat["entries"]:
        if render(e, only):
            n += 1
    print(f"rendered {n} panel(s)" + (f" (only {only})" if only else ""))
