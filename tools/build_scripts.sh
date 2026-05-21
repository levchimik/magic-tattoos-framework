#!/usr/bin/env bash
# Compile all MTF Papyrus scripts. Run from project root or anywhere.
# Usage:
#   bash tools/build_scripts.sh                  # compile all
#   bash tools/build_scripts.sh MTF_MainQuest    # compile one
set -euo pipefail

PROJ="F:/stuff/MagicTattoosFramework"
CAPRICA="F:/stuff/Skyrim modding/tools/Caprica/Caprica.exe"
FLAGS="S:/SteamLibrary/steamapps/common/Skyrim Special Edition/Data/Source/Scripts/TESV_Papyrus_Flags.flg"
SRC="$PROJ/source/scripts"
DEPS="$PROJ/_deps"
DEPLOY="F:/Modlists/Modding Essentials/mods/MagicTattoosFramework/scripts"

cd "$SRC"

if [[ $# -gt 0 ]]; then
    # Explicit targets: compile only the named scripts (one per Caprica
    # invocation so a per-file syntax error is easier to attribute).
    for t in "$@"; do
        f="${t%.psc}.psc"
        echo "=== $f ==="
        "$CAPRICA" --game skyrim -f "$FLAGS" -i ".;$DEPS" -o . "$f"
    done
else
    # Auto-discover all .psc in source/scripts/ and compile in ONE
    # Caprica invocation. Each separate invocation reloads the ~14k
    # dep imports — batching keeps it to a single load. Roughly 10×
    # wall-clock improvement on a full build vs the previous per-file
    # loop.
    #
    # The `*.psc` glob matches exactly .psc (not .psc.bak etc.). Drop
    # WIP scripts in a sibling folder (e.g. source/scripts/_wip/) if
    # you don't want them auto-compiled.
    shopt -s nullglob
    sources=( *.psc )
    shopt -u nullglob
    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "ERROR: no .psc files found in $SRC"
        exit 1
    fi
    echo "=== compiling ${#sources[@]} scripts ==="
    "$CAPRICA" --game skyrim -f "$FLAGS" -i ".;$DEPS" -o . "${sources[@]}"
fi
echo "Build OK"

# Deploy to MO2 so the running game / next launch picks up changes.
# Without this, source/scripts/*.pex stays current but the game keeps
# loading the stale copies under MO2 — exactly the trap that ate a
# couple of test cycles on 2026-05-17.
if [[ -d "$DEPLOY" ]]; then
    cp -u "$SRC"/*.pex "$DEPLOY/"
    echo "Deployed to $DEPLOY"
else
    echo "WARNING: deploy dir not found, skipping: $DEPLOY"
fi
