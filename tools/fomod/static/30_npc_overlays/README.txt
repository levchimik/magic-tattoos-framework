MTF NPC Overlays
================

A tiny override mod for Magic Tattoos Framework. The only thing it ships is
a `skee64.ini` that sets:

    [Overlays]
    bPlayerOnly=0

This is required for MTF to apply tattoo overlays to tracked NPCs. By default
RaceMenu's NiOverride (SKEE) only allocates body/hand/face/feet overlay nodes
on the player; with `bPlayerOnly=0` the same overlay slots are created on
every humanoid actor, which is what MTF's NPC tracker needs.

Install
-------
Enable this mod in MO2 and place it AFTER `RaceMenu Anniversary Edition` in
the left pane (mod order). MO2 wins loose-file conflicts by load order — the
last mod to provide `SKSE/Plugins/skee64.ini` is the one SKEE reads.

Cost
----
NiOverride pre-allocates overlay slots on every humanoid NPC. RAM use grows
roughly proportional to the active NPC population. RaceMenu's stock ini warns
"NOT RECOMMENDED" for this reason; every mod that puts tattoos on NPCs
(SlaveTats, RapeTattoos, Bathing in Skyrim, etc.) requires this flip too.
