# CLAUDE.md — Magic Tattoos Framework

Project-local guide. Pairs with `F:/stuff/Skyrim modding/CLAUDE.md` (safety
rules, tooling) and `F:/stuff/Skyrim modding/KNOWLEDGEBASE.md` (engine quirks).
Anything generic to Skyrim modding lives there; anything specific to this
codebase lives here.

## What MTF Is

Skyrim SE/AE framework for **condition-driven body-overlay tattoos with
gameplay effects**. Pack authors ship a JSON catalog of textures
(`Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/*.json`).
The framework picks a slot based on per-slot condition predicates, draws
its layers via NiOverride with tint / emissive / alpha / animated pulse,
and dispatches a list of gameplay effects per slot.

**Architecture in one sentence:** one host quest (`MTF_MainQuest`) walks
a roster of tracked actors on a slow tick, evaluates plugin-supplied
condition predicates, and on tier change calls plugin-supplied effect
hooks plus a C++ native (`MTFPulse.dll`) that drives NiOverride at 20Hz.

## Repo Layout

```
MagicTattoosFramework/
├── MagicTattoosFramework.esp        host ESP (ESL-flagged)
├── MTF_Plugin_FMR.esp               plugin ESP — Fertility Mode
├── MTF_Plugin_SLA.esp               plugin ESP — SexLab Aroused
├── MTF_Plugin_SexLab.esp            plugin ESP — SexLab Framework
├── MTF_Plugin_OStim.esp             plugin ESP — OStim Standalone
├── MTF_Plugin_BFNG.esp              plugin ESP — Beeing Female NG
├── source/scripts/                  Papyrus source (.psc) — edit here
├── _deps/                           minimal stubs for foreign types (slaFrameWorkScr, FWController, etc.)
├── cpp-plugin/                      SKSE C++ plugin source (MTFPulse.dll, CMake)
├── data/SKSE/Plugins/               visual catalogs, waveform LUTs (shipped JSON)
├── presets/                         dev sample presets (not auto-deployed)
├── plans/                           design docs (integrations.md, etc.)
├── tools/build_scripts.sh           compile + deploy Papyrus
└── README.md                        public-facing description
```

Compiled `.pex` lives alongside the `.psc` after a build. The build script
auto-deploys them into the user's MO2 mods folder — see Build & Deploy.

## Build & Deploy

```bash
# Compile all Papyrus, auto-deploy to MO2
bash tools/build_scripts.sh

# Compile a single script (faster iteration)
bash tools/build_scripts.sh MTF_MainQuest
```

The script does TWO deploy passes:
1. **Host `.pex`** → `F:/Modlists/Modding Essentials/mods/MagicTattoosFramework/scripts/`
2. **Per-plugin `.pex`** (`MTF_Plugin_*.pex`, except `_Base`) → their own MO2 mod folder, e.g.
   `mods/MTF_Plugin_FMR/scripts/`. Skipping this pass lets stale per-mod-dir copies
   shadow fresh ones because MO2 left-pane priority can put a plugin mod above
   MagicTattoosFramework. If you ever see "function not found" or stale behavior,
   `grep` the deployed `.pex` directly — don't trust the source tree.

**C++ plugin (MTFPulse.dll)** is built via `cpp-plugin/build.bat` (CMake +
vcpkg). It's loaded by SKSE; the Papyrus `Scriptname MTFPulse Native Hidden`
script in `source/scripts/MTFPulse.psc` only declares the bindings —
implementation lives in `cpp-plugin/src/papyrus.cpp`.

**ESP edits** go through Spriggit YAML round-trip — back up the ESP first:
```bash
cp MyMod.esp MyMod.esp.bak
spriggit serialize --InputPath MyMod.esp --OutputPath /tmp/yaml --GameRelease SkyrimSE --PackageName Spriggit.Yaml --PackageVersion 0.40.0
# edit /tmp/yaml/...
spriggit deserialize --InputPath /tmp/yaml --OutputPath MyMod.esp
```

## Key Scripts by Role

| Script | Type | Owns |
|---|---|---|
| **MTF_MainQuest** | Quest | Host. Roster, slow-tick eval loop, slot/tier state, scratch preset buffer, preset I/O, NPC dispatch wrappers, plugin registry, MCM-facing accessors. The 5374-line god-quest — most edits live here. |
| **MTF_MCMQuest** | SKI_ConfigBase | MCM pages (General, Preset editor, Subjects, Plugins). State-pool toggle bindings, dropdowns sourced via plugin registry. No game-state logic — delegates everything to MainQuest. |
| **MTF_Plugin** | Quest (abstract) | Base class. Plugin identity (id/label), condition/effect declaration interface, optional settings page, lifecycle (`OnInit` → `_tryRegister` → host `RegisterPlugin`). Override in derived plugin scripts. |
| **MTF_Plugin_Base** | Quest (extends MTF_Plugin) | Built-in plugin (`mtf.base`). Built-in conditions (magicka/stamina/combat/hits/region/time/weather). Built-in effects (drains, cloaks, slow-time, water-breathing, detect-life, shader.play, sound.play). Cloak Cast() queue. Hit-class tracking. |
| **MTF_Plugin_FMR** | Quest (extends MTF_Plugin) | Optional. Pregnancy / ovulation conditions sourced from Fertility Mode Reloaded. Soft-master pattern. |
| **MTF_Plugin_SLA** | Quest (extends MTF_Plugin) | Optional. Arousal / exposure / orgasm-time conditions + exposure-rate / trigger-orgasm effects from SexLab Aroused (OSL/SLO portable). |
| **MTF_Plugin_SexLab** | Quest (extends MTF_Plugin) | Optional. In-scene / cum-layer / skill conditions + cum-apply / cum-remove / skill-XP effects from SexLab Framework P+. |
| **MTF_Plugin_OStim** | Quest (extends MTF_Plugin) | Optional. In-scene / excitement / times-climaxed conditions + trigger-climax / stall-climax effects from OStim Standalone. |
| **MTF_Plugin_BFNG** | Quest (extends MTF_Plugin) | Optional. Pregnancy / ovulation / cycle-phase / baby-health / num-births conditions + trigger-ovulation effect from Beeing Female NG. |
| **MTF_PluginAliasKick** | ReferenceAlias | Per-plugin ReferenceAlias filled with PlayerRef. Receives the `MTF_PluginKick` SKSE ModEvent and forwards to `MTF_Plugin._tryRegister`. Works around the "Quest can't `RegisterForModEvent`" + "queued OnUpdate dropped after `.pex` rebuild mid-save" combo. |
| **MTF_HitListener** | ReferenceAlias | Filled with PlayerRef on the host quest. `OnHit` → classify weapon/spell → bump `mtf.hit.*` counters on `MTF_Plugin_Base`. Hit-class conditions read these. |
| **MTF_ApplyTattoo** | ActiveMagicEffect | Attached to `MTF_Spell_ApplyTattoo`. Self-cast → UIListMenu of saved presets → apply/remove on the crosshair target (or self if none). |
| **MTFPulse** | Native Hidden | Papyrus binding to MTFPulse.dll. `SetActorPulse*` family pushes per-actor overlay state (rate/depth/pause, per-layer emissive/alpha/tint, optional cross-fade duration) to the C++ roster. The C++ side ticks at 20 Hz and writes NiOverride directly. **Calls return defaults silently if the DLL didn't load** — check skse64.log for the load message before debugging. |

**General rule:** the host quest is the bus. Plugins **declare** items;
the host **owns** state. Plugin scripts never read/write StorageUtil keys
that belong to a different plugin — go through the host's accessors.

## Core Systems & Code Paths

### Condition pipeline

1. **MCM** writes per-slot `condPluginId[s]` (composite key `"<pid>:<itemid>"`),
   `condParam[s]`, `condParam2[s]` on MainQuest.
2. **Slow tick** (`MTF_MainQuest.OnUpdate`, ~2s default): for each tracked
   actor, walk slots 1..7 in declared priority, call the resolved plugin's
   `CheckCondition(itemIdx, target, param, param2) → bool`. First match wins;
   tier = matching slot, else tier = 0 (Default).
3. **NPC actors** hot-load the actor's saved preset into a scratch buffer
   (`_sCond*` script-level arrays) before eval. Player uses the live
   `cond*` arrays directly. Same eval function reads through accessor helpers
   that route based on `_dispatchUseScratch`.
4. **Tier change** triggers (a) effect onDeactivate for prior tier, (b)
   `MTFPulse.SetActorPulseWithTransitionAt` with new tint/emissive/alpha/
   pulse params (cross-fade), (c) effect onActivate for new tier.

### Effect dispatch

Each slot can carry up to 4 effects, stored as parallel arrays on MainQuest:
`effectKey[slot*4+idx]`, `effectParam[…]`, `effectParam2[…]`, plus per-effect
**extras** in StorageUtil under `mtf.fx.<slot>.<idx>.ex.<field>` (player) or
`mtf.fx.scratch.<slot>.<idx>.ex.<field>` (NPCs from preset).

Plugin scripts implement `onActivate(itemIdx, target, param, param2)` and
`onDeactivate(itemIdx, target, param, param2)`. Long-running effects that
need to undo something on deactivate **must stash prev-value in StorageUtil
synchronously BEFORE the suspending call** (see KB → "Write StorageUtil
BEFORE suspending calls"). Idempotent — both hooks may fire multiple times
across tier oscillations.

Extras (per-effect bonus parameters) are declared per-plugin via
`GetEffectExtraCount(idx)` / `GetEffectExtraField(idx, n)` /
`GetEffectExtraMin/Max/Default/Label/Menu`. The host auto-discovers these
on registration; MCM renders sliders or dropdowns; loader writes both
player-live and scratch keyspaces.

### Scratch preset buffer (NPC path)

`_loadPresetToScratch(name)` reads the preset JSON via JsonUtil and writes
into `_sCond*` arrays (script-level vars, NOT properties — see KB → "Bulk
var add breaks save"). `_scratchLoadedFor` caches the last-loaded preset
name to skip reloads when the same actor evals again.

**Gotcha actively in force**: per the MEMORY entry "MTF scratch-namespace
clobber in dispatch loops" — never read `_scratchLoadedFor` inside a loop
that contains suspending calls. Snapshot the dispatch arrays into locals
BEFORE the loop.

### Preset I/O

Presets live in `Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/<name>.json`.
Shape:
```json
{
  "displayname": "Human-readable",
  "schemaversion": 7,
  "transition": { "duration": 0.3 },
  "slot": [
    { "cond": {...}, "cooldown": {...}, "effect": [{ "key": "...", "param": N, "param2": N, "extras": {...} }, ...] },
    ...8 entries total (Default + 7 conditions)
  ],
  "int": { "valid": 0 or 1 }
}
```

Saved-preset catalog is a StringList at `mtf.presets` (StorageUtil).
Per-actor applied stack is a StringList at `mtf.presets` on the actor.

### MCM state pool

SkyUI caps mod state IDs at 127. We use ~80 stable IDs total across:
generic toggles, slot picker (8), condition picker (~10), effect pickers
(4 × 8 = 32), **per-plugin enable** (16, PLUGIN_TOGGLE_1..16). Per-item
visibility (`disabledItems[]` map keyed `"<pid>:<itemid>"`) is dropdown-time
filtered, not state-bound. Don't add new state-bound widget pools without
checking the 127 ceiling.

### MTFPulse C++ contract

- One global tick at 20Hz drives all roster entries.
- `SetActorPulse*` writes a fresh entry or updates an existing one keyed on
  `(actor, baseOverlaySlot)`. Last write wins per actor.
- Cross-fade snapshots the prior entry's last interpolated state, so chained
  transitions don't snap back to the previous tier.
- Pass `transitionStartRT = Utility.GetCurrentRealTime() + 0.05` from
  Papyrus when batching multiple `Set` calls in one tick — without a shared
  anchor, first-frame alpha writes staircase the pop-on moment.
- All writes go through NiOverride; SKEE post-load race is real — schedule a
  second-chance redraw at ~3s after load (see MEMORY → "SKEE post-load race").
- `NiOverride.HasOverlays` lies after body 3D rebuild — don't gate on it
  (MEMORY → "SKEE HasOverlays lies").

## Conventions

### Storage keyspace

| Prefix | Purpose | Owner |
|---|---|---|
| `mtf.fx.<slot>.<eff>.ex.<field>` | Player effect extras (live) | MCM writes, plugins read |
| `mtf.fx.scratch.<slot>.<eff>.ex.<field>` | NPC effect extras (preset-loaded) | `_loadPresetToScratch` writes, plugins read |
| `mtf.<plugin>.<key>` | Plugin-private state | That plugin only |
| `mtf.presets` (on self / on actor) | Preset catalog / applied stack | MainQuest |
| `mtf.hit.<class>` | Hit counters | MTF_HitListener writes, Base reads |
| `mtf.pendCast.spells` / `.actors` | Cloak Cast() queue | MTF_Plugin_Base |

**JsonUtil keys must be all-lowercase** — PapyrusUtil silently lowercases on read.

### Plugin authoring

```papyrus
Scriptname MTF_Plugin_Foo extends MTF_Plugin

string Function GetPluginId()    : return "mtf.foo"     : EndFunction
string Function GetPluginLabel() : return "Foo Plugin"  : EndFunction

int  Function GetConditionCount() : return 2 : EndFunction
string Function GetConditionId(int i)
    if i == 0 : return "foo.a" : endif
    if i == 1 : return "foo.b" : endif
EndFunction
; ... GetConditionLabel, param ranges, CheckCondition
```

**Soft-master pattern** (plugin depends on a foreign mod):
```papyrus
SomeAPI Property _api Auto Hidden
bool Property _depsResolved = false Auto Hidden

Function _resolveDeps()
    if _depsResolved : return : endif
    _api = Game.GetFormFromFile(0xFORMID, "Foreign.esp") as SomeAPI
    if _api == None
        RegisterForSingleUpdate(2.0)
        return
    endif
    _depsResolved = true
EndFunction
```
Mirror the foreign type as a **minimal stub** in `_deps/`, declaring ONLY
the methods you actually call. Pulling the upstream `.psc` triggers a
dep cascade (slaMainScr, sslSystemLibrary, etc.) that won't compile.

### When to use which authoring tool

- **Spriggit YAML** — adding/editing ESP records, especially VMAD properties or aliases. The default.
- **AutoMod `esp`** — quick one-liner record creation when you don't need detailed fields.
- **xeditlib (Node)** — bulk read/analysis only. Never write.
- **Direct .psc edit** — script logic. Always.

### Migration discipline

Adding ANY post-release Auto property requires a `_migrationLevel` bump in
MainQuest and a migration block. Auto properties added after first save
**don't always attach** on existing saves — they read None forever. Use
`StorageUtil.SetXxxValue(self, "mtf.<key>", v)` for new state instead, or
attach a fresh child script. Bumped to `ml=37` on 2026-05 (Menu Options page
removal); next bump owns the next change.

## Standing Constraints (Read Before Editing)

- **Don't commit unverified changes.** Build & deploy, then wait for the user's
  in-game verification before `git commit`.
- **Backup ESPs before Spriggit** round-trip. CK edits not yet committed get
  silently dropped on deserialize.
- **Plugin Auto property cap** — every plugin script that adds new properties
  needs to either be brand-new (no existing save instances) or use StorageUtil
  from day one. Otherwise property writes silently no-op on existing saves.
- **Caprica heap on long docstrings** — keep `Scriptname { ... }` docstrings
  to one line. Multi-line is fine for functions, not the script header.
- **Papyrus array hard cap = 128**. Dispatch tables, effect pools, slot
  arrays — all stay under 128. Plan total size, not per-slot count.
- **Cross-script API design** — count + typed getters, never populated
  arrays or pipe-delimited strings (see KB → "Plugin API design").

## See Also

- `F:/stuff/Skyrim modding/CLAUDE.md` — repo-wide safety hooks, tool
  inventory, INI hierarchy, audit trail.
- `F:/stuff/Skyrim modding/KNOWLEDGEBASE.md` — engine quirks, SE vs VR
  differences, Papyrus gotchas in depth.
- `plans/integrations.md` — design doc for the SLA / SexLab / OStim / BFNG
  plugins (surface tables, soft-master notes).
- `SMOKE_TESTS.md` (TODO) — per-preset test recipes for the MTF Test Pack.
