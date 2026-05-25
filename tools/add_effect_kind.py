#!/usr/bin/env python3
"""One-shot: add `kind` field to each effect across all plugin JSON catalogs
and strip the prefix-as-label convention.

The prefix-in-label convention (`[!]` for bursts, `[+]` for continuous-special,
none for direct-AV) was implementation detail leakage — users don't need to
know how an effect is plumbed, just whether it fires once or stays active.
A structured `kind` field captures the only distinction the framework runtime
actually cares about, and MCM prepends the badge automatically at render time.

`kind` values:
  • "burst"      — fires once on activate; no rolling state; onDeactivate/
                   onTick are no-ops. Audit can ignore these.
  • "continuous" — active while the tier is on; default when omitted.

Note: a single OStim entry was historically mislabeled `[!] Set Excitement
Multiplier` despite its description saying "while active". Fixed in this
same pass.

Run: python tools/add_effect_kind.py
"""

import json
import re
from pathlib import Path

CAT_DIR = Path(__file__).resolve().parents[1] / "data" / "SKSE" / "Plugins" / \
    "StorageUtilData" / "MagicTattoosFramework" / "plugins"

# (plugin_id, effect_idx) tuples for every burst. Sourced by surveying
# descriptions across catalogs — every entry starts with "Burst —" except
# the historical OStim mis-label (idx 4), which is genuinely continuous.
BURSTS = {
    ("mtf.base", 3),  ("mtf.base", 4),  ("mtf.base", 8),
    ("mtf.base", 9),  ("mtf.base", 25), ("mtf.base", 26),
    ("mtf.bfng", 0),
    ("mtf.fmr",  0),
    ("mtf.ostim", 0), ("mtf.ostim", 1), ("mtf.ostim", 2),  # NOT idx 4
    ("mtf.sexlab", 0), ("mtf.sexlab", 1), ("mtf.sexlab", 2),
    ("mtf.sla", 2), ("mtf.sla", 4),
    # mtf.slavetats has no effects yet (only conditions)
}

# Strip `[!] ` or `[+] ` prefix; leave `[deprecated]` and any other tags alone.
PREFIX_RE = re.compile(r"^\[(?:!|\+)\]\s+")


def clean_label(s: str) -> str:
    return PREFIX_RE.sub("", s, count=1)


def main():
    total_burst_marks = 0
    total_label_strips = 0
    for path in sorted(CAT_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        pid = data.get("pluginid", "")
        effects = data.get("effects", [])
        changed = False
        for i, e in enumerate(effects):
            # 1. Strip prefix from label
            old = e.get("label", "")
            new = clean_label(old)
            if new != old:
                e["label"] = new
                total_label_strips += 1
                changed = True

            # 2. Add kind for bursts (omit field for continuous — that's the
            # default the base class will return).
            if (pid, i) in BURSTS:
                if e.get("kind") != "burst":
                    # Insert kind right after description for readability.
                    new_e: dict = {}
                    for k in ("id", "label", "description"):
                        if k in e:
                            new_e[k] = e[k]
                    new_e["kind"] = "burst"
                    for k, v in e.items():
                        if k not in new_e:
                            new_e[k] = v
                    effects[i] = new_e
                    total_burst_marks += 1
                    changed = True
            else:
                # Defensive: if a previous run wrote kind: continuous (we now
                # standardise on omitting), drop it. Idempotent re-runs.
                if e.get("kind") == "continuous":
                    e.pop("kind")
                    changed = True

        if changed:
            path.write_text(
                json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            print(f"  updated {path.name}")

    print(f"Done. Stripped {total_label_strips} prefixes, "
          f"marked {total_burst_marks} bursts.")


if __name__ == "__main__":
    main()
