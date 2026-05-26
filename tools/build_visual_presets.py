#!/usr/bin/env python3
"""Generate 4 visual stress-test preset JSONs (MTF_Vis01..MTF_Vis04).

Each preset:
  * Single rx-overlays texture (distinct per preset).
  * Slot 0 baseline = peace tier: cool color (green or blue), slow pulse.
  * Slot 1 with cond `mtf.base:combat.in` = combat tier: hot color
    (red or yellow), fast pulse. Same texture as peace; only tint/em
    and pulse differ between tiers.
  * transition.duration = 3.0s (cross-fade between tiers).
  * fadeondeath.enabled = 1, mode 0, 2000ms.

Output: data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/

Run from project root:
    python tools/build_visual_presets.py
"""
from __future__ import annotations
import json
from pathlib import Path

PACK_ID = "mtf.rx-overlays"
MAX_LAYERS = 4

# Texture set requested by the user; verified against
# mtf.rx-overlays.json entry ids. Peace = green/blue per spec;
# combat = red/yellow per spec. Pulse rates vary per preset.
PRESETS = [
    {
        "name": "MTF_Vis01",
        "display": "Vis 01 Magic Scar (green/red)",
        "entry": "Magic Scar",
        "peace_color": "00FF00",   # green
        "peace_rate": 0.6,
        "peace_depth": 60,
        "peace_wave": "heartbeat",
        "combat_color": "FF1010",  # red
        "combat_rate": 4.0,
        "combat_depth": 90,
        "combat_wave": "square",
    },
    {
        "name": "MTF_Vis02",
        "display": "Vis 02 Spine MagicBook (blue/yellow)",
        "entry": "Spine MagicBook",
        "peace_color": "1080FF",   # blue
        "peace_rate": 1.0,
        "peace_depth": 60,
        "peace_wave": "triangle",
        "combat_color": "FFE020",  # yellow
        "combat_rate": 5.0,
        "combat_depth": 95,
        "combat_wave": "sawtooth",
    },
    {
        "name": "MTF_Vis03",
        "display": "Vis 03 Chest DragonMoon (green/red)",
        "entry": "Chest DragonMoon",
        "peace_color": "40FF60",   # green-mint
        "peace_rate": 0.4,
        "peace_depth": 55,
        "peace_wave": "triplehump",
        "combat_color": "FF4040",  # red
        "combat_rate": 3.0,
        "combat_depth": 90,
        "combat_wave": "square",
    },
    {
        "name": "MTF_Vis04",
        "display": "Vis 04 ThighL Virgo (blue/yellow)",
        "entry": "ThighL Virgo",
        "peace_color": "2070FF",   # azure
        "peace_rate": 0.8,
        "peace_depth": 60,
        "peace_wave": "doublehump",
        "combat_color": "FFCC10",  # gold
        "combat_rate": 4.5,
        "combat_depth": 95,
        "combat_wave": "doublepulse",
    },
]


def _layers(color_hex: str) -> list[dict]:
    return [
        {"tint": color_hex, "emissive": color_hex, "emissivemult": 0.6, "alpha": 100},
        *(
            {"tint": "FFFFFF", "emissive": "FFFFFF", "emissivemult": 0.0, "alpha": 100}
            for _ in range(MAX_LAYERS - 1)
        ),
    ]


def _slot(cond_key, entry, color_hex, rate, depth, wave) -> dict:
    return {
        "cond": {"pluginid": cond_key, "packid": PACK_ID, "entryid": entry},
        "persist": {"min": 0, "allowOverride": 1},
        "cool": {"min": 0},
        "pulse": {"rate": rate, "depth": depth, "waveform": wave},
        "layer": _layers(color_hex),
    }


def make_preset(p: dict) -> dict:
    peace_slot = _slot("", p["entry"], p["peace_color"], p["peace_rate"], p["peace_depth"], p["peace_wave"])
    combat_slot = _slot("mtf.base:combat.in", p["entry"], p["combat_color"], p["combat_rate"], p["combat_depth"], p["combat_wave"])
    empty_slot = {
        "cond": {"pluginid": "", "packid": "", "entryid": ""},
        "persist": {"min": 0, "allowOverride": 1},
        "cool": {"min": 0},
    }
    slots = [peace_slot, combat_slot] + [dict(empty_slot) for _ in range(6)]
    return {
        "valid": 1,
        "displayname": p["display"],
        "schemaversion": 9,
        "transition": {"duration": 3.0},
        "fadeondeath": {"enabled": 1, "mode": 0, "durationms": 2000},
        "slot": slots,
    }


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    out_dir = (
        project / "data" / "SKSE" / "Plugins" / "StorageUtilData"
        / "MagicTattoosFramework" / "presets"
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    # Sweep any prior MTF_Vis* so stale Vis05 from the previous run goes away.
    for stale in out_dir.glob("MTF_Vis*.json"):
        stale.unlink()
    for p in PRESETS:
        path = out_dir / f"{p['name']}.json"
        path.write_text(json.dumps(make_preset(p), indent=2), encoding="utf-8")
    print(f"OK: wrote {len(PRESETS)} visual presets to {out_dir}")


if __name__ == "__main__":
    main()
