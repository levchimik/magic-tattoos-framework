Scriptname MTF_DebugApply extends ActiveMagicEffect
{Magic effect attached to MTF_Spell_DebugApply. Fires OnEffectStart on
 the cast target — we add that target as a tracked subject using the
 default preset configured in MCM > Subjects.

 Console workflow:
   player.addspell <thisSpellFormID>           ; once per save (or auto via host alias)
   prid 1A695                                  ; selects Vilkas (or any NPC)
   moveto player                               ; teleport target to player
   player.cast <thisSpellFormID> 1A695         ; fires OnEffectStart with akTarget=Vilkas

 Why this exists: ReferenceAlias-script functions are unreachable from
 the vanilla console `<refid>.<func>` syntax. Magic-effect scripts ARE
 directly attached to the target actor's active-effects list, so they
 can dispatch reliably. This sidesteps the alias-dispatch limitation
 for automated testing.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    MTF_MainQuest MainQuest = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if MainQuest == None
        Debug.Notification("MTF_DebugApply: MainQuest lookup failed")
        return
    endif
    if akTarget == None
        return
    endif
    string preset = MainQuest.GetDefaultSubjectPreset()
    if preset == ""
        Debug.Notification("MTF: set default preset first (MCM > Subjects)")
        return
    endif
    int rc = MainQuest.AddTrackedActor(akTarget, preset)
    string nm = akTarget.GetDisplayName()
    if rc == 1
        Debug.Notification("MTF: added " + nm + " (preset: " + preset + ")")
        MainQuest.EvalAndDrawActor(akTarget)
    elseif rc == 0
        Debug.Notification("MTF: " + nm + " already tracked; preset refreshed")
        MainQuest.EvalAndDrawActor(akTarget)
    elseif rc == -1
        Debug.Notification("MTF: cannot tattoo the player from this spell")
    elseif rc == -3
        Debug.Notification("MTF: tracked-subject cap reached")
    elseif rc == -4
        Debug.Notification("MTF: set default preset first (MCM > Subjects)")
    endif
EndEvent
