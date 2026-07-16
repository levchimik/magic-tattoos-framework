#!/usr/bin/env bash
# tools/release_check.sh — static pre-release gate for Magic Tattoos Framework.
# Green = no known static shipping defect. NOT a substitute for the in-game smoke pass.
# Exit 0 = all hard checks pass. Exit 1 = >=1 FAIL. WARN never fails the run.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT/source/scripts"
fails=0; warns=0
red() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; fails=$((fails+1)); }
grn() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
ylw() { printf '\033[33mWARN\033[0m  %s\n' "$1"; warns=$((warns+1)); }

echo "== MTF release check =="
echo "root: $ROOT"
echo

# Only scan live source: .psc files, no .bak / .pex / backups.
PSC_GREP=(grep -nE --include='*.psc' --exclude='*.bak*' -r)

# 1. DebugMode must not be force-enabled.
if "${PSC_GREP[@]}" 'DebugMode[[:space:]]*=[[:space:]]*true' "$SRC" >/dev/null 2>&1; then
  red "DebugMode force-enabled (must default false):"
  "${PSC_GREP[@]}" 'DebugMode[[:space:]]*=[[:space:]]*true' "$SRC" | sed 's/^/        /'
else
  grn "DebugMode not force-enabled"
fi

# 2. No leftover debug scaffolding / 'remove before release' markers.
MARK='\[MTF(wipe|diag|black|bio)\]|remove before release|Revert before shipping|DESTRUCTIVE SEED'
if "${PSC_GREP[@]}" -i "$MARK" "$SRC" >/dev/null 2>&1; then
  red "Leftover debug markers / scaffolding:"
  "${PSC_GREP[@]}" -i "$MARK" "$SRC" | sed 's/^/        /'
else
  grn "No leftover debug markers"
fi

# 3. Test/stress artifacts must not be in the required base FOMOD step.
BASE="$ROOT/_build/fomod-stage/00_base"
if [ -d "$BASE" ]; then
  hits="$(find "$BASE" -type f \( -iname '*Stress*' -o -iname 'MTF_TestRunner.pex' \) 2>/dev/null)"
  if [ -n "$hits" ]; then
    red "Test/stress artifacts staged in required 00_base:"
    printf '%s\n' "$hits" | sed 's/^/        /'
  else
    grn "No test artifacts in base FOMOD step"
  fi
else
  ylw "No _build/fomod-stage/00_base yet — base-content check skipped (run after a build)"
fi

# 4. Version-mislabel guard.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  tag="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || echo '')"
  if [ -n "$tag" ]; then
    ahead="$(git -C "$ROOT" rev-list "${tag}..HEAD" --count 2>/dev/null || echo 0)"
    subj="$(git -C "$ROOT" log -1 --pretty=%s 2>/dev/null || echo '')"
    if [ "${MTF_VERSION:-}" = "" ] && [ "$ahead" -gt 0 ] && ! printf '%s' "$subj" | grep -qE 'v[0-9]+\.[0-9]+\.[0-9]+'; then
      ylw "HEAD is $ahead commit(s) past tag $tag, no MTF_VERSION, no version in latest commit subject."
      ylw "  -> build_fomod.sh would reuse '$tag' and mislabel the build. Set MTF_VERSION=vX.Y.Z or tag first."
    else
      grn "Version source resolvable (tag=$tag, ahead=$ahead, MTF_VERSION='${MTF_VERSION:-unset}')"
    fi
  else
    ylw "No git tags — version falls back to v0.0.0-dev unless MTF_VERSION set"
  fi
else
  ylw "git unavailable — version check skipped"
fi

# 5. Catalog JSON validation — delegate to existing validator.
V="$ROOT/tools/validate_catalogs.py"
if [ -f "$V" ]; then
  if command -v python >/dev/null 2>&1; then PY=python
  elif command -v python3 >/dev/null 2>&1; then PY=python3
  else PY=""; fi
  if [ -n "$PY" ]; then
    if ( cd "$ROOT" && "$PY" "$V" >/dev/null 2>&1 ); then
      grn "Catalog validation passed"
    else
      red "Catalog validation failed — run: $PY $V"
    fi
  else
    ylw "no python on PATH — catalog validation skipped"
  fi
else
  ylw "tools/validate_catalogs.py missing — skipped"
fi

# 6. Stale .pex guard.
stale=0
shopt -s nullglob
for psc in "$SRC"/*.psc; do
  pex="${psc%.psc}.pex"
  if [ ! -f "$pex" ] || [ "$psc" -nt "$pex" ]; then
    ylw "stale/missing .pex for $(basename "$psc") — rebuild scripts"
    stale=$((stale+1))
  fi
done
[ "$stale" -eq 0 ] && grn "All .pex up to date with .psc"

# 7. DLL copy-divergence guard. build.bat syncs Release output -> data/ on
# every successful build, so a mismatch means a manual copy went stale (the
# exact failure that shipped a May-31 DLL in data/ until 2026-07-12). Only a
# real risk when MTF_SKIP_DLL=1 makes the FOMOD fall back to data/, so:
# mismatch = FAIL, missing build output = WARN (freshness unverifiable).
BUILT_DLL="$ROOT/cpp-plugin/build/x64-Release/Release/MTFPulse.dll"
DATA_DLL="$ROOT/data/SKSE/Plugins/MTFPulse.dll"
if [ -f "$BUILT_DLL" ] && [ -f "$DATA_DLL" ]; then
  if cmp -s "$BUILT_DLL" "$DATA_DLL"; then
    grn "data/ MTFPulse.dll matches build output"
  else
    red "data/SKSE/Plugins/MTFPulse.dll differs from build output — stale copy; re-run cpp-plugin/build.bat"
  fi
  newer_src="$(find "$ROOT/cpp-plugin/src" -name '*.cpp' -newer "$BUILT_DLL" 2>/dev/null | head -1)"
  [ -n "$newer_src" ] && ylw "C++ source newer than built DLL ($(basename "$newer_src")) — rebuild before shipping"
elif [ -f "$DATA_DLL" ]; then
  ylw "no build-dir DLL to compare against — data/ DLL freshness unverifiable (risky with MTF_SKIP_DLL=1)"
else
  ylw "no MTFPulse.dll found at all — FOMOD would ship without the SKSE plugin"
fi

echo
if [ "$fails" -gt 0 ]; then
  printf '\033[31m== %d FAIL, %d WARN — not release-ready ==\033[0m\n' "$fails" "$warns"
  exit 1
fi
printf '\033[32m== 0 FAIL, %d WARN — static checks clean ==\033[0m\n' "$warns"
echo "(Static only — run the in-game smoke pass before publishing.)"
exit 0
