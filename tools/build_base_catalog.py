#!/usr/bin/env python3
"""Build the themed metadata catalogs split out of the old mtf.base pack.

This script mirrors the dispatch logic that used to live in MTF_Plugin_Base.psc's
Get*() metadata getters, producing JSON files consumed by the JsonUtil-driven
base class (MTF_Plugin.psc). One source of truth; re-run after any catalog
change.

v0.3.9: the single mtf.base catalog was split into 5 themed modules
(mtf.attributes / mtf.combat / mtf.magic / mtf.world / mtf.fx). Each is a
separate pluginid + thin MTF_Plugin_Base subclass; all behaviour is inherited
(dispatch is id-keyed). See MODULES / CONDITION_MODULE / EFFECT_MODULE below.

Run:  python3 tools/build_base_catalog.py
Out:  data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/
        mtf.attributes.json, mtf.combat.json, mtf.magic.json,
        mtf.world.json, mtf.fx.json, and mtf.module_map.json (migrator input)

The numbers in this file MUST stay in sync with the Papyrus-side helpers that
remain in MTF_Plugin_Base.psc (the behaviour code that runs in onActivate /
onDeactivate / onTick): _isAbsShift, _isToggle, _isBurstAV, _avNameFor,
_shaderFormId, _soundFormId, _resolveResistSpell, etc. If you add or remove
an effect, update both this script AND the matching Papyrus helper.
"""

import json
import re
from pathlib import Path


def _to_id(label: str) -> str:
    """v0.2.9: snake_case id from a display label. Must match the formula
    in tools/migrate_to_string_ids.py so a regenerated catalog round-trips
    with the migrated catalog files.
    """
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")

PLUGINS_DIR = Path(__file__).resolve().parents[1] / "data" / "SKSE" / "Plugins" / \
    "StorageUtilData" / "MagicTattoosFramework" / "plugins"

# ── Helpers mirroring the Papyrus dispatch ────────────────────────────────────
def is_abs_shift(idx: int) -> bool:
    """Mirrors MTF_Plugin_Base._isAbsShift. Signed AV-point shifts; default
    range -100..100, default 0, slider unit = 'points'/'%'.

    NOTE: this applies the default to param1 only. Effects that put the
    signed shift on param2 (modify.resist, modify.skill) are NOT in this
    set — they specify min/max/default on the param2 override explicitly.

    Index ranges renumbered in v0.2.7 after modify.sneak removal
    (everything past old idx 2 shifted down by 1).
    """
    return (idx <= 1 or (4 <= idx <= 6) or (10 <= idx <= 16) or (30 <= idx <= 31))


# Idxes of burst-kind effects in Base — fires once on activate, no rolling
# state. Continuous is the default (kind field omitted in JSON). MCM
# prepends a "[!] " badge automatically for kind == burst at render time —
# don't put the prefix in labels here. Renumbered in v0.2.7.
BASE_BURSTS = {2, 3, 7, 8, 21, 22, 36}

# v0.2.9: menu enums migrated from {value: int, label: str} to
# {id: snake_case, label: str}. Plugin consumers in MTF_Plugin_Base.psc
# dispatch on the id string (e.g. _skillAVForId("sneak")) rather than
# int positions; this lets the catalog be reordered or extended without
# silently rebinding stored preset values.

# Hit class enum for the combat.hit condition's param dropdown. Ids match
# _checkHit dispatch in MTF_Plugin_Base. Pre-v0.2.5 used 7 separate
# combat.hit.* conditions; consolidated to mirror FLASH_TRIGGER_MENU.
HIT_CLASS_MENU = [
    ("any",     "Any"),
    ("blunt",   "Blunt"),
    ("bladed",  "Bladed"),
    ("ranged",  "Ranged"),
    ("fire",    "Fire"),
    ("frost",   "Frost"),
    ("shock",   "Shock"),
]
assert len(HIT_CLASS_MENU) == 7

# Location keyword enum for the location.kw condition's param dropdown.
# Ids 'player_home'..'jail' map to Skyrim location keyword form IDs in
# _locKwById (Base); 'indoors'/'outdoors' are sentinels for interior/
# exterior cell checks (no keyword lookup — special-cased).
# Pre-v0.2.5 used 6 separate location.{playerHome,dungeon,city,town,inn,jail};
# v0.2.7 also folded location.indoors / location.outdoors in here.
LOCATION_KW_MENU = [
    ("player_home", "Player Home"),
    ("dungeon",     "Dungeon"),
    ("city",        "City"),
    ("town",        "Town"),
    ("inn",         "Inn"),
    ("jail",        "Jail"),
    ("indoors",     "Indoors"),
    ("outdoors",    "Outdoors"),
]
assert len(LOCATION_KW_MENU) == 8

# Weather class enum for the weather condition's param dropdown.
# Ids map to Weather.GetClassification ints (pleasant=0, cloudy=1, rainy=2,
# snowy=3) via the inline branch in MTF_Plugin_Base.checkCondition.
# Pre-v0.2.5 used 4 separate weather.* conditions.
WEATHER_MENU = [
    ("pleasant", "Pleasant"),
    ("cloudy",   "Cloudy"),
    ("rainy",    "Rainy"),
    ("snowy",    "Snowy"),
]
assert len(WEATHER_MENU) == 4

# Resist type enum for the modify.resist effect's param1 dropdown.
# The Base script maps each id to the resist Ability spell in
# MagicTattoosFramework.esp via _resolveResistSpellById. Pre-v0.2.5
# used 6 separate modify.resist* effects keyed by element name in eid.
RESIST_TYPE_MENU = [
    ("fire",    "Fire"),
    ("frost",   "Frost"),
    ("shock",   "Shock"),
    ("magic",   "Magic"),
    ("disease", "Disease"),
    ("poison",  "Poison"),
]
assert len(RESIST_TYPE_MENU) == 6

# Skill AV enum for the modify.skill effect's param1 dropdown. The Base
# script maps each id to the Skyrim AV name via _skillAVForId. Pre-v0.2.5
# used 17 separate modify.<skillname> effects; v0.2.7 folded the
# previously-standalone modify.sneak in too. AV names follow the
# Marksman/Speechcraft Morrowind-holdover quirks (see _avNameFor docstring) —
# the ids stay reader-friendly (sneak / speech / archery) since the Papyrus
# consumer does the AV-name translation internally.
SKILL_AV_MENU = [
    ("one_handed",   "One-Handed"),
    ("two_handed",   "Two-Handed"),
    ("archery",      "Archery"),
    ("block",        "Block"),
    ("heavy_armor",  "Heavy Armor"),
    ("light_armor",  "Light Armor"),
    ("smithing",     "Smithing"),
    ("enchanting",   "Enchanting"),
    ("alchemy",      "Alchemy"),
    ("destruction",  "Destruction"),
    ("restoration",  "Restoration"),
    ("alteration",   "Alteration"),
    ("illusion",     "Illusion"),
    ("conjuration",  "Conjuration"),
    ("speech",       "Speech"),
    ("lockpicking",  "Lockpicking"),
    ("pickpocket",   "Pickpocket"),
    ("sneak",        "Sneak"),
]
assert len(SKILL_AV_MENU) == 18

# ── Conditions ────────────────────────────────────────────────────────────────
# (idx, id, label, description, param?)
# param schema: dict with optional label/min/max/default/format/menu
CONDITIONS = [
    # AV percent thresholds
    ("magicka",         "Above Magicka %",
     "Triggers when the actor's magicka is at or above {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 50}),
    ("magicka.below",   "Below Magicka %",
     "Triggers when the actor's magicka drops below {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 30}),
    ("stamina",         "Above Stamina %",
     "Triggers when the actor's stamina is at or above {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 50}),
    ("stamina.below",   "Below Stamina %",
     "Triggers when the actor's stamina drops below {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 30}),
    # Combat state
    ("combat.in",       "In Combat",
     "Triggers while the actor is in combat (engaged in active fight).",
     None),
    ("combat.alerted",  "Enemies Alerted",
     "Triggers when hostile NPCs within {param1}m are alerted to the actor.",
     {"label": "Scan radius (meters)", "min": 1, "default": 40}),
    ("combat.hostile",  "Hostile Nearby",
     "Triggers when at least one hostile NPC is within {param1}m.",
     {"label": "Scan radius (meters)", "min": 1, "default": 25}),
    # On-hit (single entry; class picked via param1 dropdown).
    ("combat.hit", "On Hit",
     "Triggers with a {param2}% chance per matching incoming hit of class {param1}.",
     {"label": "Hit class", "min": 0, "max": 6, "default": 0,
      "menu": HIT_CLASS_MENU,
      "_param2": {"label": "Chance % per hit", "min": 1, "max": 100, "default": 25}}),
    # Health %
    ("health",       "Above Health %",
     "Triggers when the actor's health is at or above {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 50}),
    ("health.below", "Below Health %",
     "Triggers when the actor's health drops below {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 30}),
    # Location — all flavors consolidated under location.kw. Values 0..5
    # are keyword lookups (player home, dungeon, …); values 6..7 are
    # engine-direct interior/exterior cell checks (formerly standalone
    # location.indoors / location.outdoors, dropped in v0.2.7).
    ("location.kw", "Location",
     "Triggers when the actor is inside a {param1}-flagged location.",
     {"label": "Location type", "min": 0, "max": len(LOCATION_KW_MENU) - 1,
      "default": 0,
      "menu": LOCATION_KW_MENU}),
    # Weather — single entry with classification dropdown.
    ("weather", "Weather",
     "Triggers when the current weather class is {param1}.",
     {"label": "Weather class", "min": 0, "max": 3, "default": 0,
      "menu": WEATHER_MENU}),
    # State (28-35)
    ("state.sprinting",     "Sprinting",
     "Triggers while the actor is sprinting.", None),
    ("state.running",       "Running",
     "Triggers while the actor is running (not walking, not sprinting).", None),
    ("state.weaponDrawn",   "Weapon Drawn",
     "Triggers while the actor has a weapon or spell drawn.", None),
    ("state.loversEmbrace", "Lover's Embrace",
     "Triggers while the actor has the Lover's Embrace rested bonus active.", None),
    ("state.sneaking",      "Sneaking",
     "Triggers while the actor is sneaking.", None),
    ("state.swimming",      "Swimming",
     "Triggers while the actor is swimming.", None),
    ("state.mounted",       "Mounted",
     "Triggers while the actor is mounted on a horse or other steed.", None),
    ("state.bleedingOut",   "Bleeding Out",
     "Triggers while the actor is downed and bleeding out.", None),
    # 36 — time.range (only condition with param2)
    ("time.range", "Time of Day Range",
     "Triggers between in-game hours {param1} and {param2} (wraps midnight if end is earlier than start).",
     {"label": "From (hour)", "max": 24, "default": 6,
      "_param2": {"label": "Till (hour, wrap if < From)", "max": 24, "default": 20}}),
    # Faction / mgef-kw
    ("faction.playerFollower",       "Is Player's Follower",
     "Triggers when the actor is one of the player's current followers.", None),
    ("magiceffect.kw.fire",          "Burning (fire MGEF)",
     "Triggers while a fire-keyword magic effect is active on the actor (burning).", None),
    ("magiceffect.kw.frost",         "Frozen (frost MGEF)",
     "Triggers while a frost-keyword magic effect is active on the actor (frozen).", None),
    ("magiceffect.kw.shock",         "Shocked (shock MGEF)",
     "Triggers while a shock-keyword magic effect is active on the actor (shocked).", None),
    ("magiceffect.kw.invisibility",  "Invisible",
     "Triggers while the actor is invisible.", None),
    # 42 — followers.any
    ("followers.any", "Has Active Follower",
     "Triggers when at least one follower NPC is within {param1}m.",
     {"label": "Scan radius (meters)", "min": 1, "default": 80}),
    # 43 — gold
    ("gold.aboveThousand", "Gold >= N x 1000",
     "Triggers when the actor's gold is at or above {param1},000.",
     {"label": "Gold threshold (x 1000)", "max": 1000, "default": 5}),
    # 44-45 — worn armor
    ("worn.heavyArmor", "Wearing Heavy Armor",
     "Triggers when the actor is wearing a heavy-armor cuirass.", None),
    ("worn.lightArmor", "Wearing Light Armor",
     "Triggers when the actor is wearing a light-armor cuirass.", None),
    # 46 — combat.casting
    ("combat.casting", "While Casting Spell",
     "Triggers while the actor is charging or holding a spell mid-cast.", None),
    # ── Shout / Dragonborn (v0.4) ──────────────────────────────────────────
    # Voice + dragon-soul reactive conditions. shout.cooldown / shout.equipped
    # are pollable engine state; dragonsoul.unspent is a steady AV threshold;
    # dragonsoul.absorbed is transient — fires for a window right AFTER the
    # DragonSouls AV increments (the soul fully lands). The game already plays
    # the blur + whirlwind VFX during the drink-in, so firing on completion is
    # the intended beat; see _checkTransientIncrease in MTF_Plugin_Base.
    # shout.learned / word.unlocked are ALSO transient: they poll the player
    # stats "Shouts Learned" / "Words Of Power Unlocked" via Game.QueryStat and
    # fire for a window right after the count rises (NB: "Words Of Power Learned"
    # is NOT a valid QueryStat string — Unlocked is the pollable one). These are
    # player-global stats, so they reflect the Dragonborn regardless of subject.
    # shout.equipped is "any shout" only — per-shout selection would need a
    # dropdown of every Shout form (deferred).
    ("shout.cooldown", "Voice on Cooldown",
     "Triggers while the actor's Shout voice is still recovering (just shouted).",
     None),
    ("shout.equipped", "Shout Equipped",
     "Triggers while the actor has any Shout readied in the voice slot.",
     None),
    ("dragonsoul.unspent", "Unspent Dragon Souls",
     "Triggers when the actor is hoarding at least {param1} unspent dragon souls.",
     {"label": "Dragon soul threshold", "min": 1, "max": 100, "default": 1}),
    ("dragonsoul.absorbed", "Absorbed Dragon Soul",
     "Triggers for {param1}s right after the actor absorbs a dragon soul.",
     {"label": "Glow duration (s)", "min": 1, "max": 30, "default": 5}),
    ("shout.learned", "Shout Learned",
     "Triggers for {param1}s right after the Dragonborn learns a new shout (reads a word wall).",
     {"label": "Glow duration (s)", "min": 1, "max": 30, "default": 5}),
    ("word.unlocked", "Word of Power Unlocked",
     "Triggers for {param1}s right after the Dragonborn unlocks a word of power (spends a dragon soul).",
     {"label": "Glow duration (s)", "min": 1, "max": 30, "default": 5}),
]
assert len(CONDITIONS) == 37, f"expected 37 conditions, got {len(CONDITIONS)}"

# ── Shader catalog (idx 55 menu) ──────────────────────────────────────────────
# Labels match MTF_Plugin_Base._shaderLabel; ordering matches _shaderFormId.
SHADERS = [
    "Fire Cloak", "Fire Burst", "Frost", "Frost Chillrend", "Shock",
    "Shock Storm", "Stoneflesh", "Ebonyflesh", "Dragonhide", "Soul Trap",
    "Ghost (Ethereal)", "Ghost Red", "Invisibility", "Muffle", "Ward Shield",
    "Reanimate", "Turn Undead Flames", "Heal", "Absorb Health",
    "Vampire Change", "Werewolf Transform", "Detect Life",
]
assert len(SHADERS) == 22

# ── Sound catalog (idx 56 menu) ───────────────────────────────────────────────
# Labels match MTF_Plugin_Base._soundLabel; ordering matches _soundFormId
# (0x900..0x921 in MagicTattoosFramework.esp).
SOUNDS = [
    "Fire — ready loop", "Fire — secondary ready", "Fire — body on fire",
    "Fire — medium crackle", "Frost — ready loop", "Frost — concentration",
    "Frost — wall hum", "Shock — concentration", "Shock — projectile arc",
    "Shock — wall hum", "Soul Trap — active hum", "Ward — shimmer (stereo)",
    "Ward — shimmer (mono)", "Restoration — heal beam",
    "Restoration — circle hum", "Detect Life — pulse",
    "Alteration — ready hum", "Illusion — ready hum",
    # Stings (one-shot stinger SOUNs)
    "UI — Level up", "UI — Skill up", "UI — New quest", "UI — Quest update",
    "UI — Quest complete", "UI — Shout learned", "UI — Shout pop (big)",
    "UI — Perk select", "UI — Journal open", "Dragon — flight roar",
    "Dragon — kill roar", "Hagraven shriek", "Conjure — portal open",
    "Conjure — portal close", "Conjure — bound weapon", "Conjure — impact",
]
assert len(SOUNDS) == 34

# ── Flash trigger preset menu (idx 33 param) ──────────────────────────────────
# v0.2.9: id column was a bitmask int pre-migration (2=Blunt, 6=Blunt+Bladed,
# 126=all-combat, 128=spell-cast). Now a stable string id; _classMaskTagsById
# in Papyrus maps each id to the C++ tag CSV. The old bitmask shape was an
# encoding-of-convenience that didn't survive UI exposure (users picked one
# option at a time anyway), so collapsing to enum ids is a no-op for users.
FLASH_TRIGGER_MENU = [
    ("disabled",                     "Disabled"),
    ("blunt_only",                   "Blunt only"),
    ("bladed_only",                  "Bladed only"),
    ("ranged_only",                  "Ranged only"),
    ("fire_only",                    "Fire only"),
    ("frost_only",                   "Frost only"),
    ("shock_only",                   "Shock only"),
    ("melee_blunt_bladed",           "Melee (Blunt + Bladed)"),
    ("physical_blunt_bladed_ranged", "Physical (Blunt + Bladed + Ranged)"),
    ("magic_fire_frost_shock",       "Magic (Fire + Frost + Shock)"),
    ("all_combat_classes",           "All combat classes"),
    ("on_spell_cast",                "On spell cast"),
]
assert len(FLASH_TRIGGER_MENU) == 12

# Extras envelope used by flash.onhit (idx 33). Pre-v0.2.4 a separate
# flash.oncast effect (idx 57) had its own envelope; merged into flash.onhit
# with trigger option 128 ("On spell cast") since v0.1.29.
FLASH_ENVELOPE_EXTRAS_33 = [
    {"name": "rampms",   "label": "Ramp up (ms)",          "min": 1, "max": 2000, "default": 150, "step": 10},
    {"name": "decayms",  "label": "Decay (ms)",            "min": 1, "max": 5000, "default": 500, "step": 10},
    {"name": "retrigms", "label": "Sustain window (ms)",   "min": 0, "max": 2000, "default": 800, "step": 10},
]
SOUND_VOLUME_EXTRAS = [
    {"name": "volume",   "label": "Volume (%)",            "min": 0, "max": 100, "default": 100, "step": 5},
]

# ── Effects ───────────────────────────────────────────────────────────────────
# Authored as a sparse table: builder fills in -100..100 / 0 defaults for the
# abs-shift majority below.
#
# Tuple shape: (idx, id, label, description, param_label, overrides_dict|None)
# overrides_dict keys: param (min/max/default/step/menu), param2, extras
EFFECTS_RAW = [
    # Low band (0-17)
    (0,  "modify.magickaRegen",
     "Modify Magicka Regen",
     "Shifts the actor's magicka regeneration rate by {param1}%.",
     "Magicka regen rate shift (mult points; + faster, - slower)", None),
    (1,  "modify.carryWeight",
     "Modify Carry Weight",
     "Shifts the actor's carry-weight cap by {param1}.",
     "Carry weight shift (points; + buff, - drain)", None),
    (2,  "damage.magicka",
     "Damage Magicka",
     "Burst — damages or restores {param1}% of the actor's base magicka when the tier activates.",
     "Burst % of base Magicka (+ restore, - damage)",
     {"param": {"min": -100, "max": 100, "default": 0}}),
    (3,  "damage.stamina",
     "Damage Stamina",
     "Burst — damages or restores {param1}% of the actor's base stamina when the tier activates.",
     "Burst % of base Stamina (+ restore, - damage)",
     {"param": {"min": -100, "max": 100, "default": 0}}),
    (4,  "modify.movementSpeed",
     "Modify Movement Speed",
     "Shifts the actor's movement-speed multiplier by {param1}%.",
     "Movement speed shift (mult points; + faster, - slower)", None),
    (5,  "modify.staminaRegen",
     "Modify Stamina Regen",
     "Shifts the actor's stamina regeneration rate by {param1}%.",
     "Stamina regen rate shift (mult points; + faster, - slower)", None),
    (6,  "modify.attackDamage",
     "Modify Attack Damage",
     "Shifts the actor's outgoing attack damage by {param1}%.",
     "Attack damage shift (% points; + buff, - drain)", None),
    (7,  "burst.stagger",
     "Stagger",
     "Burst — staggers the actor when the tier activates.",
     "", None),
    (8,  "burst.blowCover",
     "Blow Cover",
     "Burst — alerts every hostile NPC within {param1}ft to the actor's presence (blows stealth).",
     "Alert radius (feet)",
     {"param": {"min": 5, "max": 300, "default": 80, "step": 5}}),
    (9,  "scale.magickaCost",
     "Scale Magicka Cost",
     "Spells cost {param1}% of their original across all schools.",
     "Spell cost (% of original)",
     {"param": {"min": 0, "max": 400, "default": 100, "step": 5}}),
    (10, "modify.healthRegen",
     "Modify Health Regen",
     "Shifts the actor's health regeneration rate by {param1}%.",
     "Health regen rate shift (mult points; + faster, - slower)", None),
    (11, "modify.maxMagicka",
     "Modify Max Magicka",
     "Shifts the actor's maximum magicka by {param1}.",
     "Max magicka shift (points; + buff, - drain)", None),
    (12, "modify.maxStamina",
     "Modify Max Stamina",
     "Shifts the actor's maximum stamina by {param1}.",
     "Max stamina shift (points; + buff, - drain)", None),
    (13, "modify.weaponSpeed",
     "Modify Weapon Speed",
     "Shifts the actor's weapon-swing speed by {param1}%.",
     "Weapon speed shift (% points; + faster, - slower)", None),
    (14, "modify.unarmedDamage",
     "Modify Unarmed Damage",
     "Shifts the actor's unarmed melee damage by {param1}.",
     "Unarmed damage shift (points; + buff, - drain)", None),
    (15, "modify.criticalChance",
     "Modify Critical Chance",
     "Shifts the actor's critical-strike chance by {param1}%.",
     "Critical chance shift (points; + buff, - drain)", None),
    (16, "modify.bowSpeed",
     "Modify Bow Speed",
     "Shifts the actor's bow draw and release speed by {param1}.",
     "Bow speed bonus shift (units; + faster draw, - slower)", None),

    # Consolidated resists (was 6 separate modify.resist* entries, idx
    # 18-21 + 34-35). param1 picks the resist type; param2 carries the
    # signed shift in resist points. Internal routing via
    # _resolveResistSpellByIdx in MTF_Plugin_Base.
    (17, "modify.resist",
     "Modify Resist",
     "Shifts the actor's {param1} resistance by {param2} points.",
     "Resist type",
     {"param":  {"label": "Resist type", "min": 0, "max": 5, "default": 0,
                 "menu": RESIST_TYPE_MENU},
      "param2": {"label": "Resist shift (points; + resist, - weakness)",
                 "min": -100, "max": 100, "default": 0}}),

    # Toggles (engine-managed AVs that need ability-spell routing).
    (18, "toggle.muffle",
     "Muffle",
     "Toggles silenced footsteps on the actor while active.",
     "", None),
    (19, "toggle.waterbreathing",
     "Waterbreathing",
     "Toggles waterbreathing on the actor while active.",
     "", None),
    (20, "toggle.waterWalking",
     "Water Walking",
     "Toggles water-walking on the actor while active.",
     "", None),
    (21, "damage.health",
     "Damage Health",
     "Burst — damages or restores {param1}% of the actor's base health when the tier activates.",
     "Burst % of base Health (+ restore, - damage)",
     {"param": {"min": -100, "max": 100, "default": 0}}),
    (22, "burst.bounty",
     "Add Bounty",
     "Burst — adjusts the actor's bounty in their current hold by {param1} gold (positive adds, negative pays off).",
     "Bounty change (gold; + add, - remove)",
     {"param": {"min": -10000, "max": 10000, "default": 0, "step": 50}}),
    (23, "spell.modifyArmor",
     "Modify Armor",
     "Toggles a flat armor-rating bonus of {param1} while active.",
     "Armor rating points",
     {"param": {"min": 0, "max": 500, "default": 100, "step": 10}}),
    (24, "spell.detectLife",
     "Detect Life",
     "Toggles a Detect Life aura that highlights living NPCs within {param1}ft while active.",
     "Detect radius (feet)",
     {"param": {"min": 5, "max": 500, "default": 100, "step": 10}}),
    (25, "spell.slowTime",
     "Slow Time",
     "Toggles a slow-time effect that drags everything around the actor to {param1}% of normal speed while active.",
     "Time speed % (lower = slower; 100 = normal)",
     {"param": {"min": 5, "max": 100, "default": 50, "step": 5}}),
    (26, "spell.flameCloak",
     "Flame Cloak",
     "Toggles a flame cloak that burns enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (27, "spell.frostCloak",
     "Frost Cloak",
     "Toggles a frost cloak that chills enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (28, "spell.lightningCloak",
     "Lightning Cloak",
     "Toggles a lightning cloak that shocks enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (29, "flash.onhit",
     "Flash",
     "Flashes the tattoo's emissive layer to {param2}% brightness on the chosen trigger event ({param1}).",
     "Trigger event",
     # v0.2.6: default 126 ("All combat classes"). Pre-fix this was 1 which
     # isn't a valid menu value (bit 0 is unused in the class mask). See
     # roadmap note "flash.onhit refactor candidate" for the longer-term
     # semantic inversion concern (0 = Disabled here vs 0 = Any in combat.hit).
     {"param":  {"min": 0, "max": 127, "default": 126,
                 "menu": FLASH_TRIGGER_MENU},
      "param2": {"label": "Peak emissive (additive, % of 1.0)",
                 "min": 0, "max": 1000, "default": 300, "step": 10},
      "extras": FLASH_ENVELOPE_EXTRAS_33}),
    (30, "modify.absorbChance",
     "Modify Spell Absorb",
     "Shifts the actor's chance to absorb incoming spells by {param1}%.",
     "Spell absorb chance shift (points; + absorb, - vulnerable)", None),
    (31, "modify.reflectDamage",
     "Modify Reflect Damage",
     "Shifts the actor's chance to reflect incoming melee damage by {param1}%.",
     "Reflect damage chance shift (points; + reflect, - vulnerable)", None),

    # Consolidated skill modifies (was 17 separate modify.<skillname>
    # entries, idx 38-54). param1 picks the Skyrim skill; param2 carries
    # the signed shift in skill points. Internal routing via
    # _skillAVForIdx in MTF_Plugin_Base.
    (32, "modify.skill",
     "Modify Skill",
     "Shifts the actor's {param1} skill by {param2} points.",
     "Skill",
     {"param":  {"label": "Skill", "min": 0, "max": len(SKILL_AV_MENU) - 1,
                 "default": 0,
                 "menu": SKILL_AV_MENU},
      "param2": {"label": "Skill shift (points; + buff, - drain)",
                 "min": -100, "max": 100, "default": 0}}),

    (33, "shader.play",
     "Vanilla Shader",
     "Plays the {param1} effect shader on the actor while active (duration {param2}s; 0 = until removed).",
     "Shader",
     {"param":  {"min": 0, "max": len(SHADERS) - 1, "default": 0,
                 "menu": [(_to_id(l), l) for l in SHADERS]},
      "param2": {"label": "Duration (s, 0 = until removed)",
                 "min": 0, "max": 60, "default": 0}}),
    (34, "sound.play",
     "Vanilla Sound",
     "Plays the {param1} looping sound on the actor while active (duration {param2}s; 0 = until removed).",
     "Sound",
     {"param":  {"min": 0, "max": len(SOUNDS) - 1, "default": 0,
                 "menu": [(_to_id(l), l) for l in SOUNDS]},
      "param2": {"label": "Duration (s, 0 = until removed)",
                 "min": 0, "max": 60, "default": 0},
      "extras": SOUND_VOLUME_EXTRAS}),

    # ── v0.4 additions (idx 35+) ───────────────────────────────────────────
    # Appended at idx 35+ to preserve the idx-keyed is_abs_shift / BASE_BURSTS
    # helpers (which only reference idx <= 31). These declare param ranges
    # EXPLICITLY rather than relying on the idx-based abs-shift backfill.
    # Runtime classification uses the eid-prefix _isAbsShift / _isToggle, so
    # modify.jumpHeight still routes through the generic abs-shift path with no
    # new dispatch branch — only an _avNameFor entry. burst.ragdoll / drain.*
    # get explicit branches in onActivate / onTick / onDeactivate. All pure
    # Papyrus — no new ESP records.
    (35, "modify.jumpHeight",
     "Modify Jump Height",
     "Shifts the actor's jump height by {param1} points (JumpingBonus actor value).",
     "Jump height shift (points; + higher, - lower)",
     {"param": {"min": -100, "max": 300, "default": 0}}),
    (36, "burst.ragdoll",
     "Ragdoll Burst",
     "Burst — knocks down every hostile within {param1}ft with force {param2} when the tier activates. Physical CC, no magic-resist check.",
     "Knockdown radius (feet)",
     {"param":  {"min": 3, "max": 300, "default": 25, "step": 5},
      "param2": {"label": "Knockback force", "min": 1, "max": 100, "default": 10}}),
    (37, "drain.health",
     "Drain Health",
     "Continuously drains {param1} health per second while the tier is active (separate from regen — drains current value).",
     "Health drain per second",
     {"param": {"min": 0, "max": 100, "default": 5}}),
    (38, "drain.magicka",
     "Drain Magicka",
     "Continuously drains {param1} magicka per second while the tier is active (separate from regen — drains current value).",
     "Magicka drain per second",
     {"param": {"min": 0, "max": 100, "default": 5}}),
    (39, "drain.stamina",
     "Drain Stamina",
     "Continuously drains {param1} stamina per second while the tier is active (separate from regen — drains current value).",
     "Stamina drain per second",
     {"param": {"min": 0, "max": 100, "default": 5}}),

    # ── On-hit retaliation (idx 40+, v0.4 idea #3) ─────────────────────────
    # "Your tattoo bites back." While the tier is active these store a per-
    # actor magnitude flag; MTF_HitListener.OnHit reads it and retaliates
    # against the aggressor. PLAYER-ONLY — the OnHit alias only fires for the
    # player (same limitation as flash.onhit's Papyrus path; NPC flash goes
    # through the C++ sink, but retaliation has no C++ equivalent yet). The
    # elemental rows reuse the existing cloak inner-damage spells (0x845/
    # 0x849/0x84D) via DoCombatSpellApply — real typed damage with resist
    # checks + vanilla impact FX, no new ESP records. Not bursts (persistent
    # flag, event-driven), not abs-shift (explicit param ranges).
    (40, "ragdoll.onhit",
     "Ragdoll on Hit",
     "Knocks the attacker down (force {param1}) whenever the actor is struck. Player-only.",
     "Knockback force",
     {"param": {"min": 1, "max": 100, "default": 15}}),
    (41, "damage.fireOnHit",
     "Fire Damage on Hit",
     "Deals {param1} fire damage back to the attacker whenever the actor is struck. Player-only.",
     "Fire damage to attacker",
     {"param": {"min": 0, "max": 200, "default": 15}}),
    (42, "damage.frostOnHit",
     "Frost Damage on Hit",
     "Deals {param1} frost damage back to the attacker whenever the actor is struck. Player-only.",
     "Frost damage to attacker",
     {"param": {"min": 0, "max": 200, "default": 15}}),
    (43, "damage.shockOnHit",
     "Shock Damage on Hit",
     "Deals {param1} shock damage back to the attacker whenever the actor is struck. Player-only.",
     "Shock damage to attacker",
     {"param": {"min": 0, "max": 200, "default": 15}}),
    # Ambient light: Light-archetype ability (SPEL 0x925 -> MGEF 0x924, both
    # FireAndForget; Light archetype associated to our LIGH 0x928; Hit-Effect-Art
    # 0x929 = our model-less AttachLight NIF). Lights the surroundings with NO
    # visible orb, parented to the actor's 3D so it follows smoothly. Radius /
    # brightness / colour are applied to the shared LIGH form at (re)cast via
    # po3 PapyrusExtender SetLightRadius/SetLightFade/SetLightRGB (soft dep —
    # falls back to the ESP defaults if po3 is absent).
    (44, "toggle.ambientLight",
     "Ambient Light",
     "Emits light around the actor (radius {param1}, brightness {param2}%, colour {param3}) while active. No visible source.",
     "Light radius",
     {"param":  {"label": "Light radius", "min": 64, "max": 1024, "default": 350, "step": 16},
      "param2": {"label": "Brightness (%)", "min": 10, "max": 200, "default": 100, "step": 5, "format": "{0}%"},
      "extras": [{"label": "Light colour", "color": True, "default": 0xFFFFFF}]}),
]
assert len(EFFECTS_RAW) == 45, f"expected 45 effects, got {len(EFFECTS_RAW)}"
# Sanity: indices contiguous 0..34.
for i, t in enumerate(EFFECTS_RAW):
    assert t[0] == i, f"effect tuple {i} has idx {t[0]}"

# ── Module split (v0.3.9) ─────────────────────────────────────────────────────
# The monolithic mtf.base pack is split into 5 themed plugins. Each becomes its
# own pluginid + catalog JSON + thin MTF_Plugin_Base subclass (GetPluginId-only;
# all dispatch is id-keyed and inherited unchanged). Slots store the pluginid by
# value, so this is a save-migrating change: tools/.../mtf.module_map.json (emitted
# below) maps every id → its new pluginid, and the Papyrus one-shot migrator
# rewrites any stored "mtf.base" reference to the new home. EFFECTS_RAW / CONDITIONS
# stay as single global lists (the idx-keyed is_abs_shift / BASE_BURSTS helpers
# depend on the original indices); only the OUTPUT is partitioned by module.
MODULES = [
    ("mtf.attributes", "Attributes & Skills"),
    ("mtf.combat",     "Combat"),
    ("mtf.magic",      "Magic"),
    ("mtf.world",      "World & Exploration"),
    ("mtf.fx",         "Visual & Sound"),
]
MODULE_LABELS = dict(MODULES)

CONDITION_MODULE = {
    # Attributes & Skills — vitals thresholds
    "magicka": "mtf.attributes", "magicka.below": "mtf.attributes",
    "stamina": "mtf.attributes", "stamina.below": "mtf.attributes",
    "health":  "mtf.attributes", "health.below":  "mtf.attributes",
    # Combat — combat triggers + worn armour gear
    "combat.in": "mtf.combat", "combat.alerted": "mtf.combat",
    "combat.hostile": "mtf.combat", "combat.hit": "mtf.combat",
    "combat.casting": "mtf.combat", "state.weaponDrawn": "mtf.combat",
    "worn.heavyArmor": "mtf.combat", "worn.lightArmor": "mtf.combat",
    # Magic — "under a magic effect" afflictions + Dragonborn/voice (Thu'um
    # and dragon souls read as supernatural, so they live with the magic set).
    "magiceffect.kw.fire": "mtf.magic", "magiceffect.kw.frost": "mtf.magic",
    "magiceffect.kw.shock": "mtf.magic", "magiceffect.kw.invisibility": "mtf.magic",
    "shout.cooldown": "mtf.magic", "shout.equipped": "mtf.magic",
    "dragonsoul.unspent": "mtf.magic", "dragonsoul.absorbed": "mtf.magic",
    "shout.learned": "mtf.magic", "word.unlocked": "mtf.magic",
    # World & Exploration — environment, social/economy, body states
    "location.kw": "mtf.world", "weather": "mtf.world", "time.range": "mtf.world",
    "faction.playerFollower": "mtf.world", "followers.any": "mtf.world",
    "gold.aboveThousand": "mtf.world",
    "state.sprinting": "mtf.world", "state.running": "mtf.world",
    "state.sneaking": "mtf.world", "state.swimming": "mtf.world",
    "state.mounted": "mtf.world", "state.bleedingOut": "mtf.world",
    "state.loversEmbrace": "mtf.world",
}

EFFECT_MODULE = {
    # Attributes & Skills — body stats, regen, vitals bursts, skills
    "modify.magickaRegen": "mtf.attributes", "modify.staminaRegen": "mtf.attributes",
    "modify.healthRegen": "mtf.attributes", "modify.maxMagicka": "mtf.attributes",
    "modify.maxStamina": "mtf.attributes", "modify.carryWeight": "mtf.attributes",
    "modify.movementSpeed": "mtf.attributes", "modify.skill": "mtf.attributes",
    "modify.jumpHeight": "mtf.attributes",
    "damage.health": "mtf.attributes", "damage.magicka": "mtf.attributes",
    "damage.stamina": "mtf.attributes",
    # Attributes & Skills — continuous vitals drains (sit with the damage.*
    # bursts; both bleed a current AV rather than shifting a cap/regen).
    "drain.health": "mtf.attributes", "drain.magicka": "mtf.attributes",
    "drain.stamina": "mtf.attributes",
    # Combat — martial offense
    "modify.attackDamage": "mtf.combat", "modify.weaponSpeed": "mtf.combat",
    "modify.unarmedDamage": "mtf.combat", "modify.bowSpeed": "mtf.combat",
    "modify.criticalChance": "mtf.combat", "burst.stagger": "mtf.combat",
    "burst.ragdoll": "mtf.combat",
    # Combat — on-hit retaliation (idea #3)
    "ragdoll.onhit": "mtf.combat", "damage.fireOnHit": "mtf.combat",
    "damage.frostOnHit": "mtf.combat", "damage.shockOnHit": "mtf.combat",
    # Magic — ability-spell-backed effects
    "spell.flameCloak": "mtf.magic", "spell.frostCloak": "mtf.magic",
    "spell.lightningCloak": "mtf.magic", "spell.detectLife": "mtf.magic",
    "spell.slowTime": "mtf.magic", "spell.modifyArmor": "mtf.magic",
    "modify.resist": "mtf.magic", "modify.absorbChance": "mtf.magic",
    "modify.reflectDamage": "mtf.magic", "scale.magickaCost": "mtf.magic",
    "toggle.muffle": "mtf.magic", "toggle.waterbreathing": "mtf.magic",
    "toggle.waterWalking": "mtf.magic", "toggle.ambientLight": "mtf.magic",
    # World & Exploration — crime/stealth utility
    "burst.blowCover": "mtf.world", "burst.bounty": "mtf.world",
    # Visual & Sound — cosmetic
    "flash.onhit": "mtf.fx", "shader.play": "mtf.fx", "sound.play": "mtf.fx",
}

# Every catalog id must be assigned to exactly one known module.
_known = {m for m, _ in MODULES}
for _cid, _t in [(t[0], t) for t in CONDITIONS]:
    assert _cid in CONDITION_MODULE, f"condition {_cid!r} has no module"
    assert CONDITION_MODULE[_cid] in _known, f"condition {_cid!r} → unknown module"
for _e in EFFECTS_RAW:
    _eid = _e[1]
    assert _eid in EFFECT_MODULE, f"effect {_eid!r} has no module"
    assert EFFECT_MODULE[_eid] in _known, f"effect {_eid!r} → unknown module"


def _build_param(p_src):
    """Build one paramN block from a source dict. v0.2.9: menu params emit
    {id, label} per option (drops `value`), drop `min`/`max` (no longer
    meaningful), and default becomes the matching id string. Sliders
    unchanged."""
    out = {}
    if "label" in p_src:
        out["label"] = p_src["label"]
    # Color picker param (v0.4.x): stored as an int 0xRRGGBB, rendered via
    # SkyUI's AddColorOptionST swatch. Mutually exclusive with menu/text/slider
    # fields — no min/max/step/menu apply.
    if p_src.get("color"):
        out["color"] = 1
        out["default"] = p_src.get("default", 0xFFFFFF)
        return out
    is_menu = "menu" in p_src
    if is_menu:
        # Menu params: emit each option as {id, label}. `menu` source may be
        # a list of (id, label) tuples OR already-shaped dicts.
        menu_out = []
        for opt in p_src["menu"]:
            if isinstance(opt, tuple):
                opt_id, opt_label = opt
                menu_out.append({"id": opt_id, "label": opt_label})
            else:
                # Already a dict; pass through (idempotent regeneration).
                menu_out.append({"id": opt["id"], "label": opt["label"]})
        out["menu"] = menu_out
        # Default for menu params is an id string. If source supplies an id,
        # use it; if it supplies an int (legacy authoring), translate.
        if "default" in p_src:
            dv = p_src["default"]
            if isinstance(dv, str):
                out["default"] = dv
            else:
                # Legacy int default: translate to id by position. This path
                # only fires if the source data table still has int defaults
                # — once converted to id strings, the lookup is a no-op.
                out["default"] = menu_out[dv]["id"] if 0 <= dv < len(menu_out) else menu_out[0]["id"]
        # No min/max/step on menu params (dropped in v0.2.9).
    else:
        # Slider: implicit defaults are 0..100 with default 0 for conditions
        # / -100..100 default 0 for abs-shift effects (caller handles the
        # effect-side backfill via is_abs_shift).
        out["min"]     = p_src.get("min", 0)
        out["max"]     = p_src.get("max", 100)
        out["default"] = p_src.get("default", 0)
        if "step" in p_src:
            out["step"] = p_src["step"]
        if "format" in p_src:
            out["format"] = p_src["format"]
    return out


def build_condition(idx, t):
    """Assemble one condition entry. v0.2.6: implicit min/max/default backfill
    for sliders. v0.2.9: menu params emit id-based options."""
    cid, label, desc, param = t
    out = {"id": cid, "label": label, "description": desc}
    if param is not None:
        out["param"] = _build_param(param)
        if "_param2" in param:
            out["param2"] = _build_param(param["_param2"])
    return out


def build_effect(idx, t):
    """Assemble one effect entry in the v0.2.1+ uniform paramN schema.

    Each effect declares up to 5 numbered params (param1..param5). All optional;
    the framework probes paramN.label and renders/dispatches only the ones
    declared. The previous schema had asymmetric `param`/`param2`/`extras[]`
    triplet — collapsed for uniformity.

    For Base specifically, params map positionally:
      param1 = the "param" slider (slider/menu)
      param2 = the optional second slider (cloak radius, flash peak, etc)
      param3..param5 = former extras (envelope timings on flash, volume on sound)
    Fills in abs-shift defaults for the majority of effects (-100..100, default
    0, step 1) on param1.
    """
    eidx, eid, label, desc, param_label, overrides = t
    out = {"id": eid, "label": label, "description": desc}

    # Burst effects fire once on activate; continuous is the default and the
    # field is omitted (MTF_Plugin.GetEffectKind returns "continuous" when
    # absent). Bursts get the "[!]" badge prepended by MCM at render time.
    if eidx in BASE_BURSTS:
        out["kind"] = "burst"

    overrides = overrides or {}
    param_o   = overrides.get("param", {})
    param2_o  = overrides.get("param2")
    extras_o  = overrides.get("extras") or []

    # ── param1 (primary slider/menu) ───────────────────────────────────────
    # Build a source dict from param_label + overrides, then route through
    # _build_param so menu-bearing params get the id-based shape (v0.2.9).
    src = dict(param_o)
    if param_label and "label" not in src:
        src["label"] = param_label
    # Abs-shift effects (~half the catalog) get implicit -100..100/0 defaults.
    if is_abs_shift(eidx) and "menu" not in src:
        src.setdefault("min", -100)
        src.setdefault("max", 100)
        src.setdefault("default", 0)
    if src:
        out["param1"] = _build_param(src)

    # ── param2 (optional second slider/menu) ───────────────────────────────
    if param2_o is not None:
        # Strip any legacy `name` key — meaningless under positional schema.
        p2_src = {k: v for k, v in param2_o.items() if k != "name"}
        out["param2"] = _build_param(p2_src)

    # ── param3..param5 (former extras, now positional) ─────────────────────
    # extras were authored as [{name, label, min, max, step, default, menu}].
    # Under the uniform schema the `name` field is dropped — the position
    # IS the name. Plugin behaviour code reads them by index via
    # host.GetSlotEffectParam(slot, eff, n) for n in {3,4,5}.
    for i, ex in enumerate(extras_o):
        n = i + 3
        if n > 5:
            raise ValueError(f"effect idx {eidx} has more than 3 extras")
        ex_src = {k: v for k, v in ex.items() if k != "name"}
        out[f"param{n}"] = _build_param(ex_src)

    return out


def main():
    # Build every entry once from the global lists (preserves the idx-keyed
    # is_abs_shift / BASE_BURSTS backfill), then bucket by module.
    all_conditions = [(t[0], build_condition(i, t)) for i, t in enumerate(CONDITIONS)]
    all_effects    = [(t[1], build_effect(i, t))    for i, t in enumerate(EFFECTS_RAW)]

    PLUGINS_DIR.mkdir(parents=True, exist_ok=True)

    for pid, label in MODULES:
        conds = [c for cid, c in all_conditions if CONDITION_MODULE[cid] == pid]
        effs  = [e for eid, e in all_effects    if EFFECT_MODULE[eid]    == pid]
        catalog = {
            # schema 2 — see tools/migrate_to_string_ids.py history. v0.3.9
            # split the monolithic mtf.base into themed modules.
            "schemaversion": 2,
            "pluginid": pid,
            "pluginlabel": label,
            "conditions": conds,
            "effects":    effs,
        }
        out = PLUGINS_DIR / f"{pid}.json"
        with open(out, "w", encoding="utf-8") as f:
            json.dump(catalog, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"Wrote {out}  (conditions: {len(conds)}, effects: {len(effs)})")

    # Migration map for the Papyrus one-shot migrator + preset remapper: every
    # id → new pluginid. Written in PapyrusUtil's TYPE-GROUPED JsonUtil format
    # ({"string": {...}}) so the migrator reads each entry by KEY via
    # JsonUtil.GetStringValue(file, "cond:<id>"/"eff:<id>", "") — keys are dot-
    # safe (only JsonUtil *paths* split on dots; keys do not). cond:/eff: prefix
    # keeps the two namespaces distinct. The "_comment" key is ignored by
    # GetStringValue (never queried). The Python preset remapper reads the same
    # file. Single source of truth for the v0.3.9 mtf.base → module split.
    # CRITICAL: keys are LOWERCASED. PapyrusUtil JsonUtil lowercases stored
    # keys on load, so a camelCase key like "eff:modify.magickaRegen" can never
    # be matched by GetStringValue (the query "eff:modify.magickaRegen" misses
    # the lowercased store and silently returns the default). The Papyrus reader
    # (_remapBaseKey) lowercases its lookup key to match. The id VALUES in the
    # catalogs stay camelCase — only this map's KEYS are lowercased. See memory
    # note project_papyrusutil_lowercase. Asserts no case-collision below.
    strings = {"_comment": "v0.3.9 mtf.base split → themed modules; key = "
                           "cond:<id> / eff:<id> (LOWERCASED — JsonUtil "
                           "lowercases keys), value = new pluginid."}
    for cid, mod in sorted(CONDITION_MODULE.items()):
        k = f"cond:{cid}".lower()
        assert k not in strings, f"lowercased key collision: {k!r}"
        strings[k] = mod
    for eid, mod in sorted(EFFECT_MODULE.items()):
        k = f"eff:{eid}".lower()
        assert k not in strings, f"lowercased key collision: {k!r}"
        strings[k] = mod
    mig = {"string": strings}
    # One level up from plugins/ so the per-catalog validator (which scans
    # plugins/*.json) doesn't treat the map as a malformed catalog.
    mig_out = PLUGINS_DIR.parent / "mtf.module_map.json"
    with open(mig_out, "w", encoding="utf-8") as f:
        json.dump(mig, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Wrote {mig_out}  (map: {len(CONDITION_MODULE)} conds, "
          f"{len(EFFECT_MODULE)} effects)")


if __name__ == "__main__":
    main()
