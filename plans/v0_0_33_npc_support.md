# v0.0.33 — NPC support

Drafted at end of v0.0.32 session. Scope locked, ready to implement.

## Decisions

- **Targeting**: hotkey + crosshair (`Game.GetCurrentCrosshairRef()`).
- **Preset scope**: shared pool (any preset can be applied to player or NPC).
- **Lifecycle on death**: revert to tier 0 (default slot).
- **Effects on NPCs**: enabled from day one.
- **Tracking pattern**: Fertility-Mode-style — `StorageUtil.FormList(MainQuest, "mtf.tracked")`.
  Capacity 256. No `ReferenceAlias` collections.
- **Hotkey default**: unbound. User sets in MCM.
- **Scope**: full Phase 1-5 (track + eval + draw + effects + pulse + lifecycle + MCM).

## Architecture

### Tracking
- `StorageUtil.FormListAdd/Get/Count/Remove/Has(MainQuest, "mtf.tracked", actor)`.
- Per-actor state via `StorageUtil.Get/SetXxxValue(actor, "mtf.<field>", default)`:
  - `mtf.preset` (string) — assigned preset name
  - `mtf.tier` (int) — current tier
  - `mtf.cd.0..7` (float, gameTime) — per-slot cooldown expiry
  - `mtf.applied.<effectKey>` (float) — per-effect applied magnitude
    (replaces per-actor `_appliedMana` etc. on Plugin_Base)
  - `mtf.pulse.start` (float, realTime) — pulse phase reset point
  - `mtf.suspended` (int 0/1) — cell-detach flag
  - `mtf.killed` (int 0/1) — death flag
- Tracked metadata keyed on MainQuest: hotkey assignment, default-preset-for-new-subjects.

### Performance gating for 256 actors
1. **Distance gate** — skip actors farther than `fSubjectEvalRadius` (default 4096
   units, ~80m). Out-of-render = no eval, no draw.
2. **Round-robin stagger** — eval up to `MAX_EVALS_PER_TICK` (default 16) actors
   per slow tick. With 32 nearby actors at 2s tick that's 4s effective per actor.
3. **Suspend on cell detach** — actors in unloaded cells skipped entirely.

### Pulse on NPCs
- Roster max 8 (hardcoded; MCM-tunable later).
- Eviction: 9th pulser evicts the farthest-from-player.
- Fast tick (50ms) iterates roster, calls `_applyPulse(actor)`.
- Per-actor pulse phase via `StorageUtil.GetFloatValue(actor, "mtf.pulse.start", 0.0)`.

### Lifecycle hooks (PO3 PapyrusExtender global events)
- `OnActorKilled` — if tracked, force tier 0 + set `mtf.killed = 1`. Next eval skips conds for this actor.
- `OnCellAttach` / `OnCellDetach` — toggle `mtf.suspended`.
- Despawned actors (FormID 0 / `!Is3DLoaded` for >10 ticks) get culled.

### Effects refactor (the biggest change)
`MTF_Plugin_Base` currently stores per-effect applied state in per-quest floats
(`_appliedMana`, `_appliedCarry`, …). For multi-actor support these MUST move to
StorageUtil keyed on actor:
- `_getApplied(int idx)` → `_getApplied(int idx, Actor target)`
- `_setApplied(int idx, float v)` → `_setApplied(int idx, Actor target, float v)`
- `_recompute(int idx, Actor target, int param)` already takes the actor; rewire its
  read/write to per-actor storage.
- Cost-penalty spell: `AddSpell`/`RemoveSpell` already work per-actor. Just track
  via StorageUtil who has it currently.

### MCM "Subjects" page (new, 5th page)
- Header: hotkey display + "Default preset for new subjects" dropdown.
- Paginated tracked list (16 rows per page, "Next page" when count > 16).
- Per row: `<NPC name> — Preset: <name> — Tier: <tier>` menu option; click for
  preset change / remove submenu.
- Footer: "Clear all subjects" + counter.

### Hotkey
- `RegisterForKey(_hotkey)` on MCM hotkey set.
- `OnKeyDown`: `Game.GetCurrentCrosshairRef() as Actor` → `AddTrackedActor`.
- Edge cases: target is player (ignore), already tracked (toast),
  default preset empty (toast: "Set a default preset first").

## Implementation order (each step compiles + smoke-tests independently)

1. **Per-actor effects refactor** in `MTF_Plugin_Base.psc`. No NPC support yet;
   player still works identically. Verify drains/bursts behave on player after.
2. **Tracked list + preset cache + generalized draw** in `MTF_MainQuest.psc`.
   No MCM page; smoke-test via console:
   `cqf <MainQuestEditorID> AddTrackedActor <formid> <preset>`.
3. **MCM Subjects page + hotkey** in `MTF_MCMQuest.psc`.
4. **Lifecycle hooks** (OnActorKilled, OnCellAttach/Detach via PO3).
5. **NPC pulse roster** — extend the fast tick to iterate roster.
6. **Stagger + distance gate + culling** — performance gates last, after correctness.

## C++ rewrite question

**Recommendation: defer.** Reasoning:

- A SKSE plugin only helps the **20Hz pulse hot loop** on **many actors**.
  Pulse roster is hard-capped at 8 anyway — that's the realistic Papyrus ceiling
  for shared `fUpdateBudgetMS` (~1.2ms/frame total VM budget across all scripts).
- Everything else (tracking, condition eval at 2s, preset I/O, MCM, lifecycle)
  is Papyrus-native and won't benefit measurably from C++.
- A SKSE plugin is a substantial new artifact: CommonLibSSE-NG setup, Visual
  Studio build pipeline, runtime address library version pinning, MO2 packaging,
  and a CRASH risk on plugin failure (vs. Papyrus, where errors just log).
- If pulse-on-NPCs *does* hit a wall in real play, the right move is a focused
  SKSE plugin that does ONE thing: iterate a roster of (actor, base, rate,
  depth, pause, phase) tuples per frame and write NiOverride emissive. That's
  ~200 lines of C++ once we know exactly what it needs to do.
- Better to know the actual bottleneck from production usage than design for
  imagined ones.

So: **finish Papyrus NPC support first → playtest → measure → write a small
targeted plugin only if needed**.
