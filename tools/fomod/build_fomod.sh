#!/usr/bin/env bash
# Build the MTF FOMOD installer.
#
# Pipeline: rebuild ESPs from spriggit/ YAML (_build/esps/), rebuild the
# MTFPulse.dll SKSE plugin (cpp-plugin/build.bat), pull .pex from source/scripts/,
# INI/waveforms from data/, content-pack JSONs from content-packs/, NPC overlays
# skee64.ini from tools/fomod/static/, test pack from test-pack/; arrange them
# into option-folder subtrees under _build/fomod-stage/; run the static release
# gate (tools/release_check.sh); copy the FOMOD templates into fomod/; and
# produce an archive in _build/.
#
# Usage:
#   bash tools/fomod/build_fomod.sh                # build with auto-detected version
#   MTF_VERSION=v0.1.18 bash tools/fomod/build_fomod.sh
#
# Env flags:
#   MTF_VERSION=vX.Y.Z   override version (else parsed from latest commit/tag)
#   MTF_SKIP_DLL=1       reuse the existing MTFPulse.dll (skip cpp-plugin build)
#   MTF_SKIP_CHECK=1     skip the release_check.sh pre-ship gate
#
# Requires: bash, cp, find, sed, git; cmd.exe + the C++ toolchain for the DLL
# (unless MTF_SKIP_DLL=1); 7z (preferred) or zip for archive.

set -euo pipefail

# Repo root: MTF_PROJ env override, else two levels up (tools/fomod/../..).
# `pwd -W` emits the WINDOWS form (F:/…); the sub-builds call native Windows
# exes (Caprica via build_scripts, spriggit, cmd) that can't resolve /f/… paths.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="${MTF_PROJ:-$(cd "$SELF_DIR/../.." && { pwd -W 2>/dev/null || pwd; })}"
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
# Rebuild the MTFPulse.dll SKSE plugin (cpp-plugin/build.bat).
#
# build.bat is incremental — CMake/MSBuild no-op when nothing changed, so this
# is cheap on an up-to-date tree and guarantees the FOMOD never ships a stale
# DLL (the build only LOOKS for an existing .dll; it can't tell fresh from old).
# Set MTF_SKIP_DLL=1 to reuse whatever binary is already on disk (fast iteration
# when you know the DLL is current, or when the C++ toolchain is unavailable).
# -----------------------------------------------------------------------------
if [[ "${MTF_SKIP_DLL:-0}" == "1" ]]; then
    echo "=== Skipping MTFPulse.dll rebuild (MTF_SKIP_DLL=1) ==="
else
    echo "=== Building MTFPulse.dll (cpp-plugin/build.bat) ==="
    # Run the batch from its own dir. Two cmd.exe-under-MSYS gotchas to handle:
    #   1. MSYS2_ARG_CONV_EXCL='*' stops MSYS path-mangling the cmd args.
    #   2. The '.\' prefix is REQUIRED: this environment has
    #      NoDefaultCurrentDirectoryInExePath=1, so cmd refuses to find a bare
    #      'build.bat' in cwd ("not recognized") even though it's right there —
    #      every form without './' fails identically. './build.bat' forces the
    #      cwd-relative path.
    if ( cd "$PROJ/cpp-plugin" && MSYS2_ARG_CONV_EXCL='*' cmd.exe /c ".\build.bat" ); then
        echo "  MTFPulse.dll build OK"
    else
        echo "ERROR: MTFPulse.dll build failed. Fix the C++ build, or set" >&2
        echo "       MTF_SKIP_DLL=1 to ship the existing binary." >&2
        exit 1
    fi
fi
echo

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
    "$SRC_SCRIPTS/MTF_Plugin_Base.pex"
    "$SRC_SCRIPTS/MTF_Plugin_Combat.pex"
    "$SRC_SCRIPTS/MTF_Plugin_Magic.pex"
    "$SRC_SCRIPTS/MTF_Plugin_World.pex"
    "$SRC_SCRIPTS/MTF_Plugin_Fx.pex"
    "$SRC_SCRIPTS/MTF_Plugin_Dragonborn.pex"
    "$SRC_SCRIPTS/MTF_Plugin_FMR.pex"
    "$SRC_SCRIPTS/MTF_Plugin_SLA.pex"
    "$SRC_SCRIPTS/MTF_Plugin_SexLab.pex"
    "$SRC_SCRIPTS/MTF_Plugin_OStim.pex"
    "$SRC_SCRIPTS/MTF_Plugin_BFNG.pex"
    "$SRC_SCRIPTS/MTF_Plugin_SlaveTats.pex"
    "$SRC_SCRIPTS/MTF_Plugin_SkyrimNet.pex"
    "$SRC_SCRIPTS/MTF_TestRunner.pex"
    "$DATA/SKSE/Plugins/MagicTattoosFramework.ini"
    "$DATA/meshes/MTF/MTF_AmbientLightAttach.nif"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/mtf.module_map.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.attributes.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.combat.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.magic.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.dragonborn.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.world.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.fx.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.fmr.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.sla.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.sexlab.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.ostim.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.bfng.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.slavetats.json"
    "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.skyrimnet.json"
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
#   3. $MTF_MO2_MODS/*/SKSE/Plugins/MTFPulse.dll          (any MO2 deployment;
#      the installed mod-folder name varies, so both spellings are probed).
# MO2 'mods' dir is env-overridable (MTF_MO2_MODS) so the deploy path can move.
MO2_MODS="${MTF_MO2_MODS:-F:/Modlists/Modding Essentials/mods}"
DLL=""
for cand in \
    "$PROJ/cpp-plugin/build/x64-release/Release/MTFPulse.dll" \
    "$DATA/SKSE/Plugins/MTFPulse.dll" \
    "$MO2_MODS/MagicTattoosFramework/SKSE/Plugins/MTFPulse.dll" \
    "$MO2_MODS/Magic Tattoos Framework/SKSE/Plugins/MTFPulse.dll" \
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
mkdir -p "$BASE/scripts" \
         "$BASE/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/waveforms" \
         "$BASE/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins"

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
    MTF_Plugin_Combat
    MTF_Plugin_Magic
    MTF_Plugin_World
    MTF_Plugin_Fx
    MTF_Plugin_Dragonborn
)
for s in "${BASE_SCRIPTS[@]}"; do
    cp "$SRC_SCRIPTS/${s}.pex" "$BASE/scripts/"
done

cp "$DATA/SKSE/Plugins/MagicTattoosFramework.ini" "$BASE/SKSE/Plugins/"
[[ -n "$DLL" ]] && cp "$DLL" "$BASE/SKSE/Plugins/MTFPulse.dll"
cp "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/waveforms/"*.json \
   "$BASE/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/waveforms/"

# Base plugin catalogs (v0.4 themed-module split). The monolithic mtf.base.json
# is gone; the built-in conditions/effects now live in 6 self-registering core
# modules (Attributes / Combat / Magic / Dragonborn / World / FX). Each module's
# VMAD plugin script reads its own catalog to drive MCM rendering — without these
# GetConditionCount()/GetEffectCount() return -1 and the Plugins page breaks.
CORE_CATALOGS=(
    mtf.attributes.json
    mtf.combat.json
    mtf.magic.json
    mtf.dragonborn.json
    mtf.world.json
    mtf.fx.json
)
for c in "${CORE_CATALOGS[@]}"; do
    cp "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/$c" \
       "$BASE/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/"
done

# Module map (mtf.module_map.json) — lives one level above plugins/. The save
# migrator AND the runtime _remapBaseKey read it via JsonUtil to rewrite stored
# "mtf.base:<id>" keys (from pre-v0.4 saves/presets) to "<module>:<id>". Must
# ship or old saves can't resolve their bound conditions/effects.
cp "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/mtf.module_map.json" \
   "$BASE/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/"

# skee64_custom.ini override (bPlayerOnly=0). Shipped by default so MTF can
# apply overlays to tracked NPCs out of the box. SKEE reads skee64.ini then
# layers skee64_custom.ini on top per-section, so this minimal file flips just
# the one key and leaves every other RaceMenu setting (and user customization)
# untouched — no loose-file conflict with RaceMenu's ini, load-order independent.
cp "$STATIC/00_base/SKSE/Plugins/skee64_custom.ini" "$BASE/SKSE/Plugins/skee64_custom.ini"

# Meshes — ambient-light attach carrier. The toggle.ambientLight effect's MGEF
# (0x924) uses this NIF as its HitEffectArt (ARTO 0x929); the attached LIGH
# (0x928) parents to it, so without the mesh the effect's light has nothing to
# attach to and never renders. data/meshes is the only mesh tree MTF ships;
# it was previously omitted from staging entirely, so every FOMOD install
# silently lacked the ambient light. (Guarded by the REQUIRED[] check above.)
mkdir -p "$BASE/meshes/MTF"
cp "$DATA/meshes/MTF/MTF_AmbientLightAttach.nif" "$BASE/meshes/MTF/"

echo "  staged 00_base ($(find "$BASE" -type f | wc -l) files)"

# -----------------------------------------------------------------------------
# Integration plugin folders (10_plugin_*): ESP + matching .pex
# -----------------------------------------------------------------------------
# Stage one integration plugin folder. The 4th arg is the plugin catalog
# basename (e.g. "mtf.fmr.json"); pass "" to skip only for a plugin that ships
# no JSON catalog at all.
# NOTE: the SkyrimNet bridge DOES ship a catalog (mtf.skyrimnet.json). It has
# zero conditions, but it carries the "Special"/rp.text effect, which is
# catalog-driven — so without staging the JSON that effect never registers and
# presets referencing mtf.skyrimnet:rp.text bind to nothing. (Historically this
# arg was "" back when the bridge truly had no catalog; that became a packaging
# bug once rp.text was added — fixed here.)
stage_plugin() {
    local folder="$1" esp="$2" pex="$3" catalog="${4:-}"
    local out="$STAGE/$folder"
    mkdir -p "$out/scripts"
    cp "$ESP_OUT/$esp" "$out/"
    cp "$SRC_SCRIPTS/$pex" "$out/scripts/"
    if [[ -n "$catalog" ]]; then
        mkdir -p "$out/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins"
        cp "$DATA/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/$catalog" \
           "$out/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/"
    fi
    echo "  staged $folder ($(find "$out" -type f | wc -l) files)"
}

stage_plugin "10_plugin_fmr"       "MTF_Plugin_FMR.esp"       "MTF_Plugin_FMR.pex"       "mtf.fmr.json"
stage_plugin "11_plugin_sla"       "MTF_Plugin_SLA.esp"       "MTF_Plugin_SLA.pex"       "mtf.sla.json"
stage_plugin "12_plugin_sexlab"    "MTF_Plugin_SexLab.esp"    "MTF_Plugin_SexLab.pex"    "mtf.sexlab.json"
stage_plugin "13_plugin_ostim"     "MTF_Plugin_OStim.esp"     "MTF_Plugin_OStim.pex"     "mtf.ostim.json"
stage_plugin "14_plugin_bfng"      "MTF_Plugin_BFNG.esp"      "MTF_Plugin_BFNG.pex"      "mtf.bfng.json"
stage_plugin "15_plugin_slavetats" "MTF_Plugin_SlaveTats.esp" "MTF_Plugin_SlaveTats.pex" "mtf.slavetats.json"
stage_plugin "16_plugin_skyrimnet" "MTF_Plugin_SkyrimNet.esp" "MTF_Plugin_SkyrimNet.pex" "mtf.skyrimnet.json"
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
    # Strip backup/scratch files that aren't gitignored at copy-time but
    # shouldn't ship in the FOMOD (e.g. *.json.bak from spriggit/patch
    # round-trips, *.orig from merge conflicts).
    find "$out" -type f \( -name '*.bak' -o -name '*.orig' -o -name '*~' \) -delete
    echo "  staged $folder ($(find "$out" -type f | wc -l) files)"
}

# Texture pack adapters. Ordered alphabetically by display name (matches the
# FOMOD UI order set in templates/ModuleConfig.xml). Folder numbering is
# historical — only the order within ModuleConfig.xml controls the picklist.
stage_content "23_content_bardle"     "bardle-nail-polish"
stage_content "27_content_bitchcraft" "bitchcraft"
stage_content "21_content_co1"        "community-overlays-1-body"
stage_content "29_content_co2"        "community-overlays-2"
stage_content "28_content_co3"        "community-overlays-3"
stage_content "20_content_lewdmarks"  "lewdmarks"
stage_content "25_content_lyru1"      "lyru-1"
stage_content "26_content_lyru2"      "lyru-2"
stage_content "22_content_rx"         "rx-overlays"
# Extras (not a texture adapter): optional SPID NPC-distribution component —
# ships the _DISTR.ini + sample distribution JSON. Carrier ESP records live in
# the main plugin; this folder is what makes distribution active (+ a SPID dep).
stage_content "24_content_spid"       "spid-distributor"

# -----------------------------------------------------------------------------
# 31_test_pack: smoke-test presets (from test-pack/) + F10 console-runner
#
# MTF_TestRunner.pex is a ReferenceAlias script already declared in MTF's
# ESP (alias name "MTF_TestRunner" on MTF_MainQuest). When the .pex lands
# on disk the alias binds automatically — no ESP changes needed. The
# runner depends on ConsoleUtilSSE NG (for coc teleport); description
# warns users about this.
# -----------------------------------------------------------------------------
mkdir -p "$STAGE/31_test_pack/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets" \
         "$STAGE/31_test_pack/scripts"
cp "$TESTPACK/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/"*.json \
   "$STAGE/31_test_pack/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/"
cp "$SRC_SCRIPTS/MTF_TestRunner.pex" "$STAGE/31_test_pack/scripts/"
[[ -f "$TESTPACK/README.md" ]] && cp "$TESTPACK/README.md" "$STAGE/31_test_pack/"
echo "  staged 31_test_pack ($(find "$STAGE/31_test_pack" -type f | wc -l) files)"

# -----------------------------------------------------------------------------
# 32_preset_magicka: ready-made "Magicka Tracker" example preset (examples/).
#
# A worked preset that turns one Body tattoo into a magicka gauge (Default +
# three magicka.below tiers). References the Bitchcraft pack's "Sanguine Back"
# entry, so it only renders if the Bitchcraft content pack is also installed;
# the Default slot can be repointed to any Body pack from the MCM. Documented
# in docs/MCM_OPTIONS.md ("Example — Magicka Tracker").
# -----------------------------------------------------------------------------
mkdir -p "$STAGE/32_preset_magicka/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets"
cp "$PROJ/examples/presets/"*.json \
   "$STAGE/32_preset_magicka/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/"
echo "  staged 32_preset_magicka ($(find "$STAGE/32_preset_magicka" -type f | wc -l) files)"

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
# LC_ALL=C keeps sed byte-exact: the MSVC DLL build (vcvars64/cmake) earlier in
# this script flips the shared console codepage, which otherwise made sed emit a
# UTF-16 info.xml that FOMOD parsers choke on. Forcing the C locale here pins
# UTF-8/ASCII output regardless of console state.
LC_ALL=C sed "s/@MTF_VERSION@/$VERSION/g" "$TEMPLATES/info.xml" > "$STAGE/fomod/info.xml"
cp "$TEMPLATES/ModuleConfig.xml" "$STAGE/fomod/ModuleConfig.xml"

# Optional images
if [[ -d "$FOMOD_DIR/images" ]] && [[ -n "$(ls "$FOMOD_DIR/images" 2>/dev/null)" ]]; then
    mkdir -p "$STAGE/fomod/images"
    cp -r "$FOMOD_DIR/images/." "$STAGE/fomod/images/"
fi

echo "=== Stage complete: $STAGE ==="
echo

# -----------------------------------------------------------------------------
# Coverage gate: source -> stage completeness.
#
# REQUIRED[] above guards that listed inputs EXIST. This guards the OPPOSITE
# failure: a tracked source file (or a whole directory) that nobody remembered
# to add a cp/stage_* line for, which then silently never ships. That is exactly
# how data/meshes/ (the ambient-light attach NIF) went missing from every build
# for releases — REQUIRED[] can't catch a file no one listed in the first place.
#
# Rule: every file tracked by git under data/ and content-packs/ must either
# land in the stage (matched by basename) or be named in COVERAGE_EXCLUDE with a
# comment. A newly-added source file therefore forces a conscious choice — ship
# it or exclude it — instead of vanishing. Scope is deliberately data/ +
# content-packs/, where "everything ships" is a clean invariant; source/scripts,
# examples/, and test-pack/ have bespoke per-file staging and are out of scope.
#
# Matching is by basename (the stage reorganizes files into option folders, so
# relative paths don't survive). Collisions are theoretically possible but would
# only mask an orphan, never invent one. Set MTF_SKIP_COVERAGE=1 to bypass.
# -----------------------------------------------------------------------------
if [[ "${MTF_SKIP_COVERAGE:-0}" == "1" ]]; then
    echo "=== Skipping coverage gate (MTF_SKIP_COVERAGE=1) ==="
else
    echo "=== Running coverage gate (source -> stage) ==="
    COVERAGE_EXCLUDE=(
        # Stress/visual test presets — dev-only; release_check separately
        # asserts these never appear in the base FOMOD step.
        'data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets_builtin/*'
        # MTFPulse.dll has its own multi-source lookup + conditional cp above
        # (it is NOT staged from data/), so exclude it from basename coverage.
        'data/SKSE/Plugins/MTFPulse.dll'
        # Repo-level content-pack index, not a shippable pack.
        'content-packs/README.md'
        # obi-tattoos — unreleased WIP content pack; no FOMOD option yet.
        'content-packs/obi-tattoos/*'
        # Scratch/backup files that may sit in the worktree but never ship.
        '*.bak' '*.orig' '*~'
    )
    # Basenames that made it into the stage (forward-slash paths under MSYS).
    STAGED_BN="$(find "$STAGE" -type f | sed 's#.*/##' | sort -u)"
    ORPHANS=()
    while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        skip=0
        for pat in "${COVERAGE_EXCLUDE[@]}"; do
            # [[ == ]] glob match; * spans '/' here, so dir excludes work.
            # shellcheck disable=SC2053
            if [[ "$rel" == $pat ]]; then skip=1; break; fi
        done
        [[ "$skip" == 1 ]] && continue
        if ! grep -Fxq -- "${rel##*/}" <<<"$STAGED_BN"; then
            ORPHANS+=("$rel")
        fi
    done < <(cd "$PROJ" && git ls-files data content-packs)

    if [[ ${#ORPHANS[@]} -gt 0 ]]; then
        echo "ERROR: tracked source files never reached the stage (and not excluded):" >&2
        printf '  %s\n' "${ORPHANS[@]}" >&2
        echo "Each must either get a cp/stage_* line above, or be added to" >&2
        echo "COVERAGE_EXCLUDE (with a comment) if it legitimately never ships." >&2
        exit 1
    fi
    echo "  coverage: every tracked source file is staged or explicitly excluded"
fi
echo

# -----------------------------------------------------------------------------
# Release gate: static pre-ship checks (tools/release_check.sh).
#
# Runs AFTER staging so it can validate the staged 00_base (no test/stress
# artifacts in the required base step) on top of its source-level checks
# (DebugMode default, leftover debug markers, catalog JSON, stale .pex,
# version label). A FAIL aborts before we produce an archive. MTF_VERSION is
# inherited from this script's environment, so its version check stays quiet on
# an explicit version. Set MTF_SKIP_CHECK=1 to bypass.
# -----------------------------------------------------------------------------
if [[ "${MTF_SKIP_CHECK:-0}" == "1" ]]; then
    echo "=== Skipping release_check (MTF_SKIP_CHECK=1) ==="
else
    echo "=== Running release_check.sh ==="
    if bash "$PROJ/tools/release_check.sh"; then
        echo "  release_check: clean"
    else
        echo "ERROR: release_check.sh reported FAIL(s) — aborting before archive." >&2
        echo "       Fix the issues above, or set MTF_SKIP_CHECK=1 to override." >&2
        exit 1
    fi
fi
echo

# -----------------------------------------------------------------------------
# Archive
# -----------------------------------------------------------------------------
# Strip the leading "v" from the version for the archive filename only
# (e.g. v0.3.7 -> 0.3.7). The in-FOMOD version label (info.xml) keeps the
# "v" via $VERSION; this affects just the .7z/.zip name.
ARCHIVE_BASE="MagicTattoosFramework-${VERSION#v}"
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
