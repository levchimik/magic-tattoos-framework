#!/usr/bin/env python3
"""One-shot migrator: menu-param values int -> string id.

Reads all 7 catalog JSONs (mtf.*.json under data/SKSE/Plugins/StorageUtilData/
MagicTattoosFramework/plugins/), builds a (plugin_id, item_id, paramKey,
old_value) -> new_id lookup from the existing menu entries, migrates every
preset JSON under test-pack/ and content-packs/ using that lookup, then
writes the catalogs in the new schema.

New schema per menu option:  {"id": "snake_case", "label": "Display Label"}
(was: {"value": <int>, "label": "..."})

Menu-bearing params also lose `min`/`max` (no longer meaningful) and convert
`default` from int to the matching id string.

Per-catalog `schemaversion` bumps 1 -> 2. Plugin schema version (Papyrus
PLUGIN_SCHEMA_VERSION) also bumps so old plugin catalogs hard-fail.

Idempotent: re-running on already-migrated catalogs is a no-op.

Usage:
    python tools/migrate_to_string_ids.py [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CATALOG_DIR = REPO / "data" / "SKSE" / "Plugins" / "StorageUtilData" \
    / "MagicTattoosFramework" / "plugins"
PRESET_ROOTS = [
    REPO / "test-pack" / "SKSE" / "Plugins" / "StorageUtilData"
        / "MagicTattoosFramework" / "presets",
    REPO / "content-packs",
]

NEW_CATALOG_SCHEMAVERSION = 2


def to_id(label: str) -> str:
    """Derive a snake_case id from a display label.

    'One-Handed'                 -> 'one_handed'
    'Player Home'                -> 'player_home'
    'Frost Chillrend'            -> 'frost_chillrend'
    'Ghost (Ethereal)'           -> 'ghost_ethereal'
    'Fire — ready loop'     -> 'fire_ready_loop'   (em-dash)
    'Melee (Blunt + Bladed)'     -> 'melee_blunt_bladed'
    'All combat classes'         -> 'all_combat_classes'
    'On spell cast'              -> 'on_spell_cast'
    """
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")


def each_menu_param(catalog: dict):
    """Yield (item_id, param_key, param_dict) for every menu-bearing param.

    Covers both `conditions[].param/param2` and `effects[].param1..param5`.
    """
    for section in ("conditions", "effects"):
        for item in catalog.get(section, []) or []:
            item_id = item.get("id", "?")
            for pkey, pval in list(item.items()):
                if not isinstance(pval, dict):
                    continue
                if "menu" not in pval:
                    continue
                yield item_id, pkey, pval


def build_lookup(catalogs: dict[Path, dict]) -> dict:
    """Walk every menu option across all catalogs and build:

        {(plugin_id, item_id, param_key, old_value): new_id}

    plus a side map of generated ids per menu so we can disambiguate
    label collisions WITHIN a single menu.

    Idempotency: if an option already has `id`, that id wins. If `value`
    is missing (already migrated), it just doesn't contribute a lookup
    entry (the preset migrator is no-op for that param).
    """
    lookup: dict[tuple, str] = {}
    for path, d in catalogs.items():
        plugin_id = d.get("pluginid") or path.stem
        for item_id, pkey, p in each_menu_param(d):
            seen_ids: set[str] = set()
            for opt in p.get("menu", []):
                # Already migrated?
                if "id" in opt and opt["id"]:
                    new_id = opt["id"]
                else:
                    label = opt.get("label", "")
                    new_id = to_id(label)
                    if not new_id:
                        raise ValueError(
                            f"{path.name}: empty id derived from label "
                            f"{label!r} in {item_id}/{pkey}"
                        )
                    # Disambiguate collisions inside this menu (rare)
                    base = new_id
                    n = 2
                    while new_id in seen_ids:
                        new_id = f"{base}_{n}"
                        n += 1
                seen_ids.add(new_id)
                if "value" in opt:
                    key = (plugin_id, item_id, pkey, opt["value"])
                    if key in lookup and lookup[key] != new_id:
                        raise ValueError(
                            f"{path.name}: duplicate value {opt['value']} in "
                            f"{item_id}/{pkey} would map to both "
                            f"{lookup[key]!r} and {new_id!r}"
                        )
                    lookup[key] = new_id
    return lookup


def rewrite_catalog(catalog: dict, plugin_id: str, lookup: dict) -> bool:
    """Apply the new schema to one catalog dict in-place. Returns True
    when changes were made.

    Steps per menu-bearing param:
    1. Each option gets `id`; `value` is dropped.
    2. `min` and `max` are dropped (no longer constrain anything).
    3. `default` int becomes the matching id string.
    """
    changed = False
    for item_id, pkey, p in each_menu_param(catalog):
        # Step 1: option ids.
        seen_ids: set[str] = set()
        for opt in p["menu"]:
            if "id" not in opt or not opt["id"]:
                label = opt.get("label", "")
                new_id = to_id(label)
                base = new_id
                n = 2
                while new_id in seen_ids:
                    new_id = f"{base}_{n}"
                    n += 1
                opt["id"] = new_id
                changed = True
            seen_ids.add(opt["id"])
            if "value" in opt:
                del opt["value"]
                changed = True
        # Step 2: drop min/max on menu params.
        for k in ("min", "max"):
            if k in p:
                del p[k]
                changed = True
        # Step 3: default int -> id string.
        if "default" in p:
            dv = p["default"]
            if isinstance(dv, int):
                # Find the id whose old value matched.
                new_default = lookup.get((plugin_id, item_id, pkey, dv))
                if new_default is None:
                    # Old default didn't match any menu option (orphan).
                    # Fall back to first menu option's id; print a warning.
                    new_default = p["menu"][0]["id"]
                    print(
                        f"  WARN: {plugin_id}.{item_id}.{pkey} default={dv} "
                        f"not in menu; using {new_default!r} (first option)"
                    )
                p["default"] = new_default
                changed = True
    if catalog.get("schemaversion") != NEW_CATALOG_SCHEMAVERSION:
        catalog["schemaversion"] = NEW_CATALOG_SCHEMAVERSION
        changed = True
    return changed


def migrate_presets(lookup: dict, menu_param_keys: set, dry_run: bool) -> tuple[int, int]:
    """Walk every preset .json under PRESET_ROOTS, rewrite int menu params
    to string ids. Returns (files_touched, rewrites)."""
    files_touched = 0
    rewrites = 0
    for root in PRESET_ROOTS:
        if not root.exists():
            continue
        for preset_path in root.rglob("*.json"):
            try:
                d = json.loads(preset_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as e:
                print(f"  SKIP: {preset_path}: {e}")
                continue
            if not isinstance(d, dict):
                continue
            changed = False
            slots = d.get("slot")
            if not isinstance(slots, list):
                continue
            for s_idx, slot in enumerate(slots):
                if not isinstance(slot, dict):
                    continue
                # Cond param/param2. pluginid format is "<plugin_id>:<item_id>"
                # (e.g. "mtf.bfng:cycle.phase"), NOT "/".
                cond = slot.get("cond")
                if isinstance(cond, dict):
                    cond_key = cond.get("pluginid", "")
                    if ":" in cond_key:
                        plugin_id, item_id = cond_key.split(":", 1)
                        for jkey, pkey in (("param", "param"), ("param2", "param2")):
                            if jkey in cond and (plugin_id, item_id, pkey) in menu_param_keys:
                                old = cond[jkey]
                                if isinstance(old, int):
                                    new = lookup.get((plugin_id, item_id, pkey, old))
                                    if new is not None:
                                        cond[jkey] = new
                                        changed = True
                                        rewrites += 1
                                    else:
                                        print(
                                            f"  WARN: {preset_path.name} slot[{s_idx}] "
                                            f"cond.{jkey}={old} not in {plugin_id}.{item_id} "
                                            f"menu; leaving as-is"
                                        )
                # Effect param1..5. Same ":" separator on effect key.
                for e_idx, eff in enumerate(slot.get("effect", []) or []):
                    if not isinstance(eff, dict):
                        continue
                    eff_key = eff.get("key", "")
                    if ":" not in eff_key:
                        continue
                    plugin_id, item_id = eff_key.split(":", 1)
                    for n in range(1, 6):
                        jkey = f"param{n}"
                        pkey = f"param{n}"
                        if jkey in eff and (plugin_id, item_id, pkey) in menu_param_keys:
                            old = eff[jkey]
                            if isinstance(old, int):
                                new = lookup.get((plugin_id, item_id, pkey, old))
                                if new is not None:
                                    eff[jkey] = new
                                    changed = True
                                    rewrites += 1
                                else:
                                    print(
                                        f"  WARN: {preset_path.name} slot[{s_idx}] "
                                        f"effect[{e_idx}].{jkey}={old} not in "
                                        f"{plugin_id}.{item_id} menu; leaving as-is"
                                    )
            if changed:
                files_touched += 1
                if not dry_run:
                    preset_path.write_text(
                        json.dumps(d, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8",
                    )
                print(f"  {'(dry) ' if dry_run else ''}{preset_path.relative_to(REPO)}")
    return files_touched, rewrites


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="Don't write any files")
    args = ap.parse_args()

    # Step 1: read all catalogs into memory.
    catalogs: dict[Path, dict] = {}
    for p in sorted(CATALOG_DIR.glob("mtf.*.json")):
        catalogs[p] = json.loads(p.read_text(encoding="utf-8"))
    print(f"loaded {len(catalogs)} catalogs")

    # Step 2: build the value -> id lookup BEFORE rewriting anything.
    lookup = build_lookup(catalogs)
    print(f"built {len(lookup)} value->id mappings")
    if lookup:
        sample = sorted(list(lookup.items()))[:5]
        for k, v in sample:
            print(f"    {k} -> {v!r}")
        if len(lookup) > 5:
            print(f"    ... +{len(lookup) - 5} more")

    # Set of (plugin_id, item_id, param_key) that are menu-typed.
    menu_param_keys = {(plugin_id, item_id, pkey)
                       for (plugin_id, item_id, pkey, _) in lookup.keys()}

    # Step 3: migrate presets using the lookup.
    print("\n=== migrating presets ===")
    files, rewrites = migrate_presets(lookup, menu_param_keys, args.dry_run)
    print(f"-- {files} files touched, {rewrites} param rewrites --")

    # Step 4: rewrite catalogs.
    print("\n=== rewriting catalogs ===")
    for p, d in catalogs.items():
        plugin_id = d.get("pluginid") or p.stem
        if rewrite_catalog(d, plugin_id, lookup):
            print(f"  {'(dry) ' if args.dry_run else ''}{p.relative_to(REPO)}")
            if not args.dry_run:
                p.write_text(
                    json.dumps(d, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8",
                )
        else:
            print(f"  (unchanged) {p.relative_to(REPO)}")

    print("\nOK")


if __name__ == "__main__":
    main()
