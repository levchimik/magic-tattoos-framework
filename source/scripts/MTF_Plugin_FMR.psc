Scriptname MTF_Plugin_FMR extends MTF_Plugin
{Conditions and effects backed by Fertility Mode (original or Reloaded).
 Soft-master: lookup at runtime; if Fertility Mode isn't loaded the plugin
 skips registration.

 Metadata loaded from mtf.fmr.json by the base class.

 Conditions read FMR's ImmersiveEffectsFaction rank on the actor: FMR's
 poll loop encodes the full fertility state into that single rank
 (1..100 = pregnancy stage, 118 = ovulation, etc.). Faction ranks live
 ON THE ACTOR — sidesteps the array-property quirks that make direct
 Storage.LastConception[i]/LastOvulation[i] reads unreliable.

   0  pregnancy  — rank in (0, 100]; the rank itself IS the belly stage.
                    Min belly stage param = minimum rank to fire.
   1  ovulation  — rank == 118 (egg present OR in cycle ovulation window).
                    Pregnancy ranks (1..100) take precedence — naturally
                    false during pregnancy with no extra gate.

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

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        ; Deps not yet loaded (Fertility Mode may not be active, or its forms
        ; aren't resolvable yet). Re-arm; without this the bail is silent
        ; and we'd stay unregistered for the session.
        RegisterForSingleUpdate(2.0)
        return
    endif
    MTF_MainQuest host = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if host == None || host.registeredPlugins == None
        RegisterForSingleUpdate(1.0)
        return
    endif
    host.RegisterPlugin(self)
    _registered = true
EndFunction

; ── Behaviour (stays in Papyrus — can't be data) ────────────────────────────
int Function _trackedIndex(Actor target)
    if target == None || FMR_Storage == None || FMR_Storage.TrackedActors == None
        return -1
    endif
    return FMR_Storage.TrackedActors.Find(target as Form)
EndFunction

bool Function checkCondition(Actor target, int param, string cid)
    if target == None
        return false
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
        ; Original Fertility Mode v3 lacks ImmersiveEffectsFaction.
        return false
    endif
    int rank = target.GetFactionRank(FMR_IEFaction)
    if cid == "pregnancy"
        ; Pregnancy: rank 1..100 directly IS the belly-stage percentage.
        return rank >= 1 && rank <= 100 && rank >= param
    elseif cid == "ovulation"
        ; Ovulation: rank 118 (egg present OR in ovulation window).
        ; Pregnancy ranks (1..100) take precedence — no !isPregnant gate needed.
        return rank == 118
    endif
    return false
EndFunction

Function onActivate(Actor target, int param, int param2, string eid)
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
