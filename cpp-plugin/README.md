# MTFPulse — SKSE companion plugin

A minimal-scope SKSE plugin for Magic Tattoos Framework. Owns one
responsibility: the per-frame pulse animation loop. The Papyrus side
keeps owning conditions, presets, cooldowns, effects, and the slow
2-second condition evaluation. When an actor's tier transitions into a
pulse-configured slot, Papyrus calls `MTFPulse.SetActorPulse(actor,
rate, depth, pause, layerN, startRT, emMults, baseSlot, isFemale)`. When
the actor leaves the pulse tier (or dies / is untracked), Papyrus calls
`MTFPulse.ClearActor(actor)`.

Inside the plugin, a 32-slot roster (`pulse_roster.{h,cpp}`) holds the
snapshotted entries. A per-frame tick walks the roster, computes the
emissive multiplier using the same wave formula as the Papyrus path:

```
wave = (in cycle) 0.5 - 0.5·cos(2π·rate·tMod)
       (in pause) 0
mult = (1 - depth) + depth · wave
```

and writes the per-layer emissive intensity via SKEE/NiOverride.

## Why C++ at all

The Papyrus pulse path at 20 Hz fits within `fUpdateBudgetMS` for a
single actor (the player) but doesn't scale: the VM has a hard global
budget shared across all scripts, and an `_applyPulseRoster` of 8 actors
× ~5 NiOverride calls each at 20 Hz means 800 native calls per second of
Papyrus bookkeeping. C++ runs the same math in microseconds per frame
with no VM contention.

This plugin can be tested in isolation against the v0.0.32 Papyrus
codebase (player only) first; the v0.0.33 NPC support branch then
forwards its roster updates to this plugin when both are loaded.

## Build prerequisites

- Visual Studio 2022 (or 2026 / VS 18) with the **Desktop development
  with C++** workload. VS bundles its own vcpkg under
  `VC/vcpkg/vcpkg.exe`; build.bat uses that one.
- CMake ≥ 3.21 (bundled with VS).
- Git (build.bat will clone `extern/CommonLibSSE-NG` on first run).
- Skyrim AE 1.6.1170 target.

## Build

```cmd
cd cpp-plugin
build.bat                  REM Release
build.bat debug            REM Debug
build.bat configure        REM configure only
```

First-time setup is automated by build.bat:
1. Clones `extern/CommonLibSSE-NG` at tag v3.7.0 if absent.
2. Runs the VS-bundled vcpkg in manifest mode to install
   spdlog / fmt / rapidcsv / catch2 (~35s the first time, near-instant
   thereafter — vcpkg caches built packages).
3. CMake configures with the vcpkg toolchain + explicit
   `CMAKE_PREFIX_PATH` (necessary because the VS vcpkg toolchain
   doesn't auto-prepend its install prefix during the
   `add_subdirectory` of CommonLibSSE-NG).
4. Builds via MSBuild.

Or via Visual Studio: run `build.bat configure` once from a regular
command prompt to clone CommonLibSSE-NG and install vcpkg deps, then
open the `cpp-plugin/` folder in VS — it picks up `CMakePresets.json`
and the build tree the build.bat created.

Output DLL lands at:
```
build/x64-Release/Release/MTFPulse.dll
```

## Deploy

```
Copy build/x64-release/Release/MTFPulse.dll  →  <Skyrim>/Data/SKSE/Plugins/
```

Or drop into a fresh MO2 mod folder under `<modlist>/mods/MTFPulse/SKSE/Plugins/`.

The plugin writes a log to:
```
%USERPROFILE%/Documents/My Games/Skyrim Special Edition/SKSE/MTFPulse.log
```

Expect `MTFPulse vX.Y.Z loaded` on the first line. If the log is missing
the plugin didn't load — check the SKSE log
(`Documents/My Games/Skyrim Special Edition/SKSE/skse64.log`).

## Status — what's wired vs not

| Component                             | Status         |
|---------------------------------------|----------------|
| SKSE plugin entry + logging           | ✅              |
| Papyrus natives registration          | ✅              |
| Roster Set / Clear / ClearAll         | ✅              |
| Per-frame tick (SKSE task scheduler)  | ⚠️ stub        |
| Wave math (matches Papyrus)           | ✅              |
| NiOverride emissive write             | ❌ TODO         |
| Real per-frame hook (vs task loop)    | ❌ TODO         |

Once the NiOverride write is in, the plugin is testable end-to-end. To
hook NiOverride from C++ we go through the SKSE messaging API: a
`kPostLoad` listener queries the SKEE plugin (publisher
`"po3_NiOverride"` / version > 5) and grabs the
`NiOverrideInterface` vtable. The intensity write is one of its
methods (the same one Papyrus' `NiOverride.AddNodeOverrideFloat`
ultimately dispatches to under the hood).

## File layout

```
cpp-plugin/
├── CMakeLists.txt          FetchContent CommonLibSSE-NG, sources, /W4
├── CMakePresets.json       x64-release / x64-debug / ninja-release
├── build.bat               vcvars64 + cmake wrapper
├── README.md               this file
└── src/
    ├── main.cpp            SKSEPluginLoad, messaging, frame-task loop
    ├── papyrus.{h,cpp}     SetActorPulse / ClearActor / ClearAll / SetEnabled / Size
    ├── pulse_roster.{h,cpp} Roster singleton + Tick (wave math)
    └── log.h               spdlog file sink under Documents/.../SKSE/
```
