#!/usr/bin/env bash
# Deserialize all plugin YAML mirrors under spriggit/ into binary .esp files.
#
# We don't commit the binary ESPs to git — only the Spriggit YAML mirrors
# (one folder per plugin under spriggit/). This script rebuilds the .esp files
# from those YAML sources, dropping the output into _build/esps/.
#
# build_fomod.sh calls this first; you can also run it standalone before
# deploying to MO2 manually.
#
# Usage:
#   bash tools/build_esps.sh                # deserialize every plugin
#   bash tools/build_esps.sh <PluginName>   # deserialize a single plugin
#                                           # (e.g. MTF_Plugin_SkyrimNet)
#
# Requires: spriggit (dotnet global tool, v0.40.x).

set -euo pipefail

PROJ="F:/stuff/MagicTattoosFramework"
SRC="$PROJ/spriggit"
OUT="$PROJ/_build/esps"

if ! command -v spriggit >/dev/null 2>&1; then
    echo "ERROR: spriggit not on PATH. Install with:" >&2
    echo "  dotnet tool install -g Spriggit.CLI" >&2
    exit 1
fi

mkdir -p "$OUT"

if [[ $# -gt 0 ]]; then
    PLUGINS=("$@")
else
    # Auto-discover every plugin folder that has a spriggit-meta.json.
    PLUGINS=()
    while IFS= read -r meta; do
        PLUGINS+=("$(basename "$(dirname "$meta")")")
    done < <(find "$SRC" -mindepth 2 -maxdepth 2 -name 'spriggit-meta.json' | sort)
fi

if [[ ${#PLUGINS[@]} -eq 0 ]]; then
    echo "ERROR: no plugins found under $SRC" >&2
    exit 1
fi

echo "=== Deserializing ${#PLUGINS[@]} plugin(s) to $OUT ==="
for name in "${PLUGINS[@]}"; do
    in_dir="$SRC/$name"
    out_esp="$OUT/$name.esp"
    if [[ ! -f "$in_dir/spriggit-meta.json" ]]; then
        echo "  ! skip $name — no spriggit-meta.json at $in_dir" >&2
        continue
    fi
    # Spriggit reads PackageName/Version/Release from spriggit-meta.json,
    # so --GameRelease MUST NOT be passed to deserialize.
    spriggit deserialize \
        --InputPath "$in_dir" \
        --OutputPath "$out_esp" \
        >/dev/null
    size=$(stat -c %s "$out_esp" 2>/dev/null || stat -f %z "$out_esp")
    echo "  + $name.esp (${size} bytes)"
done

echo "=== Done ==="
