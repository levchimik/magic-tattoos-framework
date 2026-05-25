"""One-shot preset migrator for the v0.2.5 modify.skill / modify.resist
consolidation. Walks every preset under
test-pack/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/ and
rewrites:

  mtf.base:modify.<skillname> → mtf.base:modify.skill
                                param1 = skill enum (per SKILL_AV_MENU)
                                param2 = the old param1 (shift)

  mtf.base:modify.resist<Type> → mtf.base:modify.resist
                                 param1 = resist enum (per RESIST_TYPE_MENU)
                                 param2 = the old param1 (shift)

Idempotent — already-migrated entries pass through untouched.
"""
import json
import pathlib
import sys

# Match SKILL_AV_MENU in tools/build_base_catalog.py and modify.skill's
# param1 dropdown values.
SKILL_MAP = {
    "modify.oneHanded":   0,
    "modify.twoHanded":   1,
    "modify.archery":     2,
    "modify.block":       3,
    "modify.heavyArmor":  4,
    "modify.lightArmor":  5,
    "modify.smithing":    6,
    "modify.enchanting":  7,
    "modify.alchemy":     8,
    "modify.destruction": 9,
    "modify.restoration": 10,
    "modify.alteration":  11,
    "modify.illusion":    12,
    "modify.conjuration": 13,
    "modify.speech":      14,
    "modify.lockpicking": 15,
    "modify.pickpocket":  16,
}

# Match RESIST_TYPE_MENU in tools/build_base_catalog.py and modify.resist's
# param1 dropdown values.
RESIST_MAP = {
    "modify.resistFire":    0,
    "modify.resistFrost":   1,
    "modify.resistShock":   2,
    "modify.resistMagic":   3,
    "modify.resistDisease": 4,
    "modify.resistPoison":  5,
}


def migrate_effect(e):
    """Return True if the effect dict was modified."""
    key = e.get("key", "")
    if not key.startswith("mtf.base:"):
        return False
    eid = key.split(":", 1)[1]
    if eid in SKILL_MAP:
        e["key"] = "mtf.base:modify.skill"
        e["param2"] = e.get("param1", 0)
        e["param1"] = SKILL_MAP[eid]
        return True
    if eid in RESIST_MAP:
        e["key"] = "mtf.base:modify.resist"
        e["param2"] = e.get("param1", 0)
        e["param1"] = RESIST_MAP[eid]
        return True
    return False


def migrate_preset(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    changed = 0
    for slot in d.get("slot", []):
        for e in slot.get("effect", []):
            if migrate_effect(e):
                changed += 1
    if changed:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(d, f, indent="\t", ensure_ascii=False)
            f.write("\n")
    return changed


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    preset_dir = root / "test-pack" / "SKSE" / "Plugins" / "StorageUtilData" / "MagicTattoosFramework" / "presets"
    if not preset_dir.is_dir():
        print(f"preset dir not found: {preset_dir}", file=sys.stderr)
        return 1
    total = 0
    for p in sorted(preset_dir.glob("*.json")):
        n = migrate_preset(p)
        if n:
            print(f"  {p.name}: migrated {n} effect entries")
            total += n
    print(f"Migrated {total} effect entries across the preset directory.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
