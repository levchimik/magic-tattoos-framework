# MTF Refactor Roadmap

Living document of refactor opportunities, in priority order.
Updated 2026-05-24 after the JSON-catalog migration (commit `6358c3d`).

---

## ✓ Done

### JSON-driven plugin metadata (commit `6358c3d`, 5 plugins + base loader)

Lifted per-plugin metadata (id/label/description/param/menu/extras/settings)
from Papyrus `elseif` chains into JSON catalogs at
`Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/<pluginId>.json`.
Each migrated plugin script now contains only identity + dep wiring +
behaviour hooks. Base class metadata getters call JsonUtil on demand
— no caching, no new script-level vars (the bulk-var cliff bit
the first attempt; see `project_papyrus_bulk_var_add` memory).

Net Papyrus delta: **−1,307 lines** across 5 plugins (BFNG, OStim, SLA,
SexLab, SlaveTats) plus FMR (already migrated in `4c59c8b`).

---

## Pending — high value

### 1. MTF_Plugin_Base metadata → JSON

The big one. **3,903 lines**, **47 conditions**, **58 effects**, ~566
`elseif`s. Migrating Base completes the catalog pattern and would shrink
the largest file by an expected 2,000–3,000 lines.

**Why it was deferred:** simple chain parsing won't work. Base's
metadata getters use split-function helpers
(`_effectIdLow` / `_effectIdHigh` / `_effectIdVeryHigh` — the
Papyrus-VM elseif-truncation workaround) and category-dispatch helpers
(`_isAbsShift`, `_isToggle`, `_isBurstAV`, `_classMaskToTags`) that
return different ranges for different idx CATEGORIES, not specific
idxes. The first extractor attempt (deleted) attributed wrong menu
options to wrong effects and propagated `-100` from the abs-shift
fallback to non-shift effects.

**Path forward:** either
1. Write a smarter Python extractor that resolves `_isAbsShift(idx)`
   etc. to the actual idx sets they cover, then traces correctly, OR
2. Hand-curate `mtf.base.json` over a focused session reading the
   `.psc` carefully — tedious but reliable (47 + 58 = 105 entries).

Option 2 is probably faster end-to-end given how much can go wrong with
the helpers. ~3 hours of careful work.

**Once done:** delete most of Base's metadata methods (keeping only the
behaviour and the helpers `_isAbsShift`/`_avNameFor`/etc. that
`onActivate`/`onDeactivate` actually use).

### 2. Defensive `onDeactivate` audit

The base class has a long warning comment about `onDeactivate` being a
silent footgun — if you mutate persistent state in `onActivate` and
forget to balance in `onDeactivate`, the buff stays applied silently
after the tattoo is removed. MTF can't statically detect this.

**Idea:** add a debug-mode "unbalanced activates" tracker. Each
`onActivate` call increments a per-(plugin, effect) counter; each
`onDeactivate` decrements. At session end (or on demand from MCM),
dump any positive counts to the log. Plugin authors get free
verification that their lifecycle is balanced.

Cheap to implement (~50 lines on MainQuest), high value for catching
authoring bugs early. No save-state risk if implemented via StorageUtil
keyed on (pluginId, effectId).

---

## Pending — high effort / unclear value

### 3. MTF_MainQuest split (6,726 lines, 272 functions)

The kitchen sink. Natural seams visible:

- **Plugin registry & dispatch** (`RegisterPlugin`, slot-eval loop,
  effect activate/deactivate dispatch). ~1,500 lines.
- **Preset I/O** (load/save slot state to JSON). ~800 lines.
- **Per-effect helpers** (cloak tick `_cloakTickAll`, pending-cast
  queue drain, etc.). ~600 lines.
- **MCM <-> framework bridge** (slot getters/setters MCMQuest calls).
  ~1,000 lines.
- **Storage utilities + actor tracking**. ~500 lines.
- **Misc** (~2,000 lines).

**Why this is risky:** MainQuest's save-state is dense — moving vars
out of it tickles `project_papyrus_property_attach` and
`project_papyrus_bulk_var_add`. Has to be done with the same discipline
the JSON refactor needed: don't move/add script-level vars on existing
scripts unless absolutely necessary, use StorageUtil for new state, use
fresh-attached quest scripts for split-out components.

**Why this might not be worth it:** the file is grokkable section-by-
section thanks to section headers and the consistent helper-prefix
convention. The 272-function count is mostly small focused helpers, not
giant ones. Splitting introduces cross-script call overhead and adds
ESP records.

**Recommendation:** only split if a specific section becomes a hotspot
(e.g. if Preset I/O becomes its own product surface and someone needs
to embed it in another mod). Don't split for the sake of size.

### 4. MTF_MCMQuest split (4,589 lines, 78 functions, 11 elseifs)

Big render code, less risky than MainQuest because MCM doesn't hold
critical state — most of it is page-build logic.

Could split per-page:
- Slots page (the main tier/condition/effect picker UI)
- Plugins page (per-plugin settings)
- Presets page (preset save/load UI)
- Settings page (global MTF knobs)

**Why this might not be worth it:** SkyUI's MCM is structured around
one script per Mod Configuration Menu; splitting requires building a
dispatcher that re-routes events into sub-scripts. The boilerplate cost
may exceed the readability gain.

**Recommendation:** revisit only if MCM gains a major new page
(e.g. content-pack browser / authoring UI) that's natural to host on
its own script.

---

## Pending — small / opportunistic

### 5. Per-plugin opt-in catalog caching

The current base class is pure JsonUtil-on-demand. If any plugin's MCM
render becomes perceptibly slow (Base, when migrated, will be the first
to hit this — 105 entries × multiple metadata fields each), add
per-plugin local caching using the FMR-style pattern (≤15 script-level
vars, well under the bulk-var cliff).

This is an opt-in optimization — implement only when measured. Pre-
optimizing it would re-create the bulk-var-add hazard.

### 6. Content pack catalog format alignment

`content-packs/<pack>/pack.json` already uses a shared structure (used
by `MTF_MainQuest.LoadPack` etc). Worth auditing for duplicated metadata
that could be promoted to a shared loader — particularly if the layer
specs or tier defaults repeat across packs.

Not urgent; the current per-pack structure is small and readable.

### 7. xeditlib / Spriggit consistency for plugin ESPs

The integration-plugin ESPs (`MTF_Plugin_FMR.esp`, etc.) are tiny
(~400 bytes each — just the quest record). They live as Spriggit YAML
mirrors under `spriggit/` and get deserialized by `tools/build_esps.sh`.
This is fine as-is; flagging only because the ESP files themselves are
git-ignored and easy to forget.

---

## Reference: refactor-safe Papyrus discipline

Lessons baked in from this round (memory notes consulted):

- `project_papyrus_bulk_var_add` — never add >~30 script-level vars
  to an existing-in-save script; on a shared BASE class the threshold
  is lower because every derived instance counts (~270 events on a
  9-plugin base class will hard-freeze the VM).
- `project_papyrus_property_attach` — post-release `Auto Hidden`
  properties on existing scripts don't reliably backing-attach. Use
  StorageUtil for new state.
- `project_papyrus_property_array_writes` — indexed writes to remote
  script arrays through Auto properties can hit transient copies; use
  faction ranks or actor values where the other mod exposes them
  (`project_faction_as_state_probe`).
- `project_papyrus_array_none_cast_noise` — `== None` checks on Auto
  array properties log false-positive cast errors; don't gate accessors
  on them.
- `project_papyrusutil_lowercase` — JSON catalog keys MUST be all
  lowercase (PapyrusUtil lowercases on read).

When in doubt: **don't change save-state shape on an established
script**. Add new behaviour, not new fields.
