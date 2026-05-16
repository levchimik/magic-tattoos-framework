# Test cheat-sheet — v0.0.32 (preset format: schema v5)

## Setup

1. Deploy preset:
   ```
   <MO2 mod>/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/test_v030.json
   ```
   Note `StorageUtilData`, not `StorageUtil` — that's where `JsonInFolder` scans.

2. In-game: MCM → Magic Tattoos Framework → General → Selected preset → pick
   "Test v0.0.32" → Load selected.

3. The 8 slots are now configured. Each new condition gets a distinct color
   so you can see which is firing at a glance.

## Preset format (schema v5 / v0.0.32+)

Nested JSON tree with hex colors. Hand-authorable:

```json
{
  "valid": 1,
  "schemaversion": 4,
  "displayname": "My Preset",
  "slot": [
    {
      "cond":     {"pluginid": "mtf.base:health.below", "param": 50, "packid": "", "entryid": "010"},
      "cooldown": {"min": 0, "mode": 0},
      "pulse":    {"rate": 2.0, "depth": 60},
      "layer":    [{"tint": "#FF0000", "emissive": "#FF0000", "emissivemult": 3.0, "alpha": 100}],
      "effect":   [{"key": "mtf.base:burst.stagger", "param": 0, "param2": 0}]
    },
    ...
  ]
}
```

Hex colors accept `"#RRGGBB"` or `"RRGGBB"`. Decimal ints still work for
backwards-compatibility. Effect rows can be omitted entirely if not used.
Layer arrays under MAX_LAYERS_PER_SLOT (4) are fine — defaults fill in.

`pulse` is optional and may be omitted (= rate 0, disabled). `rate` is
cycles/sec (0–5 Hz typical); `depth` is 0–100 % — how far the glow dims
from peak. The slot's emissive strength is the **peak** of the wave;
depth tells you how dark the trough gets. `pause` (seconds) holds the
glow at the trough between cycles. Formula:
`mult = (1 - depth) + depth * (0.5 - 0.5 * cos(2π * rate * t))`
applied during the cycle window, with `mult = (1 - depth)` during pause.
Final emissive = `base_emissivemult * mult`. Updates at 20 Hz only while
a pulsing slot is the active tier.

**Schema bumped to 5 in v0.0.32.** v4 files still load (pulse defaults
to off); saved files write v5.

## Cascade (slot 1 highest priority → slot 7 lowest)

| Slot | Condition           | Color   | How to trigger |
|------|---------------------|---------|----------------|
| 1    | `health.below 50%`  | red ✦   | `player.modav health -200` (heal back with `+200`); fast pulse (2 Hz, 60%) |
| 2    | `state.weaponDrawn` | orange ✦| Press R / draw any weapon; slow pulse (0.8 Hz, 40%) |
| 3    | `state.sprinting`   | yellow  | Hold sprint key while moving |
| 4    | `state.running`     | green   | Move at run speed (not walk, not sprint) |
| 5    | `location.playerHome` | blue  | `coc breezehome` |
| 6    | `location.indoors`  | magenta | `coc whiterunbanneredmare` (any non-home interior) |
| 7    | `state.loversEmbrace` | pink ✦| `player.addspell CDA1D` (sleep with spouse IRL or via console); heartbeat pulse (0.5 Hz, 70%) |
| 0    | (default)           | white   | Falls through when nothing else triggers |

✦ = pulse enabled. Watch the glow breathe — depth% is the swing around the
base emissive intensity, rate Hz is cycles/sec.

Because of the cascade: to test slot 4 (running, green), make sure you're
not sprinting, not in combat-low-health, weapon sheathed, outdoors, and
not under Lover's Embrace. If you don't move you'll see slot 0 (white).

## Console commands

### Health
```
player.modav health -200      ; ~hurt → slot 1 (red)
player.modav health 200       ; heal back
player.setav health 50        ; force exact value (may need restoreav)
```

### Movement state
Use the regular sprint/run/walk keys — no console shortcut. To toggle
walk/run lock: `setrunmode 1` / `setrunmode 0`. To check what state
the engine thinks the player is in: `getav speedmult`.

### Weapon drawn
```
player.drawweapon             ; equivalent to pressing R; equip a weapon first
player.sheatheweapon
```

### Location teleports
```
coc breezehome                ; player home (Whiterun)
coc honeyside                 ; player home (Riften)
coc whiterunbanneredmare      ; inn (also indoors)
coc whiterundragonsreach      ; indoors but not home
coc bleakfallsbarrow01        ; dungeon
coc riverwood                 ; outdoors town
coc whiterunorigin            ; outdoors city
```

To list locations with a keyword: `help "LocTypePlayerHouse" 0 KYWD`
then check what holds it — slower than just trying the COC commands.

### Lover's Embrace
```
player.addspell CDA1D         ; grant LoversComfort (vanilla "Lover's Comfort")
player.removespell CDA1D      ; remove it
```
Normally acquired by sleeping in the same bed as your married spouse.
The condition checks `target.HasSpell(LoversComfort)` so the addspell
shortcut works fine for testing.

### Weather
The classification used by the conditions:
- 0 = Pleasant (sunny / clear)
- 1 = Cloudy
- 2 = Rainy
- 3 = Snowy

Force weather with `fw <formID>`. Tested vanilla IDs:
```
fw 81B16     ; SkyrimClear (classification 0)
fw 81B17     ; SkyrimCloudy (1)
fw 10A23F    ; SkyrimRain (2)
fw 81B1A     ; SkyrimStorm (2, with thunder)
fw 81B19     ; SkyrimSnow (3)
fw 81B1B     ; SkyrimSnowStorm (3)
sw 0          ; release forced weather, let the system pick again
```

If `fw <id>` complains, try `forceweather <id>` (full command name).
The classification is per-weather form: a single form has one value.
Some packs (Obsidian Weathers etc.) override these — if your install
has a weather mod the classifications still hold (they're a form
property, not engine-derived).

## What to watch for

- **Switching is instant**: cooldown is 0 on all test slots, so the color
  should change on the same MainQuest tick (default 2s).
- **Effects are empty**: this preset is condition-only. Add effects via
  MCM if you want to see them fire — none of the new conditions ship
  with effects bound by default.
- **Default slot is white**: when no condition matches and you're in
  clear weather outdoors not moving fast, slot 0 wins. Confirms
  "always-on" baseline works.

## Resetting

To wipe the preset back to defaults:
- MCM → Presets → Delete selected ("Test v0.0.30")
- Or MCM → just reset individual slots via the per-condition default
  buttons.
