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
| **Test_Flash_Cost** | scale.magickaCost (50 = spells cost 50% of their original) + flash.onhit (1, 300ms) | Load preset, cast a spell, get hit | Spell costs cut in half; on hit, screen flashes for 300ms. |
| **Test_Shaders** | shader.play with 4 vanilla EffectShader FormIDs (params 0, 9, 14, 17) | Load preset | Player covered in 4 stacked shaders. |
| **Test_Shaders_Timed** | Same as Test_Shaders but with `param2 > 0` (5s timed) | Load preset | Shaders apply, fade out at 5s mark. |
| **Test_Sounds** | sound.play, 4 distinct SOUN records (params 2/5/7/10) | Load preset | 4 sound stings play simultaneously on slot enter. |
| **Test_Sounds_Timed** | Same as Test_Sounds + 5s timed cutoff | Load preset | Sounds engage, looping ones stop at 5s. |
| **Test_Sounds_Stings_Conjure** | Conjure-family stings (3s) | Load preset | Conjuration ambience plays for 3s. |
| **Test_Sounds_Stings_Roars** | Dragon/beast roar stings (5s) | Load preset | Roar plays for 5s. |
| **Test_Sounds_Stings_UI** | Inventory / UI stings (3s) | Load preset | UI click/chime stings play. |
| **Test_Sounds_Volume** | Same SOUN with volume extras at 100/50/25/10% | Load preset | Volume audibly decreases across the 4 stacked plays. |

### A2. Condition logic (multi-condition AND/OR)

| Preset | What it exercises | How to trigger | Expected evidence |
|---|---|---|---|
| **Test_MultiCond_AND** | Per-slot **multi-condition** logic (schema 9): one Condition slot holds two conditions combined with the **AND** operator, so the slot fires only when *both* pass. Exercises `_checkOneCond` / `_slotCondsMetLive` and preset round-trip of `op` + `count` + extra (`condx`) conditions. | Load preset. Satisfy only one of the two conditions → slot must stay inactive. Satisfy both → slot activates. | NotificationLog: tier stays at 0 (Default) while only one condition is met; tier→1 only once **both** conditions are simultaneously true. Flip an OR variant by editing `op` and the slot should fire when *either* is met. |

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

Excitement-family conditions are scene-gated in `MTF_Plugin_OStim.checkCondition`
(return false outside `IsInOStim`), and effects are scene-gated in `onActivate`
— OStim's own API already no-ops outside scenes, so no explicit scene gate
is needed inside the preset's slot conditions. (`scene.composition` with the
`any` value is the explicit in-scene gate when you do want one.)

| Preset | What it exercises | How to trigger | Expected evidence |
|---|---|---|---|
| **Test_OStim** | Excitement-ladder state machine. Slot 1 `times.climaxed>=2` → `sound.play` (highest priority — overrides everything post-2nd-climax). Slot 2 `excitement>=60` → `trigger.climax`. Slot 3 `excitement>=30` → `excitement.set 50`. Slot 4 `excitement>=10` → `excitement.mult.set 3`. | Start an OStim scene. Watch excitement rise: tier→4 at 10 (mult kicks in, excitement starts climbing 3×), tier→3 at 30 (jumps to 50), tier→2 at 60 (climax fires). After 2nd climax (typically manual via OStim UI since excitement doesn't reset post-climax), tier→1 (sfx). | NotificationLog: rapid tier sequence 4→3→2 as excitement climbs; tier stays at 2 post-climax since OStim doesn't reset excitement. Trigger a 2nd climax manually → tier→1 sfx plays. |
| **Test_OStim_Composition** | `scene.composition` ladder — one slot per composition, each with a distinct sfx. Slot 1 `solo`→`ui_level_up`, 2 `1m1f`→`ui_skill_up`, 3 `2f`→`ui_new_quest`, 4 `2m`→`ui_quest_update`, 5 `mmf`→`ui_quest_complete`, 6 `mff`→`ui_shout_learned`, 7 `4p`→`ui_perk_select`. Sex is schlong-based (futa fills the male slot). Needs OStim API 7.3.5c+. | Start OStim scenes of varying composition (use `player.placeatme` to add partners, then start a scene). | NotificationLog: tier matches the actor's current scene composition (e.g. a 1-male-1-female scene → tier 2, `ui_skill_up`); changes if the roster changes mid-scene. |

### D2. Multi-area overlays (Phase 1-3)

Requires content packs enabled in the modlist:
- `MTF Content - Community Overlays 1 Face` — `mtf.community-overlays-1-face` (`"area": "Face"`)
- `MTF Content - Bardle Nail Polish` — `mtf.bardle-nail-polish` (`"area": "Hand"`)

Tests the v0.1.17 work that lets MTF paint into NiOverride's Face / Hand /
Feet pools alongside Body.

**Feet area content note:** No dedicated feet-overlay packs were
identified in the local mod survey. The Feet routing exercises the *same
code paths* as Hand (`PulseEntry.area`, `AreaName()`, `_areaIndex()`,
`Feet [ovlN]` node format) — passing Hand tests is strong evidence Feet
routing also works. When a Feet-area content pack lands, drop it in via
the same recipe (`docs/CONTENT_PACKS.md`) and copy `Test_MultiArea_HandApply`
to `Test_MultiArea_FeetApply` with the new packid/entryid.

The presets test the player MCM-base path (load preset → it becomes the
active base; tier evaluation drives the face overlay). The Apply Tattoo
spell path is exercised by **picking any of these presets and casting Apply
Tattoo on self** — should land "applied" and paint the face entry above
the MCM-base body presets.

| Preset | What it exercises | How to trigger | Expected evidence |
|---|---|---|---|
| **Test_MultiArea_FaceApply** | Phase 1 apply path: face pack → `Face [ovlN]` nodes (not Body). MCM Face overlay-slot slider (default 0) determines the base. | Load preset, wait ≥3s. | Face overlay 01 paints onto the head (e.g. swirl on forehead/cheeks). Body untouched. NotificationLog: tier→0 entry. |
| **Test_MultiArea_HandApply** | Phase 1 apply path: hand pack → `Hand [ovlN]` nodes. Same code path as Face but separate area. Strong proxy for Feet routing (identical code paths). | Load preset, wait ≥3s, look at character's hands/nails. | Bardle "Full Dark" nail polish paints on the fingernails. Body and face untouched. NotificationLog: tier→0 entry. |
| **Test_MultiArea_FaceTier** | Phase 2 player draw path: face area participates in tier evaluation. `mtf.base:stamina.below` param=99 swaps face 01 → face 20 when stamina drops under 99%. | Load preset, sprint a few seconds (or `player.damageav stamina 30`). | Tier→0 at stamina>=99% (face 01), tier→1 at stamina<99% (face 20). Wait for stamina to fully regen → tier→0 again. Body untouched throughout. |
| **Test_MultiArea_FacePulse** | Phase 3 C++ pulse: AreaName(e.area) routes to `Face [ovlN]`, not `Body [ovlN]`. 2-layer face entry "07" with orange glow on layer 1 (emissivemult=2.0), pulse 1Hz / 80% depth. | Load preset. | Face overlay 07's secondary layer glows orange and pulses at 1 Hz. Body untouched. Save+reload → pulse resumes via post-load redraw. |
| **Test_MultiArea_FaceBody** | Area-filter correctness: body pack in slot 0, face pack on stamina<99% in slot 1. Verifies cross-area texture pollution doesn't happen. | Load preset, sprint to drop stamina under 99%, then wait for regen. | At stamina>=99% (tier=0): body LewdMarks 001 paints; face area clears (no face pack at tier 0). At stamina<99% (tier=1): face 07 paints; body area clears. Critical: face texture must NEVER appear on the body nodes, and body texture must NEVER appear on the face nodes — that's the area-filter regression test. |

**Known limitation (deferred work):** Tier is shared across areas in the
player MCM-base path. `_drawOverlayForActorAt` correctly clears the area
whose pack doesn't match the tier's resolved pack (no cross-area texture
pollution), but the consequence is that body and face can't both be
"active" simultaneously through MCM conditions — a tier=1 face entry
clears the body. To get body and face *simultaneously* visible, apply
two separate presets via the Apply Tattoo spell (one body-only, one
face-only). The Apply path's stacked presets keep their own per-(preset,
area) tier state, so a body preset at its tier 0 + a face preset at its
tier 0 (or any tier) coexist independently. Per-area condition eval on a
single MCM-base preset is a future enhancement.

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
  "schemaversion": 9,
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
- **Multi-condition slots (schema 9):** a slot's `cond` can hold more than
  one condition combined by a single operator. The primary condition stays
  in `cond` (`pluginid` / `param` / `param2`); extra conditions serialize
  alongside as `cond.condx1`, `cond.condx2`, … with `op` selecting **AND**
  (all must pass) vs **OR** (any passes) and `count` recording how many
  conditions the slot holds. A slot with no `count` reports 1 and evaluates
  exactly like a legacy single-condition slot — old presets are untouched.

## Standing rules for smoke tests

- **Verify via NotificationLog only.** Not log files.
- **MTF Debug mode must be on** (MCM → General) for tier-change notifications
  to fire. Toggle every fresh new game — it's per-save.
- **Wait ≥10s** after changing state before checking — slow-tick eval runs
  every ~2s but tier transitions debounce.
- **NPC-side tests** require explicitly tagging an NPC as a subject first
  (MCM → Subjects → Add subject). Player-only tests don't.
