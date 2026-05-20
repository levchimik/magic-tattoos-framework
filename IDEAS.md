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
