# MTF Descriptions Review

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

# Content-pack entry descriptions

Pack JSONs carry per-entry `tags` and `description` fields. Both were
**grounded by visual inspection of the actual texture** rather than
inferred from labels: every `.dds` was converted to PNG via `texconv`,
multi-layer entries composited via `mtf_vision_composite.py`, the result
overlaid on the CBBE body (or hands) diffuse for placement, and a stencil
view of the alpha-union used for design detail. The image was then
described in 1–3 sentences depending on complexity, with structured
tags for `subject`, `style`, and `placement` (no `color` — the mod
recolors at runtime).

The runtime accessor is `MTF_MainQuest.GetEntryDescription(packId, entryId)`;
empty descriptions fall back to `<entry label>` so packs without grounded
text still produce readable LLM output (just less narratively rich).

To regenerate after editing source textures or pack JSONs:
1. Re-render reference PNGs: `python tools/mtf_vision_render_by_id.py`
2. (Optional) spawn writer subagents — see commit history for the prompts
3. Aggregate patches: `python tools/mtf_vision_apply_patches.py --commit`
4. Regenerate this doc: `python tools/mtf_vision_regen_doc.py`
5. Re-deploy via `bash tools/build_scripts.sh` (content-pack JSONs are
   data, no compile needed)

## Pack: `mtf.lewdmarks-slavetats` — "LewdMarks (SlaveTats)" (96 entries)

All **96** entries grounded from visual inspection of the rendered alpha-union over the CBBE body/hands UV.

| id | label | placement | description |
|---|---|---|---|
| `001` | Mark 001 | lower abdomen above the pubic mound | A tribal fertility sigil with a solid heart at the center, framed by two curling fallopian arms that sweep outward into bulbous ovary lobes capped by small horn-like tufts. A pointed descending tail drops from the lower midline as a stylized cervix; the overall silhouette suggests a uterus enclosing the central heart. |
| `002` | Mark 002 | lower abdomen, just above the pubic mound | A small heart sits at the center, surrounded by twin upward-swept fallopian arms that flare into pointed wing tips with curled ovary terminals. From the base, a pair of slender forked cervix-tails descend symmetrically toward the pubic mound, with delicate filigree filling the negative space. The overall silhouette frames the heart in a uterus-shaped envelope of curls and points. |
| `003` | Mark 003 | lower abdomen fanning down toward the pubic mound | A downward-pointing V-shaped tribal sigil with a small heart at its center, framed by curling arms that hint at a uterus enclosing the heart. Twin upward-curling flame-like tendrils rise from the shoulders and a long tapered tail drops to a point below. The whole design fans across the lower belly and narrows toward the pubic mound. |
| `004` | Mark 004 | lower abdomen just above the pubic mound | A solid filled tribal sigil with a small heart at the center, flanked by two long horn-like arms that taper outward and end in curled tips suggesting ovaries. A tiny heart accent sits inside each curl, and a clustered spike of tails drops below the central heart toward the pubic mound. The overall silhouette suggests a uterus wrapping the heart. |
| `005` | Mark 005 | lower abdomen above the pubic mound | A wide crest with a bold central heart held between two scroll-curled ovary lobes that taper into spiked tufts at the outer tips. Below the heart, layered feathered fronds and curling tendrils cascade downward like a stylized cervix and vaginal channel, hinting at fertility anatomy without literal labeling. |
| `006` | Mark 006 | lower abdomen, just above the pubic mound | An ornate sigil built around a solid heart at its center, enclosed by a larger open heart-shaped frame of filigree linework with twin scrolling S-curls rising from the upper shoulders. A small heart accent crowns the top and another hangs as a pendant from the base, and the overall silhouette suggests a uterus cradling the central heart. Inked low and wide across the lower abdomen above the pubic mound. |
| `007` | Mark 007 | lower abdomen above the pubic mound | A large open heart drawn in thick outline sits at the center, with a smaller inner heart nested inside it. Two scrolled tendrils sweep outward from the heart's shoulders and curl back on themselves like ram-horns. Inked low and wide across the lower belly above the pubic mound. |
| `008` | Mark 008 | lower abdomen, just above the pubic mound | Two large rolled scrolls bracket the center like coiled ovaries, their inner curls echoing each other in mirror symmetry. A small crown-like cluster of tiny lobes rises along the top axis, and a pair of descending tendrils trails downward to a forked cervix point. The composition reads as a stylized uterus with no single central heart, built entirely from paired scroll motifs. |
| `009` | Mark 009 | lower abdomen, just above the pubic mound | An anatomical fertility sigil — a heart-shaped uterus holds a small round ovum at its center, orbited by three spermatozoa arranged at 120-degree intervals with curled flagella reaching back toward the uterine wall. Twin curling fallopian arms wrap outward from the uterus, and delicate filigree tracery fills the body of the sigil as it sits low and wide on the abdomen above the pubic mound. |
| `010` | Mark 010 | lower abdomen above the pubic mound | A detailed anatomical uterus rendered in dense ink, with a small heart nested inside the uterine body at the very center. Twin fallopian tubes curve outward and terminate in rounded ovary lobes on either side, while a tapered cervix and vaginal canal descend below to a fine point. The overall silhouette is unmistakably uterus-shaped, framing the central heart. |
| `011` | Mark 011 | lower abdomen, just above the pubic mound | A small heart at the center is framed by curling arms that hint at a uterus, with twin long fallopian tubes sweeping outward and ending in seed-shaped ovary lobes. Leafy fronds trail from each ovary tip and a short tapered cervix descends below the heart toward the pubic mound. Inked low and wide across the lower abdomen. |
| `012` | Mark 012 | lower abdomen, just above the pubic mound | A small heart rests at the center of an anatomically suggestive uterus body, framed by two horizontally extended fallopian arms tipped with leaf-shaped ovary pods. Tiny thorn-spikes line the upper edge of each arm, and a slender beaded cervix column drops from the base to a small terminal flourish. The whole figure spreads wide and low across the abdomen. |
| `013` | Mark 013 | lower abdomen above the pubic mound | A clear uterine silhouette rendered as tribal linework — two outer arms curl up into hooked ovary horns, and a small heart sits centered inside the fundus where a womb cavity would be. A small star punctuates the top of the heart, and feathered tendrils descend through the cervix region into a pointed vaginal tail. |
| `014` | Mark 014 | lower abdomen, just above the pubic mound | A near-medical rendering of the female reproductive system — a domed uterus sits at the center with a tiny heart marked on its body, flanked by twin fallopian tubes that arc upward and outward to round ovaries dotted with follicles. A ribbed cervical canal descends straight down from the uterus toward the pubic mound, with small ornamental curls accenting the ovary tips. |
| `015` | Mark 015 | lower abdomen, just above the pubic mound | A heart-in-heart sits at the center crowned by a small flame-like flourish, flanked by two pointed leaf-pod ovaries at either side. Symmetrical scrollwork curls outward from beneath the heart and a small tapered cervix-tail drops to a point below. The outer silhouette suggests a wide, low uterine envelope enclosing the central heart. |
| `016` | Mark 016 | lower abdomen above the pubic mound | A central heart sits above a smaller second heart, the pair stacked at the core of the sigil. Leafy arched arms sweep out to either side and terminate in small round berry-like bulbs that read as ovary lobes, with curling tails dropping below. The framing arms suggest a uterus cradling the twin hearts. |
| `017` | Mark 017 | lower abdomen, just above the pubic mound | A bold heart sits at the center with two short horn-tips rising from its lobes, flanked by sweeping bat-like wings made of layered flame-cuts. The wing tips curl inward at the bottom edges into rolled ovary terminals. There is no separate cervix-tail; the whole design reads as a heart enthroned within a winged uterine silhouette. |
| `018` | Mark 018 | lower abdomen above the pubic mound | A heart at the center contains a smaller solid heart inside it, both crowned by a short spike. Two pointed leaf-shaped arms extend outward, each carrying an eye-like void at its tip, and a thin tapered tail drops from the base. The curving arms hint at a uterus enclosing the heart. |
| `019` | Mark 019 | lower abdomen, spread wide across the hips | A central heart anchors a horizontally stretched composition, with two long pointed fallopian wings reaching far outward and terminating in small curled ovary tips. A short beaded vertical cervix accent drops below the heart to a small ornamental knot. The whole sigil spreads exceptionally wide across the lower abdomen. |
| `020` | Mark 020 | lower abdomen, just above the pubic mound | An openwork sigil with a small heart at the center, framed by curling arms that hint at a uterus and twin upswept horn-like fallopian tubes coiling outward at the shoulders. Forked scroll-tendrils descend from the base and curl back inward, with delicate flourishes filling the negative space. Sits low and wide across the lower abdomen above the pubic mound. |
| `021` | Mark 021 | lower abdomen, just above the pubic mound | A small upright faceted diamond sits at the top center above paired heart-suggestive curls, with two large mirrored rolled scrolls flaring outward to ovary terminals at either side. Inside the central pocket, two spermatozoa face each other as bulb-headed curls with sweeping flagella. The outer silhouette closes downward into a uterine envelope without an explicit cervix-tail. |
| `022` | Mark 022 | lower abdomen above the pubic mound | A small filled heart sits at the visual center, cradled by two large inward-curling scrolls that mirror each other above and below it. The outer linework sweeps wide into long pointed wing-tips on either side, framing the heart in a broad shield-like silhouette that nods at a uterine outline. |
| `023` | Mark 023 | lower abdomen above the pubic mound | A small heart at the center is framed by two horn-like arms that arc upward and outward, with curled tips suggesting ovary lobes. A slender tapered cervix-tail descends below the heart with a small inner spike. The overall silhouette of the framing arms reads as a uterus enclosing the central heart. |
| `024` | Mark 024 | lower abdomen above the pubic mound | A bold central heart anchors the design, framed by two long sweeping horn-like arms that taper to fine outward-curling points. A clustered cervix-tail drops below the heart in pointed barbs toward the pubic mound. The curving framework around the heart suggests a uterus silhouette. |
| `025` | Mark 025 | lower abdomen above the pubic mound | Two oval ovary loops sit side by side at the upper center, joined by a notched spade-shaped pendant where a cervix would hang. Spindly tendrils sweep outward from each loop into pointed tips, and a single teardrop droplet dangles beneath the central pendant. |
| `026` | Mark 026 | lower abdomen, wide across the pubic mound | A wide gothic sigil with a small heart at the center cradled inside curling fallopian arms that read as a uterus, flanked by sweeping bat-like wings tipped with small roses on slender stems. A second pendant heart hangs below the central one, and forked spiked tails drape downward and curl back inward toward the pubic mound. |
| `027` | Mark 027 | lower abdomen, just above the pubic mound | A dense baroque damask panel built from mirrored acanthus-leaf scrolls, paired bird-like silhouettes perched at the upper inner corners, and a small central crest with a quatrefoil motif. A single beaded pendant drops from the base to a teardrop terminal. There is no anatomical heart or uterus iconography; the design is pure ornamental filigree. |
| `028` | Mark 028 | lower abdomen, wide above the pubic mound | A solidly filled fertility sigil with a small heart at the center cradled inside curling arms that hint at a uterus, topped by a small ornamental crown. Twin sweeping fallopian arms curl outward into feathered scrollwork plumes, and a clustered drip of layered tendrils descends from the base toward the pubic mound. Inked low and broad across the lower abdomen. |
| `029` | Mark 029 | lower abdomen, just above the pubic mound | A bold filled heart with a smaller heart cutout at its center sits on a flat plinth, flanked by short curled flourishes that drape outward like rolled ovary tips. From beneath the plinth a long beaded dagger-shaped pendant descends to a sharp point. The outer envelope reads as a wide uterine silhouette cradling the heart. |
| `030` | Mark 030 | lower abdomen above the pubic mound | A tiny solid heart sits at the dead center, ringed by four spermatozoa — each a small bulb-head with a curled flagellum — that sweep outward and merge into long tribal arms reaching across the abdomen. The flagella curl inward toward the heart while the outer arms taper into pointed wing-tips, giving the design a radial fertility-orbit feel. |
| `031` | Mark 031 | lower abdomen above the pubic mound | A solid heart sits at the apex with a small faceted crystal dangling directly beneath it on a beaded chain, framed by two long inward-hooking ovary horns that flare into pointed claws. A descending column of stacked diamond beads and a spear-tipped tail drops through the cervix region, while feathered tribal fronds sweep out to either side. |
| `032` | Mark 032 | lower abdomen above the pubic mound | A faceted diamond-cut crystal sits at the center inside a horseshoe scroll, with a small heart perched at the top and another small heart dripping beneath it on a beaded stem. Long curling vines and leafy filigree sweep outward to either side, and a chain of tiny droplet beads hangs below the lower heart toward the pubic mound. |
| `033` | Mark 033 | lower abdomen, wide above the pubic mound | A slim swept sigil with a small heart at the center framed by curling arms that hint at a uterus, capped by a thin antenna-like spike rising from the top. Twin long fallopian wings sweep horizontally outward into needle-fine points, and a short vertical tail of beaded droplets descends below the heart toward the pubic mound. |
| `034` | Mark 034 | lower abdomen above the pubic mound | Two horned tribal heads face inward from either side toward a small central heart, their swept antler-like horns curling outward into spiked tips. Below the heart a long fanged skull-like drop hangs through the center, framed by feathered tendrils that taper into a narrow vaginal tail at the bottom. |
| `035` | Mark 035 | lower abdomen above the pubic mound | A bold heart contains a smaller hollow heart nested inside it, with a faceted diamond-shaped gem floating just above the upper notch on a short stem. Two thick inward-curling scrolls form the ovary lobes to either side, and curling tribal fronds drape below the heart into a layered cervix-tail and the overall silhouette suggests a uterus. |
| `036` | Mark 036 | lower abdomen, wide above the pubic mound | A gothic sigil with a small heart at the center cradled inside curling arms that hint at a uterus, surmounted by an upright cross capped with a small crown. Twin pointed bat-like fallopian wings sweep outward at the shoulders, and forked descending tendrils curl back inward below the heart toward the pubic mound. |
| `037` | Mark 037 | lower abdomen, wide above the pubic mound | A central heart at the core is wrapped in two concentric heart-shaped layers, with twin angular feathered wings sweeping outward from the upper shoulders. A single teardrop dangles below the base on a thin stem, and the overall silhouette suggests a uterus enclosing the layered heart at its center. |
| `038` | Mark 038 | lower abdomen, just above the pubic mound | A mirror-symmetric tribal flourish with a vertical pointed seed-shape at the dead center, flanked by paired curling brackets that fan outward. Small round dots punctuate the upper field and curled tendrils radiate outward, with small horn-tips capping the upper corners. The design reads as an abstract decorative flourish without an explicit heart at the center. |
| `039` | Mark 039 | lower abdomen above the pubic mound | A heavy uterus-shaped silhouette dominates the design, its two arms sweeping up into outward-curling horn tips with a small heart notched into the top of the fundus. The body is filled with bold tribal shapes that read as cervix, fundus and vaginal column, ending in a downward-pointed tail through the cervix region. |
| `040` | Mark 040 | lower abdomen above the pubic mound | A small heart sits at the top center above a second nested heart, flanked by two oval ovary loops that each enclose a tiny dot for an ovum. Long curling fallopian arms reach up to small accent hearts at the outer tips, and a coiled serpentine cervix-tail descends through the midline with a teardrop bead at the very bottom. |
| `041` | Mark 041 | lower abdomen above the pubic mound | A small filled heart caps the center, held between two inward-curling scroll arms that loop into ovary lobes with hooked claw tips. A pair of curling tribal hooks frame a long forked stem that drops from the cervix region into two parallel arrow-tipped darts, and the overall silhouette suggests a uterus enclosing the central heart. |
| `042` | Mark 042 | lower abdomen, just above the pubic mound | A slim faceted teardrop crystal crowns the apex above a small heart-in-heart at the center. Two large mirrored swan-curve arms sweep outward and downward, and inside the central pocket a pair of spermatozoa face the heart as bulb-headed shapes with long curled flagella tucked beneath. The outer silhouette reads as a uterine envelope framing the crystal, heart, and paired sperm. |
| `043` | Mark 043 | lower abdomen above the pubic mound | A central heart is enclosed within a rounded oval frame topped by two short upright horns, the whole crowning element reading like a horned uterus shielding the heart. Two large wing-like petals sweep down and outward from the base, ending in inward-rolled spirals. Slender tendrils curl above and beside the horned crown. |
| `044` | Mark 044 | lower abdomen, wide above the pubic mound | A large heart sits at the center framed by sweeping feathered tribal wings that curl outward and downward into pointed flares. Twin small scroll-curls coil at the lower shoulders of the heart, and the broad silhouette suggests a uterus cradling the heart at its center. Inked low and wide across the lower abdomen above the pubic mound. |
| `045` | Mark 045 | lower abdomen above the pubic mound | A small heart sits at the center with a tiny droplet-keyhole inside it, framed by curling arms that suggest a uterus. Two large jagged spike-wings sweep upward and outward to sharp barbed tips, and short tails drop below the heart. The overall silhouette is V-shaped and aggressive. |
| `046` | Mark 046 | lower abdomen above the pubic mound | A bold filled heart anchors the center, with a small diamond-shaped crown rising just above it. Symmetric ornamental scrollwork sweeps outward to either side in tight curls and leafy flourishes. A short flame-tongue tail descends below the heart toward the pubic mound. |
| `047` | Mark 047 | lower abdomen above the pubic mound | A central heart with a small inner scroll is flanked by two long curving arms that hook upward and outward to fine barbed points. A pointed tail drops sharply downward from the heart's base. The arching arms suggest a uterus framing the heart at the center. |
| `048` | Mark 048 | lower abdomen, just above the pubic mound | A single thick-bordered heart dominates the design, with two short pointed flame-cuts at the upper lobes and a layered leaf-fan flourish filling its lower hollow. There is no fallopian or ovary anatomy; the entire mark is one stylized heart shield. It sits squarely above the pubic mound. |
| `049` | Mark 049 | lower abdomen above the pubic mound | A bold central heart carries a keyhole shape cut into its lower face, framed by an inner curling scroll on either side and a small accent flourish above. Long thin tribal wings sweep horizontally outward to pointed tips far to either side, and a single teardrop hangs straight down from the bottom of the heart. |
| `050` | Mark 050 | lower abdomen above the pubic mound | A small notched heart sits centered within a larger pointed heart shell, capped by a tall trident-like spike rising from the upper notch. Curling fallopian arms sweep outward into thin pointed scroll wings, and layered fronds taper downward into a forked cervix-tail through the lower midline. |
| `051` | Mark 051 | lower abdomen, wide above the pubic mound | A gothic sigil with a small heart at the center framed by curling arms that hint at a uterus, flanked by twin bat-like fallopian wings rising from the upper shoulders and tipped with small pointed heads. A spade-shaped pendant hangs from the bottom on a thin descending stem, with forked spiked tendrils draping outward from the base toward the pubic mound. |
| `052` | Mark 052 | lower abdomen above the pubic mound | A central heart with a tiny spike-crown above is framed by two short curling arms that bulge outward into rounded ovary lobes. A double set of curled tails drops below the heart, with a small spiral terminus at the bottom. The wrapping arms suggest a uterus around the central heart. |
| `053` | Mark 053 | lower abdomen above the pubic mound | A small heart at the very center sits inside a dense ornate framework of curling tendrils and pointed flourishes. Two arched arms sweep outward and terminate in coiled ovary-like tips, while leafy fronds descend below toward the pubic mound. The full silhouette reads strongly as a uterus enclosing the heart. |
| `054` | Mark 054 | lower abdomen above the pubic mound | A small heart sits at the dead center as a stand-in ovum, ringed by several spermatozoa whose bulb-heads and curled flagella swim inward from the surrounding filigree — pairs hang above the heart and at the lower flanks, with more tucked into the outer eye-shaped ovary loops. Long curling tribal arms sweep out to either side and the overall silhouette suggests a uterus crowded with seeking sperm. |
| `055` | Mark 055 | lower abdomen, wide above the pubic mound | An ornate sigil with a small heart at the center cradled inside curling arms that hint at a uterus, surmounted by a small pointed crown spire. Twin long swept fallopian wings extend horizontally outward at the shoulders, and a clustered ribbon-tendril dripping from the base curls into a teardrop above the pubic mound. |
| `056` | Mark 056 | lower abdomen, just above the pubic mound | A small upright faceted crystal rises from the apex above a central heart that contains two facing spermatozoa as paisley-shaped curls with curled tails. Sweeping fallopian arms extend outward to rolled ovary tips, with long pointed cervix-tails draping down from the base. The composition's outer silhouette suggests a uterine envelope crowned by the crystal. |
| `057` | Mark 057 | lower abdomen, just above the pubic mound | A heart-in-heart sits at the center, flanked by long sweeping flame-wing fallopian arms that flare to pointed tips on either side. A small cross-shaped beaded cervix accent drops below the heart, with delicate radiating tendrils filling the outer edges. The overall outline reads as a wide winged uterine envelope around the heart. |
| `058` | Mark 058 | lower abdomen above the pubic mound | A bold central heart is flanked by two large bat-wings that sweep up and outward to pointed tips. A second smaller heart nests inside the main one, and layered flame-like tails drop below toward the pubic mound. The wings curl in on themselves at the heart's shoulders. |
| `059` | Mark 059 | lower abdomen, just above the pubic mound | A faceted crystal sits at the very top apex above a bold central heart, with curling tendrils arcing inward from the upper flanks toward the heart. Sprawling curling vines and feathered tendrils sweep outward into wing-tips on either side, and a coiled descending tail drops below the heart with a small bead at its terminus. |
| `060` | Mark 060 | lower abdomen above the pubic mound | A small heart at the center is crowned by a tall pointed spike that reads like a crystal or diamond rising above it, with secondary blades flaring out to either side. Mirrored crystal-spike clusters point downward below the heart, and the entire silhouette is jagged and sharply geometric. The radiating points around the central heart give a crystalline rather than purely organic feel. |
| `061` | Mark 061 | lower abdomen, spread wide above the pubic mound | A horizontal banner of full-bloom roses runs across the lower abdomen, the central rose flanked by two outward-facing rose heads and bordered by thorned vines and pointed leaves. A small teardrop pendant drops from the lower center. There is no anatomical heart or uterus iconography in this design. |
| `062` | Mark 062 | lower abdomen above the pubic mound | A highly literal anatomical uterus rendered in dense ink, with the uterine body, twin fallopian tubes, and rounded ovaries clearly drawn at the top. A small vertical detail marks the cervix inside the body, and the vaginal canal descends below into a bulbous terminus. The whole silhouette is unmistakably a uterus — no heart appears at the center. |
| `063` | Mark 063 | lower abdomen above the pubic mound | A clean anatomical uterus is rendered as bold outline, its two fallopian arms curling up and outward into rounded ovary bulbs. A small heart is set into the upper fundus as the womb's inner marker, with a narrow cervix and a long tapered vaginal column extending downward to a pointed tip. |
| `064` | Mark 064 | lower abdomen, just above the pubic mound | The whole outer silhouette is a heart-shaped uterus, with a small downward-pointing faceted diamond marking the cervix at its lowest tip. At the upper shoulders, paired paisley curls read as spermatozoa with bulb-heads and tucked flagella facing inward. Two leaf-shaped ovary pods perch at the very top corners. |
| `065` | Mark 065 | lower abdomen, just above the pubic mound | A wide uterine silhouette holds three stacked wavy lines at its core suggesting fluid or amnion, with curling fallopian arms scrolling outward and back to rolled ovary terminals. A small bow-and-tassel ornament hangs from the base where the cervix would be. There is no explicit central heart in this design. |
| `066` | Mark 066 | lower abdomen above the pubic mound | A stylized muscular humanoid stands at the center with arms raised and curled outward in twin sweeping loops that double as the fallopian arms of a uterus. A small heart marker sits on the chest of the figure, and the torso tapers into a column of legs that reads as the cervix and vaginal channel — the overall silhouette suggests a uterus built from a human form. |
| `067` | Mark 067 | lower abdomen, wide above the pubic mound | A central heart is topped by two upward-pointing horn-like spikes and framed by sweeping tribal wings that curl outward from the lower shoulders. A small pointed heart-pendant descends below the main heart and the overall silhouette suggests a uterus cradling the heart at its center. Sits low and wide across the lower abdomen. |
| `068` | Mark 068 | lower abdomen above the pubic mound | A large pointed heart dominates the center, topped by a faceted diamond-shaped gem and crowned by two outward-curling horn tips that rise above the fundus like demon brows. Flame-shaped fronds and curling tendrils splay outward from the heart on both sides, and a small inner flourish nests where a cervix-mark would sit. |
| `069` | Mark 069 | lower abdomen, wide above the pubic mound | A wide tribal sigil with a small heart at the center cradled inside curling arms that hint at a uterus, with two upturned horn-spikes rising from the top and twin pointed ovary curls forming eye-like slits at the shoulders. A short pointed cervix-tail descends from the base and the overall silhouette evokes a horned skull or bull mask above the pubic mound. |
| `070` | Mark 070 | lower abdomen above the pubic mound | Two heart shapes nest stacked inside the upper fundus of a clear tribal uterus silhouette, with a tall pronged crown rising above the top notch. Each fallopian arm sweeps outward into an ovary lobe containing a small accent heart, and a feathered tail descends from the cervix between two flanking spike-tendrils. |
| `071` | Mark 071 | lower abdomen, just above the pubic mound | A central heart is surrounded by radiating spiked rays and flanked by small upright faceted diamond accents at the upper corners and apex, with a larger diamond hanging directly below the heart at the cervix point. Tapered flame-blade curls drop from the lower edges. The radiant geometry frames the heart like a crowned medallion. |
| `072` | Mark 072 | lower abdomen above the pubic mound | A circular medallion sits at the center crowned by a small leafy tuft on top, with a stylized heart-and-scroll motif filling its inner disc. Two long horizontal blade-wings sweep outward from the medallion's flanks into sharp pointed tips, giving the design the look of a winged faction crest or guild insignia rather than the anatomical motifs of the surrounding set. |
| `073` | Mark 073 | lower abdomen, centered above the pubic mound | An occult alchemical sigil — a dot-in-circle-in-circle motif at the top crowned by a small upward curl, joined to a horizontal cross-bar whose ends are open (non-closed) circles each containing a central dot. Below the cross-bar, twin sinuous lines coil into a tight braid down the vertical axis, ending in small curled terminals over the pubic mound. |
| `074` | Mark 074 | lower abdomen, wide above the pubic mound | An ornamental crown of swept tribal scrollwork arcs horizontally across the top, with two upturned spike-curls at each outer tip. A small heart hangs at the center below the crown on a slender stem, descending into a tapered diamond-tipped pendant tail that drops toward the pubic mound. |
| `075` | Mark 075 | lower abdomen above the pubic mound | A detailed anatomical uterus framed in ornate tribal ink, with a small heart nested inside the uterine cavity at the very center. Twin fallopian tubes curve outward to leaf-shaped ovaries on either side, and a descending vagina with vertical inner detail drops below. The overall silhouette is unmistakably uterus-shaped, cradling the central heart. |
| `076` | Mark 076 | lower abdomen, just above the pubic mound | A small heart sits at the very top of the design, directly above a vertical pointed teardrop pendant at the center. Two large curling tendrils sweep outward from beside the teardrop like decorative wings, and additional pointed barbs flare to either side as the device settles low and wide on the abdomen above the pubic mound. |
| `077` | Mark 077 | lower abdomen, narrowing toward the pubic mound | A small heart with twin upturned horns at its top sits between two short pointed bat-wing fallopian arms. From beneath the heart a long slim leaf-blade pendant descends to a sharp point, flanked by curled inner brackets. The narrow vertical composition fans down toward the pubic mound. |
| `078` | Mark 078 | lower abdomen, just above the pubic mound | A small upright faceted crystal rises from the apex above a bold central heart, with the whole outer silhouette forming a clear heart-shaped uterus around it. Curling arms flank the heart and sweep down into flame-blade tails that taper toward the pubic mound. The design closes without a separate cervix-tail. |
| `079` | Mark 079 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized wind emblem — flowing curled tendrils sweep outward like gathered breeze, with a small heart at the apex. The whole device sits wide and low across the abdomen above the pubic mound. |
| `080` | Mark 080 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized lightning emblem — three spiraling current-curls arranged around a central pivot, with pointed horn-tips at the upper corners. A narrow forked tail descends from the bottom toward the pubic mound. |
| `081` | Mark 081 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized fire emblem — an upright flame at the center flanked by curled ram-horn flourishes scrolling outward. Pointed beak-tips extend at the outer edges, sitting wide and low across the abdomen above the pubic mound. |
| `082` | Mark 082 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized ice emblem — a six-pointed snowflake at the center framed by sharp angular shards radiating outward to crystalline points. The whole device sits wide and low across the abdomen above the pubic mound. |
| `083` | Mark 083 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized earth emblem — a square geometric labyrinth of interlocking right-angle paths at the center, with twin pointed beak-tips at the outer edges. The whole device sits wide and low across the abdomen above the pubic mound. |
| `084` | Mark 084 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized nature emblem — a smaller nested heart at the center surrounded by curling leaves and floral scrollwork sprouting outward to either side. The whole device sits wide and low across the abdomen above the pubic mound. |
| `085` | Mark 085 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized water emblem — a swirling teardrop motif at the center with curling currents radiating outward. Leafy butterfly-wing flourishes sweep outward at either side, sitting wide and low across the abdomen above the pubic mound. |
| `086` | Mark 086 | wide across the lower abdomen above the pubic mound | A wide banner-style design with a central heart containing a smaller inner heart, crowned by a short diamond spike. Two webbed bat-wings sweep outward from beneath the heart, flanked by leafy tendrils and small bulb accents. The full silhouette spans broadly across the lower belly. |
| `087` | Mark 087 | wide across the lower abdomen above the pubic mound | A wide banner-style heart at the center is topped by two short upright horns with curling inner spirals, suggesting a horned uterus crowning the heart. Symmetric scrollwork fans out to either side in tight curls and pointed flourishes, with a slender beaded tail descending below the heart. The whole motif spreads broadly across the lower belly. |
| `088` | Mark 088 | vertical strip down the lower abdomen | A long vertical serpent-staff sigil — a teardrop sits at the very top above a spiral-eye that loops into the head of a single serpent. The serpent winds tightly down a straight vertical staff in a series of stacked coils, ending in a small curled tail just above the pubic mound. |
| `089` | Mark 089 | lower abdomen above the pubic mound | A bold heart sits at the center inside a curled scrollwork frame, flanked by two outward-flaring bat-style wings whose membranes are notched into pointed claw-tips. A narrow tribal tail with a small accent heart and feathered tendrils drops below the central heart through the cervix region. |
| `090` | Mark 090 | lower abdomen, just above the pubic mound | A hollow line-drawn heart sits at the center, framed by two outward-curling fallopian arms that scroll into leaf-shaped ovary pods at their tips. A small flame and a single teardrop pendant hang directly below the heart at the cervix point. The overall outline forms a wide uterine envelope around the open heart. |
| `091` | Mark 091 | lower abdomen, just above the pubic mound | A solid cat head with pointed ears, slit-cutout eyes, a small triangular nose and whisker-mouth fills the center, flanked by a four-toed paw print on each side. The design contains no anatomical or fertility iconography; it is simply a feline crest with paws. It sits low and centered above the pubic mound. |
| `092` | Mark 092 | lower abdomen, wide above the pubic mound | A gothic sigil with a small heart at the center cradled inside curling arms that hint at a uterus, crowned at the top by a small upright diamond crystal flanked by two pointed spikes. Twin scalloped bat-like fallopian wings sweep outward at the shoulders, and a short beaded vertical tail descends from the base toward the pubic mound. |
| `093` | Mark 093 | lower abdomen, wide above the pubic mound | A central heart is topped by two upturned devil horns and flanked by sweeping bat-like wings that arc broadly outward from the shoulders. A thin infinity loop dangles below the heart and tapers into an arrow-tipped tail that points downward toward the pubic mound. |
| `094` | Mark 094 | lower abdomen, just above the pubic mound | A small heart with twin upturned horns sits between two long pointed bat-wing fallopian arms that sweep outward and downward. Below the heart a slender ornamental cross descends as the cervix pendant, with curled inner brackets framing it. The outer envelope spreads wide across the lower belly. |
| `095` | Mark 095 | lower abdomen, wide above the pubic mound | A stylized uterine glyph — twin angular fallopian arms sweep outward from a domed body, with a single lidded eye staring forward from the center of the uterus. A downward-pointing dagger-shape descends from the cervix toward the pubic mound, and small hook-curls accent the ovary tips at each shoulder. |
| `096` | Mark 096 | lower abdomen, wide above the pubic mound | An ornamental sigil with a small heart at the center cradled inside curling arms that hint at a uterus, crowned at the top by an upright diamond crystal flanked by two slim outward-leaning spear-spikes. Twin sweeping fallopian wings curl outward from the shoulders, and a tapered tail of layered curls descends from the base toward the pubic mound. |

## Pack: `mtf.lewdmarks-racemenu` — "LewdMarks (RaceMenu Overlays)" (96 entries)

All **96** entries grounded from visual inspection of the rendered alpha-union over the CBBE body/hands UV.

| id | label | placement | description |
|---|---|---|---|
| `001` | Mark 001 | lower abdomen above the pubic mound | A tribal fertility sigil with a solid heart at the center, framed by two curling fallopian arms that sweep outward into bulbous ovary lobes capped by small horn-like tufts. A pointed descending tail drops from the lower midline as a stylized cervix; the overall silhouette suggests a uterus enclosing the central heart. |
| `002` | Mark 002 | lower abdomen, just above the pubic mound | A small heart sits at the center, surrounded by twin upward-swept fallopian arms that flare into pointed wing tips with curled ovary terminals. From the base, a pair of slender forked cervix-tails descend symmetrically toward the pubic mound, with delicate filigree filling the negative space. The overall silhouette frames the heart in a uterus-shaped envelope of curls and points. |
| `003` | Mark 003 | lower abdomen fanning down toward the pubic mound | A downward-pointing V-shaped tribal sigil with a small heart at its center, framed by curling arms that hint at a uterus enclosing the heart. Twin upward-curling flame-like tendrils rise from the shoulders and a long tapered tail drops to a point below. The whole design fans across the lower belly and narrows toward the pubic mound. |
| `004` | Mark 004 | lower abdomen just above the pubic mound | A solid filled tribal sigil with a small heart at the center, flanked by two long horn-like arms that taper outward and end in curled tips suggesting ovaries. A tiny heart accent sits inside each curl, and a clustered spike of tails drops below the central heart toward the pubic mound. The overall silhouette suggests a uterus wrapping the heart. |
| `005` | Mark 005 | lower abdomen above the pubic mound | A wide crest with a bold central heart held between two scroll-curled ovary lobes that taper into spiked tufts at the outer tips. Below the heart, layered feathered fronds and curling tendrils cascade downward like a stylized cervix and vaginal channel, hinting at fertility anatomy without literal labeling. |
| `006` | Mark 006 | lower abdomen, just above the pubic mound | An ornate sigil built around a solid heart at its center, enclosed by a larger open heart-shaped frame of filigree linework with twin scrolling S-curls rising from the upper shoulders. A small heart accent crowns the top and another hangs as a pendant from the base, and the overall silhouette suggests a uterus cradling the central heart. Inked low and wide across the lower abdomen above the pubic mound. |
| `007` | Mark 007 | lower abdomen above the pubic mound | A large open heart drawn in thick outline sits at the center, with a smaller inner heart nested inside it. Two scrolled tendrils sweep outward from the heart's shoulders and curl back on themselves like ram-horns. Inked low and wide across the lower belly above the pubic mound. |
| `008` | Mark 008 | lower abdomen, just above the pubic mound | Two large rolled scrolls bracket the center like coiled ovaries, their inner curls echoing each other in mirror symmetry. A small crown-like cluster of tiny lobes rises along the top axis, and a pair of descending tendrils trails downward to a forked cervix point. The composition reads as a stylized uterus with no single central heart, built entirely from paired scroll motifs. |
| `009` | Mark 009 | lower abdomen, just above the pubic mound | An anatomical fertility sigil — a heart-shaped uterus holds a small round ovum at its center, orbited by three spermatozoa arranged at 120-degree intervals with curled flagella reaching back toward the uterine wall. Twin curling fallopian arms wrap outward from the uterus, and delicate filigree tracery fills the body of the sigil as it sits low and wide on the abdomen above the pubic mound. |
| `010` | Mark 010 | lower abdomen above the pubic mound | A detailed anatomical uterus rendered in dense ink, with a small heart nested inside the uterine body at the very center. Twin fallopian tubes curve outward and terminate in rounded ovary lobes on either side, while a tapered cervix and vaginal canal descend below to a fine point. The overall silhouette is unmistakably uterus-shaped, framing the central heart. |
| `011` | Mark 011 | lower abdomen, just above the pubic mound | A small heart at the center is framed by curling arms that hint at a uterus, with twin long fallopian tubes sweeping outward and ending in seed-shaped ovary lobes. Leafy fronds trail from each ovary tip and a short tapered cervix descends below the heart toward the pubic mound. Inked low and wide across the lower abdomen. |
| `012` | Mark 012 | lower abdomen, just above the pubic mound | A small heart rests at the center of an anatomically suggestive uterus body, framed by two horizontally extended fallopian arms tipped with leaf-shaped ovary pods. Tiny thorn-spikes line the upper edge of each arm, and a slender beaded cervix column drops from the base to a small terminal flourish. The whole figure spreads wide and low across the abdomen. |
| `013` | Mark 013 | lower abdomen above the pubic mound | A clear uterine silhouette rendered as tribal linework — two outer arms curl up into hooked ovary horns, and a small heart sits centered inside the fundus where a womb cavity would be. A small star punctuates the top of the heart, and feathered tendrils descend through the cervix region into a pointed vaginal tail. |
| `014` | Mark 014 | lower abdomen, just above the pubic mound | A near-medical rendering of the female reproductive system — a domed uterus sits at the center with a tiny heart marked on its body, flanked by twin fallopian tubes that arc upward and outward to round ovaries dotted with follicles. A ribbed cervical canal descends straight down from the uterus toward the pubic mound, with small ornamental curls accenting the ovary tips. |
| `015` | Mark 015 | lower abdomen, just above the pubic mound | A heart-in-heart sits at the center crowned by a small flame-like flourish, flanked by two pointed leaf-pod ovaries at either side. Symmetrical scrollwork curls outward from beneath the heart and a small tapered cervix-tail drops to a point below. The outer silhouette suggests a wide, low uterine envelope enclosing the central heart. |
| `016` | Mark 016 | lower abdomen above the pubic mound | A central heart sits above a smaller second heart, the pair stacked at the core of the sigil. Leafy arched arms sweep out to either side and terminate in small round berry-like bulbs that read as ovary lobes, with curling tails dropping below. The framing arms suggest a uterus cradling the twin hearts. |
| `017` | Mark 017 | lower abdomen, just above the pubic mound | A bold heart sits at the center with two short horn-tips rising from its lobes, flanked by sweeping bat-like wings made of layered flame-cuts. The wing tips curl inward at the bottom edges into rolled ovary terminals. There is no separate cervix-tail; the whole design reads as a heart enthroned within a winged uterine silhouette. |
| `018` | Mark 018 | lower abdomen above the pubic mound | A heart at the center contains a smaller solid heart inside it, both crowned by a short spike. Two pointed leaf-shaped arms extend outward, each carrying an eye-like void at its tip, and a thin tapered tail drops from the base. The curving arms hint at a uterus enclosing the heart. |
| `019` | Mark 019 | lower abdomen, spread wide across the hips | A central heart anchors a horizontally stretched composition, with two long pointed fallopian wings reaching far outward and terminating in small curled ovary tips. A short beaded vertical cervix accent drops below the heart to a small ornamental knot. The whole sigil spreads exceptionally wide across the lower abdomen. |
| `020` | Mark 020 | lower abdomen, just above the pubic mound | An openwork sigil with a small heart at the center, framed by curling arms that hint at a uterus and twin upswept horn-like fallopian tubes coiling outward at the shoulders. Forked scroll-tendrils descend from the base and curl back inward, with delicate flourishes filling the negative space. Sits low and wide across the lower abdomen above the pubic mound. |
| `021` | Mark 021 | lower abdomen, just above the pubic mound | A small upright faceted diamond sits at the top center above paired heart-suggestive curls, with two large mirrored rolled scrolls flaring outward to ovary terminals at either side. Inside the central pocket, two spermatozoa face each other as bulb-headed curls with sweeping flagella. The outer silhouette closes downward into a uterine envelope without an explicit cervix-tail. |
| `022` | Mark 022 | lower abdomen above the pubic mound | A small filled heart sits at the visual center, cradled by two large inward-curling scrolls that mirror each other above and below it. The outer linework sweeps wide into long pointed wing-tips on either side, framing the heart in a broad shield-like silhouette that nods at a uterine outline. |
| `023` | Mark 023 | lower abdomen above the pubic mound | A small heart at the center is framed by two horn-like arms that arc upward and outward, with curled tips suggesting ovary lobes. A slender tapered cervix-tail descends below the heart with a small inner spike. The overall silhouette of the framing arms reads as a uterus enclosing the central heart. |
| `024` | Mark 024 | lower abdomen above the pubic mound | A bold central heart anchors the design, framed by two long sweeping horn-like arms that taper to fine outward-curling points. A clustered cervix-tail drops below the heart in pointed barbs toward the pubic mound. The curving framework around the heart suggests a uterus silhouette. |
| `025` | Mark 025 | lower abdomen above the pubic mound | Two oval ovary loops sit side by side at the upper center, joined by a notched spade-shaped pendant where a cervix would hang. Spindly tendrils sweep outward from each loop into pointed tips, and a single teardrop droplet dangles beneath the central pendant. |
| `026` | Mark 026 | lower abdomen, wide across the pubic mound | A wide gothic sigil with a small heart at the center cradled inside curling fallopian arms that read as a uterus, flanked by sweeping bat-like wings tipped with small roses on slender stems. A second pendant heart hangs below the central one, and forked spiked tails drape downward and curl back inward toward the pubic mound. |
| `027` | Mark 027 | lower abdomen, just above the pubic mound | A dense baroque damask panel built from mirrored acanthus-leaf scrolls, paired bird-like silhouettes perched at the upper inner corners, and a small central crest with a quatrefoil motif. A single beaded pendant drops from the base to a teardrop terminal. There is no anatomical heart or uterus iconography; the design is pure ornamental filigree. |
| `028` | Mark 028 | lower abdomen, wide above the pubic mound | A solidly filled fertility sigil with a small heart at the center cradled inside curling arms that hint at a uterus, topped by a small ornamental crown. Twin sweeping fallopian arms curl outward into feathered scrollwork plumes, and a clustered drip of layered tendrils descends from the base toward the pubic mound. Inked low and broad across the lower abdomen. |
| `029` | Mark 029 | lower abdomen, just above the pubic mound | A bold filled heart with a smaller heart cutout at its center sits on a flat plinth, flanked by short curled flourishes that drape outward like rolled ovary tips. From beneath the plinth a long beaded dagger-shaped pendant descends to a sharp point. The outer envelope reads as a wide uterine silhouette cradling the heart. |
| `030` | Mark 030 | lower abdomen above the pubic mound | A tiny solid heart sits at the dead center, ringed by four spermatozoa — each a small bulb-head with a curled flagellum — that sweep outward and merge into long tribal arms reaching across the abdomen. The flagella curl inward toward the heart while the outer arms taper into pointed wing-tips, giving the design a radial fertility-orbit feel. |
| `031` | Mark 031 | lower abdomen above the pubic mound | A solid heart sits at the apex with a small faceted crystal dangling directly beneath it on a beaded chain, framed by two long inward-hooking ovary horns that flare into pointed claws. A descending column of stacked diamond beads and a spear-tipped tail drops through the cervix region, while feathered tribal fronds sweep out to either side. |
| `032` | Mark 032 | lower abdomen above the pubic mound | A faceted diamond-cut crystal sits at the center inside a horseshoe scroll, with a small heart perched at the top and another small heart dripping beneath it on a beaded stem. Long curling vines and leafy filigree sweep outward to either side, and a chain of tiny droplet beads hangs below the lower heart toward the pubic mound. |
| `033` | Mark 033 | lower abdomen, wide above the pubic mound | A slim swept sigil with a small heart at the center framed by curling arms that hint at a uterus, capped by a thin antenna-like spike rising from the top. Twin long fallopian wings sweep horizontally outward into needle-fine points, and a short vertical tail of beaded droplets descends below the heart toward the pubic mound. |
| `034` | Mark 034 | lower abdomen above the pubic mound | Two horned tribal heads face inward from either side toward a small central heart, their swept antler-like horns curling outward into spiked tips. Below the heart a long fanged skull-like drop hangs through the center, framed by feathered tendrils that taper into a narrow vaginal tail at the bottom. |
| `035` | Mark 035 | lower abdomen above the pubic mound | A bold heart contains a smaller hollow heart nested inside it, with a faceted diamond-shaped gem floating just above the upper notch on a short stem. Two thick inward-curling scrolls form the ovary lobes to either side, and curling tribal fronds drape below the heart into a layered cervix-tail and the overall silhouette suggests a uterus. |
| `036` | Mark 036 | lower abdomen, wide above the pubic mound | A gothic sigil with a small heart at the center cradled inside curling arms that hint at a uterus, surmounted by an upright cross capped with a small crown. Twin pointed bat-like fallopian wings sweep outward at the shoulders, and forked descending tendrils curl back inward below the heart toward the pubic mound. |
| `037` | Mark 037 | lower abdomen, wide above the pubic mound | A central heart at the core is wrapped in two concentric heart-shaped layers, with twin angular feathered wings sweeping outward from the upper shoulders. A single teardrop dangles below the base on a thin stem, and the overall silhouette suggests a uterus enclosing the layered heart at its center. |
| `038` | Mark 038 | lower abdomen, just above the pubic mound | A mirror-symmetric tribal flourish with a vertical pointed seed-shape at the dead center, flanked by paired curling brackets that fan outward. Small round dots punctuate the upper field and curled tendrils radiate outward, with small horn-tips capping the upper corners. The design reads as an abstract decorative flourish without an explicit heart at the center. |
| `039` | Mark 039 | lower abdomen above the pubic mound | A heavy uterus-shaped silhouette dominates the design, its two arms sweeping up into outward-curling horn tips with a small heart notched into the top of the fundus. The body is filled with bold tribal shapes that read as cervix, fundus and vaginal column, ending in a downward-pointed tail through the cervix region. |
| `040` | Mark 040 | lower abdomen above the pubic mound | A small heart sits at the top center above a second nested heart, flanked by two oval ovary loops that each enclose a tiny dot for an ovum. Long curling fallopian arms reach up to small accent hearts at the outer tips, and a coiled serpentine cervix-tail descends through the midline with a teardrop bead at the very bottom. |
| `041` | Mark 041 | lower abdomen above the pubic mound | A small filled heart caps the center, held between two inward-curling scroll arms that loop into ovary lobes with hooked claw tips. A pair of curling tribal hooks frame a long forked stem that drops from the cervix region into two parallel arrow-tipped darts, and the overall silhouette suggests a uterus enclosing the central heart. |
| `042` | Mark 042 | lower abdomen, just above the pubic mound | A slim faceted teardrop crystal crowns the apex above a small heart-in-heart at the center. Two large mirrored swan-curve arms sweep outward and downward, and inside the central pocket a pair of spermatozoa face the heart as bulb-headed shapes with long curled flagella tucked beneath. The outer silhouette reads as a uterine envelope framing the crystal, heart, and paired sperm. |
| `043` | Mark 043 | lower abdomen above the pubic mound | A central heart is enclosed within a rounded oval frame topped by two short upright horns, the whole crowning element reading like a horned uterus shielding the heart. Two large wing-like petals sweep down and outward from the base, ending in inward-rolled spirals. Slender tendrils curl above and beside the horned crown. |
| `044` | Mark 044 | lower abdomen, wide above the pubic mound | A large heart sits at the center framed by sweeping feathered tribal wings that curl outward and downward into pointed flares. Twin small scroll-curls coil at the lower shoulders of the heart, and the broad silhouette suggests a uterus cradling the heart at its center. Inked low and wide across the lower abdomen above the pubic mound. |
| `045` | Mark 045 | lower abdomen above the pubic mound | A small heart sits at the center with a tiny droplet-keyhole inside it, framed by curling arms that suggest a uterus. Two large jagged spike-wings sweep upward and outward to sharp barbed tips, and short tails drop below the heart. The overall silhouette is V-shaped and aggressive. |
| `046` | Mark 046 | lower abdomen above the pubic mound | A bold filled heart anchors the center, with a small diamond-shaped crown rising just above it. Symmetric ornamental scrollwork sweeps outward to either side in tight curls and leafy flourishes. A short flame-tongue tail descends below the heart toward the pubic mound. |
| `047` | Mark 047 | lower abdomen above the pubic mound | A central heart with a small inner scroll is flanked by two long curving arms that hook upward and outward to fine barbed points. A pointed tail drops sharply downward from the heart's base. The arching arms suggest a uterus framing the heart at the center. |
| `048` | Mark 048 | lower abdomen, just above the pubic mound | A single thick-bordered heart dominates the design, with two short pointed flame-cuts at the upper lobes and a layered leaf-fan flourish filling its lower hollow. There is no fallopian or ovary anatomy; the entire mark is one stylized heart shield. It sits squarely above the pubic mound. |
| `049` | Mark 049 | lower abdomen above the pubic mound | A bold central heart carries a keyhole shape cut into its lower face, framed by an inner curling scroll on either side and a small accent flourish above. Long thin tribal wings sweep horizontally outward to pointed tips far to either side, and a single teardrop hangs straight down from the bottom of the heart. |
| `050` | Mark 050 | lower abdomen above the pubic mound | A small notched heart sits centered within a larger pointed heart shell, capped by a tall trident-like spike rising from the upper notch. Curling fallopian arms sweep outward into thin pointed scroll wings, and layered fronds taper downward into a forked cervix-tail through the lower midline. |
| `051` | Mark 051 | lower abdomen, wide above the pubic mound | A gothic sigil with a small heart at the center framed by curling arms that hint at a uterus, flanked by twin bat-like fallopian wings rising from the upper shoulders and tipped with small pointed heads. A spade-shaped pendant hangs from the bottom on a thin descending stem, with forked spiked tendrils draping outward from the base toward the pubic mound. |
| `052` | Mark 052 | lower abdomen above the pubic mound | A central heart with a tiny spike-crown above is framed by two short curling arms that bulge outward into rounded ovary lobes. A double set of curled tails drops below the heart, with a small spiral terminus at the bottom. The wrapping arms suggest a uterus around the central heart. |
| `053` | Mark 053 | lower abdomen above the pubic mound | A small heart at the very center sits inside a dense ornate framework of curling tendrils and pointed flourishes. Two arched arms sweep outward and terminate in coiled ovary-like tips, while leafy fronds descend below toward the pubic mound. The full silhouette reads strongly as a uterus enclosing the heart. |
| `054` | Mark 054 | lower abdomen above the pubic mound | A small heart sits at the dead center as a stand-in ovum, ringed by several spermatozoa whose bulb-heads and curled flagella swim inward from the surrounding filigree — pairs hang above the heart and at the lower flanks, with more tucked into the outer eye-shaped ovary loops. Long curling tribal arms sweep out to either side and the overall silhouette suggests a uterus crowded with seeking sperm. |
| `055` | Mark 055 | lower abdomen, wide above the pubic mound | An ornate sigil with a small heart at the center cradled inside curling arms that hint at a uterus, surmounted by a small pointed crown spire. Twin long swept fallopian wings extend horizontally outward at the shoulders, and a clustered ribbon-tendril dripping from the base curls into a teardrop above the pubic mound. |
| `056` | Mark 056 | lower abdomen, just above the pubic mound | A small upright faceted crystal rises from the apex above a central heart that contains two facing spermatozoa as paisley-shaped curls with curled tails. Sweeping fallopian arms extend outward to rolled ovary tips, with long pointed cervix-tails draping down from the base. The composition's outer silhouette suggests a uterine envelope crowned by the crystal. |
| `057` | Mark 057 | lower abdomen, just above the pubic mound | A heart-in-heart sits at the center, flanked by long sweeping flame-wing fallopian arms that flare to pointed tips on either side. A small cross-shaped beaded cervix accent drops below the heart, with delicate radiating tendrils filling the outer edges. The overall outline reads as a wide winged uterine envelope around the heart. |
| `058` | Mark 058 | lower abdomen above the pubic mound | A bold central heart is flanked by two large bat-wings that sweep up and outward to pointed tips. A second smaller heart nests inside the main one, and layered flame-like tails drop below toward the pubic mound. The wings curl in on themselves at the heart's shoulders. |
| `059` | Mark 059 | lower abdomen, just above the pubic mound | A faceted crystal sits at the very top apex above a bold central heart, with curling tendrils arcing inward from the upper flanks toward the heart. Sprawling curling vines and feathered tendrils sweep outward into wing-tips on either side, and a coiled descending tail drops below the heart with a small bead at its terminus. |
| `060` | Mark 060 | lower abdomen above the pubic mound | A small heart at the center is crowned by a tall pointed spike that reads like a crystal or diamond rising above it, with secondary blades flaring out to either side. Mirrored crystal-spike clusters point downward below the heart, and the entire silhouette is jagged and sharply geometric. The radiating points around the central heart give a crystalline rather than purely organic feel. |
| `061` | Mark 061 | lower abdomen, spread wide above the pubic mound | A horizontal banner of full-bloom roses runs across the lower abdomen, the central rose flanked by two outward-facing rose heads and bordered by thorned vines and pointed leaves. A small teardrop pendant drops from the lower center. There is no anatomical heart or uterus iconography in this design. |
| `062` | Mark 062 | lower abdomen above the pubic mound | A highly literal anatomical uterus rendered in dense ink, with the uterine body, twin fallopian tubes, and rounded ovaries clearly drawn at the top. A small vertical detail marks the cervix inside the body, and the vaginal canal descends below into a bulbous terminus. The whole silhouette is unmistakably a uterus — no heart appears at the center. |
| `063` | Mark 063 | lower abdomen above the pubic mound | A clean anatomical uterus is rendered as bold outline, its two fallopian arms curling up and outward into rounded ovary bulbs. A small heart is set into the upper fundus as the womb's inner marker, with a narrow cervix and a long tapered vaginal column extending downward to a pointed tip. |
| `064` | Mark 064 | lower abdomen, just above the pubic mound | The whole outer silhouette is a heart-shaped uterus, with a small downward-pointing faceted diamond marking the cervix at its lowest tip. At the upper shoulders, paired paisley curls read as spermatozoa with bulb-heads and tucked flagella facing inward. Two leaf-shaped ovary pods perch at the very top corners. |
| `065` | Mark 065 | lower abdomen, just above the pubic mound | A wide uterine silhouette holds three stacked wavy lines at its core suggesting fluid or amnion, with curling fallopian arms scrolling outward and back to rolled ovary terminals. A small bow-and-tassel ornament hangs from the base where the cervix would be. There is no explicit central heart in this design. |
| `066` | Mark 066 | lower abdomen above the pubic mound | A stylized muscular humanoid stands at the center with arms raised and curled outward in twin sweeping loops that double as the fallopian arms of a uterus. A small heart marker sits on the chest of the figure, and the torso tapers into a column of legs that reads as the cervix and vaginal channel — the overall silhouette suggests a uterus built from a human form. |
| `067` | Mark 067 | lower abdomen, wide above the pubic mound | A central heart is topped by two upward-pointing horn-like spikes and framed by sweeping tribal wings that curl outward from the lower shoulders. A small pointed heart-pendant descends below the main heart and the overall silhouette suggests a uterus cradling the heart at its center. Sits low and wide across the lower abdomen. |
| `068` | Mark 068 | lower abdomen above the pubic mound | A large pointed heart dominates the center, topped by a faceted diamond-shaped gem and crowned by two outward-curling horn tips that rise above the fundus like demon brows. Flame-shaped fronds and curling tendrils splay outward from the heart on both sides, and a small inner flourish nests where a cervix-mark would sit. |
| `069` | Mark 069 | lower abdomen, wide above the pubic mound | A wide tribal sigil with a small heart at the center cradled inside curling arms that hint at a uterus, with two upturned horn-spikes rising from the top and twin pointed ovary curls forming eye-like slits at the shoulders. A short pointed cervix-tail descends from the base and the overall silhouette evokes a horned skull or bull mask above the pubic mound. |
| `070` | Mark 070 | lower abdomen above the pubic mound | Two heart shapes nest stacked inside the upper fundus of a clear tribal uterus silhouette, with a tall pronged crown rising above the top notch. Each fallopian arm sweeps outward into an ovary lobe containing a small accent heart, and a feathered tail descends from the cervix between two flanking spike-tendrils. |
| `071` | Mark 071 | lower abdomen, just above the pubic mound | A central heart is surrounded by radiating spiked rays and flanked by small upright faceted diamond accents at the upper corners and apex, with a larger diamond hanging directly below the heart at the cervix point. Tapered flame-blade curls drop from the lower edges. The radiant geometry frames the heart like a crowned medallion. |
| `072` | Mark 072 | lower abdomen above the pubic mound | A circular medallion sits at the center crowned by a small leafy tuft on top, with a stylized heart-and-scroll motif filling its inner disc. Two long horizontal blade-wings sweep outward from the medallion's flanks into sharp pointed tips, giving the design the look of a winged faction crest or guild insignia rather than the anatomical motifs of the surrounding set. |
| `073` | Mark 073 | lower abdomen, centered above the pubic mound | An occult alchemical sigil — a dot-in-circle-in-circle motif at the top crowned by a small upward curl, joined to a horizontal cross-bar whose ends are open (non-closed) circles each containing a central dot. Below the cross-bar, twin sinuous lines coil into a tight braid down the vertical axis, ending in small curled terminals over the pubic mound. |
| `074` | Mark 074 | lower abdomen, wide above the pubic mound | An ornamental crown of swept tribal scrollwork arcs horizontally across the top, with two upturned spike-curls at each outer tip. A small heart hangs at the center below the crown on a slender stem, descending into a tapered diamond-tipped pendant tail that drops toward the pubic mound. |
| `075` | Mark 075 | lower abdomen above the pubic mound | A detailed anatomical uterus framed in ornate tribal ink, with a small heart nested inside the uterine cavity at the very center. Twin fallopian tubes curve outward to leaf-shaped ovaries on either side, and a descending vagina with vertical inner detail drops below. The overall silhouette is unmistakably uterus-shaped, cradling the central heart. |
| `076` | Mark 076 | lower abdomen, just above the pubic mound | A small heart sits at the very top of the design, directly above a vertical pointed teardrop pendant at the center. Two large curling tendrils sweep outward from beside the teardrop like decorative wings, and additional pointed barbs flare to either side as the device settles low and wide on the abdomen above the pubic mound. |
| `077` | Mark 077 | lower abdomen, narrowing toward the pubic mound | A small heart with twin upturned horns at its top sits between two short pointed bat-wing fallopian arms. From beneath the heart a long slim leaf-blade pendant descends to a sharp point, flanked by curled inner brackets. The narrow vertical composition fans down toward the pubic mound. |
| `078` | Mark 078 | lower abdomen, just above the pubic mound | A small upright faceted crystal rises from the apex above a bold central heart, with the whole outer silhouette forming a clear heart-shaped uterus around it. Curling arms flank the heart and sweep down into flame-blade tails that taper toward the pubic mound. The design closes without a separate cervix-tail. |
| `079` | Mark 079 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized wind emblem — flowing curled tendrils sweep outward like gathered breeze, with a small heart at the apex. The whole device sits wide and low across the abdomen above the pubic mound. |
| `080` | Mark 080 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized lightning emblem — three spiraling current-curls arranged around a central pivot, with pointed horn-tips at the upper corners. A narrow forked tail descends from the bottom toward the pubic mound. |
| `081` | Mark 081 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized fire emblem — an upright flame at the center flanked by curled ram-horn flourishes scrolling outward. Pointed beak-tips extend at the outer edges, sitting wide and low across the abdomen above the pubic mound. |
| `082` | Mark 082 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized ice emblem — a six-pointed snowflake at the center framed by sharp angular shards radiating outward to crystalline points. The whole device sits wide and low across the abdomen above the pubic mound. |
| `083` | Mark 083 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized earth emblem — a square geometric labyrinth of interlocking right-angle paths at the center, with twin pointed beak-tips at the outer edges. The whole device sits wide and low across the abdomen above the pubic mound. |
| `084` | Mark 084 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized nature emblem — a smaller nested heart at the center surrounded by curling leaves and floral scrollwork sprouting outward to either side. The whole device sits wide and low across the abdomen above the pubic mound. |
| `085` | Mark 085 | lower abdomen, just above the pubic mound | A heart-shaped frame encloses a stylized water emblem — a swirling teardrop motif at the center with curling currents radiating outward. Leafy butterfly-wing flourishes sweep outward at either side, sitting wide and low across the abdomen above the pubic mound. |
| `086` | Mark 086 | wide across the lower abdomen above the pubic mound | A wide banner-style design with a central heart containing a smaller inner heart, crowned by a short diamond spike. Two webbed bat-wings sweep outward from beneath the heart, flanked by leafy tendrils and small bulb accents. The full silhouette spans broadly across the lower belly. |
| `087` | Mark 087 | wide across the lower abdomen above the pubic mound | A wide banner-style heart at the center is topped by two short upright horns with curling inner spirals, suggesting a horned uterus crowning the heart. Symmetric scrollwork fans out to either side in tight curls and pointed flourishes, with a slender beaded tail descending below the heart. The whole motif spreads broadly across the lower belly. |
| `088` | Mark 088 | vertical strip down the lower abdomen | A long vertical serpent-staff sigil — a teardrop sits at the very top above a spiral-eye that loops into the head of a single serpent. The serpent winds tightly down a straight vertical staff in a series of stacked coils, ending in a small curled tail just above the pubic mound. |
| `089` | Mark 089 | lower abdomen above the pubic mound | A bold heart sits at the center inside a curled scrollwork frame, flanked by two outward-flaring bat-style wings whose membranes are notched into pointed claw-tips. A narrow tribal tail with a small accent heart and feathered tendrils drops below the central heart through the cervix region. |
| `090` | Mark 090 | lower abdomen, just above the pubic mound | A hollow line-drawn heart sits at the center, framed by two outward-curling fallopian arms that scroll into leaf-shaped ovary pods at their tips. A small flame and a single teardrop pendant hang directly below the heart at the cervix point. The overall outline forms a wide uterine envelope around the open heart. |
| `091` | Mark 091 | lower abdomen, just above the pubic mound | A solid cat head with pointed ears, slit-cutout eyes, a small triangular nose and whisker-mouth fills the center, flanked by a four-toed paw print on each side. The design contains no anatomical or fertility iconography; it is simply a feline crest with paws. It sits low and centered above the pubic mound. |
| `092` | Mark 092 | lower abdomen, wide above the pubic mound | A gothic sigil with a small heart at the center cradled inside curling arms that hint at a uterus, crowned at the top by a small upright diamond crystal flanked by two pointed spikes. Twin scalloped bat-like fallopian wings sweep outward at the shoulders, and a short beaded vertical tail descends from the base toward the pubic mound. |
| `093` | Mark 093 | lower abdomen, wide above the pubic mound | A central heart is topped by two upturned devil horns and flanked by sweeping bat-like wings that arc broadly outward from the shoulders. A thin infinity loop dangles below the heart and tapers into an arrow-tipped tail that points downward toward the pubic mound. |
| `094` | Mark 094 | lower abdomen, just above the pubic mound | A small heart with twin upturned horns sits between two long pointed bat-wing fallopian arms that sweep outward and downward. Below the heart a slender ornamental cross descends as the cervix pendant, with curled inner brackets framing it. The outer envelope spreads wide across the lower belly. |
| `095` | Mark 095 | lower abdomen, wide above the pubic mound | A stylized uterine glyph — twin angular fallopian arms sweep outward from a domed body, with a single lidded eye staring forward from the center of the uterus. A downward-pointing dagger-shape descends from the cervix toward the pubic mound, and small hook-curls accent the ovary tips at each shoulder. |
| `096` | Mark 096 | lower abdomen, wide above the pubic mound | An ornamental sigil with a small heart at the center cradled inside curling arms that hint at a uterus, crowned at the top by an upright diamond crystal flanked by two slim outward-leaning spear-spikes. Twin sweeping fallopian wings curl outward from the shoulders, and a tapered tail of layered curls descends from the base toward the pubic mound. |

## Pack: `mtf.obi-tattoos` — "Obi's Tattoos (3BA 4K)" (18 entries)

All **18** entries grounded from visual inspection of the rendered alpha-union over the CBBE body/hands UV.

| id | label | placement | description |
|---|---|---|---|
| `1` | Tattoo 1 | front torso, spanning from the upper chest down through the navel | A dense baroque altar-throne crest in heavy filigree, built around a tall central spire with paired arches sweeping out to either side and twin fish-or-fetus creatures curling at the base. Inked across the front torso, spanning from the upper chest down through the navel. |
| `2` | Tattoo 2 | wrapping each upper arm as a sleeve band | Two mirrored arrowhead-shaped bands of intricate openwork, each centered on a filled rosette flanked by leafy fronds tapering to a sharp point. Inked as a band wrapping each upper arm like a sleeve. |
| `3` | Tattoo 3 | one on each thigh | Two mirrored circular rosettes in fine line mandala work, each ringed by a wreath of petals around a small filled center, with a curling double-scroll tendril and a tiny secondary bloom dangling below like a pendant. One inked on each thigh. |
| `4` | Tattoo 4 | upper back, descending from the nape between the shoulder blades | A large layered mandala bloom anchored between the shoulder blades, flanked by two sweeping solid wing panels veined with fine line work, capped by twin slender spires that rise up the back of the neck. The piece is fully symmetric and dominates the upper back. |
| `5` | Tattoo 5 | one on each outer thigh and hip flank | Two mirrored swirling botanical compositions in openwork, each crowned by a solid filled orb and a small crescent moon above clustered five-petal blooms and curling vines. One inked on each outer hip, sweeping down onto the upper thigh. |
| `6` | Tattoo 6 | two-part — small accent on the upper chest between the collarbones, with a larger leaf cluster around the navel | A two-part botanical composition — a small upright feathered plume topped by a small triangle sits on the upper chest between the collarbones, while a larger pair of mirrored sprays of feathered leaves drapes across the lower belly anchored around the navel with a tiny diamond ornament at its center. Fine line work throughout. |
| `7` | Tattoo 7 | upper back, descending from the nape between the shoulder blades | A large teardrop-shaped mandala filled with concentric rings of intricate geometric line work around a central bloom, capped by twin slender spires that rise up the back of the neck. The piece is fully symmetric and dominates the upper back. |
| `8` | Tattoo 8 | upper chest, above the breast line | A butterfly-like silhouette built from layered flower petals and leaves, with small dotted blossoms perched at each wingtip and a central upright plume. Inked small on the upper chest, just above the breast line. |
| `9` | Tattoo 9 | front torso, spanning from below the breasts down through the navel to the lower abdomen | A large downward-pointing triangular crest in bold filigree, built around a central blooming flower with scalloped lace edging along the sides and a small teardrop pendant hanging from the bottom point. Spans the full front belly from below the breasts down through the navel to the lower abdomen. |
| `10` | Tattoo 10 | wide band across the upper chest, above the breast line | A wide horizontal tribal band anchored by a leafy central crest with a small dotted halo above, feathered out with long sweeping symmetric flourishes to either side. Inked across the upper chest, above the breast line. |
| `11` | Tattoo 11 | full spine column, descending from the nape down to between the buttocks | A tall vertical plume of wispy flame-and-feather strokes, narrowing to fine tendril points at top and bottom around a small diamond-and-star ornament at the heart. Inked as a full spine column descending from the nape all the way down to between the buttocks. |
| `12` | Tattoo 12 | covering the whole back | An elongated diamond-shaped pendant framed in dense filigree with a dotted halo, holding a cluster of full roses in a solid filled inner panel at its heart and lace-like floral edging along its sides. Dominates the whole back as a single large piece. |
| `13` | Tattoo 13 | upper-right chest above the breast, extending onto the right shoulder and upper arm | A cluster of full-bloomed roses paired with a smaller butterfly silhouette, with looping jewelry chains draped beneath that gather into small teardrop pendants. Inked on the upper-right chest above the breast, spilling up over the right shoulder and onto the upper arm. |
| `14` | Tattoo 14 | full spine column, descending from the base of the neck down to between the buttocks | A vertical stack of ornate ornaments — a small fleur-like crown at the top, a slender beaded chain mid-section, and a large lantern-like crown of arches and pearls anchored over the mid-back. Runs as a full spine column from the base of the neck down to between the buttocks. |
| `15` | Tattoo 15 | wrapping each upper arm as a sleeve | Two mirrored pointed-oval medallions, each framing an empty almond-eye opening at the center with dense filigree petals and curling scrollwork flaring out from both tips. One inked wrapping each upper arm as a sleeve. |
| `16` | Tattoo 16 | wrapping the right upper arm as a sleeve | A naturalistic serpent rendered in fine scaled line work, its body knotted and looped over itself with the head raised and tongue flicking out. Inked wrapping the right upper arm as a sleeve. |
| `17` | Tattoo 17 | lower abdomen, arched horizontally above the pubic mound | A stylized open mouth-like motif arched horizontally, its curving upper and lower lips bristling with countless wiry hair-like tendrils along the edges like lashes or whiskers, and antenna-like tips flicking from each corner. Inked across the lower abdomen, the arch sitting just above the pubic mound. |
| `18` | Tattoo 18 | front torso, descending from the base of the neck down through the chest to below the navel | A tall, narrow dagger-shaped crest descending the front torso, built from stacked gothic spurs and runic shapes around two beaked bird skulls flanking a central diamond eye at the base. Spans from the base of the neck down through the chest to below the navel. |

## Pack: `mtf.rx-overlays` — "RX'Overlays (3BA)" (41 entries)

All **41** entries grounded from visual inspection of the rendered alpha-union over the CBBE body/hands UV.

| id | label | placement | description |
|---|---|---|---|
| `Abs Butterfly` | Abs Butterfly | lower abdomen, just below the navel | A single butterfly with finely traced wings and detailed cross-hatched shading, inked on the lower abdomen just below the navel. |
| `ArmL Turtle` | ArmL Turtle | outer left forearm | A tiny stylized turtle rendered as a solid silhouette with small star accents, inked on the outer left forearm. |
| `ArmR Fish` | ArmR Fish | outer right forearm | A pair of koi-like fish curling around one another in fine flowing linework with small star accents, inked on the outer right forearm. |
| `Boob Dragons` | Boob Dragons | around the right nipple | Three winged dragons in solid silhouette arc in flight around the right nipple, their tails trailing into loose painterly wisps as if circling overhead. |
| `Butt Butterflies` | Butt Butterflies | on the left buttock | A very small cluster of finely inked butterflies on the left buttock, so subtle they read almost as marks on skin in fine sketchy linework. |
| `Butt Butterflies2` | Butt Butterflies2 | on the left buttock | A pair of tiny butterflies inked on the left buttock in delicate fine linework. |
| `Butt Cat` | Butt Cat | on the left buttock | A stylized tribal cat face with flame-like fur strokes and a small crescent moon above its head, inked in bold flowing brushwork on the left buttock. |
| `ButtL Lips` | ButtL Lips | left buttock | A bold lipstick kiss mark inked as a single dense silhouette on the left buttock, with the texture of pressed lips clearly visible. |
| `ButtR Lips` | ButtR Lips | right buttock | A bold pair of parted, bitten lips flanked by small crescent shapes, inked as a solid silhouette on the right buttock. |
| `Chest DragonFlower` | Chest DragonFlower | centered on chest, descending the sternum to the lower abdomen | A vertical sternum piece: a stylized lotus and small medallions at the top, a beaded chain through the midline, and a winged dragon coiling at the lower belly. |
| `Chest DragonMoon` | Chest DragonMoon | centered on chest, descending the sternum to the lower abdomen | A vertical sternum piece: a row of pointed stars and small celestial motifs at the top, threading down to a winged dragon coiled at the lower belly. |
| `Chest Dragons` | Chest Dragons | upper chest, near the right collarbone | Three small winged dragons in detailed inked silhouette arrayed in a tight cluster among scattered stars and tiny crosses, set on the upper chest near the right collarbone. |
| `Chest Fairy` | Chest Fairy | centered on the chest and down the sternum | A slender winged fairy poised at the top of the sternum, with a radiant sun motif and small sparkles inked below her on the lower chest. |
| `Chest Knife` | Chest Knife | centered vertically on the sternum | An upright dagger with an ornate cross-guard, banded grip and pommel, blade pointing downward, inked vertically along the sternum. |
| `Chest Lips` | Chest Lips | centered between the breasts on the sternum | A bold pair of lips parted around a bite, accented by a small crescent, inked as a single filled mark centered between the breasts on the sternum. |
| `Chest MoonFlower` | Chest MoonFlower | centered on the chest, descending the sternum, with a wide beaded arc across the lower belly | A vertical sternum column of a stylized lotus, beaded dots and a crescent moon, fanning out into a wide beaded arc with hanging droplets across the lower abdomen. |
| `Chest StarsLeft` | Chest StarsLeft | right upper chest near the right collarbone | A scatter of pointed stars, crosses and a small ringed planet drifting in a diagonal across the right side of the upper chest, with a bold radiant sun and crescent moon as focal points near the right collarbone. |
| `Chest StarsRight` | Chest StarsRight | left upper chest near the left collarbone | A bold radiant sun above a crescent moon as focal points on the left side of the upper chest near the left collarbone, surrounded by scattered pointed stars and small crosses. |
| `Chest Sun` | Chest Sun | centered on the sternum | A radiant sun medallion with a smaller pointed star above it, inked along the sternum, with a fringe of beaded chains hanging in a fan below. |
| `Chest SunMoon` | Chest SunMoon | centered on the chest, fanning across the lower belly | A small celestial sternum piece with a starburst and crescent stacked vertically, opening into a beaded arc with hanging droplets that drapes across the lower abdomen. |
| `Chest Sword Flower` | Chest Sword Flower | centered on the chest, descending the sternum to the lower abdomen | A long sword pointing downward, its blade wrapped in rose-and-vine accents, with a jeweled hilt above and a radiant medallion fanning out at the lower belly. |
| `ChestL Birds` | ChestL Birds | left side of the chest, below the breast | A small flock of bird silhouettes scattered as if mid-flight, inked on the left side of the chest below the breast. |
| `ChestR Birds` | ChestR Birds | right side of the chest, below the breast | A small flock of bird silhouettes drifting in scattered flight, inked on the right side of the chest below the breast. |
| `ChestR Dragon` | ChestR Dragon | right side of the upper chest | Two winged dragons drawn in loose solid silhouette, facing each other on the right side of the upper chest with their tails curling behind them. |
| `Down Fairy` | Down Fairy | low on the abdomen, descending toward the pubic mound | A slender winged fairy figure drawn in fine sketchy lines, inked low on the abdomen with delicate vine-like trails reaching down toward the pubic mound. |
| `Hand Stars` | Hand Stars | right hand, on the index finger | A small drift of pointed stars, sparkles and a tiny crescent moon inked along the right index finger. |
| `Magic Scar` | Magic Scar | diagonal sweep down one side of the torso, from upper chest to lower abdomen | A long ornament traced like a magical scar, anchored at the upper chest by a radiant sun medallion and sweeping diagonally down one side of the torso to the lower abdomen, dissolving into a wispy trail of vines and tiny sparkles at its lower end. |
| `Moles` | Moles | scattered across the torso | A handful of very small pinpoint marks scattered randomly across the torso, reading as faint beauty spots rather than a deliberate design. |
| `Spine ButterflySars` | Spine ButterflySars | on the right shoulder blade, high on the upper back | A pair of small butterflies among scattered pointed stars and a small crescent moon, inked on the right shoulder blade high on the upper back. |
| `Spine Flower` | Spine Flower | running down the spine from upper back toward lower back | A long ornamental chain anchored by a symmetrical winged flourish at the top and tapering down through stacked floral medallions and beaded dotwork along the length of the spine. |
| `Spine MagicBook` | Spine MagicBook | centered between the shoulder blades on the upper back | A bold winged tome inked between the shoulder blades, with twisting root-like tendrils and ink splatter spilling downward across the upper back. |
| `SpineL Dragons` | SpineL Dragons | left of the upper spine | A small dragon in fine inked silhouette, set just left of the upper spine between the shoulder blades. |
| `SpineR Dragons` | SpineR Dragons | right of the upper spine, between the shoulder blades | A small dragon rendered in fine inked silhouette with trailing wisp-like tendrils, set just right of the upper spine between the shoulder blades. |
| `ThighL Dragons` | ThighL Dragons | outer left thigh | A few very small, minimally sketched dragon figures inked on the outer left thigh, so faint they read almost as ink ghosts on the skin. |
| `ThighL Flower` | ThighL Flower | down the outer left thigh | Small floral sprigs and a tiny detailed accent piece spaced down the outer left thigh in delicate sketchy linework. |
| `ThighL Stars` | ThighL Stars | outer left thigh | A loose drift of small pointed stars, cross sparkles and a tiny sunburst inked in a curving line along the outer left thigh. |
| `ThighL Virgo` | ThighL Virgo | outer left thigh | A slender nude maiden figure crowned by a radiant sun and surrounded by dense foliage and vines, inked as an elaborate Virgo motif on the outer left thigh. |
| `ThighR Dragons` | ThighR Dragons | outer right thigh | A few very small, minimally sketched dragon figures inked in loose linework on the outer right thigh. |
| `ThighR Flower` | ThighR Flower | down the outer right thigh | Small floral sprigs accompanied by a tiny detailed accent piece, spaced down the outer right thigh in delicate sketchy linework. |
| `ThighR Stars` | ThighR Stars | outer right thigh | A loose drift of small pointed stars, cross sparkles and a tiny sunburst inked in a curving line along the outer right thigh. |
| `ThingR Fairy` | ThingR Fairy | outer right thigh | A nude winged fairy figure caught mid-flight with one knee tucked up, her wings sweeping behind her, inked in fine sketchy lines on the outer right thigh. |

## Pack: `mtf.bardle-nail-polish` — "Bardle Nail Polish (Hand)" (16 entries)

All **16** entries grounded from visual inspection of the rendered alpha-union over the CBBE body/hands UV.

| id | label | placement | description |
|---|---|---|---|
| `bubbles` | Bubbles | all ten fingernails | Scattered fine bubble-flecks across all ten fingernails, like a delicate speckled polish. |
| `dried-blood` | Dried Blood | fingernail cuticles | A small crescent stain at the base of each fingernail, as if dried blood has crusted around every cuticle. |
| `frost` | Frost | all ten fingernails | Delicate feathery frost wisps painted on each of the ten fingernails, like ice slowly forming across the polish. |
| `full-dark` | Full Polish (Dark) | all ten fingernails | Solid full-coverage polish across every fingernail in a deep dark tone. |
| `full-light` | Full Polish (Light) | all ten fingernails | Solid full-coverage polish across every fingernail in a pale light tone. |
| `full-medium` | Full Polish (Medium) | all ten fingernails | Solid full-coverage polish across every fingernail in an even mid-tone shade. |
| `gradient` | Gradient | all ten fingernails | A gradient on every fingernail, lighter at the cuticle and deepening toward the tip. |
| `gradient-invert` | Gradient (Inverted) | all ten fingernails | An inverted gradient on every fingernail, deepest at the cuticle and fading out toward the tip. |
| `lightning` | Lightning | all ten fingernails | A small jagged lightning bolt etched onto each fingernail. |
| `marble` | Marble | all ten fingernails | An irregular marble-vein pattern of fine ink lines and flecks across each fingernail. |
| `marble-reduced` | Marble (Reduced) | all ten fingernails | A subtler marble-vein pattern on each fingernail, with sparser ink lines than the full marble polish. |
| `semi-medium` | Semi-Polish (Medium) | down the middle of each fingernail | A narrow vertical band of polish painted straight down the middle of each fingernail. |
| `semi-slanted` | Semi-Polish (Slanted) | all ten fingernails | A diagonal half-coverage polish on each fingernail, slanted across from one side to the other. |
| `splatters` | Splatters | all ten fingernails | Tiny ink splatters speckled across all ten fingernails like flicked droplets of polish. |
| `no-tip` | No Tip | fingernail base leaving the tip bare | Solid polish covering each fingernail but stopping short, leaving a bare crescent at the very tip. |
| `tip-l` | Tip L | along one edge of each fingernail | A thin vertical accent line of polish running down one edge of every fingernail. |

## Pack: `mtf.community-overlays-1-face` — "Community Overlays 1 (Face)" (20 entries)

*Textures for this pack are not installed in this build; all 20 entries currently have empty `description`. The decorator falls back to the entry label.*

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
