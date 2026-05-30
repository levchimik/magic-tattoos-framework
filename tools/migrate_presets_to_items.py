#!/usr/bin/env python3
"""Migrate MTF preset JSONs from the legacy/hybrid condition shape to the
v0.3.1 array shape.

OLD (schema 8 single-cond, or v0.3.0 hybrid multi-cond):
    "cond": {
      "packid": "", "entryid": "",
      "pluginid": "mtf.base:magicka.below", "param": 50, "param2": 0,
      "op": 0, "count": 2,
      "condx1": { "pluginid": "mtf.base:stamina.below", "param": 50 }
    }

NEW (schema 9, array):
    "cond": {
      "packid": "", "entryid": "",
      "op": 0,
      "items": [
        { "pluginid": "mtf.base:magicka.below", "param": 50 },
        { "pluginid": "mtf.base:stamina.below", "param": 50 }
      ]
    }

- Condition 0 comes from the flat pluginid/param/param2 keys.
- Extras come from condx1..condxN (or count-1, whichever is present).
- An unconfigured slot (empty/absent pluginid, no condx) gets NO items array.
- packid / entryid are preserved; pluginid/param/param2/op/count/condx* are
  stripped from cond. op is preserved (default 0).
- Bumps top-level schemaversion to 9.
- Idempotent: a cond that already has "items" is left untouched.

Usage:
    python tools/migrate_presets_to_items.py           # migrate in place
    python tools/migrate_presets_to_items.py --dry-run # report only
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

PRESET_DIRS = [
    Path("test-pack/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets"),
    Path("data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets"),
]


def _item_from(src: dict) -> dict:
    """Build one items[] element from a source cond/condx dict.
    Keeps param/param2 only when present (loader defaults them otherwise),
    preserving their original int-or-string type."""
    item = {"pluginid": src.get("pluginid", "")}
    if "param" in src:
        item["param"] = src["param"]
    if "param2" in src:
        item["param2"] = src["param2"]
    return item


def migrate_cond(cond: dict) -> dict:
    """Return a new cond dict in array shape. Pure; no mutation of input."""
    if not isinstance(cond, dict):
        return cond
    if "items" in cond:
        return cond  # already migrated

    out: dict = {}
    # Preserve visual keys verbatim, in canonical order.
    if "packid" in cond:
        out["packid"] = cond["packid"]
    if "entryid" in cond:
        out["entryid"] = cond["entryid"]

    pid0 = cond.get("pluginid", "")
    if not pid0:
        # Unconfigured slot — no items array, no op. Keep packid/entryid only.
        return out

    out["op"] = int(cond.get("op", 0))

    items = [_item_from(cond)]
    # Extras: prefer explicit count, else discover condxN until a gap.
    count = cond.get("count")
    if isinstance(count, int) and count > 1:
        idxs = range(1, count)
    else:
        idxs = []
        j = 1
        while f"condx{j}" in cond:
            idxs.append(j)
            j += 1
    for j in idxs:
        cx = cond.get(f"condx{j}")
        if isinstance(cx, dict) and cx.get("pluginid", ""):
            items.append(_item_from(cx))
    out["items"] = items
    return out


def migrate_file(path: Path, dry: bool) -> tuple[bool, str]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return False, f"PARSE-ERR {e}"
    if not isinstance(data, dict):
        return False, "not an object"

    changed = False
    slots = data.get("slot")
    if isinstance(slots, list):
        for s in slots:
            if isinstance(s, dict) and isinstance(s.get("cond"), dict):
                new_cond = migrate_cond(s["cond"])
                if new_cond != s["cond"]:
                    s["cond"] = new_cond
                    changed = True

    if data.get("schemaversion") != 9:
        data["schemaversion"] = 9
        changed = True

    if changed and not dry:
        path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    return changed, "migrated" if changed else "unchanged"


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    total = changed = 0
    for d in PRESET_DIRS:
        if not d.is_dir():
            continue
        for fp in sorted(d.glob("*.json")):
            total += 1
            did, msg = migrate_file(fp, dry)
            changed += 1 if did else 0
            flag = "CHANGED" if did else "  ok   "
            print(f"  [{flag}] {fp.name}: {msg}")
    verb = "would change" if dry else "changed"
    print(f"\n{verb} {changed}/{total} preset(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
