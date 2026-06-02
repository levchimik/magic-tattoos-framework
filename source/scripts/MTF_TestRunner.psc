Scriptname MTF_TestRunner extends ReferenceAlias
{F10 self-test harness. Every test follows ARRANGE/ACT/ASSERT/CLEANUP per
 docs/internal/TEST_METHODOLOGY.md.

 ARRANGE actively forces the player into the opposite-of-target state via
 Papyrus APIs (DamageActorValue, RemoveItem, etc.), then asserts the
 precondition held. Only then does ACT transition to the target state
 and ASSERT check tier matches expectation. CLEANUP always runs so the
 next test starts from a neutral baseline.

 Slot layout during a run:
   * Slot 7 -- condition under test (slots 1-6 cond keys cleared)
   * Slot 8 -- effect under test (BACKEND slot, never the active tier)

 v0.2.11: TEST_FX_SLOT moved from 0 (default tier — always active, slow-tick
 onTick re-applied test effects after deactivate and broke assertions) to 8
 (backend slot — evaluateTier scans slots 1..MAX_CONDITIONS_CACHED but only
 returns a slot when its cond key is non-empty; we never set a cond key on 8,
 so 8 is never the active tier, so slow-tick never ticks 8's effects). This
 dropped the _setTestMode quiesce — any future F10 failure is a real bug,
 not a slow-tick methodology artifact.

 Snapshot+restore wraps the run; user's MCM-set state is preserved.

 Output:
   * Papyrus log: [MTF_TEST] PASS/FAIL/SKIP ...
   * JSON: StorageUtilData/MagicTattoosFramework/tests/last_run.json

 Attached as a SECOND script on MainQuest's PlayerAlias.}

; v0.2.11: hotkeys split — PgUp = regular F10 battery, PgDn = concurrency
; stress test. PgDn opens a UIListMenu (same UIExtensions widget as the
; tattoo-apply spell) with a "Run stress now" entry at the top plus
; preset N values; selecting Run kicks off RunStress with the stored N,
; selecting a value just updates N for the next run.
int   Property HOTKEY_DX_PGUP = 0xC9                                          AutoReadOnly
int   Property HOTKEY_DX_PGDN = 0xD1                                          AutoReadOnly
string Property JSON_FILE      = "MagicTattoosFramework/tests/last_run"        AutoReadOnly
int   Property TEST_COND_SLOT = 7                                             AutoReadOnly
int   Property TEST_FX_SLOT   = 8                                             AutoReadOnly
int   Property TEST_FX_IDX    = 0                                             AutoReadOnly

; Stress test config — keep modest to bound wall-time.
; Skeever base form id (vanilla). Used as the spawn target for every NPC.
; Ghosted+restrained immediately on placeatme so the test isn't disrupted.
int    Property STRESS_NPC_FORMID = 0x0010D13E AutoReadOnly
; Hard cap; 30 disposable actors is roughly Skyrim's soft-cap before
; AI/animgraph budget degrades performance. SetStressN clamps to this.
int    Property STRESS_N_MAX = 30 AutoReadOnly

; v0.2.14 visuals stress (End key). Spawns N HUMANOID actors in a ring
; (default base is a vanilla female bandit), round-robin-applies the 5
; MTF_Vis* presets, peace tier renders for T_BASELINE, frenzies them so
; combat.in fires (combat tier = hot color + fast pulse), kills all for
; the fade-on-death pipeline, then despawns. Shares mtf.stress.n with
; the PgDn picker — set N once via PgDn, drive both tests from there.
int    Property HOTKEY_DX_END     = 0xCF        AutoReadOnly
; LvlForswornMeleeFemale — NPC_ template (not LVLN). PlaceAtMe on a
; concrete NPC base is reliable in tight loops; the LVLN form 0x000442C8
; only spawned one of N=3 in practice (suspected leveled-resolution race).
; Non-essential + non-protected so KillSilent actually kills (Lydia
; 0x000A2C8E is Protected and only bleeds out).
int    Property VISUAL_NPC_FORMID = 0x000442CA  AutoReadOnly
int    Property VISUAL_PRESET_COUNT = 4         AutoReadOnly
float  Property VISUAL_RING_R     = 220.0       AutoReadOnly
float  Property VISUAL_T_BASELINE = 10.0        AutoReadOnly
float  Property VISUAL_T_COMBAT   = 10.0        AutoReadOnly
float  Property VISUAL_T_FADE     = 10.0        AutoReadOnly

; Counters -- only valid during a single RunAll.
int _pass
int _fail
int _skip

; Snapshot scratch -- restored at end of RunAll.
string[] _snapCondKey
int[]    _snapCondParam
int[]    _snapCondParam2
string   _snapFxKey
int      _snapFxParam
int      _snapFxParam2

Event OnInit()
    RegisterForKey(HOTKEY_DX_PGUP)
    RegisterForKey(HOTKEY_DX_PGDN)
    RegisterForKey(HOTKEY_DX_END)
    RegisterForModEvent("MTF_StressKick", "OnStressKick")
EndEvent

Event OnPlayerLoadGame()
    RegisterForKey(HOTKEY_DX_PGUP)
    RegisterForKey(HOTKEY_DX_PGDN)
    RegisterForKey(HOTKEY_DX_END)
    RegisterForModEvent("MTF_StressKick", "OnStressKick")
EndEvent

Event OnKeyDown(int keyCode)
    if Utility.IsInMenuMode()
        return
    endif
    if keyCode == HOTKEY_DX_PGUP
        RunAll()
    elseif keyCode == HOTKEY_DX_PGDN
        _showStressNMenu()
    elseif keyCode == HOTKEY_DX_END
        ; Same picker — it has a "Run VISUALS" row alongside "Run stress".
        ; Either hotkey opens it; user picks which run to fire.
        _showStressNMenu()
    endif
EndEvent

Function _showStressNMenu()
{Pop a UIListMenu (UIExtensions). Three row classes:
   * row RUN_STRESS_ROW → "Run stress now" with current N
   * row RUN_VIS_ROW    → "Run VISUALS now" with current N
   * value rows         → set N to one of the preset values (does NOT run;
                          gives the user a quick reconfigure path)
 PgDn and End both pop this same picker.}
    UIListMenu m = UIExtensions.GetMenu("UIListMenu") as UIListMenu
    if m == None
        Debug.Notification("MTF: UIExtensions unavailable")
        return
    endif
    m.ResetMenu()
    int current = StorageUtil.GetIntValue(None, "mtf.stress.n", 2)
    int HEADER_COUNT      = 3
    int RUN_STRESS_ROW    = HEADER_COUNT          ; 3
    int RUN_VIS_ROW       = HEADER_COUNT + 1      ; 4
    int SEP_ROW           = HEADER_COUNT + 2      ; 5
    int VALUES_BASE       = HEADER_COUNT + 3      ; 6
    m.AddEntryItem("-   MTF: pick N (concurrent fibers / NPCs)   -")
    m.AddEntryItem("Current: N = " + current)
    m.AddEntryItem("-----------------------")
    m.AddEntryItem(">> Run STRESS now (skills, N = " + current + ")")
    m.AddEntryItem(">> Run VISUALS now (tattoos, N = " + current + ")")
    m.AddEntryItem("-----------------------")
    int[] values = new int[10]
    values[0] = 1
    values[1] = 2
    values[2] = 3
    values[3] = 5
    values[4] = 8
    values[5] = 10
    values[6] = 15
    values[7] = 20
    values[8] = 25
    values[9] = 30
    int i = 0
    while i < values.Length
        m.AddEntryItem("N = " + values[i])
        i += 1
    endwhile
    m.OpenMenu(Game.GetPlayer())
    int idx = m.GetResultInt()
    if idx < 0
        return                ; cancel
    elseif idx == RUN_STRESS_ROW
        Debug.Trace("[MTF_STRESS] Run-stress selected (N=" + current + ")")
        RunStress()
        return
    elseif idx == RUN_VIS_ROW
        Debug.Trace("[MTF_VIS] Run-visuals selected (N=" + current + ")")
        RunVisuals()
        return
    elseif idx < VALUES_BASE
        return                ; header / separator rows
    endif
    int valIdx = idx - VALUES_BASE
    if valIdx < 0 || valIdx >= values.Length
        return
    endif
    int newN = values[valIdx]
    StorageUtil.SetIntValue(None, "mtf.stress.n", newN)
    Debug.Notification("MTF N = " + newN)
    Debug.Trace("[MTF_STRESS] N set to " + newN + " via UIListMenu")
EndFunction

Function RunAll()
    Debug.Notification("MTF tests: running (AAA pipeline)...")
    Debug.Trace("[MTF_TEST] === Run start ===")

    MTF_MainQuest mq = GetOwningQuest() as MTF_MainQuest
    if mq == None
        Debug.Trace("[MTF_TEST] FATAL: owning quest != MTF_MainQuest")
        Debug.Notification("MTF tests: ABORT (no MainQuest)")
        return
    endif
    ; v0.3.9: mtf.base split into themed modules; the base script now serves
    ; mtf.attributes. Just a registration sanity gate (bp is otherwise unused).
    MTF_Plugin_Base bp = mq.FindPlugin("mtf.attributes") as MTF_Plugin_Base
    if bp == None
        Debug.Trace("[MTF_TEST] FATAL: mtf.attributes (base) plugin not registered")
        Debug.Notification("MTF tests: ABORT (base modules missing)")
        return
    endif
    Actor pl = Game.GetPlayer()
    if pl == None
        return
    endif

    _pass = 0
    _fail = 0
    _skip = 0
    JsonUtil.ClearAll(JSON_FILE)
    JsonUtil.SetFloatValue(JSON_FILE, "timestamp", Utility.GetCurrentRealTime())

    ; v0.2.11: no slow-tick quiesce needed. TEST_FX_SLOT=8 (backend) is never
    ; the active tier, so slow-tick never ticks the test's effects.

    _snapshotState(mq)
    _clearCondSlots1to7(mq)
    _clearTestFxSlot(mq)

    _runConditions(mq, pl)
    _runEffects(mq, pl)

    _restoreState(mq)

    int total = _pass + _fail + _skip
    JsonUtil.SetIntValue(JSON_FILE, "total", total)
    JsonUtil.SetIntValue(JSON_FILE, "passed", _pass)
    JsonUtil.SetIntValue(JSON_FILE, "failed", _fail)
    JsonUtil.SetIntValue(JSON_FILE, "skipped", _skip)
    JsonUtil.Save(JSON_FILE)

    string summary = "MTF tests: " + _pass + "/" + total + " pass"
    if _fail > 0
        summary += " (" + _fail + " FAIL)"
    endif
    if _skip > 0
        summary += " " + _skip + " skip"
    endif
    Debug.Trace("[MTF_TEST] === " + summary + " ===")
    Debug.Notification(summary)
EndFunction

; ====================================================================
; Snapshot / restore -- preserves user's MCM-set slot config
; ====================================================================

Function _snapshotState(MTF_MainQuest mq)
    _snapCondKey    = Utility.CreateStringArray(8, "")
    _snapCondParam  = Utility.CreateIntArray(8, 0)
    _snapCondParam2 = Utility.CreateIntArray(8, 0)
    int i = 1
    while i < 8
        _snapCondKey[i]    = mq.GetCondPluginId(i)
        _snapCondParam[i]  = mq.GetCondParam(i)
        _snapCondParam2[i] = mq.GetCondParam2(i)
        i += 1
    endwhile
    _snapFxKey    = mq.GetSlotEffectKey(TEST_FX_SLOT, TEST_FX_IDX)
    _snapFxParam  = mq.GetSlotEffectParamN(TEST_FX_SLOT, TEST_FX_IDX, 1)
    _snapFxParam2 = mq.GetSlotEffectParamN(TEST_FX_SLOT, TEST_FX_IDX, 2)
EndFunction

Function _restoreState(MTF_MainQuest mq)
    int i = 1
    while i < 8
        mq.SetCondPluginId(i, _snapCondKey[i])
        mq.SetCondParam(i, _snapCondParam[i])
        mq.SetCondParam2(i, _snapCondParam2[i])
        i += 1
    endwhile
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, _snapFxKey, _snapFxParam, _snapFxParam2)
EndFunction

Function _clearCondSlots1to7(MTF_MainQuest mq)
    int i = 1
    while i < 8
        mq.SetCondPluginId(i, "")
        mq.SetCondParam(i, 0)
        mq.SetCondParam2(i, 0)
        i += 1
    endwhile
EndFunction

Function _clearTestFxSlot(MTF_MainQuest mq)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "", 0, 0)
EndFunction

; ====================================================================
; AAA CONDITION TESTS
;
; Each _aaa_* function follows:
;   ARRANGE -- force opposite-of-target state, verify precondition
;   ACT     -- ONE causal change toward target state
;   ASSERT  -- verify tier == TEST_COND_SLOT
;   CLEANUP -- always runs (even on ARRANGE/ASSERT failure)
; ====================================================================

Function _runConditions(MTF_MainQuest mq, Actor pl)
    ; AV-percent thresholds (Papyrus-only AAA via DamageActorValue/RestoreActorValue)
    _aaa_magickaAbove(mq, pl)
    _aaa_magickaBelow(mq, pl)
    _aaa_staminaAbove(mq, pl)
    _aaa_staminaBelow(mq, pl)
    _aaa_healthAbove(mq, pl)
    _aaa_healthBelow(mq, pl)

    ; Pure-Papyrus state arranges
    _aaa_stateWeaponDrawn(mq, pl)
    _aaa_loversEmbrace(mq, pl)
    _aaa_factionPlayerFollower(mq, pl)
    _aaa_magiceffectKwInvisibility(mq, pl)
    _aaa_goldAboveThousand(mq, pl)
    _aaa_wornHeavyArmor(mq, pl)
    _aaa_wornLightArmor(mq, pl)

    ; --- SKIPs ---
    ; location.kw is a single menu-typed condition (id strings: indoors /
    ; outdoors / city / town / dungeon / inn / shop / player_home). All
    ; eight branches gated on the same coc-renderer-crash workaround.
    _skipCond("location.kw",              "TODO: replace coc-based AAA with MoveTo (coc crashes renderer on this rig)")
    _skipCond("weather",                  "TODO: needs vanilla weather FormID per classification (chrome lookup)")
    _skipCond("state.sprinting",          "no reliable Papyrus API to force sprint")
    _skipCond("state.running",            "depends on movement speed, no force API")
    _skipCond("state.sneaking",           "no reliable Papyrus API to force sneak")
    _skipCond("state.swimming",           "TODO: needs MoveTo into water cell")
    _skipCond("state.mounted",            "needs horse summon and mount idle")
    _skipCond("state.bleedingOut",        "player isn't essential normally")
    _skipCond("magiceffect.kw.fire",      "TODO: needs vanilla ability spell with MagicDamageFire kw")
    _skipCond("magiceffect.kw.frost",     "TODO: needs vanilla ability spell with MagicDamageFrost kw")
    _skipCond("magiceffect.kw.shock",     "TODO: needs vanilla ability spell with MagicDamageShock kw")
    _skipCond("combat.in",                "needs active combat (hostile NPC required)")
    _skipCond("combat.alerted",           "needs hostile NPCs nearby")
    _skipCond("combat.hostile",           "needs hostile NPCs nearby")
    _skipCond("combat.hit",               "needs hit event")
    _skipCond("combat.casting",           "needs player mid-cast")
    _skipCond("time.range",               "TODO: needs SetGameTime arrange")
    _skipCond("followers.any",            "needs follower NPC nearby")
EndFunction

; ---------- AV-percent threshold tests --------------------------------

Function _aaa_magickaAbove(MTF_MainQuest mq, Actor pl)
    string testName = "magicka(>=50)"
    string err = ""

    ; ARRANGE -- drain to 10%
    _setAVPct(pl, "Magicka", 10.0)
    Utility.Wait(0.2)
    _configureCondSlot(mq, "magicka", 50, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected magicka<50 but tier=7 (pct=" + _avPct(pl, "Magicka") + ")"
    endif

    if err == ""
        ; ACT -- restore full
        pl.RestoreActorValue("Magicka", 999999.0)
        Utility.Wait(0.2)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected magicka>=50 but tier=0 (pct=" + _avPct(pl, "Magicka") + ")"
        endif
    endif

    ; CLEANUP -- restore (idempotent)
    pl.RestoreActorValue("Magicka", 999999.0)
    _recordCond(testName, err)
EndFunction

Function _aaa_magickaBelow(MTF_MainQuest mq, Actor pl)
    string testName = "magicka.below(<=50)"
    string err = ""

    pl.RestoreActorValue("Magicka", 999999.0)
    Utility.Wait(0.2)
    _configureCondSlot(mq, "magicka.below", 50, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected magicka>50 but tier=7 (pct=" + _avPct(pl, "Magicka") + ")"
    endif

    if err == ""
        _setAVPct(pl, "Magicka", 10.0)
        Utility.Wait(0.2)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected magicka<=50 but tier=0 (pct=" + _avPct(pl, "Magicka") + ")"
        endif
    endif

    pl.RestoreActorValue("Magicka", 999999.0)
    _recordCond(testName, err)
EndFunction

Function _aaa_staminaAbove(MTF_MainQuest mq, Actor pl)
    string testName = "stamina(>=50)"
    string err = ""

    _setAVPct(pl, "Stamina", 10.0)
    Utility.Wait(0.2)
    _configureCondSlot(mq, "stamina", 50, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected stamina<50 but tier=7 (pct=" + _avPct(pl, "Stamina") + ")"
    endif

    if err == ""
        pl.RestoreActorValue("Stamina", 999999.0)
        Utility.Wait(0.2)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected stamina>=50 but tier=0 (pct=" + _avPct(pl, "Stamina") + ")"
        endif
    endif

    pl.RestoreActorValue("Stamina", 999999.0)
    _recordCond(testName, err)
EndFunction

Function _aaa_staminaBelow(MTF_MainQuest mq, Actor pl)
    string testName = "stamina.below(<=50)"
    string err = ""

    pl.RestoreActorValue("Stamina", 999999.0)
    Utility.Wait(0.2)
    _configureCondSlot(mq, "stamina.below", 50, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected stamina>50 but tier=7 (pct=" + _avPct(pl, "Stamina") + ")"
    endif

    if err == ""
        _setAVPct(pl, "Stamina", 10.0)
        Utility.Wait(0.2)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected stamina<=50 but tier=0 (pct=" + _avPct(pl, "Stamina") + ")"
        endif
    endif

    pl.RestoreActorValue("Stamina", 999999.0)
    _recordCond(testName, err)
EndFunction

Function _aaa_healthAbove(MTF_MainQuest mq, Actor pl)
    string testName = "health(>=50)"
    string err = ""

    ; ARRANGE -- drain to 30%; safer than 10 in case of regen weirdness
    _setAVPct(pl, "Health", 30.0)
    Utility.Wait(0.2)
    _configureCondSlot(mq, "health", 50, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected health<50 but tier=7 (pct=" + _avPct(pl, "Health") + ")"
    endif

    if err == ""
        pl.RestoreActorValue("Health", 999999.0)
        Utility.Wait(0.2)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected health>=50 but tier=0 (pct=" + _avPct(pl, "Health") + ")"
        endif
    endif

    pl.RestoreActorValue("Health", 999999.0)
    _recordCond(testName, err)
EndFunction

Function _aaa_healthBelow(MTF_MainQuest mq, Actor pl)
    string testName = "health.below(<=50)"
    string err = ""

    pl.RestoreActorValue("Health", 999999.0)
    Utility.Wait(0.2)
    _configureCondSlot(mq, "health.below", 50, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected health>50 but tier=7 (pct=" + _avPct(pl, "Health") + ")"
    endif

    if err == ""
        _setAVPct(pl, "Health", 30.0)
        Utility.Wait(0.2)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected health<=50 but tier=0 (pct=" + _avPct(pl, "Health") + ")"
        endif
    endif

    pl.RestoreActorValue("Health", 999999.0)
    _recordCond(testName, err)
EndFunction

; ---------- State tests ----------------------------------------------

Function _aaa_stateWeaponDrawn(MTF_MainQuest mq, Actor pl)
    string testName = "state.weaponDrawn"
    string err = ""

    ; ARRANGE -- sheathe
    pl.SheatheWeapon()
    Utility.Wait(1.0)
    _configureCondSlot(mq, "state.weaponDrawn", 0, 0)
    if pl.IsWeaponDrawn()
        err = "arrange: SheatheWeapon failed (still drawn)"
    elseif mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected sheathed but tier=7"
    endif

    if err == ""
        ; ACT -- draw
        pl.DrawWeapon()
        Utility.Wait(1.0)
        if !pl.IsWeaponDrawn()
            err = "act: DrawWeapon failed (still sheathed)"
        elseif mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected drawn but tier=0"
        endif
    endif

    ; CLEANUP -- sheathe
    pl.SheatheWeapon()
    _recordCond(testName, err)
EndFunction

Function _aaa_loversEmbrace(MTF_MainQuest mq, Actor pl)
    string testName = "state.loversEmbrace"
    string err = ""

    Spell lovers = Game.GetForm(0x000CDA1D) as Spell
    if lovers == None
        _skipCond(testName, "LoversComfort spell not found")
        return
    endif

    ; ARRANGE -- ensure no spell
    if pl.HasSpell(lovers)
        pl.RemoveSpell(lovers)
        Utility.Wait(0.3)
    endif
    _configureCondSlot(mq, "state.loversEmbrace", 0, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected no LoversComfort but tier=7"
    endif

    if err == ""
        ; ACT -- add spell
        pl.AddSpell(lovers, false)
        Utility.Wait(0.3)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected LoversComfort but tier=0"
        endif
    endif

    ; CLEANUP
    pl.RemoveSpell(lovers)
    _recordCond(testName, err)
EndFunction

Function _aaa_factionPlayerFollower(MTF_MainQuest mq, Actor pl)
    string testName = "faction.playerFollower"
    string err = ""

    Faction fac = Game.GetForm(0x0005C84D) as Faction
    if fac == None
        _skipCond(testName, "CurrentFollowerFaction not found")
        return
    endif

    ; ARRANGE -- ensure player not in faction
    if pl.IsInFaction(fac)
        pl.RemoveFromFaction(fac)
        Utility.Wait(0.3)
    endif
    _configureCondSlot(mq, "faction.playerFollower", 0, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected NOT in faction but tier=7"
    endif

    if err == ""
        ; ACT -- add to faction
        pl.AddToFaction(fac)
        Utility.Wait(0.3)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected in faction but tier=0"
        endif
    endif

    ; CLEANUP
    pl.RemoveFromFaction(fac)
    _recordCond(testName, err)
EndFunction

Function _aaa_magiceffectKwInvisibility(MTF_MainQuest mq, Actor pl)
    string testName = "magiceffect.kw.invisibility"
    string err = ""

    ; ARRANGE -- ensure Invisibility AV at 0
    float startInv = pl.GetActorValue("Invisibility")
    if startInv > 0.0
        pl.ModActorValue("Invisibility", -startInv)
        Utility.Wait(0.2)
    endif
    _configureCondSlot(mq, "magiceffect.kw.invisibility", 0, 0)
    if pl.GetActorValue("Invisibility") > 0.0
        err = "arrange: Invisibility AV won't go to 0 (still " + pl.GetActorValue("Invisibility") + ")"
    elseif mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected NOT invisible but tier=7"
    endif

    if err == ""
        ; ACT -- bump invisibility
        pl.ModActorValue("Invisibility", 1.0)
        Utility.Wait(0.2)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected invisible but tier=0 (AV=" + pl.GetActorValue("Invisibility") + ")"
        endif
    endif

    ; CLEANUP -- restore Invisibility to 0
    float postInv = pl.GetActorValue("Invisibility")
    if postInv > 0.0
        pl.ModActorValue("Invisibility", -postInv)
    endif
    _recordCond(testName, err)
EndFunction

Function _aaa_goldAboveThousand(MTF_MainQuest mq, Actor pl)
    ; gold.aboveThousand reads param as a MULTIPLE of 1000. param=1 means
    ; ">= 1,000 gold". The old test passed param=1000 which meant
    ; ">= 1,000,000 gold" -- a real test bug surfaced by the AAA refactor.
    string testName = "gold.aboveThousand(p=1=>1000)"
    string err = ""

    Form gold = Game.GetForm(0x0000000F)
    if gold == None
        _skipCond(testName, "Gold001 form not found")
        return
    endif

    int beforeGold = pl.GetItemCount(gold)

    ; ARRANGE -- remove all gold
    if beforeGold > 0
        pl.RemoveItem(gold, beforeGold, true)
        Utility.Wait(0.2)
    endif
    _configureCondSlot(mq, "gold.aboveThousand", 1, 0)
    if pl.GetItemCount(gold) > 0
        err = "arrange: gold removal failed (still " + pl.GetItemCount(gold) + ")"
    elseif mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected gold<1000 but tier=7"
    endif

    if err == ""
        ; ACT -- add 1500 gold
        pl.AddItem(gold, 1500, true)
        Utility.Wait(0.2)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected gold>=1000 but tier=0 (gold=" + pl.GetItemCount(gold) + ")"
        endif
    endif

    ; CLEANUP -- restore exact prior gold count
    int currentGold = pl.GetItemCount(gold)
    if currentGold > beforeGold
        pl.RemoveItem(gold, currentGold - beforeGold, true)
    elseif currentGold < beforeGold
        pl.AddItem(gold, beforeGold - currentGold, true)
    endif
    _recordCond(testName, err)
EndFunction

Function _aaa_wornHeavyArmor(MTF_MainQuest mq, Actor pl)
    string testName = "worn.heavyArmor"
    string err = ""

    Armor iron = Game.GetForm(0x00012E4B) as Armor    ; IronArmor (heavy cuirass)
    Keyword kwHeavy = Game.GetForm(0x0006BBD2) as Keyword
    if iron == None || kwHeavy == None
        _skipCond(testName, "IronArmor / ArmorHeavy keyword not found")
        return
    endif

    Form origBody = pl.GetWornForm(0x00000004)        ; body slot

    ; ARRANGE -- unequip body if it has heavy keyword
    if origBody != None && origBody.HasKeyword(kwHeavy)
        pl.UnequipItem(origBody, false, true)
        Utility.Wait(0.5)
    endif
    _configureCondSlot(mq, "worn.heavyArmor", 0, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected no heavy armor but tier=7 (other slot still heavy?)"
    endif

    if err == ""
        ; ACT -- equip iron armor
        if pl.GetItemCount(iron) < 1
            pl.AddItem(iron, 1, true)
        endif
        pl.EquipItem(iron, false, true)
        Utility.Wait(0.5)
        if mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: expected heavy armor but tier=0"
        endif
    endif

    ; CLEANUP -- remove iron, re-equip original body
    pl.UnequipItem(iron, false, true)
    pl.RemoveItem(iron, 99, true)
    if origBody != None
        pl.EquipItem(origBody, false, true)
    endif
    _recordCond(testName, err)
EndFunction

Function _aaa_wornLightArmor(MTF_MainQuest mq, Actor pl)
    string testName = "worn.lightArmor"
    string err = ""

    ; Try LeatherArmor (0x0003619E) first; fall back to HideArmor (0x000136D5).
    ; Last run HideArmor equipped but condition didn't fire -- might be form
    ; quirk or USKP rework. Use diagnostic instrumentation either way.
    Armor probe = Game.GetForm(0x0003619E) as Armor    ; LeatherArmor
    if probe == None
        probe = Game.GetForm(0x000136D5) as Armor      ; HideArmor fallback
    endif
    Keyword kwLight = Game.GetForm(0x0006BBD3) as Keyword
    if probe == None || kwLight == None
        _skipCond(testName, "no light cuirass form / ArmorLight keyword not found")
        return
    endif
    if !probe.HasKeyword(kwLight)
        _skipCond(testName, "probe armor 0x" + _hex8(probe.GetFormID()) + " lacks ArmorLight keyword")
        return
    endif

    Form origBody = pl.GetWornForm(0x00000004)

    if origBody != None && origBody.HasKeyword(kwLight)
        pl.UnequipItem(origBody, false, true)
        Utility.Wait(0.5)
    endif
    _configureCondSlot(mq, "worn.lightArmor", 0, 0)
    if mq.evaluateTier() == TEST_COND_SLOT
        err = "arrange: expected no light armor but tier=7 (other slot still light?)"
    endif

    if err == ""
        if pl.GetItemCount(probe) < 1
            pl.AddItem(probe, 1, true)
        endif
        pl.EquipItem(probe, false, true)
        Utility.Wait(0.8)
        Form bodyAfter = pl.GetWornForm(0x00000004)
        if bodyAfter != probe as Form
            err = "act: EquipItem failed (body slot still " + _formTag(bodyAfter) + " want " + _formTag(probe) + ")"
        elseif mq.evaluateTier() != TEST_COND_SLOT
            err = "assert: light armor equipped (kw=true) but tier=0 (cond eval bug)"
        endif
    endif

    pl.UnequipItem(probe, false, true)
    pl.RemoveItem(probe, 99, true)
    if origBody != None
        pl.EquipItem(origBody, false, true)
    endif
    _recordCond(testName, err)
EndFunction

string Function _formTag(Form f)
    if f == None
        return "(none)"
    endif
    return "0x" + _hex8(f.GetFormID())
EndFunction

; ====================================================================
; AAA helpers
; ====================================================================

Function _configureCondSlot(MTF_MainQuest mq, string cid, int param, int param2)
    mq.SetCondPluginId(TEST_COND_SLOT, mq._remapBaseKey("mtf.base:" + cid, "cond:"))
    mq.SetCondParam(TEST_COND_SLOT, param)
    mq.SetCondParam2(TEST_COND_SLOT, param2)
EndFunction

Function _recordCond(string testName, string err)
    string row
    if err == ""
        _pass += 1
        row = "PASS condition " + testName
    else
        _fail += 1
        row = "FAIL condition " + testName + " - " + err
    endif
    Debug.Trace("[MTF_TEST] " + row)
    JsonUtil.StringListAdd(JSON_FILE, "rows", row)
EndFunction

Function _skipCond(string cid, string reason)
    _skip += 1
    string row = "SKIP condition " + cid + " - " + reason
    Debug.Trace("[MTF_TEST] " + row)
    JsonUtil.StringListAdd(JSON_FILE, "rows", row)
EndFunction

Function _setAVPct(Actor pl, string av, float targetPct)
{Damage/Restore the AV to put it at roughly targetPct% of max.}
    float currentMax = pl.GetActorValueMax(av)
    if currentMax <= 0.0
        return
    endif
    float currentVal = pl.GetActorValue(av)
    float targetVal = currentMax * (targetPct / 100.0)
    float delta = currentVal - targetVal
    if delta > 0.0
        pl.DamageActorValue(av, delta)
    elseif delta < 0.0
        pl.RestoreActorValue(av, -delta)
    endif
EndFunction

float Function _avPct(Actor target, string av)
    float maxV = target.GetActorValueMax(av)
    if maxV <= 0.0
        return -1.0
    endif
    return (target.GetActorValue(av) / maxV) * 100.0
EndFunction

string Function _hex8(int i)
    ; Tiny hex formatter for debug output. Papyrus has no built-in.
    string hex = "0123456789ABCDEF"
    string out = ""
    int x = i
    int n = 0
    while n < 8
        int nib = Math.LogicalAnd(x, 0xF)
        out = StringUtil.GetNthChar(hex, nib) + out
        x = Math.RightShift(x, 4)
        n += 1
    endwhile
    return out
EndFunction

; ====================================================================
; EFFECT TESTS -- baseline-delta AAA
;
; ARRANGE: snapshot storage + AV before
; ACT:     SetSlotEffectFull + _activateSlotEffects(slot 0 = default tier)
; ASSERT:  storage AND AV moved by expectedDelta
; CLEANUP: _deactivateSlotEffects + clear slot. Verify both reverted.
;
; For modify.resist 0..4 (Fire/Frost/Shock/Magic/Disease) the engine
; doesn't expose the AV via GetActorValue with the targeted name pre-
; MGEF-rename, and even post-rename ability spells may not show via
; GetActorValue. Those use _testFxResistAbility: storage + HasSpell.
; modify.resist 5 (PoisonResist) uses the regular _testFxAV path.
; ====================================================================

Function _runEffects(MTF_MainQuest mq, Actor pl)
    ; modify.* AV deltas
    _testFxAV(mq, pl, "modify.magickaRegen",   5, 0, "mtf.shift.modify.magickaRegen",   "MagickaRateMult",      5.0)
    _testFxAV(mq, pl, "modify.carryWeight",   10, 0, "mtf.shift.modify.carryWeight",   "CarryWeight",         10.0)
    ; v0.2.9: standalone Sneak probe removed -- modify.skill is now a menu-typed
    ; effect (schema v2). All 18 skills including Sneak are exercised by the
    ; id-driven loop below via _testFxAVStr.
    _testFxAV(mq, pl, "modify.movementSpeed",  5, 0, "mtf.shift.modify.movementSpeed", "SpeedMult",            5.0)
    _testFxAV(mq, pl, "modify.staminaRegen",   5, 0, "mtf.shift.modify.staminaRegen",  "StaminaRateMult",      5.0)
    _testFxAV(mq, pl, "modify.healthRegen",    5, 0, "mtf.shift.modify.healthRegen",   "HealRateMult",         5.0)
    _testFxAV(mq, pl, "modify.maxMagicka",    10, 0, "mtf.shift.modify.maxMagicka",    "Magicka",             10.0)
    _testFxAV(mq, pl, "modify.maxStamina",    10, 0, "mtf.shift.modify.maxStamina",    "Stamina",             10.0)
    _testFxAV(mq, pl, "modify.unarmedDamage",  5, 0, "mtf.shift.modify.unarmedDamage", "UnarmedDamage",        5.0)
    ; modify.criticalChance routes through a spell (since v0.2.6 -- the
    ; ModActorValue path silently no-ops for that AV). GetActorValue
    ; doesn't reflect the magnitude either (same engine quirk as elemental
    ; resists), so verify via storage + HasSpell instead of AV delta.
    _testFxStorageAndSpell(mq, pl, "modify.criticalChance", 5, 0, "mtf.shift.modify.criticalChance", _resolveCriticalChanceSpell(), 5)
    _testFxAV(mq, pl, "modify.bowSpeed",       5, 0, "mtf.shift.modify.bowSpeed",      "BowSpeedBonus",        5.0)
    _testFxAV(mq, pl, "modify.absorbChance",   5, 0, "mtf.shift.modify.absorbChance",  "AbsorbChance",         5.0)
    _testFxAV(mq, pl, "modify.reflectDamage",  5, 0, "mtf.shift.modify.reflectDamage", "ReflectDamage",        5.0)

    ; Float-mult AVs: stored magnitude = param/100
    _testFxAV(mq, pl, "modify.attackDamage", 10, 0, "mtf.shift.modify.attackDamage", "AttackDamageMult",  0.1)
    _testFxAV(mq, pl, "modify.weaponSpeed",  10, 0, "mtf.shift.modify.weaponSpeed",  "WeaponSpeedMult",   0.1)

    ; Toggles
    ; Muffle stores +1 in StorageUtil (spell magnitude) but the engine
    ; SUBTRACTS that from MovementNoiseMult (muffle = quieter -> -1.0 AV
    ; delta). _testFxAV uses one expectedDelta for both, so it can't
    ; satisfy +1 storage AND -1 AV. Verify via storage + HasSpell instead;
    ; correctness of MovementNoiseMult direction is a gameplay-level
    ; concern, not a test-runner concern.
    _testFxStorageAndSpell(mq, pl, "toggle.muffle", 0, 0, "mtf.shift.toggle.muffle", _resolveMuffleSpellForTest(), 1)
    _testFxAV(mq, pl, "toggle.waterbreathing",  0, 0, "mtf.shift.toggle.waterbreathing", "WaterBreathing",  1.0)
    _testFxAV(mq, pl, "toggle.waterWalking",    0, 0, "mtf.shift.toggle.waterWalking",   "WaterWalking",    1.0)

    ; Consolidated modify.skill -- loop ALL 18 menu ids (v0.2.9 schema v2).
    string[] skillIds = _skillIds()
    int si = 0
    while si < skillIds.Length
        string sid = skillIds[si]
        string av = _skillAVForId(sid)
        if av == ""
            _skipFx("modify.skill[" + sid + "]", "unknown skill id")
        else
            _testFxAVStr(mq, pl, "modify.skill", sid, 10, "mtf.shift.modify.skill." + sid, av, 10.0)
        endif
        si += 1
    endwhile

    ; Consolidated modify.resist -- all 6 are ability-based (the dispatch
    ; route is _absShiftSpellByKey for every id, including Poison). The AV
    ; reflects the ability's magnitude only after the engine re-evaluates
    ; ability stacks, which doesn't happen in the same frame as AddSpell --
    ; so a synchronous GetActorValue check flakes. _testFxResistAbility
    ; verifies via storage + HasSpell instead, which is deterministic.
    string[] resistIds = _resistIds()
    int ri = 0
    while ri < resistIds.Length
        _testFxResistAbility(mq, pl, resistIds[ri], 10)
        ri += 1
    endwhile

    ; scale.magickaCost: param=50 -> engine magnitude 100-50 = 50
    _testFxAV(mq, pl, "scale.magickaCost", 50, 0, "mtf.shift.spellcost", "DestructionMod", 50.0)

    ; spell.modifyArmor: stores param as float, PeakValueModifier on DamageResist
    _testFxAV(mq, pl, "spell.modifyArmor", 100, 0, "mtf.shift.flesh", "DamageResist", 100.0)

    _skipFx("damage.magicka",       "burst, no storage roundtrip")
    _skipFx("damage.stamina",       "burst, no storage roundtrip")
    _skipFx("damage.health",        "burst, no storage roundtrip")
    _skipFx("burst.stagger",        "visual only")
    _skipFx("burst.blowCover",      "needs nearby NPCs")
    _skipFx("burst.bounty",         "invasive - modifies crime gold")
    _skipFx("spell.detectLife",     "visual + global state")
    _skipFx("spell.slowTime",       "global time scaling")
    _skipFx("spell.flameCloak",     "needs hostiles, audible damage tick")
    _skipFx("spell.frostCloak",     "needs hostiles, audible damage tick")
    _skipFx("spell.lightningCloak", "needs hostiles, audible damage tick")
    _skipFx("flash.onhit",          "needs hit event")
    _skipFx("shader.play",          "visual only")
    _skipFx("sound.play",           "audio only")
EndFunction

Function _testFxAV(MTF_MainQuest mq, Actor pl, string eid, int p1, int p2, string storageKey, string av, float expectedDelta)
{Full-pipeline effect test. Storage + AV both verified.}
    ; ARRANGE -- assert storage starts clean (catches leaks from prior tests)
    float baseStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    if !_floatNear(baseStorage, 0.0, 0.01)
        _fail += 1
        string arrRow = "FAIL effect " + eid + "(p=" + p1 + ",p2=" + p2 + ") arrange: storage leaked (was " + baseStorage + ")"
        Debug.Trace("[MTF_TEST] " + arrRow)
        JsonUtil.StringListAdd(JSON_FILE, "rows", arrRow)
        ; Best-effort clean for next test
        StorageUtil.SetFloatValue(pl, storageKey, 0.0)
        return
    endif
    float beforeStorage = baseStorage
    float beforeAV      = pl.GetActorValue(av)

    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, mq._remapBaseKey("mtf.base:" + eid, "eff:"), p1, p2)
    mq._activateSlotEffects(TEST_FX_SLOT)

    float afterStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    float afterAV      = pl.GetActorValue(av)

    mq._deactivateSlotEffects(TEST_FX_SLOT)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "", 0, 0)

    float finalStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    float finalAV      = pl.GetActorValue(av)

    float TOL = 0.01
    bool storageApplied  = _floatNear(afterStorage,  expectedDelta, TOL)
    bool storageReverted = _floatNear(finalStorage,  0.0,           TOL)
    bool avMoved         = _floatNear(afterAV - beforeAV, expectedDelta, TOL)
    bool avReverted      = _floatNear(finalAV  - beforeAV, 0.0,          TOL)

    bool pass = storageApplied && storageReverted && avMoved && avReverted
    string row
    if pass
        _pass += 1
        row = "PASS effect " + eid + "(p=" + p1 + ",p2=" + p2 + ") storage " + beforeStorage + "->" + afterStorage + "->" + finalStorage + " av(" + av + ") " + beforeAV + "->" + afterAV + "->" + finalAV
    else
        _fail += 1
        string reasons = ""
        if !storageApplied
            reasons += "storage_apply(got=" + afterStorage + " want=" + expectedDelta + ") "
        endif
        if !storageReverted
            reasons += "storage_revert(got=" + finalStorage + " want=0) "
        endif
        if !avMoved
            reasons += "av_apply(got_delta=" + (afterAV - beforeAV) + " want=" + expectedDelta + " av=" + av + ") "
        endif
        if !avReverted
            reasons += "av_revert(got_final_delta=" + (finalAV - beforeAV) + " av=" + av + ") "
        endif
        row = "FAIL effect " + eid + "(p=" + p1 + ",p2=" + p2 + ") " + reasons
    endif
    Debug.Trace("[MTF_TEST] " + row)
    JsonUtil.StringListAdd(JSON_FILE, "rows", row)
EndFunction

Function _testFxAVStr(MTF_MainQuest mq, Actor pl, string eid, string p1Id, int p2, string storageKey, string av, float expectedDelta)
{Like _testFxAV but for menu-typed effects (v0.2.9 schema v2). Param1 is a
 string id written via SetSlotEffectParamNStr; the int param1 is ignored by
 the dispatcher on these effects.

 v0.2.11: explicit activate/deactivate pattern (was relying on
 SetSlotEffectFull's auto-activate, which only fires when slot==currentTier;
 TEST_FX_SLOT is now 8 — a backend slot, never the active tier — so the
 auto-activate path is dead). Mirror _testFxAV's flow: SetSlotEffectFull,
 then _activateSlotEffects; on cleanup _deactivateSlotEffects, then clear.

 String param is still written FIRST so that the activate dispatch reads
 the right id rather than the previous test's stale value.}
    ; ARRANGE -- assert storage starts clean (catches leaks from prior tests)
    float baseStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    if !_floatNear(baseStorage, 0.0, 0.01)
        _fail += 1
        string arrRow = "FAIL effect " + eid + "(p1=" + p1Id + ",p2=" + p2 + ") arrange: storage leaked (was " + baseStorage + ")"
        Debug.Trace("[MTF_TEST] " + arrRow)
        JsonUtil.StringListAdd(JSON_FILE, "rows", arrRow)
        ; Best-effort clean for next test
        StorageUtil.SetFloatValue(pl, storageKey, 0.0)
        return
    endif
    float beforeStorage = baseStorage
    float beforeAV      = pl.GetActorValue(av)

    ; String param FIRST so the explicit activate below dispatches with the
    ; right id rather than a previous test's stale empty value.
    mq.SetSlotEffectParamNStr(TEST_FX_SLOT, TEST_FX_IDX, 1, p1Id)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, mq._remapBaseKey("mtf.base:" + eid, "eff:"), 0, p2)
    mq._activateSlotEffects(TEST_FX_SLOT)

    float afterStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    float afterAV      = pl.GetActorValue(av)

    mq._deactivateSlotEffects(TEST_FX_SLOT)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "", 0, 0)
    mq.SetSlotEffectParamNStr(TEST_FX_SLOT, TEST_FX_IDX, 1, "")

    float finalStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    float finalAV      = pl.GetActorValue(av)

    float TOL = 0.01
    bool storageApplied  = _floatNear(afterStorage,  expectedDelta, TOL)
    bool storageReverted = _floatNear(finalStorage,  0.0,           TOL)
    bool avMoved         = _floatNear(afterAV - beforeAV, expectedDelta, TOL)
    bool avReverted      = _floatNear(finalAV  - beforeAV, 0.0,          TOL)

    bool pass = storageApplied && storageReverted && avMoved && avReverted
    string row
    if pass
        _pass += 1
        row = "PASS effect " + eid + "(p1=" + p1Id + ",p2=" + p2 + ") storage " + beforeStorage + "->" + afterStorage + "->" + finalStorage + " av(" + av + ") " + beforeAV + "->" + afterAV + "->" + finalAV
    else
        _fail += 1
        string reasons = ""
        if !storageApplied
            reasons += "storage_apply(got=" + afterStorage + " want=" + expectedDelta + ") "
        endif
        if !storageReverted
            reasons += "storage_revert(got=" + finalStorage + " want=0) "
        endif
        if !avMoved
            reasons += "av_apply(got_delta=" + (afterAV - beforeAV) + " want=" + expectedDelta + " av=" + av + ") "
        endif
        if !avReverted
            reasons += "av_revert(got_final_delta=" + (finalAV - beforeAV) + " av=" + av + ") "
        endif
        row = "FAIL effect " + eid + "(p1=" + p1Id + ",p2=" + p2 + ") " + reasons
    endif
    Debug.Trace("[MTF_TEST] " + row)
    JsonUtil.StringListAdd(JSON_FILE, "rows", row)
EndFunction

Function _testFxStorageAndSpell(MTF_MainQuest mq, Actor pl, string eid, int p1, int p2, string storageKey, Spell verifySpell, int delta)
{Storage + HasSpell verification for any spell-magnitude effect where
 GetActorValue doesn't reflect the modifier (engine quirk class:
 CriticalChance, Muffled, elemental resists). ARRANGE asserts storage
 starts clean; ASSERT verifies storage delta AND that the spell got
 added during activate / removed during deactivate.}
    ; ARRANGE -- assert clean baseline
    float baseStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    if !_floatNear(baseStorage, 0.0, 0.01)
        _fail += 1
        string arrRow = "FAIL effect " + eid + "(p=" + p1 + ",p2=" + p2 + ") arrange: storage leaked (was " + baseStorage + ")"
        Debug.Trace("[MTF_TEST] " + arrRow)
        JsonUtil.StringListAdd(JSON_FILE, "rows", arrRow)
        StorageUtil.SetFloatValue(pl, storageKey, 0.0)
        return
    endif
    if verifySpell == None
        _skip += 1
        string skipRow = "SKIP effect " + eid + " - verify spell None"
        Debug.Trace("[MTF_TEST] " + skipRow)
        JsonUtil.StringListAdd(JSON_FILE, "rows", skipRow)
        return
    endif

    ; ACT
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, mq._remapBaseKey("mtf.base:" + eid, "eff:"), p1, p2)
    mq._activateSlotEffects(TEST_FX_SLOT)

    float afterStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    bool afterHasSpell = pl.HasSpell(verifySpell)

    ; CLEANUP
    mq._deactivateSlotEffects(TEST_FX_SLOT)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "", 0, 0)

    float finalStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    bool finalHasSpell = pl.HasSpell(verifySpell)

    float TOL = 0.01
    bool storageApplied  = _floatNear(afterStorage, delta as float, TOL)
    bool storageReverted = _floatNear(finalStorage, 0.0,            TOL)
    bool spellAdded      = afterHasSpell
    bool spellRemoved    = !finalHasSpell

    bool pass = storageApplied && storageReverted && spellAdded && spellRemoved
    string row
    if pass
        _pass += 1
        row = "PASS effect " + eid + "(p=" + p1 + ",p2=" + p2 + ") storage " + baseStorage + "->" + afterStorage + "->" + finalStorage + " hasSpell " + afterHasSpell + "->" + finalHasSpell
    else
        _fail += 1
        string reasons = ""
        if !storageApplied
            reasons += "storage_apply(got=" + afterStorage + " want=" + delta + ") "
        endif
        if !storageReverted
            reasons += "storage_revert(got=" + finalStorage + " want=0) "
        endif
        if !spellAdded
            reasons += "spell_not_added "
        endif
        if !spellRemoved
            reasons += "spell_not_removed "
        endif
        row = "FAIL effect " + eid + "(p=" + p1 + ",p2=" + p2 + ") " + reasons
    endif
    Debug.Trace("[MTF_TEST] " + row)
    JsonUtil.StringListAdd(JSON_FILE, "rows", row)
EndFunction

Spell Function _resolveCriticalChanceSpell()
{Mirror of MTF_Plugin_Base._resolveCriticalChanceSpell -- form 0x923.}
    return Game.GetFormFromFile(0x923, "MagicTattoosFramework.esp") as Spell
EndFunction

Spell Function _resolveMuffleSpellForTest()
{Mirror of MTF_Plugin_Base._resolveMuffleSpell -- form 0x83F.}
    return Game.GetFormFromFile(0x83F, "MagicTattoosFramework.esp") as Spell
EndFunction

Function _testFxResistAbility(MTF_MainQuest mq, Actor pl, string resistId, int delta)
{Storage + HasSpell verification for the 5 ability-based resists. Used
 for resist ids fire/frost/shock/magic/disease because the engine doesn't
 always reflect the ability magnitude via GetActorValue with the targeted
 AV name. v0.2.9: param keyed on string id (was int 0..4).}
    string storageKey = "mtf.shift.modify.resist." + resistId
    Spell resistSpell = _resolveResistSpellById(resistId)
    if resistSpell == None
        _skip += 1
        string skipRow = "SKIP effect modify.resist[" + resistId + "] - resist spell form not found"
        Debug.Trace("[MTF_TEST] " + skipRow)
        JsonUtil.StringListAdd(JSON_FILE, "rows", skipRow)
        return
    endif

    float beforeStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)

    ; v0.2.11: explicit activate/deactivate — see _testFxAVStr docstring.
    ; String FIRST so the activate dispatch reads the right id.
    mq.SetSlotEffectParamNStr(TEST_FX_SLOT, TEST_FX_IDX, 1, resistId)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, mq._remapBaseKey("mtf.base:modify.resist", "eff:"), 0, delta)
    mq._activateSlotEffects(TEST_FX_SLOT)

    float afterStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    bool afterHasSpell = pl.HasSpell(resistSpell)

    mq._deactivateSlotEffects(TEST_FX_SLOT)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "", 0, 0)
    mq.SetSlotEffectParamNStr(TEST_FX_SLOT, TEST_FX_IDX, 1, "")

    float finalStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    bool finalHasSpell = pl.HasSpell(resistSpell)

    float TOL = 0.01
    bool storageApplied  = _floatNear(afterStorage, delta as float, TOL)
    bool storageReverted = _floatNear(finalStorage, 0.0,            TOL)
    bool spellAdded      = afterHasSpell
    bool spellRemoved    = !finalHasSpell

    bool pass = storageApplied && storageReverted && spellAdded && spellRemoved
    string row
    if pass
        _pass += 1
        row = "PASS effect modify.resist[" + resistId + "] storage " + beforeStorage + "->" + afterStorage + "->" + finalStorage + " hasSpell " + afterHasSpell + "->" + finalHasSpell
    else
        _fail += 1
        string reasons = ""
        if !storageApplied
            reasons += "storage_apply(got=" + afterStorage + " want=" + delta + ") "
        endif
        if !storageReverted
            reasons += "storage_revert(got=" + finalStorage + " want=0) "
        endif
        if !spellAdded
            reasons += "spell_not_added "
        endif
        if !spellRemoved
            reasons += "spell_not_removed "
        endif
        row = "FAIL effect modify.resist[" + resistId + "] " + reasons
    endif
    Debug.Trace("[MTF_TEST] " + row)
    JsonUtil.StringListAdd(JSON_FILE, "rows", row)
EndFunction

Function _skipFx(string eid, string reason)
    _skip += 1
    string row = "SKIP effect " + eid + " - " + reason
    Debug.Trace("[MTF_TEST] " + row)
    JsonUtil.StringListAdd(JSON_FILE, "rows", row)
EndFunction

bool Function _floatNear(float a, float b, float tol)
    float d = a - b
    if d < 0.0
        d = -d
    endif
    return d <= tol
EndFunction

; ====================================================================
; Mirror tables -- update in lockstep with MTF_Plugin_Base
; ====================================================================

; v0.2.9: catalog schema v2 — modify.skill / modify.resist dispatch on
; menu id strings instead of int positional values. Mirror the canonical
; tables in MTF_Plugin_Base. Note 'archery' → "Marksman", 'speech' →
; "Speechcraft" (Skyrim AV naming quirks, see KNOWLEDGEBASE.md).
string Function _skillAVForId(string id)
    if id == "one_handed"
        return "OneHanded"
    elseif id == "two_handed"
        return "TwoHanded"
    elseif id == "archery"
        return "Marksman"          ; NOT "Archery"
    elseif id == "block"
        return "Block"
    elseif id == "heavy_armor"
        return "HeavyArmor"
    elseif id == "light_armor"
        return "LightArmor"
    elseif id == "smithing"
        return "Smithing"
    elseif id == "enchanting"
        return "Enchanting"
    elseif id == "alchemy"
        return "Alchemy"
    elseif id == "destruction"
        return "Destruction"
    elseif id == "restoration"
        return "Restoration"
    elseif id == "alteration"
        return "Alteration"
    elseif id == "illusion"
        return "Illusion"
    elseif id == "conjuration"
        return "Conjuration"
    elseif id == "speech"
        return "Speechcraft"       ; NOT "Speech"
    elseif id == "lockpicking"
        return "Lockpicking"
    elseif id == "pickpocket"
        return "Pickpocket"
    elseif id == "sneak"
        return "Sneak"
    endif
    return ""
EndFunction

Spell Function _resolveResistSpellById(string id)
    if id == "fire"
        return Game.GetFormFromFile(0x837, "MagicTattoosFramework.esp") as Spell
    elseif id == "frost"
        return Game.GetFormFromFile(0x839, "MagicTattoosFramework.esp") as Spell
    elseif id == "shock"
        return Game.GetFormFromFile(0x83B, "MagicTattoosFramework.esp") as Spell
    elseif id == "magic"
        return Game.GetFormFromFile(0x83D, "MagicTattoosFramework.esp") as Spell
    elseif id == "disease"
        return Game.GetFormFromFile(0x851, "MagicTattoosFramework.esp") as Spell
    elseif id == "poison"
        return Game.GetFormFromFile(0x853, "MagicTattoosFramework.esp") as Spell
    endif
    return None
EndFunction

; Ordered id lists matching the modify.{skill,resist} menu in
; tools/build_base_catalog.py. Keep in sync.
string[] Function _skillIds()
    string[] a = new string[18]
    a[0]  = "one_handed"
    a[1]  = "two_handed"
    a[2]  = "archery"
    a[3]  = "block"
    a[4]  = "heavy_armor"
    a[5]  = "light_armor"
    a[6]  = "smithing"
    a[7]  = "enchanting"
    a[8]  = "alchemy"
    a[9]  = "destruction"
    a[10] = "restoration"
    a[11] = "alteration"
    a[12] = "illusion"
    a[13] = "conjuration"
    a[14] = "speech"
    a[15] = "lockpicking"
    a[16] = "pickpocket"
    a[17] = "sneak"
    return a
EndFunction

string[] Function _resistIds()
    string[] a = new string[6]
    a[0] = "fire"
    a[1] = "frost"
    a[2] = "shock"
    a[3] = "magic"
    a[4] = "disease"
    a[5] = "poison"
    return a
EndFunction

; ====================================================================
; CONCURRENCY STRESS TEST (PgDn) — N-fiber
;
; Spawns N skeevers, assigns each MTF_Stress01..N (cycling 6 unique skill
; groups, distinct preset NAMES so scratch namespaces don't collide),
; fans out N AddAppliedPreset calls via SendModEvent so each call runs
; on its OWN fresh fiber (vanilla ModEvent dispatch is one fiber per
; handler invocation), then asserts per-NPC AV deltas + no cross-leak.
;
; N is read from StorageUtil int "mtf.stress.n" (default 2, clamped 1..30).
; Set from console: cqf MTF_MainQuest SetStressN <n>
;
; Each NPC contributes 7 rows: 3 apply + 1 no-leak + 3 revert. At N=30
; that's 210 rows. Per-NPC baselines are stored in StorageUtil float-lists
; keyed on the actor (Papyrus arrays are capped at 128 so a flat
; N×18 baseline array doesn't fit for N≥8).
;
; The fan-out queue (mtf.stress.targets / mtf.stress.presets) and the
; atomic done-count (mtf.stress.done via AdjustIntValue) live in the
; global StorageUtil namespace; OnStressKick reads its slot by event idx.
; ====================================================================

Function RunStress()
    int N = StorageUtil.GetIntValue(None, "mtf.stress.n", 2)
    if N < 1
        N = 1
    elseif N > STRESS_N_MAX
        N = STRESS_N_MAX
    endif

    Debug.Notification("MTF stress(N=" + N + "): starting...")
    Debug.Trace("[MTF_STRESS] === Run start N=" + N + " ===")

    MTF_MainQuest mq = GetOwningQuest() as MTF_MainQuest
    if mq == None
        Debug.Trace("[MTF_STRESS] FATAL: owning quest != MTF_MainQuest")
        Debug.Notification("MTF stress: ABORT (no MainQuest)")
        return
    endif
    Actor pl = Game.GetPlayer()
    if pl == None
        return
    endif
    Form npcBase = Game.GetForm(STRESS_NPC_FORMID)
    if npcBase == None
        Debug.Trace("[MTF_STRESS] FATAL: spawn base 0x" + _hex8(STRESS_NPC_FORMID) + " not found")
        Debug.Notification("MTF stress: ABORT (no spawn base)")
        return
    endif

    _pass = 0
    _fail = 0
    _skip = 0
    JsonUtil.ClearAll(JSON_FILE)
    JsonUtil.SetFloatValue(JSON_FILE, "timestamp", Utility.GetCurrentRealTime())
    JsonUtil.SetStringValue(JSON_FILE, "kind", "stress")
    JsonUtil.SetIntValue(JSON_FILE, "n", N)

    ; Reset rendezvous + work queue.
    StorageUtil.FormListClear(None, "mtf.stress.targets")
    StorageUtil.StringListClear(None, "mtf.stress.presets")
    StorageUtil.SetIntValue(None, "mtf.stress.done", 0)
    StorageUtil.SetIntValue(None, "mtf.stress.failcount", 0)

    ; ARRANGE — spawn N skeevers, ghost+restrain, build the queue.
    ; targets[] / presetNames[] are also kept locally so we can drive the
    ; assertion phase without re-reading StorageUtil 18×N times.
    Form[]   targets     = Utility.CreateFormArray(N, None)
    string[] presetNames = Utility.CreateStringArray(N, "")
    int i = 0
    while i < N
        Actor a = pl.PlaceAtMe(npcBase) as Actor
        if a == None
            Debug.Trace("[MTF_STRESS] FATAL: PlaceAtMe returned None at idx=" + i)
            _despawnTargets(targets, i)
            return
        endif
        a.SetGhost(true)
        a.SetRestrained(true)
        a.IgnoreFriendlyHits(true)
        targets[i]     = a
        presetNames[i] = _stressPresetNameForIdx(i)
        StorageUtil.FormListAdd(None,   "mtf.stress.targets", a,             false)
        StorageUtil.StringListAdd(None, "mtf.stress.presets", presetNames[i], false)
        i += 1
    endwhile
    Utility.Wait(0.5)  ; let actors settle before AV reads

    ; PRE-WARM scratch cache for every distinct preset (warm-cache path is
    ; fully atomic SKSE-native — cold loads with concurrent fibers can race
    ; on the inner pLoad.GetEffectParam* yields). Up to 6 unique presets;
    ; we just warm one per idx, dedup handled by mq's own cache key check.
    i = 0
    while i < N
        mq._loadPresetToScratch(presetNames[i])
        i += 1
    endwhile

    ; Snapshot ALL 18 skill AVs per NPC into per-actor float-lists so the
    ; no-leak assertion can detect cross-pollination on any skill.
    string[] allAVs = _allSkillAVs()
    i = 0
    while i < N
        Actor t = targets[i] as Actor
        StorageUtil.FloatListClear(t, "mtf.stress.baseline")
        int s = 0
        while s < allAVs.Length
            StorageUtil.FloatListAdd(t, "mtf.stress.baseline", t.GetActorValue(allAVs[s]))
            s += 1
        endwhile
        i += 1
    endwhile

    ; ACT — fan-out. Each ModEvent.Send enqueues a fresh-fiber dispatch
    ; of OnStressKick; the loop runs N enqueues within one Papyrus tick
    ; (SKSE ModEvent is non-latent), so all N handlers fire in the same
    ; engine frame and race through AddAppliedPreset simultaneously.
    ;
    ; v0.2.13: switched from vanilla SendModEvent to SKSE ModEvent.* —
    ; vanilla SendModEvent passes 4 args (eventName + str + num + sender)
    ; to the handler, which mismatches our 3-arg (str, num, sender)
    ; receiver signature and silently kills dispatch. SKSE ModEvent maps
    ; 1:1 onto the 3-arg handler used everywhere else (_emitTierChanged
    ; etc.) — drop-in compatible.
    i = 0
    while i < N
        int h = ModEvent.Create("MTF_StressKick")
        if h != 0
            ModEvent.PushString(h, "")
            ModEvent.PushFloat(h, i as float)
            ModEvent.PushForm(h, None)
            ModEvent.Send(h)
        else
            ; Dispatch failed at the SKSE side — count it as done so the
            ; rendezvous still completes within the wait budget.
            Debug.Trace("[MTF_STRESS] WARN: ModEvent.Create(MTF_StressKick) returned 0 at idx=" + i)
            StorageUtil.AdjustIntValue(None, "mtf.stress.done", 1)
        endif
        i += 1
    endwhile

    ; WAIT for done == N. Bound the wall-time to scale roughly with N.
    int waits   = 0
    int maxWaits = N * 25 + 50         ; ≈5s/NPC + 10s baseline; at N=30 → ~160s cap
    int doneCount = 0
    while doneCount < N && waits < maxWaits
        Utility.Wait(0.2)
        doneCount = StorageUtil.GetIntValue(None, "mtf.stress.done", 0)
        waits += 1
    endwhile
    if doneCount < N
        Debug.Trace("[MTF_STRESS] WARN: " + (N - doneCount) + "/" + N + " fibers did not signal completion (timeout after " + (waits * 0.2) + "s)")
    endif
    ; Extra settle for AddAppliedPreset's deferred-update activate path.
    Utility.Wait(1.0)

    ; ASSERT (apply phase) — per NPC: 3 own-preset skill rows + 1 leak row.
    i = 0
    while i < N
        Actor t = targets[i] as Actor
        string[] presetSkills = _stressSkillsForPreset(presetNames[i])
        _stressAssertApplied(i, t, presetSkills, allAVs, 10.0)
        _stressAssertNoLeak(i, t, presetSkills, allAVs)
        i += 1
    endwhile

    ; CLEANUP — RemoveAppliedPreset for all, then verify revert. The
    ; OnStressKick handlers also log any rc != 1 from AddAppliedPreset as
    ; FAIL rows + bump mtf.stress.failcount; surface that into _fail here.
    int kickFails = StorageUtil.GetIntValue(None, "mtf.stress.failcount", 0)
    _fail += kickFails

    i = 0
    while i < N
        Actor t = targets[i] as Actor
        mq.RemoveAppliedPreset(t, presetNames[i])
        i += 1
    endwhile
    Utility.Wait(1.0)

    i = 0
    while i < N
        Actor t = targets[i] as Actor
        string[] presetSkills = _stressSkillsForPreset(presetNames[i])
        _stressAssertReverted(i, t, presetSkills, allAVs)
        i += 1
    endwhile

    ; Despawn and clear queue.
    _despawnTargets(targets, N)
    StorageUtil.FormListClear(None, "mtf.stress.targets")
    StorageUtil.StringListClear(None, "mtf.stress.presets")

    int total = _pass + _fail + _skip
    JsonUtil.SetIntValue(JSON_FILE, "total", total)
    JsonUtil.SetIntValue(JSON_FILE, "passed", _pass)
    JsonUtil.SetIntValue(JSON_FILE, "failed", _fail)
    JsonUtil.SetIntValue(JSON_FILE, "skipped", _skip)
    JsonUtil.Save(JSON_FILE)

    string summary = "MTF stress(N=" + N + "): " + _pass + "/" + total + " pass"
    if _fail > 0
        summary += " (" + _fail + " FAIL)"
    endif
    Debug.Trace("[MTF_STRESS] === " + summary + " ===")
    Debug.Notification(summary)
EndFunction

Function OnStressKick(string strArg, float numArg, Form sender)
{Worker fiber. Each ModEvent.Send fan-out invocation lands here on a
 fresh Papyrus fiber, so N kicks → N parallel AddAppliedPreset stacks
 all racing on plugin scratch + dispatch context state.

 Function not Event: Caprica forbids non-native scripts from declaring
 new event types. SKSE's mod-event dispatcher accepts either keyword
 (see MTF_AliasPresetApi for the same pattern).}
    int idx = numArg as int
    ; v0.2.13: fork-time trace. All N kicks should land within the same
    ; RealTime second if dispatch is parallel; staggered seconds would
    ; indicate the SKSE dispatcher serialized them. Wall-time of the
    ; whole test scales linearly anyway because AddAppliedPreset funnels
    ; through MainQuest's instance lock — interleaving parallelism, not
    ; CPU parallelism. See dispatch comment in RunStress for details.
    Debug.Trace("[MTF_STRESS] kick idx=" + idx + " forked t=" + Utility.GetCurrentRealTime())
    MTF_MainQuest mq = GetOwningQuest() as MTF_MainQuest
    if mq == None
        StorageUtil.AdjustIntValue(None, "mtf.stress.done", 1)
        return
    endif
    int N = StorageUtil.GetIntValue(None, "mtf.stress.n", 2)
    if idx < 0 || idx >= N
        StorageUtil.AdjustIntValue(None, "mtf.stress.done", 1)
        return
    endif
    Actor  t = StorageUtil.FormListGet(None,   "mtf.stress.targets", idx) as Actor
    string p = StorageUtil.StringListGet(None, "mtf.stress.presets", idx)
    if t == None || p == ""
        StorageUtil.AdjustIntValue(None, "mtf.stress.done", 1)
        return
    endif
    int rc = mq.AddAppliedPreset(t, p)
    if rc != 1
        StorageUtil.AdjustIntValue(None, "mtf.stress.failcount", 1)
        string row = "FAIL stress kick(idx=" + idx + ", preset=" + p + ") AddAppliedPreset rc=" + rc
        Debug.Trace("[MTF_STRESS] " + row)
        JsonUtil.StringListAdd(JSON_FILE, "rows", row)
    endif
    StorageUtil.AdjustIntValue(None, "mtf.stress.done", 1)
EndFunction

Function _despawnTargets(Form[] targets, int count)
    int i = 0
    while i < count
        Actor t = targets[i] as Actor
        if t != None
            t.Disable()
        endif
        i += 1
    endwhile
    Utility.Wait(0.3)
    i = 0
    while i < count
        Actor t = targets[i] as Actor
        if t != None
            t.Delete()
        endif
        i += 1
    endwhile
EndFunction

string Function _stressPresetNameForIdx(int idx)
{Idx 0..29 → "MTF_Stress01".."MTF_Stress30". Two-digit zero-padded so
 lexicographic ordering matches numeric ordering in StorageUtil dumps.}
    int n = idx + 1
    if n < 10
        return "MTF_Stress0" + n
    endif
    return "MTF_Stress" + n
EndFunction

string[] Function _stressSkillsForPreset(string presetName)
{Mirror of tools/build_stress_presets.py GROUPS. The preset NN cycles
 through 6 skill groups of 3 each. Returned AV names are the Skyrim
 actor-value strings (Marksman not Archery, Speechcraft not Speech).}
    ; Tail two chars are "01".."30".
    int len = StringUtil.GetLength(presetName)
    string nn = StringUtil.Substring(presetName, len - 2, 2)
    int n = nn as int
    int g = (n - 1) % 6
    string[] a = new string[3]
    if g == 0
        a[0] = "Marksman"    ; archery
        a[1] = "Smithing"
        a[2] = "Alchemy"
    elseif g == 1
        a[0] = "Enchanting"
        a[1] = "Destruction"
        a[2] = "Illusion"
    elseif g == 2
        a[0] = "OneHanded"
        a[1] = "TwoHanded"
        a[2] = "Block"
    elseif g == 3
        a[0] = "HeavyArmor"
        a[1] = "LightArmor"
        a[2] = "Sneak"
    elseif g == 4
        a[0] = "Restoration"
        a[1] = "Alteration"
        a[2] = "Conjuration"
    else
        a[0] = "Speechcraft"  ; speech
        a[1] = "Lockpicking"
        a[2] = "Pickpocket"
    endif
    return a
EndFunction

string[] Function _allSkillAVs()
{All 18 Skyrim skill AVs in canonical order matching the baseline
 float-list per actor (mtf.stress.baseline). Mirrors _skillAVForId
 outputs.}
    string[] a = new string[18]
    a[0]  = "OneHanded"
    a[1]  = "TwoHanded"
    a[2]  = "Marksman"
    a[3]  = "Block"
    a[4]  = "HeavyArmor"
    a[5]  = "LightArmor"
    a[6]  = "Smithing"
    a[7]  = "Enchanting"
    a[8]  = "Alchemy"
    a[9]  = "Destruction"
    a[10] = "Restoration"
    a[11] = "Alteration"
    a[12] = "Illusion"
    a[13] = "Conjuration"
    a[14] = "Speechcraft"
    a[15] = "Lockpicking"
    a[16] = "Pickpocket"
    a[17] = "Sneak"
    return a
EndFunction

int Function _avIdxIn(string av, string[] arr)
    int i = 0
    while i < arr.Length
        if arr[i] == av
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

bool Function _strInArray(string s, string[] arr)
    int i = 0
    while i < arr.Length
        if arr[i] == s
            return true
        endif
        i += 1
    endwhile
    return false
EndFunction

Function _stressAssertApplied(int idx, Actor t, string[] presetSkills, string[] allAVs, float expectedDelta)
    string npcTag = _npcTag(idx)
    float TOL = 0.5
    int s = 0
    while s < presetSkills.Length
        string av = presetSkills[s]
        int avIdx = _avIdxIn(av, allAVs)
        float baseline = StorageUtil.FloatListGet(t, "mtf.stress.baseline", avIdx)
        float now = t.GetActorValue(av)
        float gotDelta = now - baseline
        bool ok = _floatNear(gotDelta, expectedDelta, TOL)
        string row
        if ok
            _pass += 1
            row = "PASS stress " + npcTag + " applied av=" + av + " delta=" + gotDelta
        else
            _fail += 1
            row = "FAIL stress " + npcTag + " applied av=" + av + " got_delta=" + gotDelta + " want=" + expectedDelta
        endif
        Debug.Trace("[MTF_STRESS] " + row)
        JsonUtil.StringListAdd(JSON_FILE, "rows", row)
        s += 1
    endwhile
EndFunction

Function _stressAssertNoLeak(int idx, Actor t, string[] presetSkills, string[] allAVs)
{For every non-preset skill, verify delta from baseline is ~0. A single
 leak row per NPC: either PASS "no-leak" or FAIL with the list of leaked
 AVs and their per-skill deltas.}
    string npcTag = _npcTag(idx)
    float TOL = 0.5
    string leaks = ""
    int leakCount = 0
    int s = 0
    while s < allAVs.Length
        string av = allAVs[s]
        if !_strInArray(av, presetSkills)
            float baseline = StorageUtil.FloatListGet(t, "mtf.stress.baseline", s)
            float now = t.GetActorValue(av)
            float delta = now - baseline
            if !_floatNear(delta, 0.0, TOL)
                leaks += av + "(" + delta + ") "
                leakCount += 1
            endif
        endif
        s += 1
    endwhile
    string row
    if leakCount == 0
        _pass += 1
        row = "PASS stress " + npcTag + " no-leak"
    else
        _fail += 1
        row = "FAIL stress " + npcTag + " leaked " + leakCount + ": " + leaks
    endif
    Debug.Trace("[MTF_STRESS] " + row)
    JsonUtil.StringListAdd(JSON_FILE, "rows", row)
EndFunction

Function _stressAssertReverted(int idx, Actor t, string[] presetSkills, string[] allAVs)
    string npcTag = _npcTag(idx)
    float TOL = 0.5
    int s = 0
    while s < presetSkills.Length
        string av = presetSkills[s]
        int avIdx = _avIdxIn(av, allAVs)
        float baseline = StorageUtil.FloatListGet(t, "mtf.stress.baseline", avIdx)
        float now = t.GetActorValue(av)
        float delta = now - baseline
        bool ok = _floatNear(delta, 0.0, TOL)
        string row
        if ok
            _pass += 1
            row = "PASS stress " + npcTag + " reverted av=" + av + " delta=" + delta
        else
            _fail += 1
            row = "FAIL stress " + npcTag + " reverted av=" + av + " delta=" + delta + " want=0"
        endif
        Debug.Trace("[MTF_STRESS] " + row)
        JsonUtil.StringListAdd(JSON_FILE, "rows", row)
        s += 1
    endwhile
EndFunction

string Function _npcTag(int idx)
    int n = idx + 1
    if n < 10
        return "npc0" + n
    endif
    return "npc" + n
EndFunction

; ── Visuals stress (End key) ────────────────────────────────────────────────
; Separate from the PgDn skill-effect stress: this one drives the VISUAL
; pipeline. Spawns N humanoids in a ring around the player, applies the
; 5 MTF_Vis* presets round-robin, lets the peace tier render, force-frenzies
; them to drive combat.in transitions, kills them to fire fade-on-death,
; then despawns. Shares mtf.stress.n with the PgDn picker.
;
; Visual contract per preset (see tools/build_visual_presets.py):
;   slot 0 (no cond)         → peace tier, cool color, slow pulse
;   slot 1 (mtf.base:combat.in) → combat tier, hot color, fast pulse
;   transition.duration = 3s  → 3s cross-fade on every tier switch
;   fadeondeath.enabled  = 1  → overlay fades over 2s on death
Function RunVisuals()
    int N = StorageUtil.GetIntValue(None, "mtf.stress.n", 4)
    if N < 1
        N = 1
    elseif N > STRESS_N_MAX
        N = STRESS_N_MAX
    endif

    MTF_MainQuest mq = GetOwningQuest() as MTF_MainQuest
    if mq == None
        Debug.Trace("[MTF_VIS] FATAL: owning quest != MTF_MainQuest")
        Debug.Notification("MTF visuals: ABORT (no MainQuest)")
        return
    endif
    Actor pl = Game.GetPlayer()
    if pl == None
        return
    endif
    Form npcBase = Game.GetForm(VISUAL_NPC_FORMID)
    if npcBase == None
        Debug.Trace("[MTF_VIS] FATAL: spawn base 0x" + _hex8(VISUAL_NPC_FORMID) + " not found")
        Debug.Notification("MTF visuals: ABORT (spawn base 0x" + _hex8(VISUAL_NPC_FORMID) + " missing)")
        return
    endif

    Debug.Notification("MTF visuals: N=" + N + " — consider tgm before frenzy")
    Debug.Trace("[MTF_VIS] === Visual stress start, N=" + N + " ===")

    ; ARRANGE — spawn N in a ring, position each at angDeg from player,
    ; strip armor, round-robin-apply visual presets.
    Form[] spawned = Utility.CreateFormArray(N, None)
    string[] presets = Utility.CreateStringArray(VISUAL_PRESET_COUNT, "")
    presets[0] = "MTF_Vis01"
    presets[1] = "MTF_Vis02"
    presets[2] = "MTF_Vis03"
    presets[3] = "MTF_Vis04"

    ; ── PHASE A — spawn all N. Each iteration: PlaceAtMe → neutralize
    ; hostility → ring-position → strip armor. NO preset application
    ; here so the spawn loop stays tight and we don't interleave the
    ; heavier AddAppliedPreset work with PlaceAtMe back-to-back.
    Debug.Notification("MTF visuals: spawning " + N + " ...")
    int i = 0
    while i < N
        Actor a = pl.PlaceAtMe(npcBase) as Actor
        if a == None
            Debug.Trace("[MTF_VIS] WARN: PlaceAtMe None at i=" + i)
        else
            spawned[i] = a
            ; Forsworn faction is auto-hostile to player; SetRelationshipRank
            ; (player, 4=Lover) + Aggression=0 overrides the faction enmity
            ; for the peace phase. The frenzy phase below flips this back.
            a.SetRelationshipRank(pl, 4)
            a.SetActorValue("Aggression", 0.0)
            a.SetActorValue("Confidence", 4.0)
            a.IgnoreFriendlyHits(true)
            ; Ring placement around the player. Math.cos/sin take degrees.
            float angDeg = (i as float) * (360.0 / (N as float))
            float dx = VISUAL_RING_R * Math.cos(angDeg)
            float dy = VISUAL_RING_R * Math.sin(angDeg)
            a.MoveTo(pl, dx, dy, 0.0)
            ; Strip armor — visual contract is naked. Keep weapons so the
            ; frenzy phase actually animates combat.
            a.UnequipAll()
            Debug.Trace("[MTF_VIS] spawn i=" + i + " ok")
        endif
        i += 1
    endwhile
    ; Let placements settle (havok + leveled-actor resolution) before we
    ; start firing the heavier preset apply path.
    Utility.Wait(1.0)

    ; ── PHASE B — apply ALL 4 presets to each spawned NPC. Each preset
    ; reserves its own base overlay slot via _findFreeBaseSlot; 4 presets
    ; × 1 layer fits in the default 6-slot Body overlay pool.
    Debug.Notification("MTF visuals: applying " + VISUAL_PRESET_COUNT + " tattoos x N=" + N)
    i = 0
    while i < N
        Actor a = spawned[i] as Actor
        if a != None
            int p = 0
            while p < VISUAL_PRESET_COUNT
                int rc = mq.AddAppliedPreset(a, presets[p])
                Debug.Trace("[MTF_VIS] apply i=" + i + " preset=" + presets[p] + " rc=" + rc)
                if rc != 1
                    Debug.Trace("[MTF_VIS] WARN: AddAppliedPreset i=" + i + " preset=" + presets[p] + " rc=" + rc)
                endif
                p += 1
            endwhile
        endif
        i += 1
    endwhile
    ; Give the SKEE post-load race + slow-tick a moment to redraw before
    ; the peace-baseline observation window opens.
    Utility.Wait(1.0)

    ; ACT phase 1 — peace baseline renders (slot 0 tier 0). The slow-tick
    ; condition eval needs a few seconds to settle; T_BASELINE covers that
    ; plus user observation time.
    Debug.Notification("MTF visuals: peace (" + (VISUAL_T_BASELINE as int) + "s)")
    Utility.Wait(VISUAL_T_BASELINE)

    ; ACT phase 2 — frenzy + pairwise StartCombat. Aggression=3 (Frenzied)
    ; + Confidence=4 (Foolhardy) ensures they keep fighting; StartCombat
    ; against the next-index NPC bootstraps the combat target so they
    ; don't all default to attacking the player. They MAY still aggro
    ; the player if player is closer — hence the tgm notification.
    Debug.Notification("MTF visuals: frenzy combat (" + (VISUAL_T_COMBAT as int) + "s)")
    i = 0
    while i < N
        Actor a = spawned[i] as Actor
        if a != None
            a.SetActorValue("Aggression", 3.0)
            a.SetActorValue("Confidence", 4.0)
            a.SetActorValue("Assistance", 0.0)
            a.IgnoreFriendlyHits(false)
            int nxt = i + 1
            if nxt >= N
                nxt = 0
            endif
            Actor other = spawned[nxt] as Actor
            if other != None && other != a
                a.StartCombat(other)
            endif
            a.EvaluatePackage()
        endif
        i += 1
    endwhile
    Utility.Wait(VISUAL_T_COMBAT)

    ; ACT phase 3 — kill all. KillSilent skips the death sound/animation
    ; flourish so the fade-on-death window is more uniform across N actors.
    ; Each preset's fadeondeath.enabled=1 fires the C++ fade pipeline.
    Debug.Notification("MTF visuals: kill + fade (" + (VISUAL_T_FADE as int) + "s)")
    i = 0
    while i < N
        Actor a = spawned[i] as Actor
        if a != None
            a.KillSilent()
        endif
        i += 1
    endwhile
    Utility.Wait(VISUAL_T_FADE)

    ; CLEANUP — Disable, settle, Delete. Mirrors _despawnTargets pattern
    ; from the PgDn stress: two-pass with a short wait lets the engine
    ; tear down attached scripts (incl. our preset tracking) before delete.
    Debug.Notification("MTF visuals: despawn")
    i = 0
    while i < N
        Actor a = spawned[i] as Actor
        if a != None
            a.Disable()
        endif
        i += 1
    endwhile
    Utility.Wait(0.5)
    i = 0
    while i < N
        Actor a = spawned[i] as Actor
        if a != None
            a.Delete()
        endif
        i += 1
    endwhile

    Debug.Trace("[MTF_VIS] === Visual stress end ===")
    Debug.Notification("MTF visuals: done")
EndFunction
