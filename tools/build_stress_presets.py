#!/usr/bin/env python3
"""Generate 30 stress test preset JSON files (MTF_Stress01..MTF_Stress30).

Each preset shifts 3 unique skills by +10 (modify.skill, param2=10).
The 18 Skyrim skills are split into 6 groups of 3; presets 01..30 cycle
through these 6 groups, so the WORK is identical every 6 presets but the
preset NAMES (and therefore their scratch namespaces under
mtf.fx.scratch.<presetName>.*) stay distinct. That keeps per-preset state
properly partitioned in StorageUtil while letting us scale concurrency
beyond the number of unique skill groups.

Output: data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/MTF_Stress{01..30}.json

Run from project root:
    python tools/build_stress_presets.py
"""
from __future__ import annotations
import json
from pathlib import Path

# Skill groups must match MTF_TestRunner._stressSkillsForPreset (same
# ordering, same partitions). Skyrim AV names differ from the menu ids
# for archery (Marksman) and speech (Speechcraft); the menu id is used
# here because the dispatch reads param1 as the menu id, not the AV.
GROUPS: list[tuple[str, str, str]] = [
    ("archery",     "smithing",    "alchemy"),
    ("enchanting",  "destruction", "illusion"),
    ("one_handed",  "two_handed",  "block"),
    ("heavy_armor", "light_armor", "sneak"),
    ("restoration", "alteration",  "conjuration"),
    ("speech",      "lockpicking", "pickpocket"),
]

GROUP_DESCS = [
    "archery/smithing/alchemy",
    "enchanting/destruction/illusion",
    "one-handed/two-handed/block",
    "heavy-armor/light-armor/sneak",
    "restoration/alteration/conjuration",
    "speech/lockpicking/pickpocket",
]

EMPTY_SLOT = {
    "cond": {"entryid": "", "packid": "", "param": 0, "pluginid": ""},
    "cooldown": {"min": 0, "mode": 0},
}


def make_preset(n: int) -> dict:
    g = (n - 1) % len(GROUPS)
    skills = GROUPS[g]
    effects = [
        {"key": "mtf.base:modify.skill", "param2": 10, "param1": s}
        for s in skills
    ]
    slot0 = {**EMPTY_SLOT, "effect": effects}
    slots = [slot0] + [dict(EMPTY_SLOT) for _ in range(7)]
    return {
        "displayname": f"Stress {n:02d} ({GROUP_DESCS[g]})",
        "schemaversion": 8,
        "valid": 1,
        "transition": {"duration": 0.0},
        "slot": slots,
    }


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    out_dir = project / "data" / "SKSE" / "Plugins" / "StorageUtilData" / "MagicTattoosFramework" / "presets"
    out_dir.mkdir(parents=True, exist_ok=True)
    for n in range(1, 31):
        path = out_dir / f"MTF_Stress{n:02d}.json"
        path.write_text(json.dumps(make_preset(n), indent=2), encoding="utf-8")
    print(f"OK: wrote 30 presets to {out_dir}")


if __name__ == "__main__":
    main()
