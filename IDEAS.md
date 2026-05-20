# Future Effect Ideas

Snapshot of missing effect categories identified during the v0.1.4 naming
cleanup audit. Not committed to a roadmap — these are candidates to add when
needed. Prioritized by likely usefulness for a state-reactive-tattoo mod.

The four "Modify Disease Resist / Poison Resist / Spell Absorb / Reflect
Damage" effects were extracted from this list and implemented (idx 35-38).
Everything below is still open.

## High-impact gaps

### 1. Skill modifiers (18 AVs)
Biggest single hole. Every Skyrim skill is its own AV that responds to
ModActorValue; they slot straight into `_recomputeAbsShift`. Adding them is
~1 line per skill in the ID/label/AV ladder functions.

- `OneHanded`, `TwoHanded`, `Archery`, `Block`
- `HeavyArmor`, `LightArmor` (Sneak already covered as `scale.sneak`)
- `Smithing`, `Enchanting`, `Alchemy`
- `Destruction`, `Restoration`, `Alteration`, `Illusion`, `Conjuration`
- `Speech`, `Lockpicking`, `Pickpocket`

Suggested IDs: `modify.oneHanded`, `modify.twoHanded`, etc.

### 2. Damage Armor burst
We have `scale.armor` (multiplicative DamageResist). Missing: one-shot
"strip armor durability" effect — vanilla "Damage Armor" MGEF behavior.
Different mechanic from DamageResist shift.

### 3. Movement abilities (toggles)
- `Invisibility` toggle (vanilla Invisibility spell)
- `NightEye` toggle (vanilla Night Eye)
- `JumpingBonus` additive shift (jump height)
- Candlelight / Magelight toggle (carried light source)

### 4. On-hit elemental damage
`flash.onhit` handles the visual. Missing: companion `damage.fireOnHit` /
`damage.frostOnHit` / `damage.shockOnHit` that deal elemental damage to the
attacker. "Your tattoo bites back" mechanic — natural pairing with the
flash visual.

## Medium-impact gaps

### 5. Crowd-control bursts
Only Stagger exists.
- `burst.paralyze` (apply Paralysis to attacker or self)
- `burst.fear` (area, causes nearby actors to flee)
- `burst.calm` (area, pacifies)
- `burst.frenzy` (area, makes them attack each other)

### 6. DoT-style continuous drain effects
Cloaks tick continuously. Missing straight `drain.health` / `drain.magicka`
/ `drain.stamina` that drains while the tier is active (separate mechanic
from regen modifier — drains current value, regen modifies replenishment).

## Lower-priority gaps

### 7. Bounty management
We have `burst.bounty` (additive). No "clear bounty" or per-hold bounty
(Skyrim tracks bounty per faction).

### 8. Become Ethereal toggle
Vanilla Become Ethereal shout effect — invuln + can't attack.

### 9. Slowfall toggle
Vanilla Slow Fall effect.

## Plugin-specific gaps

### SLA (MTF_Plugin_SLA)
Current: `arousal.rate`, `arousal.rate.npc`, `modify.arousal`.

Missing:
- `trigger.orgasm` (SLA exposes `OrgasmActor` API)
- `drain.arousal` (negative-only floor — cleansing aura)

### FMR (MTF_Plugin_FMR)
Current: `trigger.ovulation` only.

Missing FMR API hooks:
- `trigger.conception`
- `modify.cyclePhase`
- `toggle.cycleSuppression`

## Implementation pattern reference

For new additive AV effects (most of the above):
1. Bump `GetEffectCount()`
2. Add entry to `_effectIdHigh` and `_effectLabelHigh`
3. Add to `_avNameForHigh` if hitting an actor value
4. Add to `_effectParamLabelHigh`
5. Extend `_isAbsShift` range (or `_isPctShift` for multiplicative)
6. Build + deploy

For engine-managed Resist*-style AVs that ignore direct `ModActorValue`,
add an Ability spell to MagicTattoosFramework.esp and extend
`_resolveResistSpell`. See `_absShiftSpell` for the pattern.

For new toggles bound to vanilla spells (Invisibility, NightEye, etc.),
follow the `_applyCloak` / `_removeCloak` pattern.

## Per-slot effect cap

- **Storage cap**: `MTF_MainQuest.MAX_EFFECTS_PER_SLOT()`. Currently
  hardcoded to 16. **Hard ceiling 16** — the Papyrus VM caps every
  array at 128 elements, and the effect arrays are sized
  `8 slots × MAX_EFFECTS_PER_SLOT`, so 8×16 = 128 exactly fills the
  cap. Pushing past it (we tried 20) silently fails every allocation
  and cascades into pluginCount-wipe / empty-dropdown chaos. To go
  higher we'd need per-slot arrays instead of one flat array, or move
  effect storage to StorageUtil. Dispatch loops, JSON serde, and
  `CompactEffectsAfter` obey this. JSON-authored presets can bind up
  to this many effects per condition slot. Bumping requires editing
  the source and rebuilding `MTF_MainQuest.psc`; `EnsureArrays`
  re-indexes existing saves `s*oldN+e → s*newN+e` on next load, no
  data loss.

  **TODO: INI-driven config.** Tried wiring `MAX_EFFECTS_PER_SLOT()`
  through a new `MTFPulse.GetConfigInt(key, default)` C++ native
  reading `Data/SKSE/Plugins/MagicTattoosFramework.ini`. The C++ side
  works (`MTFPulse::Config::Load()` resolves the INI next to the DLL
  and parses via Win32 `GetPrivateProfileIntW`; the native is
  registered on `kDataLoaded`). Papyrus side rolled back because the
  runtime arrived on a save with broken Auto-property attachment
  ("Cannot cast from None to String[]", "Cannot create an array into a
  non-array variable" errors against `effectKey`, `visualPackIds`,
  etc.). Couldn't tell whether the native call itself made it worse;
  hardcoding takes that variable out until property attachment is
  stable. `MTFPulse.GetConfigInt` stays as dead-but-callable Papyrus
  declaration + C++ binding for the next attempt.
- **MCM cap**: `MTF_MainQuest.MAX_EFFECTS_PER_SLOT_MCM()` = 4. Each
  visible row requires 6 SkyUI state blocks (`SLOT_EFFECT_<i>_TYPE`,
  `_PARAM`, `_P2`, `_EX1`, `_EX2`, `_EX3`) with hand-written event
  handlers — Papyrus state names are compile-time so this can't be
  looped. Raising the cap requires adding ~120 lines of boilerplate
  per new visible row in `MTF_MCMQuest.psc`.
- **Hidden effects** (rows beyond the MCM cap) still dispatch normally.
  The MCM conditions page surfaces a `(+N more — not editable here)`
  hint when hidden effects exist. Clearing a visible row promotes a
  hidden one into view via the compact-shift in `_acceptEffectType` →
  `CompactEffectsAfter`.

## Implementation pattern reference (continued)

When raising the MCM cap from K to K+1, add to `MTF_MCMQuest.psc`:
1. One more `_drawEffectRow` call in the `OnPageReset` chain (wrapped
   in the same progressive-disclosure gate as the others).
2. 6 new state blocks: `SLOT_EFFECT_<K+1>_{TYPE,PARAM,P2,EX1,EX2,EX3}`,
   each mirroring the K-th set with `(K)` substituted for `(K-1)`.
3. Then bump `MAX_EFFECTS_PER_SLOT_MCM()` to K+1.
