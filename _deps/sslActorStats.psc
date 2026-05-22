Scriptname sslActorStats extends Quest
{Minimal stub for MTF_Plugin_SexLab to compile against SexLab Framework P+.
 Declares only the public methods MTF actually calls. The real script
 extends sslSystemLibrary (which cascades to dozens more deps); we only
 need the stat read/write surface.}

int Function GetSkill(Actor ActorRef, string Skill)
    return 0
EndFunction

float Function GetSkillFloat(Actor ActorRef, string Skill)
    return 0.0
EndFunction

int Function GetLewd(Actor ActorRef)
    return 0
EndFunction

int Function GetPure(Actor ActorRef)
    return 0
EndFunction

float Function GetPurity(Actor ActorRef)
    ; Real: (GetPure - GetLewd) * 1.5 — signed delta. Negative = lewd-
    ; leaning, 0 = neutral, positive = pure-leaning. Used by MTF's
    ; "purity" condition (v0.1.17 replacement for the old `lewd` and
    ; `pure` raw-counter conditions).
    return 0.0
EndFunction

Function AddSkillXP(Actor ActorRef, float Foreplay = 0.0, float Vaginal = 0.0, float Anal = 0.0, float Oral = 0.0)
EndFunction
