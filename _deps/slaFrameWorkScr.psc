Scriptname slaFrameworkScr extends Quest
{Minimal canonical-class stub used by MTF_Plugin_SLA to compile against any
 SLA fork (OSL Aroused, SLO Aroused NG, Aroused Redux). Declares only the
 methods MTF actually calls — the full source pulls in fork-specific deps
 (slaMainScr, slaConfigScr, OSLAroused_ModInterface) that we don't want to
 cascade-compile.

 All listed methods exist on every fork's slaFrameworkScr class with
 matching signatures. At runtime Game.GetFormFromFile(0x04290F,
 "SexLabAroused.esm") resolves to whichever fork the user has loaded.}

int Function GetActorArousal(Actor akRef)
    return -2
EndFunction

int Function GetActorExposure(Actor akRef)
    return -2
EndFunction

Int Function SetActorExposure(Actor akRef, Int val)
    return -2
EndFunction

float Function GetActorExposureRate(Actor akRef)
    return -2.0
EndFunction

Float Function SetActorExposureRate(Actor akRef, Float val)
    return -2.0
EndFunction

Function UpdateActorOrgasmDate(Actor akRef)
EndFunction

Float Function GetActorDaysSinceLastOrgasm(Actor akRef)
    return 0.0
EndFunction

bool Function IsActorArousalLocked(Actor akRef)
    return false
EndFunction
