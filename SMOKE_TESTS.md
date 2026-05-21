# MTF Smoke Tests

Per-preset test catalog for Magic Tattoos Framework. Each preset in the
`MTF Test Pack` MO2 mod exercises one specific code path. Run them to
verify the framework still behaves after a code change, or to repro a
specific bug.

## Quick start

1. Enable **"MTF Test Pack"** in MO2 left pane (already in modlist.txt).
2. In-game: open MCM → Magic Tattoos Framework → Conditions sub-tab.
3. Find the **"Selected preset"** dropdown in the right pane.
4. Pick a `Test: ...` entry → click **"Load selected"**.
5. Trigger the scenario per the table below.
6. Verify via **MCM → Magic Tattoos Framework → NotificationLog**.

The NotificationLog page is the source of truth — every `Debug.Notification`
toast is captured persistently. Do NOT chase pass/fail in `Papyrus.0.log`
or `MTFPulse.log`; both contain benign noise that misleads verdicts.

## Naming conventions

- `Test_<Topic>` — exercises one effect family or condition.
- `Test_<Topic>_<Variant>` — variant (e.g. `_Timed`, `_Stings_UI`).
- `Test_<PluginName>_<Surface>` — exercises one integration plugin.

In-game display names are all prefixed `Test:` so they cluster together
in the preset dropdown.

## Test catalog

### A. Base effects (no dependencies)

| Preset | What it exercises | How to trigger | Expected evidence |
|---|---|---|---|
| **Test_Modifies_Stats** | 16 stat-modifier effects (magickaRegen, carryWeight, sneak, speed, staminaRegen, attackDamage, healthRegen, maxMagicka, maxStamina, weaponSpeed, unarmedDamage, criticalChance, bowSpeed, absorbChance, reflectDamage) | Load preset | NotificationLog: tier-change to slot 1, all 16 effects fire onActivate. Visible in `player.getav` calls. |
| **Test_Modifies_Skills** | 17 skill modifiers (oneHanded, twoHanded, archery, block, heavyArmor, lightArmor, smithing, enchanting, alchemy, destruction, restoration, alteration, illusion, conjuration, speech, lockpicking, pickpocket) | Load preset | Same shape as Stats. Skill HUD bars shift. Tests AV naming inversions (Marksman, Speechcraft). |
| **Test_Resists_Toggles** | Resist family (Fire/Frost/Shock/Magic/Disease/Poison) + toggle.muffle / waterbreathing / waterWalking | Load preset, walk into water | Resist AVs shift; walk on water visibly; muffle quiets footsteps. |
| **Test_Spells_Cloaks** | spell.modifyArmor (100), spell.detectLife (100ft), spell.slowTime (60%), flameCloak/frostCloak/lightningCloak (8ft, 5dmg/s) | Load preset | DetectLife paints actors red through walls; slow-time visible; cloak applies damage to nearby enemies. |
| **Test_Bursts** | One-shot bursts: damage.magicka/stamina/health, burst.stagger, burst.blowCover, burst.bounty | Load preset | Health/Magicka/Stamina drop instantly; player staggers; cover blown if sneaking; bounty +100 in current hold. |
| **Test_Flash_Cost** | scale.magickaCost (50% = double cost) + flash.onhit (1, 300ms) | Load preset, cast a spell, get hit | Spell costs double; on hit, screen flashes for 300ms. |
| **Test_Shaders** | shader.play with 4 vanilla EffectShader FormIDs (params 0, 9, 14, 17) | Load preset | Player covered in 4 stacked shaders. |
| **Test_Shaders_Timed** | Same as Test_Shaders but with `param2 > 0` (5s timed) | Load preset | Shaders apply, fade out at 5s mark. |
| **Test_Sounds** | sound.play, 4 distinct SOUN records (params 2/5/7/10) | Load preset | 4 sound stings play simultaneously on slot enter. |
| **Test_Sounds_Timed** | Same as Test_Sounds + 5s timed cutoff | Load preset | Sounds engage, looping ones stop at 5s. |
| **Test_Sounds_Stings_Conjure** | Conjure-family stings (3s) | Load preset | Conjuration ambience plays for 3s. |
| **Test_Sounds_Stings_Roars** | Dragon/beast roar stings (5s) | Load preset | Roar plays for 5s. |
| **Test_Sounds_Stings_UI** | Inventory / UI stings (3s) | Load preset | UI click/chime stings play. |
| **Test_Sounds_Volume** | Same SOUN with volume extras at 100/50/25/10% | Load preset | Volume audibly decreases across the 4 stacked plays. |

### B. SLA — SexLab Aroused

Requires OSL Aroused or SLO Aroused NG (portable `slaFrameWorkScr`).

| Preset | What it exercises | How to trigger | Expected evidence |
|---|---|---|---|
| **Test_SLA_DaysSinceOrgasm** | `days.since.orgasm` condition (>=1 day) | Load preset, console `set TimeScale to 10000` then wait 5s, restore | Tier→1 entry in NotificationLog when 1+ in-game day has passed since last orgasm. |
| **Test_SLA_ArousalLock** | `arousal.lock` condition (locked=1) | Load preset, lock arousal via SLA's MCM or `set sla.lock=1` | Tier→1 when lock engaged. |
| **Test_SLA_ExposureRate** | `exposure.rate` condition (>=10) + `set.exposure.rate` effect | Load preset | Rate read, then set to preset value via effect. On deactivate, restored from stashed prev value. |
| **Test_SLA_TriggerOrgasm** | `trigger.orgasm` one-shot effect | Load preset | SLA registers a fresh orgasm event; days-since-orgasm counter resets to 0. |

### C. SexLab Framework

Requires SexLab Framework P+. Registry must be initialized (MCM Setup +
at least one SLAL anim pack installed).

| Preset | What it exercises | How to trigger | Expected evidence |
|---|---|---|---|
| **Test_SexLab_InScene** | `in.scene` condition | Start a SexLab scene targeting the player | Tier→1 while scene active; tier→0 after end. |
| **Test_SexLab_CumLayers** | `cum.total >= 1` condition | Load preset; cast a vanilla cum-apply through SexLab's debug | Tier→1 when ≥1 cum layer present anywhere. |
| **Test_SexLab_SkillVaginal** | `skill.vaginal >= 100` XP condition | Complete vaginal SexLab scenes until 100 XP accrued (or `set` via console) | Tier→1 when threshold crossed. |
| **Test_SexLab_AddCum** | `cum.apply` one-shot effect (3 vaginal layers) | Load preset | NotificationLog shows 3 layers added; visible if vaginal cum textures are installed. |

### D. OStim Standalone

Requires OStim Standalone (not classic OStim).

| Preset | What it exercises | How to trigger | Expected evidence |
|---|---|---|---|
| **Test_OStim_InScene** | `in.scene` condition | Start an OStim scene | Tier→1 while OActor.IsInOStim returns true. |
| **Test_OStim_Excitement** | `excitement >= 30` condition + `set.excitement` effect | Load preset, then ModifyExcitement via OStim API or naturally raise via scene | Tier→1 at threshold; effect re-sets to preset value. |
| **Test_OStim_TriggerClimax** | `trigger.climax` one-shot (bypass stall) | Load preset during an OStim scene | OActor.Climax fires; participants finish. |

### E. BFNG — Beeing Female NG

Requires the crajjjj fork of BeeingFemale NG. **Not yet installed in our
testbed** — these presets exist for when the dependency lands.

| Preset | What it exercises | How to trigger | Expected evidence |
|---|---|---|---|
| **Test_BFNG_Pregnancy** | `pregnancy >= 1` condition | Load preset, trigger pregnancy via BFNG's debug (`FWController.Pregnant(player, ...)`) | Tier→1 when pregnant. |
| **Test_BFNG_Ovulation** | `ovulation` condition + `trigger.ovulation` effect | Load preset (effect on slot 0 fires immediately, guarded against current pregnancy) | NotificationLog: ovulation triggered; tier→1 enters ovulation phase. |
| **Test_BFNG_CyclePhases** | `cycle.phase` condition with 4 tiers (Follicular/Ovulating/Luteal/Menstruating) | Advance BFNG's cycle via debug | Tier rotates through 4 phases as the BFNG state machine progresses. |

## Adding a new smoke test

1. Author the preset JSON in `F:/stuff/MagicTattoosFramework/test-pack/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/Test_<Topic>.json`.
2. Copy to `F:/Modlists/Modding Essentials/mods/MTF Test Pack/SKSE/...` (or use a deploy script — none committed yet; manual `cp -r` for now).
3. Add a row to the relevant table above with: what it exercises, how to trigger, expected NotificationLog evidence.
4. **Don't** put the preset in `overwrite/` going forward — the test-pack mod folder is canonical.

### Preset shape reference

```json
{
  "displayname": "Test: <Short name>",
  "schemaversion": 7,
  "transition": { "duration": 0.3 },
  "slot": [
    {                                                    // slot 0 = Default
      "cond":     { "pluginid": "", "param": 0, "param2": 0, "packid": "", "entryid": "" },
      "cooldown": { "min": 0, "mode": 0 },
      "effect":   [ { "key": "mtf.base:burst.stagger", "param": 0, "param2": 0 } ]
    },
    {                                                    // slot 1 = Condition 1
      "cond":     { "pluginid": "mtf.bfng:pregnancy", "param": 1, "param2": 0 },
      "cooldown": { "min": 0, "mode": 0 },
      "effect":   [ { "key": "mtf.base:sound.play", "param": 27, "param2": 5, "extras": { "volume": 100 } } ]
    }
    // ...6 more slots, all empty if unused
  ],
  "int": { "valid": 1 }
}
```

- `slot[0]` is Default — used as the always-on baseline. Effects here
  fire immediately when the preset is the active one.
- `slot[1..7]` are Condition slots evaluated in declared priority. First
  matching wins.
- An empty `pluginid` means the slot is unset and never fires. Don't leave
  empty slots between filled ones — they don't affect priority, but keeping
  them contiguous helps readability.
- `extras` are per-effect bonus parameters declared by the plugin. The
  loader auto-discovers them; just include the keys the plugin expects.

## Standing rules for smoke tests

- **Verify via NotificationLog only.** Not log files.
- **MTF Debug mode must be on** (MCM → General) for tier-change notifications
  to fire. Toggle every fresh new game — it's per-save.
- **Wait ≥10s** after changing state before checking — slow-tick eval runs
  every ~2s but tier transitions debounce.
- **NPC-side tests** require explicitly tagging an NPC as a subject first
  (MCM → Subjects → Add subject). Player-only tests don't.
