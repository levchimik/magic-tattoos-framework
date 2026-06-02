#!/usr/bin/env python3
"""Remap `mtf.base:<id>` keys in preset JSON files to their themed module.

The v0.3.9 split moved the monolithic mtf.base pack into 5 themed modules. Preset
files store the bound key by value in two places:
  - condition: slot[].cond.items[].pluginid   e.g. "mtf.base:magicka.below"
  - effect:    slot[].effect[].key            e.g. "mtf.base:modify.skill"
Both are "<pluginid>:<id>" strings. This rewrites the pluginid to the new module
using the same id→module map the catalog generator emits (imported below, so the
mapping is single-source-of-truth). The id strings are unchanged.

Condition and effect id namespaces don't overlap, so a single id→module lookup is
unambiguous and we can rewrite any "mtf.base:<id>" string wherever it appears.

Run (default targets — shipped presets in the repo):
  python tools/migrate_preset_modules.py
Extra targets (e.g. the user's deployed / overwrite preset dirs):
  python tools/migrate_preset_modules.py "F:/Modlists/.../overwrite/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets"

Idempotent: a key already pointing at a module is left alone. Files with no
mtf.base keys are untouched (not rewritten).
"""

import json
import sys
from pathlib import Path

from build_base_catalog import CONDITION_MODULE, EFFECT_MODULE

REPO = Path(__file__).resolve().parents[1]

# Combined id → module. Assert no id collisions across the two namespaces so the
# flat lookup stays unambiguous.
ID_TO_MODULE = {}
for _src in (CONDITION_MODULE, EFFECT_MODULE):
    for _id, _mod in _src.items():
        assert _id not in ID_TO_MODULE, f"id {_id!r} in both cond and eff maps"
        ID_TO_MODULE[_id] = _mod

_SUD = "SKSE/Plugins/StorageUtilData/MagicTattoosFramework"
DEFAULT_TARGETS = [
    REPO / "examples" / "presets",
    REPO / "data" / _SUD / "presets_builtin",
    # Test-fixture presets shipped via the test-pack overlay (deploy to the
    # same StorageUtilData/.../presets/ path in MO2).
    REPO / "test-pack" / _SUD / "presets",
]

OLD_PREFIX = "mtf.base:"


def _remap_value(val):
    """Return the rewritten string, or None if no change."""
    if not isinstance(val, str) or not val.startswith(OLD_PREFIX):
        return None
    bare = val[len(OLD_PREFIX):]
    mod = ID_TO_MODULE.get(bare)
    if mod is None:
        print(f"    WARN: unknown id {bare!r} (left as-is)")
        return None
    return f"{mod}:{bare}"


def _walk(obj):
    """Recursively rewrite in place. Returns number of keys changed."""
    n = 0
    if isinstance(obj, dict):
        for k, v in obj.items():
            nv = _remap_value(v)
            if nv is not None:
                obj[k] = nv
                n += 1
            else:
                n += _walk(v)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            nv = _remap_value(v)
            if nv is not None:
                obj[i] = nv
                n += 1
            else:
                n += _walk(v)
    return n


def _process_file(path: Path) -> int:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"  SKIP {path.name}: {e}")
        return 0
    changed = _walk(data)
    if changed:
        path.write_text(
            json.dumps(data, indent=1, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"  {path.name}: rewrote {changed} key(s)")
    return changed


def main():
    targets = [Path(a) for a in sys.argv[1:]] or DEFAULT_TARGETS
    files = []
    for t in targets:
        if t.is_dir():
            files.extend(sorted(t.glob("*.json")))
        elif t.is_file():
            files.append(t)
        else:
            print(f"  (target not found, skipped: {t})")
    total_files = 0
    total_keys = 0
    for f in files:
        c = _process_file(f)
        if c:
            total_files += 1
            total_keys += c
    print(f"Done: {total_keys} key(s) across {total_files} file(s) "
          f"(scanned {len(files)}).")


if __name__ == "__main__":
    main()
