# MTF Descriptions Review (v0.1.20)

One-line human-readable descriptions for every MTF condition, effect, and
content-pack entry. Consumed by the **SkyrimNet bridge** (and any future
LLM/AI integration) via these getters:

- `MTF_Plugin.GetConditionDescription(int idx)`
- `MTF_Plugin.GetEffectDescription(int idx)`
- `MTF_MainQuest.GetEntryDescription(string packId, string entryId)`
- `MTF_MainQuest.GetPackDescription(string packId)`

All effect/condition descriptions below are already **baked into the
.psc files** (committed). Pack/entry descriptions below are **drafts** —
they live in the optional `description` field of each visuals/\*.json
entry. The runtime falls back to the short label when `description` is
empty, so you can refine these incrementally without breaking anything.

If you edit any description here, copy it into the matching source file
(per "Editing" footnote in each section) and rebuild.

---

## Plugin: mtf.base — "Base"

### Conditions (46)

| idx | id | description |
|---|---|---|
| 0 | `magicka` | Triggers when the actor's magicka is at or above the chosen percentage. |
| 1 | `magicka.below` | Triggers when the actor's magicka drops below the chosen percentage. |
| 2 | `stamina` | Triggers when the actor's stamina is at or above the chosen percentage. |
| 3 | `stamina.below` | Triggers when the actor's stamina drops below the chosen percentage. |
| 4 | `combat.in` | Triggers while the actor is in combat (engaged in active fight). |
| 5 | `combat.alerted` | Triggers when hostile NPCs within the scan radius are alerted to the actor. |
| 6 | `combat.hostile` | Triggers when at least one hostile NPC is within the scan radius. |
| 7 | `combat.hit` | Triggers stochastically when the actor takes any incoming hit. |
| 8 | `combat.hit.blunt` | Triggers stochastically when the actor is struck by a blunt weapon (mace, warhammer, unarmed). |
| 9 | `combat.hit.bladed` | Triggers stochastically when the actor is struck by a bladed weapon. |
| 10 | `combat.hit.ranged` | Triggers stochastically when the actor is hit by an arrow or bolt. |
| 11 | `combat.hit.magic.fire` | Triggers stochastically when the actor takes fire-school magic damage. |
| 12 | `combat.hit.magic.frost` | Triggers stochastically when the actor takes frost-school magic damage. |
| 13 | `combat.hit.magic.shock` | Triggers stochastically when the actor takes shock-school magic damage. |
| 14 | `health` | Triggers when the actor's health is at or above the chosen percentage. |
| 15 | `health.below` | Triggers when the actor's health drops below the chosen percentage. |
| 16 | `location.indoors` | Triggers whenever the actor is inside any interior cell. |
| 17 | `location.outdoors` | Triggers whenever the actor is in an exterior worldspace. |
| 18 | `location.playerHome` | Triggers when the actor is inside a location flagged as the player's home. |
| 19 | `location.dungeon` | Triggers when the actor is inside a dungeon-type location. |
| 20 | `location.city` | Triggers when the actor is inside a city worldspace (Whiterun, Solitude, etc.). |
| 21 | `location.town` | Triggers when the actor is inside a town-type location. |
| 22 | `location.inn` | Triggers when the actor is inside an inn or tavern. |
| 23 | `location.jail` | Triggers when the actor is held in a jail cell. |
| 24 | `weather.pleasant` | Triggers when the current weather is clear or sunny. |
| 25 | `weather.cloudy` | Triggers when the current weather is cloudy. |
| 26 | `weather.rainy` | Triggers when the current weather is rainy. |
| 27 | `weather.snowy` | Triggers when the current weather is snowy. |
| 28 | `state.sprinting` | Triggers while the actor is sprinting. |
| 29 | `state.running` | Triggers while the actor is running (not walking, not sprinting). |
| 30 | `state.weaponDrawn` | Triggers while the actor has a weapon or spell drawn. |
| 31 | `state.loversEmbrace` | Triggers while the actor has the Lover's Embrace rested bonus active. |
| 32 | `state.sneaking` | Triggers while the actor is sneaking. |
| 33 | `state.swimming` | Triggers while the actor is swimming. |
| 34 | `state.mounted` | Triggers while the actor is mounted on a horse or other steed. |
| 35 | `state.bleedingOut` | Triggers while the actor is downed and bleeding out. |
| 36 | `time.range` | Triggers between the configured start and end in-game hours (wraps midnight if end is earlier than start). |
| 37 | `faction.playerFollower` | Triggers when the actor is one of the player's current followers. |
| 38 | `magiceffect.kw.fire` | Triggers while a fire-keyword magic effect is active on the actor (burning). |
| 39 | `magiceffect.kw.frost` | Triggers while a frost-keyword magic effect is active on the actor (frozen). |
| 40 | `magiceffect.kw.shock` | Triggers while a shock-keyword magic effect is active on the actor (shocked). |
| 41 | `magiceffect.kw.invisibility` | Triggers while the actor is invisible. |
| 42 | `followers.any` | Triggers when at least one follower NPC is within the scan radius. |
| 43 | `gold.aboveThousand` | Triggers when the actor's gold is at or above the threshold (measured in thousands). |
| 44 | `worn.heavyArmor` | Triggers when the actor is wearing a heavy-armor cuirass. |
| 45 | `worn.lightArmor` | Triggers when the actor is wearing a light-armor cuirass. |

### Effects (57)

| idx | id | description |
|---|---|---|
| 0 | `modify.magickaRegen` | Shifts the actor's magicka regeneration rate by the configured amount. |
| 1 | `modify.carryWeight` | Shifts the actor's carry-weight cap by the configured amount. |
| 2 | `modify.sneak` | Shifts the actor's Sneak skill by the configured amount. |
| 3 | `damage.magicka` | Burst — damages or restores the actor's magicka pool by a percentage of its base value when the tier activates. |
| 4 | `damage.stamina` | Burst — damages or restores the actor's stamina pool by a percentage of its base value when the tier activates. |
| 5 | `modify.movementSpeed` | Shifts the actor's movement-speed multiplier (faster or slower). |
| 6 | `modify.staminaRegen` | Shifts the actor's stamina regeneration rate. |
| 7 | `modify.attackDamage` | Shifts the actor's outgoing attack damage by a percentage. |
| 8 | `burst.stagger` | Burst — staggers the actor when the tier activates. |
| 9 | `burst.blowCover` | Burst — alerts every hostile NPC within the alert radius to the actor's presence (blows stealth). |
| 10 | `scale.magickaCost` | Shifts the spell-cost multiplier across all magic schools (discount or penalty). |
| 11 | `modify.healthRegen` | Shifts the actor's health regeneration rate. |
| 12 | `modify.maxMagicka` | Shifts the actor's maximum magicka by the configured amount. |
| 13 | `modify.maxStamina` | Shifts the actor's maximum stamina by the configured amount. |
| 14 | `modify.weaponSpeed` | Shifts the actor's weapon-swing speed (faster or slower). |
| 15 | `modify.unarmedDamage` | Shifts the actor's unarmed melee damage. |
| 16 | `modify.criticalChance` | Shifts the actor's critical-strike chance. |
| 17 | `modify.bowSpeed` | Shifts the actor's bow draw and release speed. |
| 18 | `modify.resistFire` | Shifts the actor's fire resistance. |
| 19 | `modify.resistFrost` | Shifts the actor's frost resistance. |
| 20 | `modify.resistShock` | Shifts the actor's shock resistance. |
| 21 | `modify.resistMagic` | Shifts the actor's magic resistance. |
| 22 | `toggle.muffle` | Toggles silenced footsteps on the actor while active. |
| 23 | `toggle.waterbreathing` | Toggles waterbreathing on the actor while active. |
| 24 | `toggle.waterWalking` | Toggles water-walking on the actor while active. |
| 25 | `damage.health` | Burst — damages or restores the actor's health pool by a percentage of its base value when the tier activates. |
| 26 | `burst.bounty` | Burst — adjusts the actor's bounty in their current hold (positive adds bounty, negative pays it off). |
| 27 | `spell.modifyArmor` | Toggles a flat armor-rating bonus on the actor while active. |
| 28 | `spell.detectLife` | Toggles a Detect Life aura that highlights living NPCs within the configured radius while active. |
| 29 | `spell.slowTime` | Toggles a slow-time effect that drags everything around the actor to the configured percentage of normal speed while active. |
| 30 | `spell.flameCloak` | Toggles a flame cloak that burns enemies within the radius while active. |
| 31 | `spell.frostCloak` | Toggles a frost cloak that chills enemies within the radius while active. |
| 32 | `spell.lightningCloak` | Toggles a lightning cloak that shocks enemies within the radius while active. |
| 33 | `flash.onhit` | Causes the tattoo's emissive layer to briefly flash bright on every incoming hit of the configured class (any / melee / magic / etc.). |
| 34 | `modify.resistDisease` | Shifts the actor's disease resistance. |
| 35 | `modify.resistPoison` | Shifts the actor's poison resistance. |
| 36 | `modify.absorbChance` | Shifts the actor's chance to absorb incoming spells. |
| 37 | `modify.reflectDamage` | Shifts the actor's chance to reflect incoming melee damage. |
| 38 | `modify.oneHanded` | Shifts the actor's One-Handed weapon skill. |
| 39 | `modify.twoHanded` | Shifts the actor's Two-Handed weapon skill. |
| 40 | `modify.archery` | Shifts the actor's Archery (Marksman) skill. |
| 41 | `modify.block` | Shifts the actor's Block skill. |
| 42 | `modify.heavyArmor` | Shifts the actor's Heavy Armor skill. |
| 43 | `modify.lightArmor` | Shifts the actor's Light Armor skill. |
| 44 | `modify.smithing` | Shifts the actor's Smithing skill. |
| 45 | `modify.enchanting` | Shifts the actor's Enchanting skill. |
| 46 | `modify.alchemy` | Shifts the actor's Alchemy skill. |
| 47 | `modify.destruction` | Shifts the actor's Destruction magic skill. |
| 48 | `modify.restoration` | Shifts the actor's Restoration magic skill. |
| 49 | `modify.alteration` | Shifts the actor's Alteration magic skill. |
| 50 | `modify.illusion` | Shifts the actor's Illusion magic skill. |
| 51 | `modify.conjuration` | Shifts the actor's Conjuration magic skill. |
| 52 | `modify.speech` | Shifts the actor's Speech (persuasion / barter) skill. |
| 53 | `modify.lockpicking` | Shifts the actor's Lockpicking skill. |
| 54 | `modify.pickpocket` | Shifts the actor's Pickpocket skill. |
| 55 | `shader.play` | Plays a vanilla effect shader on the actor (visual-only — dragon-soul absorb, ash pile, frost cloak, etc.) while active. |
| 56 | `sound.play` | Plays a vanilla looping sound on the actor while active. |

*Editing:* `source/scripts/MTF_Plugin_Base.psc` — functions `GetConditionDescription`, `_effectDescriptionLow`, `_effectDescriptionHigh`.

---

## Plugin: mtf.sla — "SLA (SexLab Aroused)"

### Conditions (4)

| idx | id | description |
|---|---|---|
| 0 | `arousal` | Triggers when the actor's SexLab Aroused exposure reaches the threshold. |
| 1 | `days.since.orgasm` | Triggers when the actor has not orgasmed for at least the configured number of days. |
| 2 | `exposure.rate` | Triggers when the actor's exposure accrual rate is at or above the threshold. |
| 3 | `arousal.lock` | Triggers when the actor's arousal-locked flag matches the configured state (locked or unlocked). |

### Effects (5)

| idx | id | description |
|---|---|---|
| 0 | `arousal.rate` | Steadily raises the actor's own exposure by the configured amount every in-game hour while active. |
| 1 | `arousal.rate.npc` | Steadily raises the exposure of nearby NPCs within the aura radius every in-game hour (pheromone-style aura). |
| 2 | `modify.arousal` | Burst — adds the configured exposure delta to the actor's arousal pool when the tier activates. |
| 3 | `set.exposure.rate` | Sets the actor's exposure accrual rate to the configured value while active, then restores the previous value on deactivate. |
| 4 | `trigger.orgasm` | Burst — resets the actor's 'days since orgasm' counter to zero when the tier activates. |

*Editing:* `source/scripts/MTF_Plugin_SLA.psc`.

---

## Plugin: mtf.ostim — "OStim Standalone"

### Conditions (6)

| idx | id | description |
|---|---|---|
| 0 | `in.scene` | Triggers while the actor is currently in an OStim scene. |
| 1 | `excitement` | Triggers when the actor's OStim excitement is at or above the threshold (scene-only). |
| 2 | `excitement.mult` | Triggers when the actor's OStim excitement multiplier is at or above the threshold (scene-only). |
| 3 | `times.climaxed` | Triggers when the actor has climaxed at least the configured number of times in the current scene. |
| 4 | `climax.stalled` | Triggers when the actor's climax-stalled flag matches the configured state. |
| 5 | `has.schlong` | Triggers when the actor has a schlong-classified body equipped. |

### Effects (5)

| idx | id | description |
|---|---|---|
| 0 | `trigger.climax` | Burst — forces an OStim climax on the actor (optionally bypassing any active stall). |
| 1 | `excitement.modify` | Burst — adds or subtracts the configured amount from the actor's OStim excitement. |
| 2 | `excitement.set` | Burst — sets the actor's OStim excitement to an absolute value. |
| 3 | `climax.stall` | Stalls the actor's OStim climax while active; releases the stall on deactivate. |
| 4 | `excitement.mult.set` | Burst — sets the actor's OStim excitement-rise multiplier (e.g. 3 = excitement accumulates 3x faster). |

*Editing:* `source/scripts/MTF_Plugin_OStim.psc`.

---

## Plugin: mtf.sexlab — "SexLab Framework"

### Conditions (10)

| idx | id | description |
|---|---|---|
| 0 | `in.scene` | Triggers while the actor is currently in a SexLab scene. |
| 1 | `cum.total` | Triggers when the actor has at least the configured total cum-layer count applied. |
| 2 | `cum.vaginal` | Triggers when the actor has at least the configured vaginal cum-layer count applied. |
| 3 | `cum.oral` | Triggers when the actor has at least the configured oral cum-layer count applied. |
| 4 | `cum.anal` | Triggers when the actor has at least the configured anal cum-layer count applied. |
| 5 | `skill.vaginal` | Triggers when the actor's SexLab vaginal lifetime XP is at or above the threshold. |
| 6 | `skill.anal` | Triggers when the actor's SexLab anal lifetime XP is at or above the threshold. |
| 7 | `skill.oral` | Triggers when the actor's SexLab oral lifetime XP is at or above the threshold. |
| 8 | `purity` | Triggers when the actor's signed purity score (positive = pure, negative = lewd) is at or above the threshold. |
| 9 | `has.strapon` | Triggers when the actor has a strapon equipped. |

### Effects (3)

| idx | id | description |
|---|---|---|
| 0 | `cum.apply` | Burst — applies cum visual layers of the chosen type (vaginal/oral/anal) and count on the actor. |
| 1 | `cum.remove` | Burst — removes cum layers of the chosen type from the actor (or all types). |
| 2 | `skill.add.xp` | Burst — adds the configured amount of XP to one of the actor's SexLab skills (vaginal/anal/oral/foreplay). |

*Editing:* `source/scripts/MTF_Plugin_SexLab.psc`.

---

## Plugin: mtf.fmr — "Fertility Mode (v3 / Reloaded)"

### Conditions (2)

| idx | id | description |
|---|---|---|
| 0 | `pregnancy` | Triggers when the actor is pregnant and her belly stage is at or above the threshold. |
| 1 | `ovulation` | Triggers while the actor is in her ovulation window (recent ovulation, egg still alive). |

### Effects (1)

| idx | id | description |
|---|---|---|
| 0 | `trigger.ovulation` | Burst — forces the actor to begin ovulating (no effect if already pregnant). |

*Editing:* `source/scripts/MTF_Plugin_FMR.psc`.

---

## Plugin: mtf.bfng — "Beeing Female NG"

### Conditions (5)

| idx | id | description |
|---|---|---|
| 0 | `pregnancy` | Triggers when the actor is pregnant and her belly stage is at or above the threshold. |
| 1 | `ovulation` | Triggers while the actor is in her ovulating cycle phase. |
| 2 | `cycle.phase` | Triggers when the actor's cycle phase matches the chosen value (follicular / ovulating / luteal / menstruating). |
| 3 | `baby.health` | Triggers while the actor is pregnant and the baby's health is at or above the threshold. |
| 4 | `num.births` | Triggers when the actor has given birth at least the configured number of times. |

### Effects (1)

| idx | id | description |
|---|---|---|
| 0 | `trigger.ovulation` | Burst — forces the actor's cycle into the ovulating phase (no effect if already pregnant). |

*Editing:* `source/scripts/MTF_Plugin_BFNG.psc`.

---

## Plugin: mtf.slavetats — "SlaveTats Bridge"

### Conditions

None.

### Effects (1)

| idx | id | description |
|---|---|---|
| 0 | `slavetats.mirror` | Mirrors the slot's tattoo into SlaveTats's JFormDB so SlaveTats-aware mods (SLSF, etc.) can see and query the tattoo as if SlaveTats had painted it. |

*Editing:* `source/scripts/MTF_Plugin_SlaveTats.psc`.

---

## Plugin: mtf.skyrimnet — "SkyrimNet Bridge"

Bridge has no MCM-bindable conditions or effects. It's a passive listener
+ decorator. Nothing to describe per-item.

---

# Content-pack entry descriptions (drafts)

Pack JSONs gain an **optional** top-level `description` and per-entry
`description` field. Drafts below are for packs whose entries have
**meaningful labels** — packs with generic enumerated labels
(`LewdMarks` "Mark 001"–"Mark 096", `Obi Tattoos` "Tattoo 1"–"Tattoo 18",
`Community Overlays 1 Face` "Face 01"–"Face 30") are skipped because
without seeing the textures any draft would be plausible-sounding
fabrication. The runtime falls back to `<entry label>` when description
is empty, so those packs still produce readable LLM output — just less
narratively rich.

For each pack you can:
1. Edit the JSON at `content-packs/<pack>/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/<pack>.json`
2. Add `"description": "..."` next to the existing `"label"` field on
   the pack (top-level) and on individual entries.
3. Re-deploy via `bash tools/build_scripts.sh` (descriptions live in the
   pack JSON, no compile needed for content packs).

## Pack: mtf.bardle-nail-polish — "Bardle's Nail Polish" (16 entries)

**Pack description (draft):** "A set of cosmetic nail-polish overlays:
swatches, gradients, marbled finishes, and edge-of-frost variants for
fingertips and toenails."

| id | label | description (draft) |
|---|---|---|
| (see JSON) | Bubbles | Translucent bubble-pattern lacquer scattered across the nail. |
| (see JSON) | Dried Blood | A rust-red lacquer the colour of dried blood, opaque and a little ragged at the cuticle. |
| (see JSON) | Frost | A pale, frosted polish with cold blue highlights along each nail's edge. |
| (see JSON) | Full Polish (Dark) | A solid dark lacquer covering the entire nail. |
| (see JSON) | Full Polish (Light) | A solid pale lacquer covering the entire nail. |
| (see JSON) | Full Polish (Medium) | A solid mid-tone lacquer covering the entire nail. |
| (see JSON) | Gradient | A gradient polish blending from base to tip. |
| (see JSON) | Gradient (Inverted) | A gradient polish blending from tip back to base. |
| (see JSON) | Lightning | Jagged white lightning strokes etched onto a dark base lacquer. |
| (see JSON) | Marble | An ornate marbled polish with veins of contrasting colour swirling across each nail. |
| (see JSON) | Marble (Reduced) | A subtler marbled finish — restrained veining on a calm base. |
| (see JSON) | Semi-Polish (Medium) | Half-coverage polish leaving the lower nail bare. |
| (see JSON) | Semi-Polish (Slanted) | Polish applied at a slant, exposing one corner of each nail. |
| (see JSON) | Splatters | Tiny splattered drops of contrasting colour across the nail. |
| (see JSON) | No Tip | French-style polish with the very tip left unpainted. |
| (see JSON) | Tip L | French-style polish with only the left edge tipped. |

## Pack: mtf.rx-overlays — "RX' Overlays" (42 entries)

**Pack description (draft):** "A collection of full-body tattoo overlays
in a soft inked style — butterflies, dragons, fairies, stars, and other
motifs distributed across chest, arms, back, hips, thighs, and abdomen."

| id | label | description (draft) |
|---|---|---|
| (see JSON) | Abs Butterfly | A delicate butterfly inked across the lower abdomen, wings spread over the navel. |
| (see JSON) | ArmL Turtle | A small turtle motif tattooed on the left forearm. |
| (see JSON) | ArmR Fish | A pair of fish circling each other on the right forearm. |
| (see JSON) | Boob Dragons | Twin dragons coiled symmetrically across the chest. |
| (see JSON) | Butt Butterflies | Two butterflies tattooed across the buttocks. |
| (see JSON) | Butt Butterflies 2 | An alternate butterfly arrangement across the buttocks. |
| (see JSON) | Butt Cat | A stylised cat silhouette tattooed across the buttocks. |
| (see JSON) | ButtL Lips | A small pair of lips inked on the left buttock. |
| (see JSON) | ButtR Lips | A small pair of lips inked on the right buttock. |
| (see JSON) | Chest DragonFlower | A dragon entwined with a flowering vine across the chest. |
| (see JSON) | Chest DragonMoon | A dragon arcing beneath a crescent moon across the chest. |
| (see JSON) | Chest Dragons | A pair of dragons inked across the chest, facing one another. |
| (see JSON) | Chest Fairy | A winged fairy figure tattooed across the chest. |
| (see JSON) | Chest Knife | A dagger inked vertically down the centre of the chest. |
| (see JSON) | Chest Lips | A pair of lips tattooed on the chest. |
| (see JSON) | Chest MoonFlower | A flowering vine wrapping a crescent moon across the chest. |
| (see JSON) | Chest StarsLeft | A scattering of stars across the left side of the chest. |
| (see JSON) | Chest StarsRight | A scattering of stars across the right side of the chest. |
| (see JSON) | Chest Sun | A stylised sun radiating across the upper chest. |
| (see JSON) | Chest SunMoon | A sun and moon together across the chest. |
| (see JSON) | Chest Sword Flower | A sword laid against a wreath of flowers across the chest. |
| (see JSON) | ChestL Birds | Small birds in flight inked on the left side of the chest. |
| (see JSON) | ChestR Birds | Small birds in flight inked on the right side of the chest. |
| (see JSON) | ChestR Dragon | A single dragon coiled on the right side of the chest. |
| (see JSON) | Down Fairy | A fairy descending along the lower back. |
| (see JSON) | Hand Stars | A trail of small stars inked across the back of the hand. |
| (see JSON) | Magic Scar | A jagged scar-line glowing faintly with magical residue. |
| (see JSON) | Moles | A scattering of small dark moles inked across the skin. |
| (see JSON) | Neck Sword | A slender sword tattooed along the side of the neck. |
| (see JSON) | Spine ButterflySars | Butterflies and stars climbing the length of the spine. |
| (see JSON) | Spine Flower | A flowering vine running the length of the spine. |
| (see JSON) | Spine MagicBook | An open spellbook inked between the shoulder blades. |
| (see JSON) | SpineL Dragons | Dragons coiled down the left side of the spine. |
| (see JSON) | SpineR Dragons | Dragons coiled down the right side of the spine. |
| (see JSON) | ThighL Dragons | Dragons inked across the left thigh. |
| (see JSON) | ThighL Flower | A blooming flower across the left thigh. |
| (see JSON) | ThighL Stars | A scatter of stars across the left thigh. |
| (see JSON) | ThighL Virgo | The Virgo glyph inked on the left thigh. |
| (see JSON) | ThighR Dragons | Dragons inked across the right thigh. |
| (see JSON) | ThighR Flower | A blooming flower across the right thigh. |
| (see JSON) | ThighR Stars | A scatter of stars across the right thigh. |
| (see JSON) | ThingR Fairy | A small fairy figure inked on the right thigh. |

## Pack: mtf.community-overlays-1-face — "Community Overlays 1 (Face)" (20 entries)

Only the two "Extra" entries have descriptive labels.

| id | label | description (draft) |
|---|---|---|
| (see JSON) | Extra: Gemstone | A small inlaid gemstone — a marking sometimes given to mage initiates. |
| (see JSON) | Extra: Renegade | A facial scar-mark associated with outlaws and oath-breakers. |

The numbered `Face 01`–`Face 30` entries have generic labels and would need
visual reference to describe meaningfully — leave them blank for now.

## Packs with no drafts (generic labels)

These ship with `description: ""` on every entry. The decorator falls
back to `<entry label>` (e.g. *"a Mark 047 tattoo from the LewdMarks
SlaveTats set"*). Fill in `description` per-entry incrementally as you
look at the textures.

- `mtf.lewdmarks-racemenu` (96 entries: "Mark 001"–"Mark 096")
- `mtf.lewdmarks-slavetats` (96 entries: "Mark 001"–"Mark 096")
- `mtf.obi-tattoos` (18 entries: "Tattoo 1"–"Tattoo 18")
- `mtf.community-overlays-1-face` (face 01–30 — the numbered ones)

---

# How the SkyrimNet bridge uses these

When SkyrimNet renders a prompt containing
`{{mtf_active_tattoos(actorUUID)}}`, the bridge:

1. Reads `host.currentTier` (the slot index whose conditions currently
   win for the player).
2. Reads `ResolveSlotPackId(tier)` / `ResolveSlotEntryId(tier)`, then
   `GetEntryDescription(packId, entryId)` — falling back to
   `"a <entryLabel> tattoo from the <packLabel> set"` if description is
   empty.
3. For every effect bound to that slot, calls `GetEffectDescription(eIdx)`
   on the owning plugin, falling back to `GetEffectLabel(eIdx)`.
4. Joins them into:
   `"The player has <tattoo description>. Its effect: <eff1> <eff2> …"`

The same string is also pushed via
`SkyrimNetApi.RegisterShortLivedEvent("mtf_tattoo_state", …, 30000ms,
target, None)` on every `MTF_TierChanged` so NPCs get scene-context
awareness even when the prompt template doesn't explicitly call the
decorator.

Better descriptions → better NPC roleplay. Bare-minimum LLM-usable
output works today with what's baked in; richer pack-entry visuals
unlock the more atmospheric "*the dragon coiled across her chest seems
to pulse in time with her arousal*" kind of narration.
