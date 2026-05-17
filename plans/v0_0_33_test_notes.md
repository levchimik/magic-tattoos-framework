# v0.0.33 NPC support — overnight build, test notes

All six Papyrus implementation steps from `v0_0_33_npc_support.md` are
committed on branch `v0.0.33-npc-support` and the `.pex` files are deployed
to `F:\Modlists\Modding Essentials\mods\MagicTattoosFramework\scripts\`.

The ESP wasn't touched in this branch — no record adds, no script binding
changes. Loose `.pex` deploy is enough; no Vortex/MO2 archive rebuild.

## Quick verification path

1. Load any save that previously had MTF v0.0.32 working.
2. Open MCM → Magic Tattoos Framework. You should see a new page
   **Subjects** between *Conditions* and *Plugins*.
3. On Subjects:
   - **Add-target hotkey**: click and press a free key (e.g. `J`).
   - **Default preset for new subjects**: pick the v0.0.32 test preset.
   - The tracked list will be empty initially.
4. Close MCM. Point the crosshair at any NPC (Lydia, a guard, a Whiterun
   wandering peasant) and press the hotkey. You should see a corner
   notification "MTF: added \<Name\> (preset: Test v0.0.32)" and within
   a couple of seconds, the tattoo appears on the NPC.
5. Re-open MCM → Subjects. The actor should now be listed with their
   current tier ("T0" baseline). Click the row → pick a different preset
   or "Remove subject".

## Things to look for

- **Player flow unchanged**: existing player tattoo + pulse should work
  exactly like v0.0.32. Test by toggling weapon-drawn, hurting yourself,
  etc.; tiers should switch and the pulse should breathe at the same
  cadence as before.
- **NPC tier switching**: hit the NPC with a weapon (slot 1 will fire if
  the NPC's health drops below 50%). Damage them for slot 1 (red) test.
  Run them out of combat for slot 0.
- **NPC pulse**: slots 1, 2, 7 in the test preset have pulse configured.
  When an NPC's tier hits one of those, you should see the breathing
  glow on the NPC's body — synced with their own clock (not the
  player's), since each actor has its own `mtf.pulse.start`.
- **Cooldowns**: per-actor — slot cooldowns track separately for the
  player and each tracked NPC.
- **Performance**: round-robin walks at most 16 actors per slow tick
  (`MAX_EVALS_PER_TICK`), distance gated at 4096 units (~80m). With
  ~5–10 NPCs in view you should feel zero impact.

## Known limitations / things still to wire

1. **NPC pulse params don't live-update from MCM**: changing rate/depth/
   pause sliders only affects the player's pulse (which reads cond*
   arrays live). The NPC pulse roster snapshots params on tier
   transition. To force a refresh after editing a preset, briefly
   change the NPC's tier (e.g. by altering a condition param) or remove
   + re-add the subject.

2. **`magic.costPenalty` effect uses a shared spell form**: if two
   subjects both have this effect with different param values, the most
   recent activation's magnitude clobbers the others. Per-actor cloned
   spell forms would be required to fix; deferred.

3. **Hotkey is held on `MTF_HitListener`** (alias on player). If you've
   removed or replaced the player alias in your save somehow, the
   hotkey won't fire — MCM toast will say "set a default preset first"
   but never the hotkey toast. Reload the preset / quest to re-register.

4. **The MCM Subjects page caps at 16 rows per page**. Use the
   *Previous page / Next page* options. Cap is currently 256 subjects
   total (`TRACKED_CAP`).

5. **Cell-detach behavior relies on PO3 `OnObjectUnloaded`** with form
   type 43 (Actor). If PO3 PapyrusExtender isn't in the load order this
   build will silently skip the suspension logic — actors will keep
   getting evaluated whether or not their 3D is loaded. (Is3DLoaded
   is checked in `_processTrackedActorOnce` as a backstop.)

## If something goes wrong

- Check the Papyrus log (`Documents\My Games\Skyrim Special Edition\
  Logs\Script\Papyrus.0.log`) for `[MTF_Main]` traces or stack errors.
- The migration block in MCM `OnVersionUpdate` bumps `_migrationLevel`
  to 33 and back-migrates Plugin_Base's legacy applied magnitudes. If
  drain effects look doubled or stale after upgrade, the migration
  didn't run — disable then re-enable MTF in MCM to nudge it.
- Console smoke test: select an NPC, `cqf MTF_MainQuest AddTrackedActor`
  with form ID won't work (cqf doesn't pass refs). Use
  `cqf MTF_MainQuest EvalAndDrawActor` after using the hotkey to force
  an eval on a tracked NPC.
