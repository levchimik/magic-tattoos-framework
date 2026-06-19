#!/usr/bin/env python3
"""Validate MTF plugin catalog JSON files against the v1 schema.

Walks data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/*.json,
checks every catalog against the rules below, prints a flat list of failures
to stderr, and exits non-zero on any failure.

Hook into tools/build_scripts.sh so an invalid catalog fails the build before
the .pex hits the deploy folder.

Schema v2 (as of v0.2.9):

Top level
    schemaversion: int  must be 2
    pluginid:      str  must be non-empty
    pluginlabel:   str  must be non-empty
    conditions:    list of condition objects (may be empty)
    effects:       list of effect objects (may be empty)

Condition object
    id:          str  non-empty, unique within conditions
    label:       str  non-empty
    description: str  may be empty
    param:       optional paramN sub-object (positional param1)
    param2:      optional paramN sub-object

Effect object
    id:          str  non-empty, unique within effects
    label:       str  non-empty
    description: str  may be empty
    kind:        optional, currently only "burst" recognised (absent = continuous)
    param1..param5: optional paramN sub-objects (contiguous from 1)

paramN sub-object
    label:   str         required, non-empty
    default: number|str  required (str id when menu present; number for sliders)
    menu:    optional list of {id: str, label: str} — when present, min/max forbidden;
             default must match one of the menu ids; ids must be unique within the menu
             and match the [a-z0-9_]+ pattern.
    min:     number      required when no menu (slider mode)
    max:     number      required when no menu
    step:    number      optional (slider only)

v0.2.9 migration note: menu options were {value: int, label: str} in v1. The
`value` field was dropped in favour of `id` strings so catalog reorders and
catalog growth never silently rebind stored preset values.

Cross-checks
    No duplicate condition IDs within a single catalog
    No duplicate effect IDs within a single catalog
    For numeric params: min <= default <= max
    paramN must be contiguous starting from 1 (no param3 without param2)
    For conditions: param can exist without param2, but param2 without param is invalid
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

# Where catalogs live, relative to repo root.
CATALOG_DIR = Path("data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins")
EXPECTED_SCHEMAVERSION = 2
ID_PATTERN = __import__("re").compile(r"^[a-z0-9_]+$")
KNOWN_KIND_VALUES = {"burst"}  # absent = continuous; extend when adding new kinds


def _is_number(x: Any) -> bool:
    """True for int/float but explicitly not bool (bool is a subclass of int)."""
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def validate_param(p: dict, breadcrumb: str) -> list[str]:
    """Validate a paramN sub-object. Returns a list of error strings."""
    errors: list[str] = []
    if not isinstance(p, dict):
        return [f"{breadcrumb}: expected object, got {type(p).__name__}"]

    label = p.get("label")
    if not isinstance(label, str) or label == "":
        errors.append(f"{breadcrumb}.label: must be non-empty string")

    has_menu = "menu" in p
    is_text  = p.get("text") is True
    is_color = p.get("color") is True or p.get("color") == 1
    if is_text and has_menu:
        errors.append(
            f"{breadcrumb}: cannot declare both `text: true` and `menu` on the same param"
        )
    if is_color and (has_menu or is_text):
        errors.append(
            f"{breadcrumb}: `color` is mutually exclusive with `menu`/`text`"
        )
    if "default" not in p:
        # Text params: default is optional (defaults to "" — empty seed text).
        if not is_text:
            errors.append(f"{breadcrumb}.default: required field missing")
    elif is_text:
        # Text mode: default is a string (may be empty — the input dialog
        # opens with no seed text). Any string is legal — roleplay flavor.
        if not isinstance(p["default"], str):
            errors.append(
                f"{breadcrumb}.default: must be a string for text params"
            )
    elif has_menu:
        # Menu mode: default is the id string of one of the options.
        if not isinstance(p["default"], str) or p["default"] == "":
            errors.append(
                f"{breadcrumb}.default: must be a non-empty string id when menu present"
            )
    else:
        # Slider mode: default is a number.
        if not _is_number(p["default"]):
            errors.append(f"{breadcrumb}.default: must be a number (slider param)")

    if is_text:
        # Text mode: min/max/step/menu/format are all forbidden — the param
        # is a free-form string fed into an MCM input dialog.
        for k in ("min", "max", "step", "menu", "format"):
            if k in p:
                errors.append(
                    f"{breadcrumb}.{k}: forbidden on text params"
                )
        return errors

    if is_color:
        # Color mode: stored as a 0xRRGGBB int via SkyUI's color swatch.
        # default must be a number; min/max/step/menu/format are forbidden
        # (the swatch covers the full range).
        if "default" in p and not _is_number(p["default"]):
            errors.append(f"{breadcrumb}.default: must be a number (color param, 0xRRGGBB)")
        for k in ("min", "max", "step", "menu", "format"):
            if k in p:
                errors.append(
                    f"{breadcrumb}.{k}: forbidden on color params"
                )
        return errors

    if has_menu:
        m = p["menu"]
        if not isinstance(m, list) or len(m) == 0:
            errors.append(f"{breadcrumb}.menu: must be non-empty list of {{id, label}}")
        else:
            menu_ids: list[str] = []
            seen_ids: set[str] = set()
            for i, item in enumerate(m):
                bc = f"{breadcrumb}.menu[{i}]"
                if not isinstance(item, dict):
                    errors.append(f"{bc}: expected object")
                    continue
                opt_id = item.get("id")
                lbl    = item.get("label")
                if not isinstance(opt_id, str) or opt_id == "":
                    errors.append(f"{bc}.id: must be non-empty string")
                elif not ID_PATTERN.match(opt_id):
                    errors.append(
                        f"{bc}.id: {opt_id!r} must match [a-z0-9_]+"
                    )
                elif opt_id in seen_ids:
                    errors.append(
                        f"{bc}.id: duplicate {opt_id!r} within this menu"
                    )
                else:
                    seen_ids.add(opt_id)
                    menu_ids.append(opt_id)
                if not isinstance(lbl, str) or lbl == "":
                    errors.append(f"{bc}.label: must be non-empty string")
                # v0.2.9: legacy `value` field must not appear (migrator strips it).
                if "value" in item:
                    errors.append(
                        f"{bc}: legacy `value` field present; re-run "
                        f"tools/migrate_to_string_ids.py"
                    )
            # default must match one of the menu ids
            d = p.get("default")
            if isinstance(d, str) and menu_ids and d not in menu_ids:
                errors.append(
                    f"{breadcrumb}.default ({d!r}) is not one of the menu ids {menu_ids}"
                )
        # min/max are meaningless on menu params and must be absent.
        for k in ("min", "max", "step"):
            if k in p:
                errors.append(
                    f"{breadcrumb}.{k}: forbidden on menu params (v0.2.9 schema)"
                )
    else:
        # Numeric range mode — min/max required, default must be in range.
        if "min" not in p:
            errors.append(f"{breadcrumb}.min: required field missing (numeric param with no menu)")
        elif not _is_number(p["min"]):
            errors.append(f"{breadcrumb}.min: must be a number")
        if "max" not in p:
            errors.append(f"{breadcrumb}.max: required field missing (numeric param with no menu)")
        elif not _is_number(p["max"]):
            errors.append(f"{breadcrumb}.max: must be a number")
        if "step" in p and not _is_number(p["step"]):
            errors.append(f"{breadcrumb}.step: must be a number")
        if (
            _is_number(p.get("min"))
            and _is_number(p.get("max"))
            and _is_number(p.get("default"))
        ):
            mn, mx, df = p["min"], p["max"], p["default"]
            if mn > mx:
                errors.append(f"{breadcrumb}: min ({mn}) > max ({mx})")
            if df < mn or df > mx:
                errors.append(
                    f"{breadcrumb}: default ({df}) outside [min={mn}, max={mx}]"
                )

    return errors


def validate_condition(c: dict, idx: int, plugin_id: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(c, dict):
        return [f"{plugin_id} conditions[{idx}]: expected object, got {type(c).__name__}"]

    cond_id = c.get("id")
    breadcrumb_cond = (
        f"{plugin_id} conditions[{idx}] (id={cond_id!r})"
        if isinstance(cond_id, str)
        else f"{plugin_id} conditions[{idx}]"
    )

    if not isinstance(cond_id, str) or cond_id == "":
        errors.append(f"{breadcrumb_cond}.id: must be non-empty string")
    if not isinstance(c.get("label"), str) or c.get("label") == "":
        errors.append(f"{breadcrumb_cond}.label: must be non-empty string")
    if not isinstance(c.get("description"), str):
        errors.append(f"{breadcrumb_cond}.description: must be string (may be empty)")

    # param / param2 / param3 — contiguous: a higher paramN without its
    # predecessor is invalid (param3 requires param2 requires param).
    if "param2" in c and "param" not in c:
        errors.append(f"{breadcrumb_cond}: param2 present without param")
    if "param3" in c and "param2" not in c:
        errors.append(f"{breadcrumb_cond}: param3 present without param2")
    if "param" in c:
        errors += validate_param(c["param"], f"{breadcrumb_cond}.param")
    if "param2" in c:
        errors += validate_param(c["param2"], f"{breadcrumb_cond}.param2")
    if "param3" in c:
        errors += validate_param(c["param3"], f"{breadcrumb_cond}.param3")

    # Unknown keys warning — catches typos like "paarm" or "lable"
    known = {"id", "label", "description", "param", "param2", "param3"}
    extra = set(c.keys()) - known
    if extra:
        errors.append(f"{breadcrumb_cond}: unknown keys {sorted(extra)}")

    return errors


def validate_effect(e: dict, idx: int, plugin_id: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(e, dict):
        return [f"{plugin_id} effects[{idx}]: expected object, got {type(e).__name__}"]

    fx_id = e.get("id")
    breadcrumb_fx = (
        f"{plugin_id} effects[{idx}] (id={fx_id!r})"
        if isinstance(fx_id, str)
        else f"{plugin_id} effects[{idx}]"
    )

    if not isinstance(fx_id, str) or fx_id == "":
        errors.append(f"{breadcrumb_fx}.id: must be non-empty string")
    if not isinstance(e.get("label"), str) or e.get("label") == "":
        errors.append(f"{breadcrumb_fx}.label: must be non-empty string")
    if not isinstance(e.get("description"), str):
        errors.append(f"{breadcrumb_fx}.description: must be string (may be empty)")
    if "kind" in e:
        if e["kind"] not in KNOWN_KIND_VALUES:
            errors.append(
                f"{breadcrumb_fx}.kind: {e['kind']!r} not in known kinds "
                f"{sorted(KNOWN_KIND_VALUES)} (absent = continuous)"
            )

    # param1..param5 contiguous from 1
    present = []
    for n in range(1, 6):
        key = f"param{n}"
        if key in e:
            present.append(n)
            errors += validate_param(e[key], f"{breadcrumb_fx}.{key}")
    if present and present != list(range(1, present[-1] + 1)):
        errors.append(
            f"{breadcrumb_fx}: paramN must be contiguous starting at param1; got param{present}"
        )

    known = {"id", "label", "description", "kind", "param1", "param2", "param3", "param4", "param5"}
    extra = set(e.keys()) - known
    if extra:
        errors.append(f"{breadcrumb_fx}: unknown keys {sorted(extra)}")

    return errors


def validate_catalog(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        with path.open(encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return [f"{path}: invalid JSON — {e}"]
    except OSError as e:
        return [f"{path}: cannot open — {e}"]

    if not isinstance(data, dict):
        return [f"{path}: root must be an object"]

    pid = data.get("pluginid", "<unknown>")

    # Top-level fields
    sv = data.get("schemaversion")
    if sv != EXPECTED_SCHEMAVERSION:
        errors.append(
            f"{path}: schemaversion expected {EXPECTED_SCHEMAVERSION}, got {sv!r}"
        )
    if not isinstance(data.get("pluginid"), str) or data.get("pluginid") == "":
        errors.append(f"{path}: pluginid must be non-empty string")
    if not isinstance(data.get("pluginlabel"), str) or data.get("pluginlabel") == "":
        errors.append(f"{path}: pluginlabel must be non-empty string")

    # Filename ↔ pluginid sanity: mtf.base.json should declare pluginid "mtf.base"
    expected_pid = path.stem
    if isinstance(data.get("pluginid"), str) and data["pluginid"] != expected_pid:
        errors.append(
            f"{path}: pluginid {data['pluginid']!r} does not match filename stem "
            f"{expected_pid!r}"
        )

    # Conditions
    conditions = data.get("conditions")
    if conditions is None:
        errors.append(f"{path}: conditions field missing (use [] for none)")
    elif not isinstance(conditions, list):
        errors.append(f"{path}: conditions must be a list")
    else:
        seen_ids: dict[str, int] = {}
        for i, c in enumerate(conditions):
            errors += validate_condition(c, i, pid)
            if isinstance(c, dict) and isinstance(c.get("id"), str):
                if c["id"] in seen_ids:
                    errors.append(
                        f"{pid} conditions: duplicate id {c['id']!r} "
                        f"at index {i} (first seen at index {seen_ids[c['id']]})"
                    )
                else:
                    seen_ids[c["id"]] = i

    # Effects
    effects = data.get("effects")
    if effects is None:
        errors.append(f"{path}: effects field missing (use [] for none)")
    elif not isinstance(effects, list):
        errors.append(f"{path}: effects must be a list")
    else:
        seen_ids = {}
        for i, e in enumerate(effects):
            errors += validate_effect(e, i, pid)
            if isinstance(e, dict) and isinstance(e.get("id"), str):
                if e["id"] in seen_ids:
                    errors.append(
                        f"{pid} effects: duplicate id {e['id']!r} "
                        f"at index {i} (first seen at index {seen_ids[e['id']]})"
                    )
                else:
                    seen_ids[e["id"]] = i

    known_top = {"schemaversion", "pluginid", "pluginlabel", "conditions", "effects"}
    extra = set(data.keys()) - known_top
    if extra:
        errors.append(f"{path}: unknown top-level keys {sorted(extra)}")

    return errors


def main(argv: list[str]) -> int:
    # Allow override via argv[1] for unit testing; default to repo-relative path.
    catalog_dir = Path(argv[1]) if len(argv) > 1 else CATALOG_DIR
    if not catalog_dir.is_dir():
        print(f"validate_catalogs: directory not found: {catalog_dir}", file=sys.stderr)
        return 2

    catalogs = sorted(catalog_dir.glob("*.json"))
    if not catalogs:
        print(f"validate_catalogs: no *.json files in {catalog_dir}", file=sys.stderr)
        return 2

    all_errors: list[str] = []
    for cat in catalogs:
        errors = validate_catalog(cat)
        if errors:
            all_errors.extend(errors)

    if all_errors:
        print(
            f"validate_catalogs: {len(all_errors)} error(s) across {len(catalogs)} catalog(s):",
            file=sys.stderr,
        )
        for err in all_errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(f"validate_catalogs: OK — {len(catalogs)} catalog(s) clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
