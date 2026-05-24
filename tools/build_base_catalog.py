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
    range -100..100, default 0, slider unit = 'points'/'%'."""
    return (idx <= 2 or (5 <= idx <= 7) or (11 <= idx <= 21) or (34 <= idx <= 54))

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
    # On-hit (7-13)
    ("combat.hit",        "On Hit (Any)",
     "Triggers with a {param1}% chance per incoming hit (any type).",
     {"label": "Chance % per hit", "min": 1, "default": 25}),
    ("combat.hit.blunt",  "On Hit (Blunt: mace/warhammer/fist)",
     "Triggers with a {param1}% chance per blunt-weapon hit (mace, warhammer, unarmed).",
     {"label": "Chance % per hit", "min": 1, "default": 25}),
    ("combat.hit.bladed", "On Hit (Bladed)",
     "Triggers with a {param1}% chance per bladed-weapon hit.",
     {"label": "Chance % per hit", "min": 1, "default": 25}),
    ("combat.hit.ranged", "On Hit (Ranged)",
     "Triggers with a {param1}% chance per ranged hit (arrow or bolt).",
     {"label": "Chance % per hit", "min": 1, "default": 25}),
    ("combat.hit.magic.fire",  "On Hit (Fire)",
     "Triggers with a {param1}% chance per fire-school damage hit.",
     {"label": "Chance % per hit", "min": 1, "default": 25}),
    ("combat.hit.magic.frost", "On Hit (Frost)",
     "Triggers with a {param1}% chance per frost-school damage hit.",
     {"label": "Chance % per hit", "min": 1, "default": 25}),
    ("combat.hit.magic.shock", "On Hit (Shock)",
     "Triggers with a {param1}% chance per shock-school damage hit.",
     {"label": "Chance % per hit", "min": 1, "default": 25}),
    # Health %
    ("health",       "Above Health %",
     "Triggers when the actor's health is at or above {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 50}),
    ("health.below", "Below Health %",
     "Triggers when the actor's health drops below {param1}%.",
     {"label": "Health/Magicka/Stamina % threshold", "default": 30}),
    # Location (16-23)
    ("location.indoors",    "Indoors",
     "Triggers whenever the actor is inside any interior cell.", None),
    ("location.outdoors",   "Outdoors",
     "Triggers whenever the actor is in an exterior worldspace.", None),
    ("location.playerHome", "In Player Home",
     "Triggers when the actor is inside a location flagged as the player's home.", None),
    ("location.dungeon",    "In Dungeon",
     "Triggers when the actor is inside a dungeon-type location.", None),
    ("location.city",       "In City",
     "Triggers when the actor is inside a city worldspace (Whiterun, Solitude, etc.).", None),
    ("location.town",       "In Town",
     "Triggers when the actor is inside a town-type location.", None),
    ("location.inn",        "In Inn",
     "Triggers when the actor is inside an inn or tavern.", None),
    ("location.jail",       "In Jail",
     "Triggers when the actor is held in a jail cell.", None),
    # Weather (24-27)
    ("weather.pleasant", "Weather: Clear / Sunny",
     "Triggers when the current weather is clear or sunny.", None),
    ("weather.cloudy",   "Weather: Cloudy",
     "Triggers when the current weather is cloudy.", None),
    ("weather.rainy",    "Weather: Rainy",
     "Triggers when the current weather is rainy.", None),
    ("weather.snowy",    "Weather: Snowy",
     "Triggers when the current weather is snowy.", None),
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
assert len(CONDITIONS) == 47, f"expected 47 conditions, got {len(CONDITIONS)}"

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

# Extras envelope used by flash.onhit (idx 33) and flash.oncast (idx 57).
FLASH_ENVELOPE_EXTRAS_33 = [
    {"name": "rampms",   "label": "Ramp up (ms)",          "min": 1, "max": 2000, "default": 150, "step": 10},
    {"name": "decayms",  "label": "Decay (ms)",            "min": 1, "max": 5000, "default": 500, "step": 10},
    {"name": "retrigms", "label": "Sustain window (ms)",   "min": 0, "max": 2000, "default": 800, "step": 10},
]
FLASH_ENVELOPE_EXTRAS_57 = [
    {"name": "rampms",   "label": "Ramp up (ms)",          "min": 1, "max": 2000, "default": 200, "step": 10},
    {"name": "decayms",  "label": "Decay (ms)",            "min": 1, "max": 5000, "default": 600, "step": 10},
    {"name": "retrigms", "label": "Sustain window (ms)",   "min": 0, "max": 2000, "default": 250, "step": 10},
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
    # Low band (0-12)
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
     "[!] Damage Magicka",
     "Burst — damages or restores {param1}% of the actor's base magicka when the tier activates.",
     "Burst % of base Magicka (+ restore, - damage)",
     {"param": {"min": -100, "max": 100, "default": 0}}),
    (4,  "damage.stamina",
     "[!] Damage Stamina",
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
     "[!] Stagger",
     "Burst — staggers the actor when the tier activates.",
     "",
     {"param": {"min": 0, "max": 0, "default": 0}}),
    (9,  "burst.blowCover",
     "[!] Blow Cover",
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

    # High band (13-34)
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
    (18, "modify.resistFire",
     "Modify Fire Resist",
     "Shifts the actor's fire resistance by {param1}%.",
     "Fire resist shift (points; + resist, - weakness)", None),
    (19, "modify.resistFrost",
     "Modify Frost Resist",
     "Shifts the actor's frost resistance by {param1}%.",
     "Frost resist shift (points; + resist, - weakness)", None),
    (20, "modify.resistShock",
     "Modify Shock Resist",
     "Shifts the actor's shock resistance by {param1}%.",
     "Shock resist shift (points; + resist, - weakness)", None),
    (21, "modify.resistMagic",
     "Modify Magic Resist",
     "Shifts the actor's magic resistance by {param1}%.",
     "Magic resist shift (points; + resist, - weakness)", None),
    (22, "toggle.muffle",
     "[+] Muffle",
     "Toggles silenced footsteps on the actor while active.",
     "",
     {"param": {"min": 0, "max": 0, "default": 0}}),
    (23, "toggle.waterbreathing",
     "[+] Waterbreathing",
     "Toggles waterbreathing on the actor while active.",
     "",
     {"param": {"min": 0, "max": 0, "default": 0}}),
    (24, "toggle.waterWalking",
     "[+] Water Walking",
     "Toggles water-walking on the actor while active.",
     "",
     {"param": {"min": 0, "max": 0, "default": 0}}),
    (25, "damage.health",
     "[!] Damage Health",
     "Burst — damages or restores {param1}% of the actor's base health when the tier activates.",
     "Burst % of base Health (+ restore, - damage)",
     {"param": {"min": -100, "max": 100, "default": 0}}),
    (26, "burst.bounty",
     "[!] Add Bounty",
     "Burst — adjusts the actor's bounty in their current hold by {param1} gold (positive adds, negative pays off).",
     "Bounty change (gold; + add, - remove)",
     {"param": {"min": -10000, "max": 10000, "default": 0, "step": 50}}),
    (27, "spell.modifyArmor",
     "[+] Modify Armor",
     "Toggles a flat armor-rating bonus of {param1} while active.",
     "Armor rating points",
     {"param": {"min": 0, "max": 500, "default": 100, "step": 10}}),
    (28, "spell.detectLife",
     "[+] Detect Life",
     "Toggles a Detect Life aura that highlights living NPCs within {param1}ft while active.",
     "Detect radius (feet)",
     {"param": {"min": 5, "max": 500, "default": 100, "step": 10}}),
    (29, "spell.slowTime",
     "[+] Slow Time",
     "Toggles a slow-time effect that drags everything around the actor to {param1}% of normal speed while active.",
     "Time speed % (lower = slower; 100 = normal)",
     {"param": {"min": 5, "max": 100, "default": 50, "step": 5}}),
    (30, "spell.flameCloak",
     "[+] Flame Cloak",
     "Toggles a flame cloak that burns enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (31, "spell.frostCloak",
     "[+] Frost Cloak",
     "Toggles a frost cloak that chills enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (32, "spell.lightningCloak",
     "[+] Lightning Cloak",
     "Toggles a lightning cloak that shocks enemies within {param2}ft for {param1} damage/s while active.",
     "Damage per second",
     {"param":  {"min": 1, "max": 200, "default": 8},
      "param2": {"label": "Radius (feet)", "min": 3, "max": 500, "default": 5}}),
    (33, "flash.onhit",
     "[+] Flash",
     "Flashes the tattoo's emissive layer to {param2}% brightness on the chosen trigger event ({param1}).",
     "Trigger event",
     {"param":  {"min": 0, "max": 127, "default": 1,
                 "menu": [{"value": v, "label": l} for v, l in FLASH_TRIGGER_MENU]},
      "param2": {"label": "Peak emissive (additive, % of 1.0)",
                 "min": 0, "max": 1000, "default": 300, "step": 10},
      "extras": FLASH_ENVELOPE_EXTRAS_33}),
    (34, "modify.resistDisease",
     "Modify Disease Resist",
     "Shifts the actor's disease resistance by {param1}%.",
     "Disease resist shift (points; + resist, - weakness)", None),

    # Very high band (35-57)
    (35, "modify.resistPoison",
     "Modify Poison Resist",
     "Shifts the actor's poison resistance by {param1}%.",
     "Poison resist shift (points; + resist, - weakness)", None),
    (36, "modify.absorbChance",
     "Modify Spell Absorb",
     "Shifts the actor's chance to absorb incoming spells by {param1}%.",
     "Spell absorb chance shift (points; + absorb, - vulnerable)", None),
    (37, "modify.reflectDamage",
     "Modify Reflect Damage",
     "Shifts the actor's chance to reflect incoming melee damage by {param1}%.",
     "Reflect damage chance shift (points; + reflect, - vulnerable)", None),
    (38, "modify.oneHanded",
     "Modify One-Handed",
     "Shifts the actor's One-Handed weapon skill by {param1}.",
     "One-Handed skill shift (points; + buff, - drain)", None),
    (39, "modify.twoHanded",
     "Modify Two-Handed",
     "Shifts the actor's Two-Handed weapon skill by {param1}.",
     "Two-Handed skill shift (points; + buff, - drain)", None),
    (40, "modify.archery",
     "Modify Archery",
     "Shifts the actor's Archery (Marksman) skill by {param1}.",
     "Archery skill shift (points; + buff, - drain)", None),
    (41, "modify.block",
     "Modify Block",
     "Shifts the actor's Block skill by {param1}.",
     "Block skill shift (points; + buff, - drain)", None),
    (42, "modify.heavyArmor",
     "Modify Heavy Armor",
     "Shifts the actor's Heavy Armor skill by {param1}.",
     "Heavy Armor skill shift (points; + buff, - drain)", None),
    (43, "modify.lightArmor",
     "Modify Light Armor",
     "Shifts the actor's Light Armor skill by {param1}.",
     "Light Armor skill shift (points; + buff, - drain)", None),
    (44, "modify.smithing",
     "Modify Smithing",
     "Shifts the actor's Smithing skill by {param1}.",
     "Smithing skill shift (points; + buff, - drain)", None),
    (45, "modify.enchanting",
     "Modify Enchanting",
     "Shifts the actor's Enchanting skill by {param1}.",
     "Enchanting skill shift (points; + buff, - drain)", None),
    (46, "modify.alchemy",
     "Modify Alchemy",
     "Shifts the actor's Alchemy skill by {param1}.",
     "Alchemy skill shift (points; + buff, - drain)", None),
    (47, "modify.destruction",
     "Modify Destruction",
     "Shifts the actor's Destruction magic skill by {param1}.",
     "Destruction skill shift (points; + buff, - drain)", None),
    (48, "modify.restoration",
     "Modify Restoration",
     "Shifts the actor's Restoration magic skill by {param1}.",
     "Restoration skill shift (points; + buff, - drain)", None),
    (49, "modify.alteration",
     "Modify Alteration",
     "Shifts the actor's Alteration magic skill by {param1}.",
     "Alteration skill shift (points; + buff, - drain)", None),
    (50, "modify.illusion",
     "Modify Illusion",
     "Shifts the actor's Illusion magic skill by {param1}.",
     "Illusion skill shift (points; + buff, - drain)", None),
    (51, "modify.conjuration",
     "Modify Conjuration",
     "Shifts the actor's Conjuration magic skill by {param1}.",
     "Conjuration skill shift (points; + buff, - drain)", None),
    (52, "modify.speech",
     "Modify Speech",
     "Shifts the actor's Speech (persuasion / barter) skill by {param1}.",
     "Speech skill shift (points; + buff, - drain)", None),
    (53, "modify.lockpicking",
     "Modify Lockpicking",
     "Shifts the actor's Lockpicking skill by {param1}.",
     "Lockpicking skill shift (points; + buff, - drain)", None),
    (54, "modify.pickpocket",
     "Modify Pickpocket",
     "Shifts the actor's Pickpocket skill by {param1}.",
     "Pickpocket skill shift (points; + buff, - drain)", None),
    (55, "shader.play",
     "[+] Vanilla Shader",
     "Plays the {param1} effect shader on the actor while active (duration {param2}s; 0 = until removed).",
     "Shader",
     {"param":  {"min": 0, "max": len(SHADERS) - 1, "default": 0,
                 "menu": [{"value": i, "label": l} for i, l in enumerate(SHADERS)]},
      "param2": {"label": "Duration (s, 0 = until removed)",
                 "min": 0, "max": 60, "default": 0}}),
    (56, "sound.play",
     "[+] Vanilla Sound",
     "Plays the {param1} looping sound on the actor while active (duration {param2}s; 0 = until removed).",
     "Sound",
     {"param":  {"min": 0, "max": len(SOUNDS) - 1, "default": 0,
                 "menu": [{"value": i, "label": l} for i, l in enumerate(SOUNDS)]},
      "param2": {"label": "Duration (s, 0 = until removed)",
                 "min": 0, "max": 60, "default": 0},
      "extras": SOUND_VOLUME_EXTRAS}),
    (57, "flash.oncast",
     "[deprecated] Flash on Cast — use Flash",
     "Flashes the tattoo's emissive layer to {param1}% brightness while the actor is casting a spell.",
     "Peak emissive (additive, % of 1.0)",
     {"param": {"min": 0, "max": 1000, "default": 300, "step": 10},
      "extras": FLASH_ENVELOPE_EXTRAS_57}),
]
assert len(EFFECTS_RAW) == 58, f"expected 58 effects, got {len(EFFECTS_RAW)}"
# Sanity: indices contiguous 0..57.
for i, t in enumerate(EFFECTS_RAW):
    assert t[0] == i, f"effect tuple {i} has idx {t[0]}"


def build_condition(idx, t):
    """Assemble one condition entry."""
    cid, label, desc, param = t
    out = {"id": cid, "label": label, "description": desc}
    if param is not None:
        p = {}
        if "label"   in param: p["label"]   = param["label"]
        # Condition base-class defaults: min 0, max 100, default 0.
        if "min"     in param: p["min"]     = param["min"]
        if "max"     in param: p["max"]     = param["max"]
        if "default" in param: p["default"] = param["default"]
        if "menu"    in param: p["menu"]    = param["menu"]
        out["param"] = p
        if "_param2" in param:
            out["param2"] = param["_param2"]
    return out


def build_effect(idx, t):
    """Assemble one effect entry. Fills in abs-shift defaults for the majority
    of effects (-100..100, default 0, step 1)."""
    eidx, eid, label, desc, param_label, overrides = t
    out = {"id": eid, "label": label, "description": desc}

    overrides = overrides or {}
    param_o   = overrides.get("param", {})
    param2_o  = overrides.get("param2")
    extras_o  = overrides.get("extras")

    # ── param block ────────────────────────────────────────────────────────
    p = {}
    # Label always present (empty string OK — base defaults to "").
    if param_label:
        p["label"] = param_label
    # For abs-shift effects we want min=-100, max=100, default=0, step=1
    # — but the base class JSON defaults are min=0/max=100/default=0/step=1.
    # We MUST write min=-100 explicitly. max=100 we can omit (matches default).
    if is_abs_shift(eidx):
        p.setdefault("min", -100)
        # Override-side wins
        for k in ("min", "max", "default", "step"):
            if k in param_o:
                p[k] = param_o[k]
    else:
        for k in ("min", "max", "default", "step"):
            if k in param_o:
                p[k] = param_o[k]
    if "menu" in param_o:
        p["menu"] = param_o["menu"]
    # Only emit param if it has content.
    if p:
        out["param"] = p

    # ── param2 block ───────────────────────────────────────────────────────
    if param2_o is not None:
        out["param2"] = param2_o

    # ── extras block ───────────────────────────────────────────────────────
    if extras_o is not None:
        out["extras"] = extras_o

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
