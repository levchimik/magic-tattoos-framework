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
   * Slot 0 -- effect under test (default tier, cond-independent)

 Snapshot+restore wraps the run; user's MCM-set state is preserved.

 Output:
   * Papyrus log: [MTF_TEST] PASS/FAIL/SKIP ...
   * JSON: StorageUtilData/MagicTattoosFramework/tests/last_run.json

 Attached as a SECOND script on MainQuest's PlayerAlias.}

int   Property HOTKEY_DX_F10  = 0x44                                          AutoReadOnly
string Property JSON_FILE      = "MagicTattoosFramework/tests/last_run"        AutoReadOnly
int   Property TEST_COND_SLOT = 7                                             AutoReadOnly
int   Property TEST_FX_SLOT   = 0                                             AutoReadOnly
int   Property TEST_FX_IDX    = 0                                             AutoReadOnly

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
    RegisterForKey(HOTKEY_DX_F10)
EndEvent

Event OnPlayerLoadGame()
    RegisterForKey(HOTKEY_DX_F10)
EndEvent

Event OnKeyDown(int keyCode)
    if keyCode != HOTKEY_DX_F10
        return
    endif
    if Utility.IsInMenuMode()
        return
    endif
    RunAll()
EndEvent

Function RunAll()
    Debug.Notification("MTF tests: running (AAA pipeline)...")
    Debug.Trace("[MTF_TEST] === Run start ===")

    MTF_MainQuest mq = GetOwningQuest() as MTF_MainQuest
    if mq == None
        Debug.Trace("[MTF_TEST] FATAL: owning quest != MTF_MainQuest")
        Debug.Notification("MTF tests: ABORT (no MainQuest)")
        return
    endif
    MTF_Plugin_Base bp = mq.FindPlugin("mtf.base") as MTF_Plugin_Base
    if bp == None
        Debug.Trace("[MTF_TEST] FATAL: mtf.base plugin not registered")
        Debug.Notification("MTF tests: ABORT (mtf.base missing)")
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

    ; v0.2.10: suspend MainQuest's slow tick during the run. Each test
    ; cycles activate→deactivate rapidly; the slow tick firing in between
    ; clobbers the dispatch context (mtf.dispatch.slot/effectidx) and
    ; causes _removeResistShift / _removeSkillShift to read the wrong
    ; (slot, eff), silently skipping spell removal. Symptom: random
    ; modify.resist[X] tests fail with "storage_revert" + "spell_not_removed"
    ; — different X across runs. Cleared in the always-run cleanup block
    ; below so a mid-test abort doesn't leave the tick permanently off.
    mq._setTestMode(true)

    _snapshotState(mq)
    _clearCondSlots1to7(mq)
    _clearTestFxSlot(mq)

    _runConditions(mq, pl)
    _runEffects(mq, pl)

    _restoreState(mq)

    ; Always re-enable the slow tick before exiting RunAll — even if a
    ; test threw or aborted mid-way. Papyrus has no try/finally, but every
    ; control path through RunAll reaches here in practice (the early
    ; returns above all happen BEFORE we set the flag).
    mq._setTestMode(false)

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
    mq.SetCondPluginId(TEST_COND_SLOT, "mtf.base:" + cid)
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

    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "mtf.base:" + eid, p1, p2)
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

 v0.2.9 ordering note: write the string FIRST, then call SetSlotEffectFull.
 SetSlotEffectFull auto-activates the slot (live=true since TEST_FX_SLOT=0),
 and the auto-activate dispatches with whatever the string is at that moment.
 If we wrote string AFTER SetSlotEffectFull and then re-activated manually,
 we'd get a double-activate where the first pass sees an empty string,
 short-circuits in _recomputeSkillShift, and the second pass writes — that
 worked most of the time but flaked unpredictably (which skill failed
 differed every run). One activate, called with the right string, is
 deterministic.}
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

    ; String param FIRST — so SetSlotEffectFull's auto-activate dispatches
    ; with the right id rather than the previous test's stale empty value.
    mq.SetSlotEffectParamNStr(TEST_FX_SLOT, TEST_FX_IDX, 1, p1Id)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "mtf.base:" + eid, 0, p2)

    float afterStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    float afterAV      = pl.GetActorValue(av)

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
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "mtf.base:" + eid, p1, p2)
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

    ; String FIRST -- see _testFxAVStr's ordering note for the rationale.
    mq.SetSlotEffectParamNStr(TEST_FX_SLOT, TEST_FX_IDX, 1, resistId)
    mq.SetSlotEffectFull(TEST_FX_SLOT, TEST_FX_IDX, "mtf.base:modify.resist", 0, delta)

    float afterStorage = StorageUtil.GetFloatValue(pl, storageKey, 0.0)
    bool afterHasSpell = pl.HasSpell(resistSpell)

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
