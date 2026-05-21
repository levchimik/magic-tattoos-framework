# MTF Test Pack — Source

Version-controlled copy of the MTF Test Pack MO2 mod folder. Deployed to
`F:/Modlists/Modding Essentials/mods/MTF Test Pack/`.

## What's inside
Smoke-test presets under `SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/`.
Each one drives the framework into one specific code path; see
`../SMOKE_TESTS.md` for the catalog.

## Workflow
1. Edit / add a preset under `test-pack/SKSE/...`
2. `cp -r test-pack/* "F:/Modlists/Modding Essentials/mods/MTF Test Pack/"`
3. Enable "MTF Test Pack" in MO2 left pane (already in modlist.txt)
4. Launch Skyrim, MCM → Magic Tattoos Framework → Conditions → Presets dropdown
5. The preset appears in the list — `Load selected` to apply it

No ESP, no scripts — just JSON.
