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
DEPLOY="F:/Modlists/Modding Essentials/mods/Magic Tattoos Framework/scripts"

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

# Deploy data/SKSE/Plugins/StorageUtilData/* (plugin catalogs, waveforms,
# any other built-in JSONs). MO2 mirrors the same layout under the mod's
# root so the StorageUtilData path resolves identically at runtime.
DATA_SRC="$PROJ/data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework"
DATA_DST="F:/Modlists/Modding Essentials/mods/Magic Tattoos Framework/SKSE/Plugins/StorageUtilData/MagicTattoosFramework"
if [[ -d "$DATA_SRC" && -d "$(dirname "$DATA_DST")" ]]; then
    mkdir -p "$DATA_DST"
    # -r recurses subdirs (plugins/, waveforms/, …); -u skips unchanged.
    cp -ru "$DATA_SRC"/. "$DATA_DST/"
    echo "Deployed data tree to $DATA_DST"
fi

# Also deploy plugin-specific .pex files to their dedicated MO2 mod dirs.
# Per-plugin ESPs (MTF_Plugin_*) live as standalone mods in MO2; their
# scripts/ folder needs to hold the matching .pex or MO2's left-pane priority
# can shadow them with stale copies. Mirror each MTF_Plugin_*.pex into its
# own mod dir if one exists.
MO2_MODS="F:/Modlists/Modding Essentials/mods"
for pex in "$SRC"/MTF_Plugin_*.pex; do
    name=$(basename "$pex" .pex)
    if [[ "$name" == "MTF_Plugin_Base" ]]; then
        # Base lives inside MagicTattoosFramework — already deployed above.
        continue
    fi
    target="$MO2_MODS/$name/scripts"
    if [[ -d "$target" ]]; then
        cp -u "$pex" "$target/"
        echo "Deployed $name.pex to $target"
    fi
done

# Companion alias scripts that live alongside a plugin (e.g. SkyrimNet
# bridge ships MTF_AliasSkyrimNet.pex on the same alias as
# MTF_PluginAliasKick — Quest scripts can't RegisterForModEvent, so the
# mod-event listener is hosted on the alias). Mapping alias→owning plugin
# is explicit so a future bridge with multiple aliases stays declarative.
declare -A ALIAS_TO_PLUGIN=(
    [MTF_AliasSkyrimNet]=MTF_Plugin_SkyrimNet
    [MTF_AliasPresetEventsTest]=MTF_Plugin_PresetEventsTest
)
for alias in "${!ALIAS_TO_PLUGIN[@]}"; do
    apex="$SRC/${alias}.pex"
    plugin="${ALIAS_TO_PLUGIN[$alias]}"
    atgt="$MO2_MODS/$plugin/scripts"
    if [[ -f "$apex" && -d "$atgt" ]]; then
        cp -u "$apex" "$atgt/"
        echo "Deployed $alias.pex to $atgt"
    fi
done
