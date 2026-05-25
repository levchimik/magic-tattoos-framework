# Writing an MTF Integration Plugin

How to add a new bridge between Magic Tattoos Framework and another
Skyrim mod's runtime state, so MTF can:

- Expose that mod's state as **conditions** picked per-slot in MCM
  (e.g. "trigger when arousal > 50", "when pregnant", "in combat").
- Fire **effects** when a tier becomes active (e.g. "boost arousal",
  "grant Ward spell", "play shader", "stagger attacker").
- Surface plugin-wide knobs on the MCM Plugins page (rate caps,
  thresholds, integration toggles).

The plugin pattern is the same one MTF itself uses internally for its
base / FMR / SLA / SexLab / OStim / BFNG / SlaveTats / SkyrimNet
plugins. Six of those eight live under `source/scripts/MTF_Plugin_*.psc`
as references.

A plugin is **one Papyrus script** (subclassing `MTF_Plugin`) plus a
tiny ESL-flagged ESP carrying a Quest that holds the script. **No
forking of MTF required.** Plugins discover the host at runtime via
`Game.GetFormFromFile`, so they ship as independent mods that just
depend on MagicTattoosFramework.esp.

---

## Contents

- [Architecture overview](#architecture-overview)
- [Minimal scaffold](#minimal-scaffold)
- [Conditions](#conditions)
- [Effects](#effects)
- [Lifecycle hooks](#lifecycle-hooks)
- [Extras: per-effect extra fields](#extras-per-effect-extra-fields)
- [Dropdowns: enum-style params](#dropdowns-enum-style-params)
- [Plugin-wide settings](#plugin-wide-settings)
- [The ESP](#the-esp)
- [Soft-master pattern](#soft-master-pattern)
- [Common pitfalls](#common-pitfalls)
- [Testing](#testing)
- [Reference: existing plugins](#reference-existing-plugins)

---

## Architecture overview

```
                            ┌──────────────────────────┐
                            │     MTF_MainQuest        │  ← host
                            │  (MagicTattoosFramework  │     (in MTF's ESP,
                            │   .esp, formId 0x803)    │      FormID 0x803)
                            └──────────┬───────────────┘
                                       │ registeredPlugins[]
                                       │
              ┌────────────────────────┼────────────────────────┐
              │                        │                        │
   ┌──────────▼──────────┐  ┌──────────▼──────────┐  ┌─────────▼──────────┐
   │   MTF_Plugin_Base   │  │   MTF_Plugin_FMR    │  │  MTF_Plugin_YOURS  │
   │ (built-in, ships    │  │ (your-mod soft-     │  │ (you author this)  │
   │  with MTF.esp)      │  │  master)            │  │                    │
   └─────────────────────┘  └─────────────────────┘  └────────────────────┘
```

### Lifecycle

1. **Save loads.** Skyrim attaches every plugin's script to its
   Quest. `MTF_Plugin.OnInit()` schedules a 0.5 s update.
2. **0.5 s later, `_tryRegister()` runs:**
   - Resolves soft-master dependencies via `Game.GetFormFromFile`.
     If the target mod isn't loaded, the resolution returns `None`
     and the plugin re-schedules itself for another 2 s; this loops
     until success or the session ends — so plugins activated
     mid-session also bind.
   - Locates the MTF host: `Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp")`.
     If the host's `registeredPlugins` array isn't yet allocated,
     re-schedule.
   - Calls `host.RegisterPlugin(self)` — the host iterates the
     plugin's vtable (`GetConditionCount`, `GetEffectCount`, …) and
     populates its global condition/effect tables.
3. **MCM opens.** Per-slot condition / effect dropdowns are rendered
   from the host's tables. Your plugin's items appear automatically.
4. **Tier evaluation tick (~2 s).** For each tracked actor, MTF walks
   the active slot's condition and calls `checkCondition(idx, actor, param)`.
5. **Tier becomes active.** MTF calls `onActivate(idx, actor, param, param2)`
   for each effect bound to that slot. Also fires `onTick` every eval
   tick and `onGameTime` once per in-game hour.
6. **Tier becomes inactive.** MTF calls `onDeactivate(idx, actor, param, param2)`
   for each previously-active effect.

### Identity

- Each plugin has a unique **pluginId** (`mtf.fmr`, `mtf.skyrimnet`).
- Each condition / effect has a unique **itemId** within its plugin
  (`pregnancy`, `trigger.ovulation`, etc.).
- Globally, items are referenced as `"<pluginId>:<itemId>"` — these
  strings live in presets and StorageUtil keys, so they must stay
  stable across versions.

---

## Minimal scaffold

A plugin doing one trivial condition and one trivial effect:

```papyrus
Scriptname MTF_Plugin_Hello extends MTF_Plugin
{Demo plugin: trigger when actor is over level 10; effect adds 50 gold.}

string Function GetPluginId()
    return "mtf.hello"
EndFunction

string Function GetPluginLabel()
    return "Hello Plugin"
EndFunction

; ── Conditions ───────────────────────────────────────────────────

int Function GetConditionCount()
    return 1
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "is.highlevel"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "Is High Level"
    endif
    return ""
EndFunction

string Function GetConditionDescription(int idx)
    if idx == 0
        return "Triggers when the actor is level {param1} or higher."
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx == 0
        return "Min level"
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    return 1
EndFunction
int Function GetConditionParamMax(int idx)
    return 100
EndFunction
int Function GetConditionParamDefault(int idx)
    return 10
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None
        return false
    endif
    if idx == 0
        return target.GetLevel() >= param
    endif
    return false
EndFunction

; ── Effects ──────────────────────────────────────────────────────

int Function GetEffectCount()
    return 1
EndFunction

string Function GetEffectId(int idx)
    if idx == 0
        return "burst.gold"
    endif
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    if idx == 0
        return "Award Gold"
    endif
    return ""
EndFunction

string Function GetEffectKind(int idx)
    if idx == 0
        return "burst"
    endif
    return "continuous"
EndFunction

string Function GetEffectDescription(int idx)
    if idx == 0
        return "Burst — adds {param1} gold to the actor's inventory on activation."
    endif
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    if idx == 0
        return "Gold amount"
    endif
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    return 1
EndFunction
int Function GetEffectParamMax(int idx)
    return 1000
EndFunction
int Function GetEffectParamDefault(int idx)
    return 50
EndFunction

Function onActivate(int idx, Actor target, int param, int param2)
    if idx == 0 && target != None
        Form gold = Game.GetFormFromFile(0x0F, "Skyrim.esm")
        target.AddItem(gold, param)
    endif
EndFunction
```

That's a complete, working plugin. Drop it in an ESP, hook the script
to a Quest, build, and MTF picks it up next save load.

---

## Conditions

A condition is a per-tick predicate. Returning `true` makes the slot
eligible for activation (subject to higher slots winning first).

### Required methods

| Method | Returns | Purpose |
|---|---|---|
| `GetConditionCount()` | int | Number of conditions this plugin provides. |
| `GetConditionId(int idx)` | string | Stable per-plugin id (lowercase, no spaces, no colons). |
| `GetConditionLabel(int idx)` | string | MCM display name. |
| `GetConditionDescription(int idx)` | string | Plain-English description. `{param1}` and `{param2}` get substituted with the current slot's values for LLM consumption. |
| `checkCondition(int idx, Actor target, int param)` | bool | The actual predicate. Called every ~2 s. |

### Optional parameter slots

A condition can declare one or two integer parameters that the user
adjusts via MCM sliders:

| Method | Purpose |
|---|---|
| `GetConditionParamLabel(int idx)` | Slider label. Return `""` if no parameter. |
| `GetConditionParamMin/Max/Default(int idx)` | Slider bounds and default. |
| `GetConditionParamFormat(int idx)` | SkyUI format string (`"{0}"`, `"{0}%"`, `"{1} s"`). Default `"{0}"`. |
| `GetConditionParam2*` | Same set for the optional 2nd parameter. Return `""` from `GetConditionParam2Label` to hide it. |

The 2nd parameter value is read in `checkCondition` via
`_host().GetEvalParam2()` rather than as a function argument (the
arity is fixed at one int param for back-compat).

### Dropdown-style conditions

For conditions whose parameter is an enum (e.g. cycle phase: 0/1/2/3),
return a menu instead of a slider:

```papyrus
int Function GetConditionParamMenuOptionCount(int idx)
    if idx == 0
        return 4
    endif
    return 0
EndFunction

int Function GetConditionParamMenuOptionValue(int idx, int optionIdx)
    if idx == 0
        return optionIdx  ; 0..3 maps directly
    endif
    return 0
EndFunction

string Function GetConditionParamMenuOptionLabel(int idx, int optionIdx)
    if idx == 0
        if optionIdx == 0
            return "Follicular"
        elseif optionIdx == 1
            return "Ovulation"
        elseif optionIdx == 2
            return "Luteal"
        elseif optionIdx == 3
            return "Menstrual"
        endif
    endif
    return ""
EndFunction
```

When `GetConditionParamMenuOptionCount` returns > 0, MCM shows a
dropdown instead of a slider. The slider min/max/default hooks become
inert.

---

## Effects

An effect is a lifecycle-bound action. It fires when a tier becomes
active (`onActivate`) and reverts when the tier becomes inactive
(`onDeactivate`).

### Required methods

| Method | Returns | Purpose |
|---|---|---|
| `GetEffectCount()` | int | Number of effects this plugin provides. |
| `GetEffectId(int idx)` | string | Stable per-plugin id. |
| `GetEffectLabel(int idx)` | string | MCM display name. Do NOT prefix `[!]` manually — set `"kind": "burst"` in the JSON catalog and the framework prepends the badge at render time. |
| `GetEffectKind(int idx)` | string | `"burst"` (one-shot on activate) or `"continuous"` (default; active while the tier is on). Determines whether MCM badges the label and whether the lifecycle audit tracks it. |
| `GetEffectDescription(int idx)` | string | Plain-English description. `{param1}` / `{param2}` substituted. |
| `onActivate(int idx, Actor target, int param, int param2)` | — | Called when the effect becomes active. |

### Optional parameter slots

Same as conditions:

| Method | Purpose |
|---|---|
| `GetEffectParamLabel(int idx)` | Slider label. Empty = no parameter. |
| `GetEffectParamMin/Max/Default/Step(int idx)` | Slider bounds, default, and step. |
| `GetEffectParamFormat(int idx)` | Format string. |
| `GetEffectParam2*` | Same set for the 2nd parameter. |

### Lifecycle hooks (optional but important)

```papyrus
Function onActivate(int idx, Actor target, int param, int param2)
Function onDeactivate(int idx, Actor target, int param, int param2)
Function onTick(int idx, Actor target, int param, int param2)
Function onGameTime(int idx, Actor target, int param, int param2)
```

- **`onActivate`** fires once when the tier just won. Apply your
  effect here.
- **`onDeactivate`** fires once when the tier stops being active.
  **Revert any persistent change here.** See "Common pitfalls" below.
- **`onTick`** fires every MTF evaluation tick (~2 s) while the
  tier is active. Use for stateful effects that need to recompute
  (e.g. a `% of current magicka` drain that shifts with gear changes).
- **`onGameTime`** fires once per in-game hour while the tier is
  active. Use for cumulative effects (e.g. SLA exposure deltas).

---

## Extras: per-effect extra fields

An effect can declare up to 3 extra typed fields that MCM renders as
additional sliders / dropdowns below `param` and `param2`. These get
stored in StorageUtil keyed by (slot, effectIdx, fieldName), and
round-trip through preset JSON automatically.

```papyrus
int Function GetEffectExtraFieldCount(int idx)
    if idx == 0
        return 2
    endif
    return 0
EndFunction

string Function GetEffectExtraFieldName(int idx, int fieldIdx)
    ; lowercase ASCII, no spaces, max 12 chars — JsonUtil lowercases keys
    if idx == 0
        if fieldIdx == 0
            return "radius"
        elseif fieldIdx == 1
            return "duration"
        endif
    endif
    return ""
EndFunction

string Function GetEffectExtraFieldLabel(int idx, int fieldIdx)
    if idx == 0
        if fieldIdx == 0
            return "Aura radius (units)"
        elseif fieldIdx == 1
            return "Duration (seconds)"
        endif
    endif
    return ""
EndFunction

int Function GetEffectExtraFieldMin(int idx, int fieldIdx)
    return 1
EndFunction
int Function GetEffectExtraFieldMax(int idx, int fieldIdx)
    if fieldIdx == 0
        return 2000  ; radius
    elseif fieldIdx == 1
        return 60    ; duration
    endif
    return 100
EndFunction
int Function GetEffectExtraFieldDefault(int idx, int fieldIdx)
    if fieldIdx == 0
        return 256
    elseif fieldIdx == 1
        return 10
    endif
    return 0
EndFunction
```

Read extras in `onActivate` via the host helper:
`_host().GetSlotEffectExtra(slotIdx, effectIdx, "radius")` returns a
float. The slot/effect indices are available from the dispatch
context — see `MTF_Plugin_Base.psc` for a working pattern.

**Field name constraints (silent footguns):**
- Lowercase ASCII only. JsonUtil lowercases keys on write, so mixed
  case reads back blank.
- No spaces. No special characters.
- Keep ≤ 12 chars — used as StorageUtil sub-keys.

---

## Dropdowns: enum-style params

Mirror of the condition dropdown API:

```papyrus
int Function GetEffectParamMenuOptionCount(int idx)
    if idx == 0
        return 3
    endif
    return 0
EndFunction

int Function GetEffectParamMenuOptionValue(int idx, int optionIdx)
    if idx == 0
        if optionIdx == 0
            return 0    ; Off
        elseif optionIdx == 1
            return 1    ; Subtle
        elseif optionIdx == 2
            return 2    ; Loud
        endif
    endif
    return 0
EndFunction

string Function GetEffectParamMenuOptionLabel(int idx, int optionIdx)
    if idx == 0
        if optionIdx == 0
            return "Off"
        elseif optionIdx == 1
            return "Subtle"
        elseif optionIdx == 2
            return "Loud"
        endif
    endif
    return ""
EndFunction
```

Stored values can be any int — non-contiguous (bitmasks like
`1|6|112`) work; MCM falls back to "Custom: N" for hand-edited preset
values outside the option list.

---

## Plugin-wide settings

Knobs that apply to the whole plugin (not per-slot) — e.g. a rate
cap, a global volume, a feature toggle. Rendered on the MCM Plugins
page under your plugin's header.

```papyrus
int Function GetSettingCount()
    return 1
EndFunction

string Function GetSettingId(int idx)
    if idx == 0
        return "narrate"
    endif
    return ""
EndFunction

string Function GetSettingLabel(int idx)
    if idx == 0
        return "Enable NPC narration"
    endif
    return ""
EndFunction

string Function GetSettingInfo(int idx)
    if idx == 0
        return "If on, tattoo changes fire SkyrimNet short-lived events."
    endif
    return ""
EndFunction

int Function GetSettingMin(int idx)
    return 0
EndFunction
int Function GetSettingMax(int idx)
    return 1
EndFunction
int Function GetSettingDefault(int idx)
    return 1
EndFunction

int Function GetSettingValue(int idx)
    if idx == 0
        return _narrateEnabled as int
    endif
    return 0
EndFunction

Function SetSettingValue(int idx, int v)
    if idx == 0
        _narrateEnabled = (v == 1)
    endif
EndFunction
```

Settings persist via StorageUtil under the plugin's own keys. The
host doesn't manage their storage — you handle persistence inside
the script (typically via `StorageUtil.SetIntValue(self, key, v)`
in `SetSettingValue` and matching `GetIntValue` in `GetSettingValue`).

---

## The ESP

A plugin needs an ESP for two reasons only:

1. To attach the script to a Quest record so Skyrim instantiates it.
2. To provide a soft-master target form ID that other tools can
   probe (`Game.GetFormFromFile(<formId>, "<your.esp>")`).

The ESP can be **tiny**. The MTF integration plugins are all ESL-flagged
and ~450 bytes each. The minimal ESP layout:

- **One Quest record** — start enabled, run-once. Attach your
  `MTF_Plugin_<name>` script as the Quest's primary script.

That's it. No spells, no perks, no NPCs, no scripts beyond the one
attached to the Quest. The Quest's only job is to anchor your script
in the game's runtime so its `OnInit` fires.

Steps to create:
1. Either open the Creation Kit and make a new ESL-flagged ESP from
   scratch, OR copy one of the existing plugin YAML mirrors under
   [`spriggit/`](../spriggit/) (e.g. `spriggit/MTF_Plugin_FMR/`) to
   `spriggit/MTF_Plugin_<YourName>/`, then edit:
   - `spriggit-meta.json` → set `ModKey` to `MTF_Plugin_<YourName>.esp`
   - `RecordData.yaml` → bump the plugin name in `MasterReferences`
     if needed
   - rename the file under `Quests/` and edit the `EditorID` to match
     your script
2. Make sure the ESP is ESL-flagged (the existing plugin templates
   already are — they use FormIDs in the `FE<slot>000800-000FFF`
   range).
3. The Quest record should be Start Game Enabled + Run Once, with
   `MTF_Plugin_<YourName>` attached as its primary script (the
   existing templates show the VMAD layout).
4. Build the ESP: `bash tools/build_esps.sh MTF_Plugin_<YourName>`
   (deserialize that one folder into `_build/esps/`).
5. Compile your `.psc` with Caprica:
   `bash tools/build_scripts.sh` (deploys the `.pex` to MO2).
6. Ship the ESP + the `.pex` in a mod folder, OR add a stage step
   to `tools/fomod/build_fomod.sh` to bundle it into the framework's
   FOMOD installer.

---

## Soft-master pattern

The whole point of the integration plugin is to bridge MTF onto
**another mod that may or may not be loaded**. Hard-mastering means
your plugin can't load without the target mod — usually too strict.

The soft-master pattern:

```papyrus
SomeQuest Property TargetQuest Auto Hidden

bool Function _resolveDeps()
    if TargetQuest != None
        return true
    endif
    TargetQuest = Game.GetFormFromFile(0xABCD, "TargetMod.esm") as SomeQuest
    return TargetQuest != None
EndFunction

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        ; Target mod not loaded (or not yet resolvable). Re-arm.
        ; WITHOUT this, the bail is silent — your plugin would never retry
        ; for the rest of the session.
        RegisterForSingleUpdate(2.0)
        return
    endif
    ; ... rest of registration
EndFunction
```

`Game.GetFormFromFile(formId, "filename.esp")` returns `None` if:
- The file isn't loaded, OR
- The form ID doesn't exist in that file, OR
- The form exists but is the wrong type for your cast.

Cache the resolved Form in an Auto Hidden property so subsequent
`_resolveDeps` calls return immediately. Re-cast on every checkCondition
is too slow.

Pick a form that's **stable across versions** of the target mod —
preferably a script Quest or a defining GlobalVariable rather than
something the mod author might re-number across updates.

---

## Common pitfalls

### onDeactivate is a no-op default — and the silent footgun

The `MTF_Plugin` base class's `onDeactivate` is an empty function.
**If your effect mutates persistent engine state in `onActivate` and
you forget to override `onDeactivate`, removing the tattoo silently
leaves the state applied.** No compile error, no log warning. Players
will report "removing the tattoo doesn't actually remove the buff".

Two cases where the no-op default is correct:
1. **Transient one-shot effects** — bursts, stagger, alerts, bounty
   bumps. They finish during `onActivate` and have no rolling state.
2. **State that lives in another framework's storage and is meant to
   decay/expire naturally** — SLA exposure deltas, FMR ovulation
   timers. Symmetric cleanup would either be wrong (refund could
   push to negative) or impossible (no cancel API on the other side).

For everything else (ModActorValue, AddSpell, persistent shader
effects, applied magic effects), implement `onDeactivate` to revert.

### ModActorValue race: write StorageUtil BEFORE the suspending call

If your effect calls `target.ModActorValue(...)` or `target.AddSpell(...)`
(any Form call — these suspend the script for a frame), two activations
landing in quick succession can both read the prior state, both
apply, and double the effect.

Fix: write your "applied amount" to StorageUtil **before** the
suspending call. The second stack reads the freshly-written value
and short-circuits.

```papyrus
; WRONG — read-then-mutate race
float prev = StorageUtil.GetFloatValue(target, "myAppliedDelta", 0.0)
target.ModActorValue("CarryWeight", -prev + newDelta)  ; suspends
StorageUtil.SetFloatValue(target, "myAppliedDelta", newDelta)

; RIGHT — write the goalpost first
float prev = StorageUtil.GetFloatValue(target, "myAppliedDelta", 0.0)
if prev == newDelta
    return  ; idempotent
endif
StorageUtil.SetFloatValue(target, "myAppliedDelta", newDelta)  ; commit first
target.ModActorValue("CarryWeight", -prev + newDelta)
```

The framework already documents this pattern internally — see
`project_papyrus_storage_before_suspend` in the project memory notes.

### Don't trust Auto-property post-release addition

If your plugin is already shipped and in a player's save, **adding
new `Auto` (or `Auto Hidden`) properties to the script doesn't always
create backing storage on existing saves**. Writes silently no-op.

For any state added after a release, prefer StorageUtil from the
start over `Auto` properties. The base class's `_registered` flag is
the only `Auto Hidden` you can reliably add, because the framework
re-initializes it on load.

### Lowercase JSON keys (PapyrusUtil quirk)

PapyrusUtil's `JsonUtil` lowercases all string keys on write. If you
expose extras with mixed-case names like `"MaxRadius"`, the reads
will silently return defaults because the stored key is `"maxradius"`.
Always use lowercase ASCII for any key that round-trips through
JSON.

### Papyrus arrays cap at 128

If your plugin needs to declare more than 128 conditions or effects,
you'll hit the engine's array limit silently. `Utility.CreateStringArray(160, ...)`
returns None. Plan total item count around 128.

---

## Testing

1. Compile your .psc + ESP.
2. Drop into MO2, enable.
3. Load a save (or start a new game) with the target soft-master mod
   active.
4. Open the MCM. Your plugin's pluginLabel should appear:
   - In the **Plugins page**, under its own header (with any
     `GetSettingCount > 0` knobs).
   - As an entry in per-slot **Condition** dropdowns (one entry per
     condition).
   - As an entry in per-slot **Effect** dropdowns (one entry per
     effect).
5. Bind a condition to a slot, save the preset, trigger the condition
   in-game. The tier should activate within ~2 s.
6. Bind an effect to the same slot. Confirm `onActivate` fires (use
   `Debug.Trace("MTF: my plugin onActivate")` and check the Papyrus
   log).

If the plugin never registers:
- Check the Papyrus log
  (`Documents/My Games/Skyrim Special Edition/Logs/Script/Papyrus.0.log`)
  for compile errors or `MTF: plugin <id> registered` messages.
- Verify `Game.GetFormFromFile` returns non-None for both the host
  and your soft-master target — easy way is to set
  `Debug.Notification("FMR_Storage: " + FMR_Storage)` in `_resolveDeps`.
- Confirm your ESP is enabled in plugins.txt.

---

## Reference: existing plugins

| Plugin | Soft-master | Demonstrates |
|---|---|---|
| `MTF_Plugin_FMR.psc` | Fertility Mode (.esm) | Form-based soft-probe, per-actor lookup table, 1 numeric condition + 1 dropdown condition + 1 burst effect with no params. |
| `MTF_Plugin_SLA.psc` | OSL Aroused (.esp) | Cross-storage read pattern, hourly tick for exposure deltas, an aura effect with extras. |
| `MTF_Plugin_SexLab.psc` | SexLab Framework SE | Event-driven state instead of poll-based check; multiple conditions sharing the same scene-active check. |
| `MTF_Plugin_OStim.psc` | OStim Standalone | Multi-source state binding (scene + per-actor excitement). |
| `MTF_Plugin_BFNG.psc` | Beeing Female NG (.esm) | Dropdown-style condition (cycle phase) with named options. |
| `MTF_Plugin_SlaveTats.psc` | SlaveTats | Bidirectional bridge — also writes TO SlaveTats's state store. Demonstrates non-conventional effect patterns. |
| `MTF_Plugin_SkyrimNet.psc` | SkyrimNet | Plugin-wide settings, no conditions/effects (it's purely a one-way bridge). Shows the `GetSettingCount > 0` pattern. |
| `MTF_Plugin_Base.psc` | (none — ships with MTF.esp) | The complete reference of every method you can override, plus all the built-in effects (drains, shaders, sounds, AV mods, resists, skill modifiers). |

Reading these in order — FMR for the basic shape, BFNG for
dropdowns, SLA for time-driven mutation, SexLab for event hookup —
covers every pattern you'll need.

The abstract base lives at `source/scripts/MTF_Plugin.psc`. Every
method's docstring documents the contract; that file is the
authoritative API reference.
