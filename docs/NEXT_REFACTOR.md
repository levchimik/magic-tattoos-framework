# MTF — Next Refactor Backlog

Deferred, non-urgent changes. Each entry notes WHAT, WHY, and the FILES/CODE
that must change.

---

## ✅ DONE (v0.3.3)

### SLA `arousal.lock` — collapsed to a single boolean
Dropped the Unlocked/Locked menu; the condition is now parameterless and fires
when arousal is locked. `checkCondition` returns `SLAFramework.IsActorArousalLocked(target)`
directly (API confirmed at `_deps/slaFrameWorkScr.psc:39`). Legacy presets that
stored a lock-state menu id simply ignore it.

### SLA `arousal.rate.npc` — gender targeting added
New `param3` menu `{both, female, male}` (default `both`). `onGameTime` reads it
via the race-free `_paramNStrEx(... , 3)` and gates the nearby-actor scan on
`a.GetActorBase().GetSex()` (0 = male, 1 = female; confirmed `_deps/ActorBase.psc:19`).

---

## TODO

### 1. Add a `modify.maxHealth` effect (parity with maxMagicka / maxStamina)

**What:** `mtf.base` has `modify.maxMagicka` and `modify.maxStamina` but no
maxHealth equivalent — asymmetric.

**Why:** A tattoo can buff/drain max magicka and stamina but not max health,
which is the most-wanted of the three for a survivability mark.

**Scope / files:**
- `data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.base.json`
  — add an effect `modify.maxHealth` mirroring `modify.maxStamina`:
    `param1` shift, min -500 / max 500 / step 5 / default 0. Description in the
    established voice, e.g. "Shifts the actor's maximum health by {param1} while active."
- `source/scripts/MTF_Plugin_Base.psc` — add onActivate/onDeactivate branches
    that `ModActorValue("Health", delta)` on apply and revert by `-delta` on
    deactivate. Follow the store-before-suspend pattern used by the other
    `modify.*` AV effects (write the applied delta to StorageUtil BEFORE the
    suspending ModActorValue call; revert reads + unsets it). DO NOT use
    SetActorValue — Health is current+max coupled; ModActorValue on the
    "Health" AV shifts the max correctly.

**Confidence to proceed:** ~85% — mirrors existing maxStamina code 1:1; only
open question is confirming the exact existing maxStamina apply/revert helper to
copy.

---

## Notes
- Items touching `MTF_Plugin_*.psc` require a **full game restart** (`.pex`
  cached at launch), not just a Load.
- Catalog-only changes reload on game Load.
- Keep descriptions in the established plain-modern, non-jargon, third-person
  voice (no mod/engine names; keep real terms like "ovulation"/"arousal").
