# MTF — Next Refactor Backlog

Deferred, non-urgent changes captured during description-rewrite work.
Each entry notes WHAT, WHY, and the FILES/CODE that must change. Nothing
here is started — pick up when scheduled.

---

## 1. SLA `arousal.lock` — collapse to a single toggle effect/condition

**What:** Drop the two-state menu (Unlocked / Locked) on the SLA arousal-lock
and make it a single "Locked" state. There's no point exposing "Unlocked"
as a selectable value — arousal is unlocked by default, so the only
meaningful thing to ask about is whether it IS locked.

**Why:** "the actor's arousal is Unlocked in place" is a nonsense bio line,
and a condition that fires on the default state is rarely useful.

**Scope / files:**
- `data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.sla.json`
  — `conditions[].id == "arousal.lock"`: remove the `menu` (Unlocked/Locked)
    so it becomes a parameterless boolean condition ("the actor's arousal is
    locked"). Decide whether it stays a condition only, or whether SLA should
    also expose lock/unlock **effects** (Lock Arousal / Unlock Arousal as two
    burst effects, or one toggle effect held for the mark's lifetime).
- `source/scripts/MTF_Plugin_SLA.psc` — `checkCondition` branch for
  `arousal.lock` currently compares the menu id string; switch to a plain
  "is locked" check. If adding effects, add `onActivate`/`onDeactivate`
  branches that call the SLA lock/unlock API.
- Verify the SLA API for the lock getter/setter before implementing
  (search the SLA `.psc` deps for `IsExposureLocked` / `LockActorExposure`
  or equivalent — name unverified).

**Migration note:** existing presets that stored the menu id ("locked"/
"unlocked") in the param-string slot — confirm the new boolean read path
treats a legacy "locked" string as locked and anything else as not, so old
presets don't silently break.

**Confidence to proceed:** needs API verification first (~60% until the SLA
lock function name is confirmed at file:line).

---

## 2. SLA `arousal.rate.npc` — add gender targeting (female / male / both)

**What:** Give the "NPC Arousal Rate" effect a gender filter so the aura can
raise arousal of only nearby females, only males, or both (current behavior
= everyone).

**Why:** Lets a tattoo's pheromone aura be oriented (e.g. only affects men),
which is the common roleplay request.

**Scope / files:**
- `data/.../plugins/mtf.sla.json` — `effects[].id == "arousal.rate.npc"`:
  add a new menu param (likely `param3` or repurpose an unused slot;
  current effect uses `param1` = delta, `param2` = radius). Menu:
  `{both, female, male}` default `both`. Update the description to mention
  the target gender via `{paramN}`.
- `source/scripts/MTF_Plugin_SLA.psc` — `onTick`/`onGameTime` branch for
  `arousal.rate.npc`: when scanning nearby actors, filter by
  `Actor.GetActorBase().GetSex()` (0 = male, 1 = female) against the
  selected menu id before applying the exposure delta.
- Re-check param-slot count vs. the catalog schema (max param5) and the
  MCM render path so the new menu param shows up in the slot editor.

**Confidence to proceed:** ~85% — `GetSex()` is a known vanilla API; the
only open question is which param slot to use and MCM render wiring.

---

## Notes
- Both items touch `MTF_Plugin_SLA.psc` → require a **full game restart**
  to take effect (`.pex` cached at launch), not just a Load.
- Catalog-only portions reload on game Load.
- Keep descriptions in the established plain-modern, non-jargon, third-person
  voice (no mod/engine names; keep real terms like "ovulation"/"arousal").
