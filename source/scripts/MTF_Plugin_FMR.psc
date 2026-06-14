Scriptname MTF_Plugin_FMR extends MTF_Plugin
{Conditions and effects backed by Fertility Mode (original or Reloaded).
 Soft-master: lookup at runtime; if Fertility Mode isn't loaded the plugin
 skips registration.

 Metadata loaded from mtf.fmr.json by the base class.

 Two condition backends, chosen at runtime by which Fertility Mode is loaded:

 * RELOADED — reads FMR's ImmersiveEffectsFaction rank on the actor. FMR's
   poll loop encodes the full fertility state into that single rank
   (1..100 = pregnancy stage, 118 = ovulation, etc.). Faction ranks live
   ON THE ACTOR — sidesteps the array-property quirks that make direct
   Storage.LastConception[i]/LastOvulation[i] reads unreliable.

 * ORIGINAL (non-Reloaded) — no ImmersiveEffectsFaction exists, so we read
   the same state straight off the _JSW_BB_Storage arrays the way FM's own
   _JSW_BB_Utility does. See _checkConditionOriginal.

   0  pregnancy  — Reloaded: rank in (0, 100], the rank IS the belly stage.
                    Original: LastConception>0, % = (now-LastConception) /
                    PregnancyDuration. Param = minimum belly-stage % to fire.
   1  ovulation  — Reloaded: rank == 118 (egg present / ovulation window).
                    Original: LastOvulation in (0, EggLife] (egg age in days).
                    Pregnancy naturally excludes ovulation (FM clears the egg
                    on conception).
   postpartum — Reloaded only: rank 101..115 (post-birth recovery). Param =
                    minimum recovery % to fire ((rank-101)/14*100).
   cycle.phase — Reloaded only: param1 (menu) picks menstruation / follicular
                    / ovulation / luteal -> faction ranks 116 / 117 / 118 / 119.
                    Original FM has no menstrual cycle, so this reads false on
                    the non-Reloaded backend. (Standalone `ovulation` above is
                    kept separately for now.)

 Effects:
   0  trigger.ovulation  — one-shot: set LastOvulation[index] = 0.001
                            (no-op if currently pregnant)}

_JSW_BB_Storage Property FMR_Storage Auto Hidden
GlobalVariable Property FMR_EggLife Auto Hidden
GlobalVariable Property FMR_PregnancyDuration Auto Hidden
; FMR's "ImmersiveEffectsFaction" (form 0x02666B in Fertility Mode.esm)
; encodes the full fertility state in the actor's rank:
;   0          = cleared / no effect
;   1..100     = pregnancy stage (1 = just conceived, 100 = full term)
;   101..115   = post-birth recovery
;   116        = menstruation
;   117        = follicular (between menstruation and ovulation)
;   118        = ovulation (egg present OR in ovulation window)
;   119        = luteal / PMS
;   120        = labor
; Set by FMR's poll loop (_JSW_BB_HandlerQuestAliasScript:1080..1096 for
; cycle phases, :1395..1405 for pregnancy). See
; project_faction_as_state_probe memory note for the broader pattern.
Faction Property FMR_IEFaction Auto Hidden

string Function GetPluginId()
    return "mtf.fmr"
EndFunction

bool Function _resolveDeps()
    if FMR_Storage != None && FMR_EggLife != None && FMR_PregnancyDuration != None && FMR_IEFaction != None
        return true
    endif
    if FMR_Storage == None
        FMR_Storage = Game.GetFormFromFile(0x000D62, "Fertility Mode.esm") as _JSW_BB_Storage
    endif
    if FMR_EggLife == None
        FMR_EggLife = Game.GetFormFromFile(0x0125F1, "Fertility Mode.esm") as GlobalVariable
    endif
    if FMR_PregnancyDuration == None
        FMR_PregnancyDuration = Game.GetFormFromFile(0x000D66, "Fertility Mode.esm") as GlobalVariable
    endif
    if FMR_IEFaction == None
        FMR_IEFaction = Game.GetFormFromFile(0x02666B, "Fertility Mode.esm") as Faction
    endif
    ; FMR_Storage is the only hard requirement (effect-activate writes
    ; directly to its array). FMR_IEFaction is FMR-only — original
    ; Fertility Mode v3 lacks it, in which case conditions read false
    ; gracefully.
    return FMR_Storage != None
EndFunction

; _tryRegister + _host lifted to MTF_Plugin base class. _resolveDeps above is
; the only thing this plugin customises.

; ── Behaviour (stays in Papyrus — can't be data) ────────────────────────────
int Function _trackedIndex(Actor target)
    if target == None || FMR_Storage == None || FMR_Storage.TrackedActors == None
        return -1
    endif
    return FMR_Storage.TrackedActors.Find(target as Form)
EndFunction

float Function _spermCount(Actor target)
{Sperm units currently active in `target`, straight off _JSW_BB_Storage.
 0 if untracked. Indexed read uses no `== None` guard
 (project_papyrus_array_none_cast_noise); a truly-None array aborts the
 function gracefully via a Papyrus error on the indexed read.}
    int i = _trackedIndex(target)
    if i < 0
        return 0.0
    endif
    return FMR_Storage.SpermCount[i]
EndFunction

int Function _childCount()
{Number of children in FMR's player child roster (PlayerChildName.Length —
 the same count FMR's own MCM shows). Flat roster, not per-actor. 0 if
 Storage is unresolved; a truly-None array aborts gracefully on the .Length
 read (project_papyrus_array_none_cast_noise convention).}
    if FMR_Storage == None
        return 0
    endif
    return FMR_Storage.PlayerChildName.Length
EndFunction

bool Function checkCondition(Actor target, int param, string cid)
    if target == None
        return false
    endif
    ; Sperm presence is read straight off _JSW_BB_Storage.SpermCount and is
    ; backend-independent (the faction-rank encoding never carries it), so
    ; handle it before the Reloaded/original split. Works on any FM variant
    ; that keeps the _JSW_BB_Storage SpermCount array. param = min sperm units.
    if cid == "inseminated"
        return _spermCount(target) >= param as float
    endif
    ; Child count = FMR's PlayerChild* roster (a flat, NON-mother-attributed
    ; list — PlayerChildAdd ignores the actor for indexing), so it's the
    ; PLAYER's children, not a per-NPC tally. Only meaningful for the player.
    ; Backend-independent; handle before the Reloaded/original split.
    if cid == "children"
        if target != Game.GetPlayer()
            return false
        endif
        return _childCount() >= param
    endif
    ; Inline resolve: the Auto Hidden FMR_IEFaction property doesn't always
    ; backing-attach mid-save (project_papyrus_property_attach), so it can
    ; stay None across reloads even after a successful registration.
    ; Re-resolve on every call when None; GetFormFromFile is cheap and self-
    ; caches into the property slot once it returns non-None.
    if FMR_IEFaction == None
        FMR_IEFaction = Game.GetFormFromFile(0x02666B, "Fertility Mode.esm") as Faction
    endif
    if FMR_IEFaction == None
        ; Original (non-Reloaded) Fertility Mode has no ImmersiveEffectsFaction
        ; rank encoding — compute the same state directly from _JSW_BB_Storage.
        return _checkConditionOriginal(target, param, cid)
    endif
    int rank = target.GetFactionRank(FMR_IEFaction)
    if cid == "pregnancy"
        ; Pregnancy: rank 1..100 directly IS the belly-stage percentage.
        return rank >= 1 && rank <= 100 && rank >= param
    elseif cid == "ovulation"
        ; Ovulation: rank 118 (egg present OR in ovulation window).
        ; Pregnancy ranks (1..100) take precedence — no !isPregnant gate needed.
        return rank == 118
    elseif cid == "postpartum"
        ; Post-birth recovery: rank 101..115. The handler sets
        ; 101 + (birthDays/RecoveryDuration)*14 (see _JSW_BB_HandlerQuestAlias
        ; :1034-1041), so recovery% = (rank-101)/14*100. param = min recovery %.
        if rank < 101 || rank > 115
            return false
        endif
        return ((rank - 101) * 100) / 14 >= param
    elseif cid == "cycle.phase"
        ; Consolidated cycle picker — param1 (menu) carries the phase id.
        ; Map to the FMR faction-rank cycle encoding (handler :1077-1096),
        ; which is set only while not pregnant. Reloaded-only; original FM
        ; has no cycle (this branch is unreachable on that backend — it
        ; routes through _checkConditionOriginal instead).
        string phaseId = _host().GetEvalParamStr()
        int wantRank = -1
        if phaseId == "menstruation"
            wantRank = 116
        elseif phaseId == "follicular"
            wantRank = 117
        elseif phaseId == "ovulation"
            wantRank = 118
        elseif phaseId == "luteal"
            wantRank = 119
        endif
        return wantRank > 0 && rank == wantRank
    endif
    return false
EndFunction

bool Function _checkConditionOriginal(Actor target, int param, string cid)
{Original (non-Reloaded) Fertility Mode path — no ImmersiveEffectsFaction, so
 read the state straight off the _JSW_BB_Storage parallel arrays the same way
 FM's own _JSW_BB_Utility does (verified against FM 3.x source):

   pregnancy  — LastConception[i] > 0 ⇒ pregnant. Progress is
                pregnantDay = (now - LastConception[i]) days over
                PregnancyDuration days (handler line 859 / utility line 90).
                Fires when that percentage >= param (min belly stage).
   ovulation  — LastOvulation[i] is the egg's ACCUMULATED AGE in days (starts
                at 0.001, grows each poll — utility 76/83), NOT a timestamp.
                A viable egg is LastOvulation[i] > 0 && <= EggLife (utility
                line 224 / config line 289). FM clears it to 0 on conception,
                so pregnancy naturally excludes ovulation.

 Indexed array reads use no `== None` guard — a truly-None array Papyrus-errors
 and aborts gracefully; a `== None` compare would spam cast noise on a valid
 array (project_papyrus_array_none_cast_noise). Globals fall back to FM's
 documented defaults (30-day pregnancy, 2-day egg) if the form didn't resolve.}
    if FMR_Storage == None
        return false
    endif
    int i = _trackedIndex(target)
    if i < 0
        return false
    endif

    if cid == "pregnancy"
        float conception = FMR_Storage.LastConception[i]
        if conception <= 0.0
            return false
        endif
        float dur = 30.0
        if FMR_PregnancyDuration != None && FMR_PregnancyDuration.GetValue() > 0.0
            dur = FMR_PregnancyDuration.GetValue()
        endif
        float pregnantDay = Utility.GetCurrentGameTime() - conception
        float pct = (pregnantDay / dur) * 100.0
        return pct >= param as float
    elseif cid == "ovulation"
        float eggAge = FMR_Storage.LastOvulation[i]
        if eggAge <= 0.0
            return false
        endif
        float eggLife = 2.0
        if FMR_EggLife != None && FMR_EggLife.GetValue() > 0.0
            eggLife = FMR_EggLife.GetValue()
        endif
        return eggAge <= eggLife
    endif
    return false
EndFunction

Function onActivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if eid != "trigger.ovulation" || target == None || FMR_Storage == None
        return
    endif
    int i = _trackedIndex(target)
    if i < 0
        return
    endif
    ; Don't interrupt an in-progress pregnancy, and don't re-trigger if she's
    ; already ovulating. Indexed access (no `== None` guard) — the guard logs
    ; false-positive cast errors on Auto arrays
    ; (project_papyrus_array_none_cast_noise); a truly-None array would
    ; Papyrus-error on the indexed read and abort the function gracefully.
    if FMR_Storage.LastConception[i] > 0.0
        return
    endif
    if FMR_Storage.LastOvulation[i] > 0.0
        return
    endif
    FMR_Storage.LastOvulation[i] = 0.001
EndFunction
