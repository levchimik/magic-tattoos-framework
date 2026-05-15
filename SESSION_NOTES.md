# LME Session Notes (pre-compact)

Saved before PC crash + modlist reinstall + context compact. Resume from here.

Last verified working state: dispatcher cap **100**, picker shows all 17 conditions, all features below working in-game.

## Uncommitted work since v0.0.14 (last commit: `2f63f92`)

Bundle this as v0.0.15.

### Files modified

All in `F:/stuff/LewdMarksEffects/source/scripts/` and deployed to `F:/Modlists/Modding Essentials/mods/LewdMarksEffects/scripts/`:

- `sd_LME_Plugin_FMR.psc` — rewritten to read `_JSW_BB_Storage` arrays directly. Works with both original Fertility Mode (v3) and FMR. Label: "Fertility Mode (v3 / Reloaded)". Plugin id kept as `lme.fmr` for save compat.
- `sd_LME_Plugin_Base.psc` — now 14 conditions:
  - `magicka` / `magicka.below` (Above/Below Magicka %)
  - `stamina` / `stamina.below`
  - `combat.in` / `combat.alerted` / `combat.hostile`
  - `combat.hit` (any), `combat.hit.blunt`, `combat.hit.bladed`, `combat.hit.ranged`,
    `combat.hit.magic.fire`, `combat.hit.magic.frost`, `combat.hit.magic.shock`
  - 5 effects unchanged
- `sd_LME_HitListener.psc` — NEW. ReferenceAlias on player; OnHit classifies akSource and calls `sd_LME_Plugin_Base._onHit(classIdx)`. Class indices: 0=ANY, 1=BLUNT, 2=BLADED, 3=RANGED, 4=FIRE, 5=FROST, 6=SHOCK.
- `sd_LME_MainQuest.psc` — added Auto Hidden Properties `menuKeys[64]`, `menuLabels[64]`, `menuCount`. Added `BuildVisibleConditionMenu(includeKey)` and `BuildVisibleEffectMenu(includeKey)` for fast picker.
- `sd_LME_MCMQuest.psc` — picker now: call `BuildVisible*Menu` once, read `MainQuest.menuLabels[i]`/`menuKeys[i]` directly in loop (no local array snapshots). Dispatcher `_newOpts` monolithic, 100-branch cap. Both callers clamp `sz` to 100.

### ESP change

`F:/stuff/LewdMarksEffects/LewdMarksEffects.esp` — added Alias ID 1 (PlayerAlias, ForcedReference → `0x000014:Skyrim.esm`) with `sd_LME_HitListener` script attached. Backup at `LewdMarksEffects.esp.prealias.bak`. Deployed copy at `F:/Modlists/Modding Essentials/mods/LewdMarksEffects/LewdMarksEffects.esp`.

YAML source at `/tmp/lme-yaml/` (likely gone after reboot — re-serialize from the deployed ESP via Spriggit if needed).

## Critical lessons (add to KNOWLEDGEBASE.md after restore)

### Papyrus VM array allocation gotchas

1. **Trampoline pattern breaks `new string[N]`.**
   ```
   string[] Function _newOpts(int n)
       if n <= 16
           return _newOpts0(n)    ; <-- trampoline through this
       endif
   EndFunction
   string[] Function _newOpts0(int n)
       ...
       return new string[N]       ; <-- silently returns length-0
   EndFunction
   ```
   Empirically verified: even with each sub-function only 16 branches, going through one extra function call layer corrupts the returned array. Keep dispatchers **monolithic** — one function, one chain.

2. **Long if-elseif chains silently fail.** 128 branches in one function → `new string[N]` returns length-0 for some inputs. 100 monolithic works (just barely). Safe ceiling probably ~100.

3. **Auto Hidden array Properties are reliable on persistent quests, flaky on MCM/state-bound scripts.** Put caches on `sd_LME_MainQuest` (extends Quest, persistent), not on `sd_LME_MCMQuest` (extends SKI_ConfigBase).

4. **Pre-existing 0-length arrays in saves.** If a prior broken pex wrote a 0-length array to a Property, the value persists across save/reload. Check `Length` and force-reallocate, not just `== None`:
   ```
   if arr == None || arr.Length < EXPECTED
       arr = new string[EXPECTED]
   endif
   ```

5. **Notification queue drops late `Debug.Notification` calls.** Multiple Debug.Notification calls in one frame — only the first ~5 reliably surface. Don't rely on order or completeness when debugging.

### Original Fertility Mode vs FMR

- Both ship as `Fertility Mode.esm`. FMR is a continuation with same FormIDs for shared records.
- `_JSW_BB_Storage` quest at `0x000D62` exists in both, with identical `Form[] TrackedActors`, `float[] LastOvulation`, `float[] LastConception` properties.
- Globals `_JSW_BB_EggLife` (`0x0125F1`) and `_JSW_BB_PregnancyDuration` (`0x000D66`) exist in both at same FormIDs.
- **FMR-only**: faction at `0x02666B` used for pregnancy/ovulation rank shortcut. Doesn't exist in original FM.
- **Truth source for ovulation/pregnancy is the Storage arrays, not the faction.** Reading Storage directly works on both mods.
- Force Ovulation in both mods sets `Storage.LastOvulation[i] = 0.001`.

### Vanilla Skyrim.esm keyword FormIDs (used in HitListener)

- `MagicDamageFire`: `01CEAD`
- `MagicDamageFrost`: `01CEAE`
- `MagicDamageShock`: `01CEAF`
- `WeapTypeWarhammer`: `06D930`

### Weapon.GetWeaponType() mapping

0 HtH · 1 OneHSword · 2 OneHDagger · 3 OneHAxe · 4 OneHMace · 5 TwoHSword · 6 TwoHAxe (includes warhammer — disambiguate via `WeapTypeWarhammer` keyword) · 7 Bow · 8 Staff · 9 Crossbow

## Caprica build command

```bash
cd "F:/stuff/LewdMarksEffects/source/scripts"
"F:/stuff/Skyrim modding/tools/Caprica/Caprica.exe" --game skyrim \
  -f "S:/SteamLibrary/steamapps/common/Skyrim Special Edition/Data/Source/Scripts/TESV_Papyrus_Flags.flg" \
  -i "." -i "../../_deps" -i "S:/SteamLibrary/steamapps/common/Skyrim Special Edition/Data/Source/Scripts" \
  -o . <files.psc>
```

`_deps/` contains SKSE stubs (Art.psc, ColorForm.psc, all `_JSW_BB_*` stubs etc.) — should survive reboot, it's outside the modlist.

## Deploy

```bash
cp source/scripts/*.pex "F:/Modlists/Modding Essentials/mods/LewdMarksEffects/scripts/"
cp LewdMarksEffects.esp "F:/Modlists/Modding Essentials/mods/LewdMarksEffects/"
```

## After modlist reinstall — sanity checks

- [ ] `S:/SteamLibrary/steamapps/common/Skyrim Special Edition/Data/Source/Scripts/TESV_Papyrus_Flags.flg` exists
- [ ] Fertility Mode (one of the two variants) is installed → `Data/Fertility Mode.esm` present
- [ ] PO3 PapyrusExtender installed
- [ ] SLA / OSL Aroused installed (Plugin_SLA depends on it)
- [ ] Registry key `HKLM\SOFTWARE\WOW6432Node\Bethesda Softworks\Skyrim Special Edition\installed path` points to `S:\SteamLibrary\steamapps\common\Skyrim Special Edition\` (for xeditlib)
- [ ] LewdMarksEffects.esp loads (FormID `0x803` = MainQuest, `0x80D` = Plugin_Base, `0x80E` = Plugin_FMR, `0x80F` = Plugin_SLA)

## Pending decisions for next session

1. Commit v0.0.15 with bundle above. Suggested message:
   > v0.0.15: Fertility Mode v3 compat, weapon-class hit conditions, picker speedup
2. Decide dispatcher cap. Last test: 100 works. 32 is the conservative pick if you want margin. Bookkeeping in `_newOpts` and the two `if sz > N` clamps must match.
3. The `sd_LME_HitListener` is reached via player alias on MainQuest — verify in-game that hits register (notification approach: add temporary `Debug.Notification` in OnHit to confirm during testing).
