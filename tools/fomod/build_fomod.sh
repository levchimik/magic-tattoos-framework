#!/usr/bin/env bash
# Build the MTF FOMOD installer.
#
# Pulls fresh artifacts from the repo (ESPs rebuilt from spriggit/ YAML into
# _build/esps/, .pex from source/scripts/, DLL/INI/waveforms from data/,
# content-pack JSONs from content-packs/, NPC overlays skee64.ini from
# tools/fomod/static/, test pack from test-pack/), arranges them into
# option-folder subtrees under _build/fomod-stage/, copies the FOMOD
# templates into fomod/, and produces an archive in _build/.
#
# Usage:
#   bash tools/fomod/build_fomod.sh                # build with auto-detected version
#   MTF_VERSION=v0.1.18 bash tools/fomod/build_fomod.sh
#
# Requires: bash, cp, find, sed, git; 7z (preferred) or zip for archive.

set -euo pipefail

PROJ="F:/stuff/MagicTattoosFramework"
SRC_SCRIPTS="$PROJ/source/scripts"
DATA="$PROJ/data"
CONTENT="$PROJ/content-packs"
TESTPACK="$PROJ/test-pack"
FOMOD_DIR="$PROJ/tools/fomod"
STATIC="$FOMOD_DIR/static"
TEMPLATES="$FOMOD_DIR/templates"
STAGE="$PROJ/_build/fomod-stage"
DIST="$PROJ/_build"

# ESPs are not committed to git — they're rebuilt from Spriggit YAML mirrors
# under spriggit/. Deserialize all of them up front into _build/esps/ so the
# rest of the script can stage them like any other file.
echo "=== Rebuilding ESPs from spriggit/ ==="
bash "$PROJ/tools/build_esps.sh"
ESP_OUT="$PROJ/_build/esps"
echo

# -----------------------------------------------------------------------------
# Version detection
# -----------------------------------------------------------------------------
if [[ -n "${MTF_VERSION:-}" ]]; then
    VERSION="$MTF_VERSION"
else
    # Parse "vX.Y.Z" out of the most recent commit subject. Falls back to
    # latest tag if the subject lacks a version, then "v0.0.0-dev".
    VERSION="$(cd "$PROJ" && git log -1 --pretty=%s 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [[ -z "$VERSION" ]]; then
        VERSION="$(cd "$PROJ" && git tag --list 'v*' --sort=-version:refname 2>/dev/null | head -1 || true)"
    fi
    if [[ -z "$VERSION" ]]; then
        VERSION="v0.0.0-dev"
    fi
fi
echo "=== Building FOMOD for MTF $VERSION ==="

# -----------------------------------------------------------------------------
# Prereq check: required artifacts must exist
# -----------------------------------------------------------------------------
REQUIRED=(
    "$ESP_OUT/MagicTattoosFramework.esp"
    "$ESP_OUT/MTF_Plugin_FMR.esp"
    "$ESP_OUT/MTF_Plugin_SLA.esp"
    "$ESP_OUT/MTF_Plugin_SexLab.esp"
    "$ESP_OUT/MTF_Plugin_OStim.esp"
    "$ESP_OUT/MTF_Plugin_BFNG.esp"
    "$ESP_OUT/MTF_Plugin_SlaveTats.esp"
    "$ESP_OUT/MTF_Plugin_SkyrimNet.esp"
    "$SRC_SCRIPTS/MTF_MainQuest.pex"
    "$SRC_SCRIPTS/MTF_Plugin_FMR.pex"
    "$SRC_SCRIPTS/MTF_Plugin_SLA.pex"
    "$SRC_SCRIPTS/MTF_Plugin_SexLab.pex"
    "$SRC_SCRIPTS/MTF_Plugin_OStim.pex"
    "$SRC_SCRIPTS/MTF_Plugin_BFNG.pex"
    "$SRC_SCRIPTS/MTF_Plugin_SlaveTats.pex"
    "$SRC_SCRIPTS/MTF_Plugin_SkyrimNet.pex"
    "$DATA/SKSE/Plugins/MagicTattoosFramework.ini"
    "$TEMPLATES/info.xml"
    "$TEMPLATES/ModuleConfig.xml"
)
MISSING=()
for f in "${REQUIRED[@]}"; do
    [[ -f "$f" ]] || MISSING+=("$f")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: missing required files:" >&2
    printf '  %s\n' "${MISSING[@]}" >&2
    echo "Run bash tools/build_scripts.sh first to compile .pex outputs." >&2
    echo "Run bash tools/build_esps.sh first to rebuild ESPs from spriggit/." >&2
    exit 1
fi

# Optional: MTFPulse.dll. Warn if absent — base option still installable
# without C++ plugin (pulses/flashes degrade to Papyrus-only).
#
# Lookup order (most authoritative first):
#   1. cpp-plugin/build/x64-release/Release/MTFPulse.dll  (actual build output)
#   2. data/SKSE/Plugins/MTFPulse.dll                     (repo-staged copy)
#   3. F:/Modlists/Modding Essentials/mods/*/SKSE/Plugins/MTFPulse.dll
#                                                         (any MO2 deployment;
#      the FOMOD-installed mod-folder name varies, so glob).
DLL=""
for cand in \
    "$PROJ/cpp-plugin/build/x64-release/Release/MTFPulse.dll" \
    "$DATA/SKSE/Plugins/MTFPulse.dll" \
    "F:/Modlists/Modding Essentials/mods/MagicTattoosFramework/SKSE/Plugins/MTFPulse.dll" \
    "F:/Modlists/Modding Essentials/mods/Magic Tattoos Framework/SKSE/Plugins/MTFPulse.dll" \
    ; do
    if [[ -f "$cand" ]]; then
        DLL="$cand"
        echo "  DLL source: $DLL"
        break
    fi
done
if [[ -z "$DLL" ]]; then
    echo "WARNING: MTFPulse.dll not found; FOMOD will ship without it." >&2
fi

# -----------------------------------------------------------------------------
# Wipe + recreate staging dir
# -----------------------------------------------------------------------------
rm -rf "$STAGE"
mkdir -p "$STAGE/fomod"

# -----------------------------------------------------------------------------
# 00_base: core mod (ESP + base scripts + DLL + INI + waveforms)
# -----------------------------------------------------------------------------
BASE="$STAGE/00_base"
mkdir -p "$BASE/scripts" "$BASE/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/waveforms"

cp "$ESP_OUT/MagicTattoosFramework.esp" "$BASE/"

# Base-mod scripts (everything except the integration plugin .pex files,
# which ship in their own option folders).
BASE_SCRIPTS=(
    MTFPulse
    MTF_ApplyTattoo
    MTF_HitListener
    MTF_MainQuest
    MTF_MCMQuest
    MTF_Plugin
    MTF_PluginAliasKick
    MTF_Plugin_Base
)
for s in "${BASE_SCRIPTS[@]}"; do
    cp "$SRC_SCRIPTS/${s}.pex" "$BASE/scripts/"
done

cp "$DATA/SKSE/Plugins/MagicTattoosFramework.ini" "$BASE/SKSE/Plugins/"
[[ -n "$DLL" ]] && cp "$DLL" "$BASE/SKSE/Plugins/MTFPulse.dll"
cp "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/waveforms/"*.json \
   "$BASE/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/waveforms/"

echo "  staged 00_base ($(find "$BASE" -type f | wc -l) files)"

# -----------------------------------------------------------------------------
# Integration plugin folders (10_plugin_*): ESP + matching .pex
# -----------------------------------------------------------------------------
stage_plugin() {
    local folder="$1" esp="$2" pex="$3"
    local out="$STAGE/$folder"
    mkdir -p "$out/scripts"
    cp "$ESP_OUT/$esp" "$out/"
    cp "$SRC_SCRIPTS/$pex" "$out/scripts/"
    echo "  staged $folder ($(find "$out" -type f | wc -l) files)"
}

stage_plugin "10_plugin_fmr"    "MTF_Plugin_FMR.esp"    "MTF_Plugin_FMR.pex"
stage_plugin "11_plugin_sla"    "MTF_Plugin_SLA.esp"    "MTF_Plugin_SLA.pex"
stage_plugin "12_plugin_sexlab" "MTF_Plugin_SexLab.esp" "MTF_Plugin_SexLab.pex"
stage_plugin "13_plugin_ostim"  "MTF_Plugin_OStim.esp"  "MTF_Plugin_OStim.pex"
stage_plugin "14_plugin_bfng"      "MTF_Plugin_BFNG.esp"      "MTF_Plugin_BFNG.pex"
stage_plugin "15_plugin_slavetats" "MTF_Plugin_SlaveTats.esp" "MTF_Plugin_SlaveTats.pex"
stage_plugin "16_plugin_skyrimnet" "MTF_Plugin_SkyrimNet.esp" "MTF_Plugin_SkyrimNet.pex"
# SkyrimNet bridge also ships an Inja prompt submodule that surfaces
# MTF active tattoos in the LLM's character_bio context. Layered on top of
# the bare ESP+PEX stage so a single FOMOD step delivers code AND prompt.
if [[ -d "$CONTENT/skyrimnet-bridge" ]]; then
    cp -r "$CONTENT/skyrimnet-bridge/." "$STAGE/16_plugin_skyrimnet/"
    echo "  + skyrimnet-bridge prompt submodule layered into 16_plugin_skyrimnet"
fi

# -----------------------------------------------------------------------------
# Content-pack folders (20-24): JSON catalogs only
# -----------------------------------------------------------------------------
stage_content() {
    local folder="$1" pack="$2"
    local out="$STAGE/$folder"
    mkdir -p "$out"
    cp -r "$CONTENT/$pack/." "$out/"
    echo "  staged $folder ($(find "$out" -type f | wc -l) files)"
}

stage_content "20_content_lewdmarks" "lewdmarks"
stage_content "22_content_rx"        "rx-overlays"
stage_content "23_content_bardle"    "bardle-nail-polish"
stage_content "24_content_co1_face"  "community-overlays-1-face"

# -----------------------------------------------------------------------------
# 30_npc_overlays: skee64.ini override (from tools/fomod/static/)
# -----------------------------------------------------------------------------
mkdir -p "$STAGE/30_npc_overlays"
cp -r "$STATIC/30_npc_overlays/." "$STAGE/30_npc_overlays/"
echo "  staged 30_npc_overlays ($(find "$STAGE/30_npc_overlays" -type f | wc -l) files)"

# -----------------------------------------------------------------------------
# 31_test_pack: smoke-test presets (from test-pack/)
# -----------------------------------------------------------------------------
mkdir -p "$STAGE/31_test_pack/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets"
cp "$TESTPACK/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/"*.json \
   "$STAGE/31_test_pack/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/"
[[ -f "$TESTPACK/README.md" ]] && cp "$TESTPACK/README.md" "$STAGE/31_test_pack/"
echo "  staged 31_test_pack ($(find "$STAGE/31_test_pack" -type f | wc -l) files)"

# -----------------------------------------------------------------------------
# _diagnostics/ — probe file installed conditionally via <conditionalFileInstalls>
# -----------------------------------------------------------------------------
if [[ -d "$STATIC/_diagnostics" ]]; then
    mkdir -p "$STAGE/_diagnostics"
    cp -r "$STATIC/_diagnostics/." "$STAGE/_diagnostics/"
    echo "  staged _diagnostics ($(find "$STAGE/_diagnostics" -type f | wc -l) files)"
fi

# -----------------------------------------------------------------------------
# fomod/ — copy templates, substitute @MTF_VERSION@
# -----------------------------------------------------------------------------
sed "s/@MTF_VERSION@/$VERSION/g" "$TEMPLATES/info.xml" > "$STAGE/fomod/info.xml"
cp "$TEMPLATES/ModuleConfig.xml" "$STAGE/fomod/ModuleConfig.xml"

# Optional images
if [[ -d "$FOMOD_DIR/images" ]] && [[ -n "$(ls "$FOMOD_DIR/images" 2>/dev/null)" ]]; then
    mkdir -p "$STAGE/fomod/images"
    cp -r "$FOMOD_DIR/images/." "$STAGE/fomod/images/"
fi

echo "=== Stage complete: $STAGE ==="
echo

# -----------------------------------------------------------------------------
# Archive
# -----------------------------------------------------------------------------
ARCHIVE_BASE="MagicTattoosFramework-FOMOD-$VERSION"
rm -f "$DIST/$ARCHIVE_BASE.7z" "$DIST/$ARCHIVE_BASE.zip"

# Locate 7z: try PATH first, then standard Windows install path.
SEVENZ=""
if command -v 7z >/dev/null 2>&1; then
    SEVENZ="7z"
elif [[ -x "/c/Program Files/7-Zip/7z.exe" ]]; then
    SEVENZ="/c/Program Files/7-Zip/7z.exe"
elif [[ -x "/c/Program Files (x86)/7-Zip/7z.exe" ]]; then
    SEVENZ="/c/Program Files (x86)/7-Zip/7z.exe"
fi

if [[ -n "$SEVENZ" ]]; then
    (cd "$STAGE" && "$SEVENZ" a -mx=7 "$DIST/$ARCHIVE_BASE.7z" . >/dev/null)
    ls -lh "$DIST/$ARCHIVE_BASE.7z"
    echo "=== 7z archive: $DIST/$ARCHIVE_BASE.7z ==="
elif command -v zip >/dev/null 2>&1; then
    (cd "$STAGE" && zip -rq "$DIST/$ARCHIVE_BASE.zip" .)
    ls -lh "$DIST/$ARCHIVE_BASE.zip"
    echo "=== zip archive (no 7z found): $DIST/$ARCHIVE_BASE.zip ==="
else
    # Final fallback: PowerShell's Compress-Archive (always present on
    # Windows 10+). Produces .zip; same content, just heavier on disk.
    if command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -Command "Compress-Archive -Force -Path '$STAGE\\*' -DestinationPath '$DIST\\$ARCHIVE_BASE.zip'" \
            && ls -lh "$DIST/$ARCHIVE_BASE.zip" \
            && echo "=== zip archive (PowerShell fallback): $DIST/$ARCHIVE_BASE.zip ==="
    else
        echo "WARNING: neither 7z, zip, nor PowerShell available; stage left at $STAGE for manual packaging." >&2
    fi
fi

echo
echo "Total files in stage:"
find "$STAGE" -type f | wc -l
