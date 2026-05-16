# Test cheat-sheet — v0.0.30

## Setup

1. Deploy preset (already done if you used the bash one-liner below):
   ```
   <MO2 mod>/SKSE/Plugins/StorageUtil/MagicTattoosFramework/presets/test_v030.json
   ```
2. In-game: MCM → Magic Tattoos Framework → General → Selected preset → pick
   "Test v0.0.30" → Load selected.
3. The 8 slots are now configured. Each new condition gets a distinct color
   so you can see which is firing at a glance.

## Cascade (slot 1 highest priority → slot 7 lowest)

| Slot | Condition           | Color   | How to trigger |
|------|---------------------|---------|----------------|
| 1    | `health.below 50%`  | red     | `player.modav health -200` (heal back with `+200`) |
| 2    | `state.weaponDrawn` | orange  | Press R / draw any weapon |
| 3    | `state.sprinting`   | yellow  | Hold sprint key while moving |
| 4    | `state.running`     | green   | Move at run speed (not walk, not sprint) |
| 5    | `location.playerHome` | blue  | `coc breezehome` |
| 6    | `location.indoors`  | magenta | `coc whiterunbanneredmare` (any non-home interior) |
| 7    | `weather.rainy`     | cyan    | `fw <rain weather id>` — see below |
| 0    | (default)           | white   | Falls through when nothing else triggers |

Because of the cascade: to test slot 4 (running, green), make sure you're
not sprinting, not in combat-low-health, weapon sheathed, outdoors,
clear weather. If you don't move you'll see slot 0 (white).

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
