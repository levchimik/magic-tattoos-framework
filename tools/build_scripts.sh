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

cd "$SRC"

if [[ $# -gt 0 ]]; then
    targets=("$@")
else
    targets=(MTF_HitListener MTF_Plugin MTF_Plugin_Base MTF_Plugin_FMR MTF_Plugin_SLA MTF_MainQuest MTF_MCMQuest)
fi

for t in "${targets[@]}"; do
    f="${t%.psc}.psc"
    echo "=== $f ==="
    "$CAPRICA" --game skyrim -f "$FLAGS" -i ".;$DEPS" -o . "$f"
done
echo "Build OK"
