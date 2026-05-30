# Writing an MTF Integration Plugin

How to add a new bridge between Magic Tattoos Framework and another
Skyrim mod's runtime state, so MTF can:

- Expose that mod's state as **conditions** picked per-slot in MCM
  (e.g. "trigger when arousal > 50", "while pregnant", "in combat").
- Fire **effects** when a tier becomes active (e.g. "boost arousal",
  "play a shader", "modify a skill", "stagger attacker").

The plugin pattern is the same one MTF uses internally for its built-in
catalog and for FMR / SLA / SexLab / OStim / BFNG / SlaveTats / SkyrimNet.
Reference implementations live under `source/scripts/MTF_Plugin_*.psc`.

A plugin is **two files**:

1. A **JSON catalog** at `Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/<pluginId>.json` — declares the plugin's conditions, effects, parameter sliders, dropdowns, and prose descriptions. All metadata lives here.
2. A **Papyrus script** subclassing `MTF_Plugin` — implements `GetPluginId()` plus four small behaviour hooks (`checkCondition`, `onActivate`, `onDeactivate`, `onTick`, `onGameTime`).

Plus a tiny ESL-flagged ESP carrying a Quest that holds the script.
**No forking of MTF required.** Plugins discover the host at runtime via
`Game.GetFormFromFile`, so they ship as independent mods that just
depend on `MagicTattoosFramework.esp`.

---

## Contents

- [Architecture overview](#architecture-overview)
- [The JSON catalog](#the-json-catalog)
- [Minimal scaffold](#minimal-scaffold)
- [Conditions](#conditions)
- [Effects](#effects)
- [Soft-master and lifecycle hooks](#soft-master-and-lifecycle-hooks)
- [The ESP](#the-esp)
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
   - Calls `_resolveDeps()` — your override probes for the target mod's
     forms / APIs. If it returns false (mod not loaded yet), the
     framework re-arms a 2 s update and loops until success.
   - Locates the MTF host at FormID 0x803. If `registeredPlugins`
     isn't yet allocated, re-arm 1 s.
   - Calls `host.RegisterPlugin(self)` — the host walks the plugin's
     catalog JSON (via the base class's JsonUtil getters) and populates
     its global condition/effect tables.
   - Calls `_onRegistered()` — your override does first-session bridge
     setup (e.g. SkyrimNet schema registration).
3. **MCM opens.** Per-slot condition / effect dropdowns are rendered
   from the host's tables. Your plugin's items appear automatically.
4. **Tier evaluation tick (~2 s).** For each tracked actor, MTF walks
   the active slot's condition and calls `checkCondition(target, param, cid)`.
5. **Tier becomes active.** MTF calls `onActivate(target, param1, param2, eid)`
   for each effect bound to that slot. Also fires `onTick` every eval
   tick and `onGameTime` once per in-game hour while the tier stays on.
6. **Tier becomes inactive.** MTF calls `onDeactivate(target, param1, param2, eid)`
   for each previously-active effect.

### Identity

- Each plugin has a unique **pluginId** (`mtf.fmr`, `mtf.skyrimnet`).
- Each condition / effect has a unique **itemId** within its plugin
  (`pregnancy`, `trigger.ovulation`, `flash.onhit`, etc.).
- Globally, items are referenced as `"<pluginId>:<itemId>"` — these
  strings live in presets and StorageUtil keys, so they must stay
  stable across versions.

**Dispatch is by id string, never by array position.** Your behaviour
hooks receive a `cid` / `eid` argument (the catalog id) and branch on
that. JSON catalog ordering is purely cosmetic — reordering entries
will never mis-dispatch.

---

## The JSON catalog

The single source of truth for everything except runtime behaviour.

**Path:** `Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/<pluginId>.json`

**JsonUtil quirk:** PapyrusUtil lowercases every string key on read.
**All JSON keys must be lowercase ASCII.** Mixed-case keys like
`pluginLabel` will read back as empty strings.

### Top level

```json
{
  "schemaversion": 2,
  "pluginid": "mtf.example",
  "pluginlabel": "Example Plugin",
  "conditions": [ ... ],
  "effects": [ ... ]
}
```

- `schemaversion` — current schema is `2`. Forward-compatibility marker;
  bumped on breaking changes (field renames/removes, semantic shifts).
  When MTF's host expects a higher version than your catalog declares,
  it logs a loud warning to the Papyrus log so users know to update
  the plugin. Schema 2 (v0.2.9) migrated menu options from
  `{value: int, label}` to `{id: string, label}` — see
  [Dropdowns](#dropdowns).
- `pluginid` — must match what `GetPluginId()` returns in your script.
- `pluginlabel` — user-facing plugin name shown on the MCM Plugins page.
- `conditions` / `effects` — arrays; either may be empty (e.g. a
  one-way bridge that only reads `onActivate` events).

### Conditions

Up to 2 parameter slots per condition (`param` + `param2`, legacy
naming kept since most conditions are single-threshold predicates).

```json
{
  "id": "pregnancy",
  "label": "Pregnancy",
  "description": "Triggers when the actor is at least {param1}% through her pregnancy.",
  "param": {
    "label": "Min belly stage (1-100)",
    "min": 1,
    "max": 100,
    "default": 1,
    "format": "{0}%"
  }
}
```

- `id` — stable per-plugin id (lowercase, no spaces, no colons). What
  `checkCondition` branches on as `cid`.
- `label` — MCM display name.
- `description` — plain-English description. `{param1}` and `{param2}`
  get substituted with the current slot's values; consumed by LLM
  bridges (SkyrimNet) so an AI narrator can explain *when* a tattoo
  will activate.
- `param` / `param2` — optional parameter declarations. Omit when the
  condition takes no parameter (e.g. boolean predicates like `in.scene`).
  - `min` / `max` / `default` — slider bounds.
  - `format` — SkyUI format string for the slider display
    (`"{0}"` raw int, `"{0}%"`, `"{1} s"`, etc.). Default `"{0}"`.
  - `step` — slider step (param2 only — historical asymmetry; the
    param1 slider always steps by 1).
  - `menu` — see [Dropdowns](#dropdowns) below.

### Effects

Up to 5 parameter slots per effect (`param1` through `param5`).
Effects have one extra field: `kind`.

```json
{
  "id": "flash.onhit",
  "label": "Flash on Hit",
  "kind": "continuous",
  "description": "When the actor is hit by a {param1}, the tattoo flashes for {param2} seconds.",
  "param1": {
    "label": "Hit class",
    "default": "any",
    "menu": [
      {"id": "any",    "label": "Any hit"},
      {"id": "bladed", "label": "Bladed"},
      {"id": "blunt",  "label": "Blunt"}
    ]
  },
  "param2": {
    "label": "Flash duration",
    "min": 1,
    "max": 30,
    "default": 8,
    "format": "{0} s"
  }
}
```

- `id` — stable per-plugin id. What the lifecycle hooks branch on as `eid`.
- `label` — MCM display name. **Do NOT prefix `[!]` manually.** Set
  `"kind": "burst"` and the framework prepends the badge at render time.
- `kind` — `"burst"` (one-shot on activate; `onDeactivate`/`onTick`
  ignored) or `"continuous"` (default; active while tier is on; you
  MUST clean up in `onDeactivate`). Determines whether the lifecycle
  audit tracks the effect and whether the MCM badges the label.
- `description` — plain-English description. `{param1}` / `{param2}`
  substituted. Same LLM-bridge purpose as conditions.
- `param1` … `param5` — up to five parameter declarations. Same shape
  as condition `param`. Omit any you don't need; the MCM probes each
  one's `.label` and only renders slots where it's non-empty.

### Dropdowns

A `menu` array on any `param*` makes that parameter render as a
dropdown instead of a slider:

```json
"param": {
  "label": "Phase",
  "default": "ovulating",
  "menu": [
    {"id": "follicular",   "label": "Follicular"},
    {"id": "ovulating",    "label": "Ovulating"},
    {"id": "luteal",       "label": "Luteal"},
    {"id": "menstruating", "label": "Menstruating"}
  ]
}
```

- `id` is the **stable string** stored on the slot and what your behaviour
  hook receives (read via `_host().GetEvalParamStr()` from
  `checkCondition`, or `host.GetSlotEffectParamNStr(slot, eff, n)` from
  effect dispatchers — schema v2, v0.2.9+).
- `id` must be `[a-z0-9_]+`. Convention is `snake_case`.
- `id`s must stay **stable across versions** — saved presets reference
  them. The `label` can be edited freely. **Don't reuse or rename ids.**
- `default` is the id (not an int) of the option used when no value has
  been stamped yet.
- Reordering the `menu` array is **safe** — saved presets reference ids,
  not positions, so users can shuffle the dropdown without breaking
  any existing slots.
- `min` / `max` are **not honoured** on menu params (the migrator strips
  them). Hand-edited presets with unknown ids fall through to the
  catch-all branch in your dispatcher (typically a safe default).

---

## Minimal scaffold

A complete plugin doing one trivial condition and one trivial effect.

### `mtf.hello.json`

`Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.hello.json`:

```json
{
  "schemaversion": 2,
  "pluginid": "mtf.hello",
  "pluginlabel": "Hello Plugin",
  "conditions": [
    {
      "id": "is.highlevel",
      "label": "Is High Level",
      "description": "Triggers when the actor is level {param1} or higher.",
      "param": {
        "label": "Min level",
        "min": 1, "max": 100, "default": 10
      }
    }
  ],
  "effects": [
    {
      "id": "burst.gold",
      "label": "Award Gold",
      "kind": "burst",
      "description": "Burst — adds {param1} gold on activation.",
      "param1": {
        "label": "Gold amount",
        "min": 1, "max": 1000, "default": 50
      }
    }
  ]
}
```

### `MTF_Plugin_Hello.psc`

```papyrus
Scriptname MTF_Plugin_Hello extends MTF_Plugin
{Demo plugin: trigger when actor is high-level; effect adds gold.}

string Function GetPluginId()
    return "mtf.hello"
EndFunction

bool Function checkCondition(Actor target, int param, string cid)
    if target == None
        return false
    endif
    if cid == "is.highlevel"
        return target.GetLevel() >= param
    endif
    return false
EndFunction

Function onActivate(Actor target, int param, int param2, string eid)
    if target == None
        return
    endif
    if eid == "burst.gold"
        Form gold = Game.GetFormFromFile(0x0F, "Skyrim.esm")
        target.AddItem(gold, param)
    endif
EndFunction
```

That's the entire plugin code. The base class supplies everything
else: catalog loading, registration loop, MCM render, preset
serialisation, lifecycle dispatch. Drop the script in an ESP (see
[The ESP](#the-esp)), build, and MTF picks it up next save load.

---

## Conditions

A condition is a per-tick predicate. Returning `true` makes the slot
eligible for activation (subject to higher slots winning first).

### Signature

```papyrus
bool Function checkCondition(Actor target, int param, string cid)
```

- `target` — the actor being evaluated. Always non-None inside the
  function body in practice, but guard defensively (`target == None`).
- `param` — the slot's `param` value (the first parameter from the JSON).
- `cid` — the catalog id string from your JSON. Dispatch on this:

```papyrus
bool Function checkCondition(Actor target, int param, string cid)
    if target == None
        return false
    endif
    if cid == "arousal"
        ; Slider param — `param` is the int threshold.
        return SLAFramework.GetActorArousal(target) >= param
    elseif cid == "arousal.lock"
        ; Parameterless boolean condition — fires when arousal is locked.
        return SLAFramework.IsActorArousalLocked(target)
    endif
    return false
EndFunction
```

### Reading the second parameter

`param2` is NOT passed as an argument (the engine-side dispatch
signature is fixed at one `int param`). Read it via the host helper:

```papyrus
int p2 = _host().GetEvalParam2()
```

This is only valid during a `checkCondition` call — it reads the
dispatch context.

### Reading menu (string-id) parameters

For params declared with a `menu`, the **id string** is the dispatch
value — the int `param` arg is meaningless. Read via the host:

```papyrus
string p1s = _host().GetEvalParamStr()
string p2s = _host().GetEvalParam2Str()
```

Same scope rule as `GetEvalParam2`: only valid inside `checkCondition`.
Effects read string params via `host.GetSlotEffectParamNStr(slot, eff, n)` —
see [Reading params 3-5](#reading-params-3-5).

### Called every ~2 s

Eval ticks fire every 2 seconds (the MTF slow-tick). Don't do heavy
work inside `checkCondition` — the same predicate may be called many
times per second across many tracked actors. Cache resolved forms in
Auto Hidden properties.

---

## Effects

An effect is a lifecycle-bound action. It fires when a tier becomes
active (`onActivate`) and reverts when the tier stops being active
(`onDeactivate`). For continuous effects, `onTick` and `onGameTime`
fire while the tier stays on.

### Signatures

```papyrus
Function onActivate(Actor target, int param, int param2, string eid)
Function onDeactivate(Actor target, int param, int param2, string eid)
Function onTick(Actor target, int param, int param2, string eid)
Function onGameTime(Actor target, int param, int param2, string eid)
```

- `target` — the actor the effect is applying to.
- `param` / `param2` — `param1` and `param2` from the JSON catalog
  (the two most common per-effect controls).
- `eid` — the catalog id string. Dispatch on this:

```papyrus
Function onActivate(Actor target, int param, int param2, string eid)
    if target == None
        return
    endif
    if eid == "cum.apply"
        SexLab.AddCumFx(target, param)            ; param = type 0/1/2
    elseif eid == "skill.add.xp"
        SLStats.AddSkillXP(target, param as float, ...)
    endif
EndFunction
```

### `kind: burst` vs `continuous`

- **`burst`** — fires once during `onActivate`; framework treats it as
  ephemeral. `onDeactivate` and `onTick` are not called. Lifecycle
  audit ignores burst effects. Examples: `trigger.ovulation`,
  `burst.gold`, `cum.apply`.
- **`continuous`** (default) — active while the tier is on. **You
  MUST clean up in `onDeactivate`.** The lifecycle audit tracks
  continuous effects. Examples: `flash.onhit`, `modify.skill`,
  `arousal.rate`.

### Reading params 3-5

The signature carries `param1` and `param2` positionally; param3–5
require an extra host call. Inside any dispatch hook:

```papyrus
MTF_MainQuest h = _host()
int slot = h._getDispatchSlot()
int eff  = h._getDispatchEffectIdx()
int p3   = h.GetSlotEffectParam(slot, eff, 3)
int p4   = h.GetSlotEffectParam(slot, eff, 4)
```

`_getDispatchSlot()` / `_getDispatchEffectIdx()` return the
currently-dispatching (slot, effect) pair; they're only valid mid-
dispatch. Snapshot them into locals before calling any suspending
function (`ModActorValue`, `AddSpell`, etc.) — a concurrent dispatch
can interleave and clobber the context.

### Reading menu (string-id) effect params

For any `paramN` declared with a `menu`, the int `param` / `param2`
args don't carry useful data — read the id string instead:

```papyrus
MTF_MainQuest h = _host()
int slot = h._getDispatchSlot()
int eff  = h._getDispatchEffectIdx()
string p1Id = h.GetSlotEffectParamNStr(slot, eff, 1)
string p2Id = h.GetSlotEffectParamNStr(slot, eff, 2)
```

Same dispatch-context lifetime rule as the int accessors.

---

## Soft-master and lifecycle hooks

The whole point of an integration plugin is to bridge MTF onto
**another mod that may or may not be loaded**. Hard-mastering means
your plugin can't load without the target mod — usually too strict.

### `_resolveDeps()`

Override this to probe for your target mod's forms / APIs:

```papyrus
SomeQuest Property TargetQuest Auto Hidden

bool Function _resolveDeps()
    if TargetQuest != None
        return true              ; cached — cheap early-out
    endif
    TargetQuest = Game.GetFormFromFile(0xABCD, "TargetMod.esm") as SomeQuest
    return TargetQuest != None
EndFunction
```

`Game.GetFormFromFile(formId, "filename.esp")` returns `None` if:

- The file isn't loaded, OR
- The form ID doesn't exist in that file, OR
- The form exists but is the wrong type for your cast.

Cache the resolved Form in an Auto Hidden property so subsequent
`_resolveDeps` calls return immediately. Re-resolving on every
`checkCondition` is too slow.

Pick a form that's **stable across versions** of the target mod —
preferably a script Quest or a defining GlobalVariable rather than
something the mod author might re-number across updates.

**You don't need to override `_tryRegister`.** The base class's
implementation already calls `_resolveDeps`, waits if it returns
false, then calls `RegisterPlugin` and `_onRegistered`. See
`source/scripts/MTF_Plugin.psc` lines 65-81 for the exact loop.

Plugins with no soft-master (like `MTF_Plugin_Base`) leave the
default `_resolveDeps()` (returns true) alone.

### `_onRegistered()`

Override for one-shot bridge setup that needs to happen after the
host has accepted the plugin:

```papyrus
Function _onRegistered()
    _setupBridge()        ; e.g. register a SkyrimNet event schema
EndFunction
```

Fires exactly once per session, on the OnInit path. **Reload-time
setup goes elsewhere** — typically your plugin's host-alias
`OnPlayerLoadGame`. See `MTF_Plugin_SkyrimNet` for the canonical
example.

---

## The ESP

A plugin needs an ESP for two reasons:

1. To attach the script to a Quest record so Skyrim instantiates it.
2. To provide a soft-master target form ID that other tools can probe.

The ESP can be **tiny**. The MTF integration plugins are all ESL-flagged
and ~450 bytes each. Minimum layout:

- **One Quest record** — Start Game Enabled + Run Once. Attach your
  `MTF_Plugin_<name>` script as the Quest's primary script.

No spells, no perks, no NPCs, no scripts beyond the one on the Quest.
The Quest's only job is to anchor your script in the runtime so its
`OnInit` fires.

### Steps to create

1. Either open the Creation Kit and make a new ESL-flagged ESP from
   scratch, OR copy one of the existing plugin YAML mirrors under
   `spriggit/` (e.g. `spriggit/MTF_Plugin_FMR/`) to
   `spriggit/MTF_Plugin_<YourName>/`, then edit:
   - `spriggit-meta.json` → set `ModKey` to `MTF_Plugin_<YourName>.esp`
   - rename the `.yaml` under `Quests/` and edit the `EditorID`
   - VMAD entry → reference your `MTF_Plugin_<YourName>` script
2. Make sure the ESP is ESL-flagged (existing templates already are —
   FormIDs in the `FE<slot>000800-000FFF` range).
3. Build the ESP: `bash tools/build_esps.sh MTF_Plugin_<YourName>`
   (deserialises that one folder into `_build/esps/`).
4. Compile the script: `bash tools/build_scripts.sh` (deploys the
   `.pex` to MO2).
5. Ship the ESP + the `.pex` + the JSON catalog in a mod folder,
   OR add a stage step to `tools/fomod/build_fomod.sh` to bundle it
   into the framework's FOMOD installer.

---

## Common pitfalls

### `onDeactivate` is a no-op default — and the silent footgun

The base class's `onDeactivate` is empty. **If your effect mutates
persistent engine state in `onActivate` and you forget to override
`onDeactivate`, removing the tattoo silently leaves the state applied.**
No compile error, no log warning. Players will report "removing the
tattoo doesn't actually remove the buff".

Two cases where the no-op default is correct:

1. **Transient one-shot effects** (bursts, stagger, alerts, bounty
   bumps). They finish during `onActivate` and have no rolling state.
   Mark these `"kind": "burst"` so the framework knows.
2. **State that lives in another framework's storage and is meant to
   decay/expire naturally** (SLA exposure deltas, FMR ovulation
   timers). Symmetric cleanup would either be wrong (refund could
   push to negative) or impossible (no cancel API on the other side).

For everything else — `ModActorValue`, `AddSpell`, persistent shader
effects, applied magic effects — implement `onDeactivate` to revert.

### `ModActorValue` race: write StorageUtil BEFORE the suspending call

If your effect calls `target.ModActorValue(...)` or `target.AddSpell(...)`
(any Form call — these suspend the script for a frame), two activations
landing in quick succession can both read the prior state, both apply,
and double the effect.

Fix: write your "applied amount" to StorageUtil **before** the
suspending call. The second stack reads the freshly-written value and
short-circuits.

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

The framework documents this pattern internally — see
`project_papyrus_storage_before_suspend` in the project memory notes.

### Auto-property post-release attach failure

If your plugin is already shipped and in a player's save, **adding
new `Auto` (or `Auto Hidden`) properties to the script doesn't always
create backing storage on existing saves**. Writes silently no-op.

For any state added after a release, prefer StorageUtil from the
start over `Auto` properties. The base class's `_registered` flag is
the only `Auto Hidden` you can reliably add, because the framework
re-initialises it on load.

### Lowercase JSON keys

PapyrusUtil's `JsonUtil` lowercases all string keys on read. If your
JSON has mixed-case keys like `"PluginLabel"`, the reads will silently
return defaults. **Always use lowercase ASCII** for any key that
round-trips through JSON.

### Dispatch is by `cid` / `eid` — not array index

If you find yourself wanting to branch on a numeric index, you're in
the wrong era. JSON array ordering is purely cosmetic; presets
reference effects by `pluginId:itemId` strings. Always branch on
`cid` / `eid`. If you need the array index for an internal lookup,
resolve it lazily via `_host()._effectIdxFor(self, eid)`.

### Don't rename menu `id`s across versions

Saved presets store the `menu[].id` string. Renaming an existing id
silently mis-dispatches old presets. Adding new options is always
safe (no positional dependency, unlike schema v1's int values).
Reordering the menu list is also safe — the MCM dropdown reflects the
new order, and old presets keep working because they reference ids
not indices. Decommission by either hiding the option (drop the menu
entry but keep the dispatcher branch) or renaming it via a one-shot
migrator (`tools/migrate_to_string_ids.py` is the reference impl).

### No per-plugin settings sliders

The MCM's per-plugin `GetSettingCount` / `GetSettingValue` API was
removed in v0.2.1. If your plugin needs user-adjustable global knobs
(rate caps, feature toggles), expose them via JSON at a custom path
the plugin reads itself, or hook into another mod's MCM. The
framework no longer provides a Settings page hook.

### Param count caps

- Conditions: at most **2** parameters (`param` + `param2`).
- Effects: at most **5** parameters (`param1`..`param5`).

The schema rejects nothing — extra fields are silently ignored.

### Papyrus 128 array limit

If your plugin needs more than 128 conditions or effects, you'll hit
the engine's array limit silently. `Utility.CreateStringArray(160, ...)`
returns None. Plan total item count around 128 (or split into multiple
plugins).

---

## Testing

1. Compile your `.psc` + build the ESP.
2. Drop into MO2, enable, deploy.
3. Load a save (or start a new game) with the target soft-master mod
   active.
4. Open the MCM. Your `pluginlabel` should appear:
   - In the **Plugins page**, under its own header.
   - As an entry in per-slot **Condition** dropdowns (one entry per
     declared condition).
   - As an entry in per-slot **Effect** dropdowns (one entry per
     declared effect).
5. Bind a condition to a slot, save the preset, trigger the condition
   in-game. The tier should activate within ~2 s.
6. Bind an effect to the same slot. Confirm `onActivate` fires (use
   `Debug.Trace("MTF.MyPlugin: onActivate eid=" + eid)` and tail the
   Papyrus log).

### If the plugin never registers

- Check the Papyrus log
  (`Documents/My Games/Skyrim Special Edition/Logs/Script/Papyrus.0.log`)
  for compile errors or `MTF: plugin <id> registered` messages.
- Confirm the JSON path is exactly
  `Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/<pluginId>.json`
  and the filename basename matches `GetPluginId()` verbatim.
- Verify `Game.GetFormFromFile` returns non-None for both the host
  and your soft-master target — drop a
  `Debug.Notification("FMR_Storage: " + FMR_Storage)` into
  `_resolveDeps` temporarily.
- Confirm your ESP is enabled in `plugins.txt`.

### Lifecycle audit

The framework keeps a per-actor counter of how many activates vs.
deactivates each effect has seen. If your `onActivate` runs N times
and `onDeactivate` runs N-3 times, you've leaked 3 applications.
Console-callable:

```
cgf "MTF_MainQuest.DumpLifecycleAudit"
cgf "MTF_MainQuest.ResetLifecycleAudit"
```

Dumps any non-zero (= leaked) entries to the Papyrus log keyed on
`pluginId.effectId`. Burst effects are skipped automatically.

---

## Reference: existing plugins

| Plugin | Soft-master | Demonstrates |
|---|---|---|
| `MTF_Plugin_Base` | (none — ships with MTF.esp) | The complete reference catalog. 33 conditions, 36 effects, every JSON schema feature, every dispatch pattern. Read first. |
| `MTF_Plugin_FMR` | Fertility Mode (.esm) | Form-based soft-probe, faction-rank as state encoding, simple burst effect. |
| `MTF_Plugin_BFNG` | Beeing Female NG (.esm) | Quest-based soft-probe, dropdown-style condition (cycle phase), simple burst effect. |
| `MTF_Plugin_SLA` | SexLab Aroused (.esp) | Hourly tick (`onGameTime`) for exposure deltas, aura effect with radius `param2`, pre-suspend StorageUtil pattern. |
| `MTF_Plugin_SexLab` | SexLab Framework SE | Multiple conditions sharing one resolved form, dual-form cast (`SexLabFramework` + `sslActorStats` from the same FormID). |
| `MTF_Plugin_OStim` | OStim Standalone | GlobalVariable as dep probe, scene-gated effects, `Climax`/`Stall` toggle pair. |
| `MTF_Plugin_SlaveTats` | JContainers + SlaveTats | Bidirectional bridge — writes JFormDB ghost entries, JContainers version probe. Demonstrates `JFormDB` round-tripping. |
| `MTF_Plugin_SkyrimNet` | SkyrimNet | Zero conditions/effects (one-way bridge), `_onRegistered` schema setup, `OnPlayerLoadGame` re-init via host alias. |

Reading order — `MTF_Plugin_BFNG` for the basic shape, `MTF_Plugin_SLA`
for the `param2` + `onGameTime` pattern, `MTF_Plugin_SkyrimNet` for
post-register hook usage — covers every pattern you'll need.

The abstract base lives at `source/scripts/MTF_Plugin.psc`. Every
method's docstring documents the contract; that file is the
authoritative API reference.
