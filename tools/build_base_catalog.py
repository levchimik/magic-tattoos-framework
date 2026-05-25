#!/usr/bin/env python3
"""Build mtf.base.json — the metadata catalog for MTF_Plugin_Base.

This script mirrors the dispatch logic that used to live in MTF_Plugin_Base.psc's
Get*() metadata getters, producing a JSON file consumed by the JsonUtil-driven
base class (MTF_Plugin.psc). One source of truth; re-run after any catalog
change.

Run:  python3 tools/build_base_catalog.py
Out:  data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.base.json

The numbers in this file MUST stay in sync with the Papyrus-side helpers that
remain in MTF_Plugin_Base.psc (the behaviour code that runs in onActivate /
onDeactivate / onTick): _isAbsShift, _isToggle, _isBurstAV, _avNameFor,
_shaderFormId, _soundFormId, _resolveResistSpell, etc. If you add or remove
an effect, update both this script AND the matching Papyrus helper.
"""

import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "data" / "SKSE" / "Plugins" / \
    "StorageUtilData" / "MagicTattoosFramework" / "plugins" / "mtf.base.json"

# ── Helpers mirroring the Papyrus dispatch ────────────────────────────────────
def is_abs_shift(idx: int) -> bool:
    """Mirrors MTF_Plugin_Base._isAbsShift. Signed AV-point shifts; default
    range -100..100, default 0, slider unit = 'points'/'%'.

    NOTE: this applies the default to param1 only. Effects that put the
    signed shift on param2 (modify.resist, modify.skill) are NOT in this
    set — they specify min/max/default on the param2 override explicitly.
    """
    return (idx <= 2 or (5 <= idx <= 7) or (11 <= idx <= 17) or (31 <= idx <= 32))


# Idxes of burst-kind effects in Base — fires once on activate, no rolling
# state. Continuous is the default (kind field omitted in JSON). MCM
# prepends a "[!] " badge automatically for kind == burst at render time —
# don't put the prefix in labels here.
BASE_BURSTS = {3, 4, 8, 9, 22, 23}

# Hit class enum for the combat.hit condition's param1 dropdown. Values
# match _checkHit's classIdx in MTF_Plugin_Base — host-side hit counters
# are keyed on the same int. Pre-v0.2.5 used 7 separate combat.hit.*
# conditions; consolidated to mirror the FLASH_TRIGGER_MENU pattern.
HIT_CLASS_MENU = [
    (0, "Any"),
    (1, "Blunt"),
    (2, "Bladed"),
    (3, "Ranged"),
    (4, "Fire"),
    (5, "Frost"),
    (6, "Shock"),
]
assert len(HIT_CLASS_MENU) == 7

# Location keyword enum for the location.kw condition's param1 dropdown.
# Values map to Skyrim location keyword form IDs in _locKwByIdx (Base).
# Pre-v0.2.5 used 6 separate location.{playerHome,dungeon,city,town,inn,jail}.
LOCATION_KW_MENU = [
    (0, "Player Home"),
    (1, "Dungeon"),
    (2, "City"),
    (3, "Town"),
    (4, "Inn"),
    (5, "Jail"),
]
assert len(LOCATION_KW_MENU) == 6

# Weather class enum for the weather condition's param1 dropdown.
# Values match Weather.GetClassification (0=pleasant, 1=cloudy, 2=rainy,
# 3=snowy). Pre-v0.2.5 used 4 separate weather.* conditions.
WEATHER_MENU = [
    (0, "Pleasant"),
    (1, "Cloudy"),
    (2, "Rainy"),
    (3, "Snowy"),
]
assert len(WEATHER_MENU) == 4

# Resist type enum for the modify.resist effect's param1 dropdown.
# Values are arbitrary stable ints; the Base script maps them to the
# resist Ability spells in MagicTattoosFramework.esp via
# _resolveResistSpellByIdx. Pre-v0.2.5 used 6 separate modify.resist*
# effects keyed by element name in the eid.
RESIST_TYPE_MENU = [
    (0, "Fire"),
    (1, "Frost"),
    (2, "Shock"),
    (3, "Magic"),
    (4, "Disease"),
    (5, "Poison"),
]
assert len(RESIST_TYPE_MENU) == 6

# Skill AV enum for the modify.skill effect's param1 dropdown.
# Values 0..16 stable; the Base script maps each to the Skyrim AV name
# via _skillAVForIdx. Pre-v0.2.5 used 17 separate modify.<skillname>
# effects. AV names follow the Marksman/Speechcraft Morrowind-holdover
# quirks (see _avNameFor docstring).
SKILL_AV_MENU = [
    (0,  "One-Handed"),
    (1,  "Two-Handed"),
    (2,  "Archery"),
    (3,  "Block"),
    (4,  "Heavy Armor"),
    (5,  "Light Armor"),
    (6,  "Smithing"),
    (7,  "Enchanting"),
    (8,  "Alchemy"),
    (9,  "Destruction"),
    (10, "Restoration"),
    (11, "Alteration"),
    (12, "Illusion"),
    (13, "Conjuration"),
    (14, "Speech"),
    (15, "Lockpicking"),
    (16, "Pickpocket"),
]
assert len(SKILL_AV_MENU) == 17

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
      "menu": [{"value": v, "label": l} for v, l in HIT_CLASS_MENU],
      "_param2": {"label": "Chance % per hit", "min": 1, "max": 100, "default": 25}}),
    # Health %
    ("health",       "Above Health %",
     "Triggers when the actor's health is at or above {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 50}),
    ("health.below", "Below Health %",
     "Triggers when the actor's health drops below {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 30}),
    # Location — indoors/outdoors stay separate (engine cell check, not
    # keyword based). The 6 keyword-based location types are consolidated
    # under location.kw with a dropdown.
    ("location.indoors",    "Indoors",
     "Triggers whenever the actor is inside any interior cell.", None),
    ("location.outdoors",   "Outdoors",
     "Triggers whenever the actor is in an exterior worldspace.", None),
    ("location.kw", "Location",
     "Triggers when the actor is inside a {param1}-flagged location.",
     {"label": "Location type", "min": 0, "max": 5, "default": 0,
      "menu": [{"value": v, "label": l} for v, l in LOCATION_KW_MENU]}),
    # Weather — single entry with classification dropdown.
    ("weather", "Weather",
     "Triggers when the current weather class is {param1}.",
     {"label": "Weather class", "min": 0, "max": 3, "default": 0,
      "menu": [{"value": v, "label": l} for v, l in WEATHER_MENU]}),
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
]
assert len(CONDITIONS) == 33, f"expected 33 conditions, got {len(CONDITIONS)}"

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
# value column is the int classMask stored on the slot; _classMaskToTags
# in Papyrus maps it to the C++ tag CSV.
FLASH_TRIGGER_MENU = [
    (0,   "Disabled"),
    (2,   "Blunt only"),
    (4,   "Bladed only"),
    (8,   "Ranged only"),
    (16,  "Fire only"),
    (32,  "Frost only"),
    (64,  "Shock only"),
    (6,   "Melee (Blunt + Bladed)"),
    (14,  "Physical (Blunt + Bladed + Ranged)"),
    (112, "Magic (Fire + Frost + Shock)"),
    (126, "All combat classes"),
    (128, "On spell cast"),
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
    (2,  "modify.sneak",
     "Modify Sneak",
     "Shifts the actor's Sneak skill by {param1}.",
     "Sneak skill shift (points; + buff, - drain)", None),
    (3,  "damage.magicka",
     "Damage Magicka",
     "Burst — damages or restores {param1}% of the actor's base magicka when the tier activates.",
     "Burst % of base Magicka (+ restore, - damage)",
     {"param": {"min": -100, "max": 100, "default": 0}}),
    (4,  "damage.stamina",
     "Damage Stamina",
     "Burst — damages or restores {param1}% of the actor's base stamina when the tier activates.",
     "Burst % of base Stamina (+ restore, - damage)",
     {"param": {"min": -100, "max": 100, "default": 0}}),
    (5,  "modify.movementSpeed",
     "Modify Movement Speed",
     "Shifts the actor's movement-speed multiplier by {param1}%.",
     "Movement speed shift (mult points; + faster, - slower)", None),
    (6,  "modify.staminaRegen",
     "Modify Stamina Regen",
     "Shifts the actor's stamina regeneration rate by {param1}%.",
     "Stamina regen rate shift (mult points; + faster, - slower)", None),
    (7,  "modify.attackDamage",
     "Modify Attack Damage",
     "Shifts the actor's outgoing attack damage by {param1}%.",
     "Attack damage shift (% points; + buff, - drain)", None),
    (8,  "burst.stagger",
     "Stagger",
     "Burst — staggers the actor when the tier activates.",
     "", None),
    (9,  "burst.blowCover",
     "Blow Cover",
     "Burst — alerts every hostile NPC within {param1}ft to the actor's presence (blows stealth).",
     "Alert radius (feet)",
     {"param": {"min": 5, "max": 300, "default": 80, "step": 5}}),
    (10, "scale.magickaCost",
     "Scale Magicka Cost",
     "Spells cost {param1}% of their original across all schools.",
     "Spell cost (% of original)",
     {"param": {"min": 0, "max": 400, "default": 100, "step": 5}}),
    (11, "modify.healthRegen",
     "Modify Health Regen",
     "Shifts the actor's health regeneration rate by {param1}%.",
     "Health regen rate shift (mult points; + faster, - slower)", None),
    (12, "modify.maxMagicka",
     "Modify Max Magicka",
     "Shifts the actor's maximum magicka by {param1}.",
     "Max magicka shift (points; + buff, - drain)", None),
    (13, "modify.maxStamina",
     "Modify Max Stamina",
     "Shifts the actor's maximum stamina by {param1}.",
     "Max stamina shift (points; + buff, - drain)", None),
    (14, "modify.weaponSpeed",
     "Modify Weapon Speed",
     "Shifts the actor's weapon-swing speed by {param1}%.",
     "Weapon speed shift (% points; + faster, - slower)", None),
    (15, "modify.unarmedDamage",
     "Modify Unarmed Damage",
     "Shifts the actor's unarmed melee damage by {param1}.",
     "Unarmed damage shift (points; + buff, - drain)", None),
    (16, "modify.criticalChance",
     "Modify Critical Chance",
     "Shifts the actor's critical-strike chance by {param1}%.",
     "Critical chance shift (points; + buff, - drain)", None),
    (17, "modify.bowSpeed",
     "Modify Bow Speed",
     "Shifts the actor's bow draw and release speed by {param1}.",
     "Bow speed bonus shift (units; + faster draw, - slower)", None),

    # Consolidated resists (was 6 separate modify.resist* entries, idx
    # 18-21 + 34-35). param1 picks the resist type; param2 carries the
    # signed shift in resist points. Internal routing via
    # _resolveResistSpellByIdx in MTF_Plugin_Base.
    (18, "modify.resist",
     "Modify Resist",
     "Shifts the actor's {param1} resistance by {param2} points.",
     "Resist type",
     {"param":  {"label": "Resist type", "min": 0, "max": 5, "default": 0,
                 "menu": [{"value": v, "label": l} for v, l in RESIST_TYPE_MENU]},
      "param2": {"label": "Resist shift (points; + resist, - weakness)",
                 "min": -100, "max": 100, "default": 0}}),

    # Toggles (engine-managed AVs that need ability-spell routing).
    (19, "toggle.muffle",
     "Muffle",
     "Toggles silenced footsteps on the actor while active.",
     "", None),
    (20, "toggle.waterbreathing",
     "Waterbreathing",
     "Toggles waterbreathing on the actor while active.",
     "", None),
    (21, "toggle.waterWalking",
     "Water Walking",
     "Toggles water-walking on the actor while active.",
     "", None),
    (22, "damage.health",
     "Damage Health",
     "Burst — damages or restores {param1}% of the actor's base health when the tier activates.",
     "Burst % of base Health (+ restore, - damage)",
     {"param": {"min": -100, "max": 100, "default": 0}}),
    (23, "burst.bounty",
     "Add Bounty",
     "Burst — adjusts the actor's bounty in their current hold by {param1} gold (positive adds, negative pays off).",
     "Bounty change (gold; + add, - remove)",
     {"param": {"min": -10000, "max": 10000, "default": 0, "step": 50}}),
    (24, "spell.modifyArmor",
     "Modify Armor",
     "Toggles a flat armor-rating bonus of {param1} while active.",
     "Armor rating points",
     {"param": {"min": 0, "max": 500, "default": 100, "step": 10}}),
    (25, "spell.detectLife",
     "Detect Life",
     "Toggles a Detect Life aura that highlights living NPCs within {param1}ft while active.",
     "Detect radius (feet)",
     {"param": {"min": 5, "max": 500, "default": 100, "step": 10}}),
    (26, "spell.slowTime",
     "Slow Time",
     "Toggles a slow-time effect that drags everything around the actor to {param1}% of normal speed while active.",
     "Time speed % (lower = slower; 100 = normal)",
     {"param": {"min": 5, "max": 100, "default": 50, "step": 5}}),
    (27, "spell.flameCloak",
     "Flame Cloak",
     "Toggles a flame cloak that burns enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (28, "spell.frostCloak",
     "Frost Cloak",
     "Toggles a frost cloak that chills enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (29, "spell.lightningCloak",
     "Lightning Cloak",
     "Toggles a lightning cloak that shocks enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (30, "flash.onhit",
     "Flash",
     "Flashes the tattoo's emissive layer to {param2}% brightness on the chosen trigger event ({param1}).",
     "Trigger event",
     # v0.2.6: default 126 ("All combat classes"). Pre-fix this was 1 which
     # isn't a valid menu value (bit 0 is unused in the class mask). See
     # roadmap note "flash.onhit refactor candidate" for the longer-term
     # semantic inversion concern (0 = Disabled here vs 0 = Any in combat.hit).
     {"param":  {"min": 0, "max": 127, "default": 126,
                 "menu": [{"value": v, "label": l} for v, l in FLASH_TRIGGER_MENU]},
      "param2": {"label": "Peak emissive (additive, % of 1.0)",
                 "min": 0, "max": 1000, "default": 300, "step": 10},
      "extras": FLASH_ENVELOPE_EXTRAS_33}),
    (31, "modify.absorbChance",
     "Modify Spell Absorb",
     "Shifts the actor's chance to absorb incoming spells by {param1}%.",
     "Spell absorb chance shift (points; + absorb, - vulnerable)", None),
    (32, "modify.reflectDamage",
     "Modify Reflect Damage",
     "Shifts the actor's chance to reflect incoming melee damage by {param1}%.",
     "Reflect damage chance shift (points; + reflect, - vulnerable)", None),

    # Consolidated skill modifies (was 17 separate modify.<skillname>
    # entries, idx 38-54). param1 picks the Skyrim skill; param2 carries
    # the signed shift in skill points. Internal routing via
    # _skillAVForIdx in MTF_Plugin_Base.
    (33, "modify.skill",
     "Modify Skill",
     "Shifts the actor's {param1} skill by {param2} points.",
     "Skill",
     {"param":  {"label": "Skill", "min": 0, "max": 16, "default": 0,
                 "menu": [{"value": v, "label": l} for v, l in SKILL_AV_MENU]},
      "param2": {"label": "Skill shift (points; + buff, - drain)",
                 "min": -100, "max": 100, "default": 0}}),

    (34, "shader.play",
     "Vanilla Shader",
     "Plays the {param1} effect shader on the actor while active (duration {param2}s; 0 = until removed).",
     "Shader",
     {"param":  {"min": 0, "max": len(SHADERS) - 1, "default": 0,
                 "menu": [{"value": i, "label": l} for i, l in enumerate(SHADERS)]},
      "param2": {"label": "Duration (s, 0 = until removed)",
                 "min": 0, "max": 60, "default": 0}}),
    (35, "sound.play",
     "Vanilla Sound",
     "Plays the {param1} looping sound on the actor while active (duration {param2}s; 0 = until removed).",
     "Sound",
     {"param":  {"min": 0, "max": len(SOUNDS) - 1, "default": 0,
                 "menu": [{"value": i, "label": l} for i, l in enumerate(SOUNDS)]},
      "param2": {"label": "Duration (s, 0 = until removed)",
                 "min": 0, "max": 60, "default": 0},
      "extras": SOUND_VOLUME_EXTRAS}),
]
assert len(EFFECTS_RAW) == 36, f"expected 36 effects, got {len(EFFECTS_RAW)}"
# Sanity: indices contiguous 0..35.
for i, t in enumerate(EFFECTS_RAW):
    assert t[0] == i, f"effect tuple {i} has idx {t[0]}"


def build_condition(idx, t):
    """Assemble one condition entry.

    v0.2.6: backfills implicit min=0/max=100/default=0 for numeric (non-menu)
    params so the catalog is fully spec'd for downstream validators. The
    base-class runtime treats missing values as these defaults — making them
    explicit costs nothing and lets `tools/validate_catalogs.py` stay strict.
    """
    cid, label, desc, param = t
    out = {"id": cid, "label": label, "description": desc}
    if param is not None:
        p = {}
        if "label"   in param: p["label"]   = param["label"]
        is_menu = "menu" in param
        # Numeric (non-menu) condition params: implicit defaults are 0..100, default 0.
        if not is_menu:
            p["min"]     = param.get("min", 0)
            p["max"]     = param.get("max", 100)
            p["default"] = param.get("default", 0)
        else:
            if "min"     in param: p["min"]     = param["min"]
            if "max"     in param: p["max"]     = param["max"]
            if "default" in param: p["default"] = param["default"]
            p["menu"] = param["menu"]
        if "step" in param: p["step"] = param["step"]
        out["param"] = p
        if "_param2" in param:
            # Recursively backfill for param2 too (currently only time.range uses this).
            p2_src = param["_param2"]
            p2 = {}
            if "label" in p2_src: p2["label"] = p2_src["label"]
            p2_menu = "menu" in p2_src
            if not p2_menu:
                p2["min"]     = p2_src.get("min", 0)
                p2["max"]     = p2_src.get("max", 100)
                p2["default"] = p2_src.get("default", 0)
            else:
                if "min"     in p2_src: p2["min"]     = p2_src["min"]
                if "max"     in p2_src: p2["max"]     = p2_src["max"]
                if "default" in p2_src: p2["default"] = p2_src["default"]
                p2["menu"] = p2_src["menu"]
            if "step" in p2_src: p2["step"] = p2_src["step"]
            out["param2"] = p2
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
    p = {}
    if param_label:
        p["label"] = param_label
    # For abs-shift effects backfill min=-100, max=100, default=0 so the
    # catalog is fully spec'd for validators. v0.2.6: previously only min
    # was written explicitly and max/default relied on runtime defaults —
    # making them explicit costs nothing and clears validate_catalogs.py.
    if is_abs_shift(eidx):
        p.setdefault("min", -100)
        p.setdefault("max", 100)
        p.setdefault("default", 0)
    for k in ("min", "max", "default", "step"):
        if k in param_o:
            p[k] = param_o[k]
    if "menu" in param_o:
        p["menu"] = param_o["menu"]
    if p:
        out["param1"] = p

    # ── param2 (optional second slider/menu) ───────────────────────────────
    if param2_o is not None:
        # Strip any legacy `name` key — meaningless under positional schema.
        p2 = {k: v for k, v in param2_o.items() if k != "name"}
        out["param2"] = p2

    # ── param3..param5 (former extras, now positional) ─────────────────────
    # extras were authored as [{name, label, min, max, step, default, menu}].
    # Under the uniform schema the `name` field is dropped — the position
    # IS the name. Plugin behaviour code reads them by index via
    # host.GetSlotEffectParam(slot, eff, n) for n in {3,4,5}.
    for i, ex in enumerate(extras_o):
        n = i + 3
        if n > 5:
            raise ValueError(f"effect idx {eidx} has more than 3 extras")
        pN = {k: v for k, v in ex.items() if k != "name"}
        out[f"param{n}"] = pN

    return out


def main():
    catalog = {
        "schemaversion": 1,
        "pluginid": "mtf.base",
        "pluginlabel": "Base",
        "conditions": [build_condition(i, t) for i, t in enumerate(CONDITIONS)],
        "effects":    [build_effect(i, t)    for i, t in enumerate(EFFECTS_RAW)],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Wrote {OUT}")
    print(f"  conditions: {len(catalog['conditions'])}")
    print(f"  effects:    {len(catalog['effects'])}")


if __name__ == "__main__":
    main()
