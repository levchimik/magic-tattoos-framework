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
    targets=("$@")
else
    targets=(MTF_HitListener MTF_Plugin MTF_Plugin_Base MTF_Plugin_FMR MTF_Plugin_SLA MTF_MainQuest MTF_MCMQuest MTF_ApplyTattoo)
fi

for t in "${targets[@]}"; do
    f="${t%.psc}.psc"
    echo "=== $f ==="
    "$CAPRICA" --game skyrim -f "$FLAGS" -i ".;$DEPS" -o . "$f"
done
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
