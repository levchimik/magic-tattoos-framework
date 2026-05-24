#!/usr/bin/env python3
"""Refactor MTF_Plugin_Base.psc: strip the metadata getters that are now
JSON-driven via the MTF_Plugin base class.

Inputs:  source/scripts/MTF_Plugin_Base.psc (pre-refactor — 3903 lines)
Output:  source/scripts/MTF_Plugin_Base.psc (rewritten in place — ~2000 lines)

What stays in Papyrus:
  • GetPluginId() — needed; the base class reads it to derive the catalog path.
  • All behaviour: onActivate, onDeactivate, onTick.
  • Category-dispatch helpers used by behaviour: _isAbsShift, _isAbsShiftFloatMult,
    _isToggle, _isBurstAV, _avNameFor, _avNameForLow, _avNameForHigh.
  • All _apply*/_remove*/_recompute*/_tick* effect runtime helpers.
  • All spell/keyword/faction property resolvers.
  • Shader and sound FormID resolvers (_shaderFormId, _soundFormId,
    _resolveShader, _resolveSound) — runtime ID lookup.
  • Legacy property block and _migrateLegacyApplied path (save compat).
  • checkCondition + all its supporting scan/check helpers.

What gets cut:
  • Every Get* metadata getter — now JSON-driven by MTF_Plugin's base class
    (it reads .conditions[idx] / .effects[idx] from
    Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.base.json).
  • Split-function helpers _effectIdLow / _effectLabelHigh / etc. — only callers
    were the deleted getters.
  • _shaderCount / _shaderLabel / _soundCount / _soundLabel — only callers were
    GetEffectParamMenu* for idx 55/56 and GetEffectParamMax (also deleted).

Run:  python tools/refactor_base_psc.py
"""

import re
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "source" / "scripts" / "MTF_Plugin_Base.psc"

# Function names to delete. Empty Function/EndFunction blocks are dropped
# wholesale, including any contiguous leading block comments (`;`-prefixed
# lines or `{...}` docstrings) and any blank lines immediately preceding.
DELETE_FUNCS = {
    # Plugin-label (returns "Base" — now in JSON .pluginlabel)
    "GetPluginLabel",
    # Conditions — every Get* metadata getter
    "GetConditionCount",
    "GetConditionId",
    "GetConditionLabel",
    "GetConditionDescription",
    "GetConditionParamLabel",
    "GetConditionParamMin",
    "GetConditionParamMax",
    "GetConditionParamDefault",
    "GetConditionParam2Label",
    "GetConditionParam2Min",
    "GetConditionParam2Max",
    "GetConditionParam2Default",
    # Effects — every Get* metadata getter
    "GetEffectCount",
    "GetEffectId",
    "_effectIdLow", "_effectIdHigh", "_effectIdVeryHigh",
    "GetEffectLabel",
    "_effectLabelLow", "_effectLabelHigh", "_effectLabelVeryHigh",
    "GetEffectDescription",
    "_effectDescriptionLow", "_effectDescriptionHigh", "_effectDescriptionVeryHigh",
    "GetEffectParamLabel",
    "_effectParamLabelLow", "_effectParamLabelHigh", "_effectParamLabelVeryHigh",
    "GetEffectParamMin", "GetEffectParamMax", "GetEffectParamDefault",
    "GetEffectParamStep", "GetEffectParamFormat",
    "GetEffectParam2Label", "GetEffectParam2Min", "GetEffectParam2Max",
    "GetEffectParam2Default", "GetEffectParam2Step", "GetEffectParam2Format",
    "GetEffectParamMenuOptionCount",
    "GetEffectParamMenuOptionValue",
    "GetEffectParamMenuOptionLabel",
    "GetEffectExtraFieldCount",
    "GetEffectExtraFieldName", "GetEffectExtraFieldLabel",
    "GetEffectExtraFieldMin", "GetEffectExtraFieldMax",
    "GetEffectExtraFieldStep", "GetEffectExtraFieldDefault",
    "GetEffectExtraFieldMenuOptionCount",
    "GetEffectExtraFieldMenuOptionValue",
    "GetEffectExtraFieldMenuOptionLabel",
    # Shader / sound label+count helpers — now in JSON .effects[55|56].param.menu
    "_shaderCount", "_shaderLabel",
    "_soundCount", "_soundLabel",
}

# Match `<ReturnType> Function <Name>(...`
# - return type may be alphanumeric (Spell, Keyword, EffectShader, int, bool, etc.)
# - Function name may start with _
FN_HEAD_RE = re.compile(r"^\s*[A-Za-z_][A-Za-z0-9_]*\s+Function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
# Also bare `Function <Name>(...` form (no return type — void)
FN_HEAD_BARE_RE = re.compile(r"^\s*Function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def fn_name(line: str) -> str | None:
    m = FN_HEAD_RE.match(line)
    if m:
        return m.group(1)
    m = FN_HEAD_BARE_RE.match(line)
    if m:
        return m.group(1)
    return None


def main():
    lines = SRC.read_text(encoding="utf-8").splitlines(keepends=False)
    out: list[str] = []
    i = 0
    n = len(lines)
    deleted_funcs: list[str] = []
    while i < n:
        line = lines[i]
        name = fn_name(line)
        if name and name in DELETE_FUNCS:
            # Walk backwards over `out` to also drop the preceding block of
            # `;` comments / `{...}` doc lines / blank lines that document
            # this function. Stops at an EndFunction line or a non-comment/
            # non-doc line.
            j = len(out) - 1
            in_doc = False
            while j >= 0:
                prev = out[j]
                stripped = prev.strip()
                if stripped == "" or stripped.startswith(";"):
                    j -= 1
                    continue
                # Multi-line `{...}` docstring — walk until opening `{`
                if stripped.endswith("}") and not stripped.startswith("EndFunction"):
                    # Probably a closing line of a docstring; walk up till `{` line
                    k = j
                    while k >= 0 and "{" not in out[k]:
                        k -= 1
                    if k >= 0:
                        j = k - 1
                        continue
                break
            out = out[: j + 1]

            # Skip body up through `EndFunction`.
            deleted_funcs.append(name)
            i += 1
            while i < n and not lines[i].strip().startswith("EndFunction"):
                i += 1
            if i < n and lines[i].strip().startswith("EndFunction"):
                i += 1  # consume EndFunction line itself
            # Also drop a single trailing blank line so deletions don't leave
            # double-blank gaps.
            if i < n and lines[i].strip() == "":
                i += 1
            continue

        out.append(line)
        i += 1

    # Collapse 3+ consecutive blank lines down to 2 (avoid huge gaps left by
    # back-to-back deletions).
    collapsed: list[str] = []
    blanks = 0
    for ln in out:
        if ln.strip() == "":
            blanks += 1
            if blanks <= 2:
                collapsed.append(ln)
        else:
            blanks = 0
            collapsed.append(ln)

    SRC.write_text("\n".join(collapsed) + "\n", encoding="utf-8")
    print(f"Refactored {SRC}")
    print(f"  before: {n} lines")
    print(f"  after:  {len(collapsed)} lines")
    print(f"  deleted: {len(deleted_funcs)} functions")

    # Sanity: confirm every DELETE_FUNCS name was actually present and deleted.
    missing = sorted(set(DELETE_FUNCS) - set(deleted_funcs))
    if missing:
        print(f"  WARNING: {len(missing)} expected functions not found:")
        for n_ in missing:
            print(f"    - {n_}")
    extra = sorted(set(deleted_funcs) - set(DELETE_FUNCS))
    if extra:
        print(f"  WARNING: deleted unexpected functions: {extra}")


if __name__ == "__main__":
    main()
