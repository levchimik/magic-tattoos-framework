Scriptname MTF_Plugin_SexLab extends MTF_Plugin
{Conditions and effects backed by SexLab Framework P+. Soft-master: lookup
 at runtime; if SexLab isn't loaded the plugin skips registration entirely.

 Conditions:
   0  in.scene       — currently in a SexLab scene (IsActorActive)
   1  cum.total      — total cum layers >= param (CountCumFx -1)
   2  cum.vaginal    — vaginal cum layers >= param
   3  cum.oral       — oral cum layers >= param
   4  cum.anal       — anal cum layers >= param
   5  skill.vaginal  — vaginal lifetime XP >= param  (0-500, step 1)
   6  skill.anal     — anal lifetime XP >= param     (0-500, step 1)
   7  skill.oral     — oral lifetime XP >= param     (0-500, step 1)
   8  purity         — signed (Pure-Lewd)*1.5 >= param  (-500..500, step 1)
                       Negative = lewd-leaning, 0 = neutral, positive = pure-leaning.
                       Backed by SexLab's GetPurity. Replaces v0.1.16's separate
                       `lewd`/`pure` raw counters — both grow over time and rarely
                       answered the "is this actor pure right now" question users
                       expected. The signed delta does.
   9  has.strapon    — actor has a strapon equipped (HasStrapon)

 Effects:
   0  cum.apply      — one-shot AddCumFx (param = type 0=vaginal/1=oral/2=anal)
                       param2 = layer count 1..5
   1  cum.remove     — one-shot RemoveCumFx (param = type, -1 = all)
   2  skill.add.xp   — one-shot AddSkillXP (param = amount, param2 = skill enum)

 Soft-dep probe: Game.GetFormFromFile(0xD62, "SexLab.esm"). The same form is
 simultaneously SexLabFramework AND sslActorStats (legacy SL quirk —
 sslActorStats extends sslSystemLibrary which the quest also attaches), so
 one probe covers both APIs.}

SexLabFramework Property SexLab Auto Hidden
sslActorStats   Property SLStats Auto Hidden

MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

string Function GetPluginId()
    return "mtf.sexlab"
EndFunction
string Function GetPluginLabel()
    return "SexLab Framework"
EndFunction

bool Function _resolveDeps()
    if SexLab != None && SLStats != None
        return true
    endif
    Form root = Game.GetFormFromFile(0xD62, "SexLab.esm")
    if root == None
        return false
    endif
    if SexLab == None
        SexLab = root as SexLabFramework
    endif
    if SLStats == None
        SLStats = root as sslActorStats
    endif
    return SexLab != None
EndFunction

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
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

; ── Conditions ────────────────────────────────────────────────────────────────

int Function GetConditionCount()
    return 10
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "in.scene"
    elseif idx == 1
        return "cum.total"
    elseif idx == 2
        return "cum.vaginal"
    elseif idx == 3
        return "cum.oral"
    elseif idx == 4
        return "cum.anal"
    elseif idx == 5
        return "skill.vaginal"
    elseif idx == 6
        return "skill.anal"
    elseif idx == 7
        return "skill.oral"
    elseif idx == 8
        return "purity"
    elseif idx == 9
        return "has.strapon"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "In Scene"
    elseif idx == 1
        return "Cum (Total Layers)"
    elseif idx == 2
        return "Cum (Vaginal)"
    elseif idx == 3
        return "Cum (Oral)"
    elseif idx == 4
        return "Cum (Anal)"
    elseif idx == 5
        return "Skill — Vaginal"
    elseif idx == 6
        return "Skill — Anal"
    elseif idx == 7
        return "Skill — Oral"
    elseif idx == 8
        return "Purity (signed)"
    elseif idx == 9
        return "Has Strapon"
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx == 0
        return ""
    elseif idx <= 4
        return "Min layers"
    elseif idx <= 7
        return "Min skill XP"
    elseif idx == 8
        return "Min purity (signed)"
    elseif idx == 9
        return ""
    endif
    return ""
EndFunction

string Function GetConditionDescription(int idx)
    if idx == 0
        return "Triggers while the actor is engaged in an intimate scene."
    elseif idx == 1
        return "Triggers when the actor has at least {param1} cum stain(s) on her body."
    elseif idx == 2
        return "Triggers when the actor has at least {param1} vaginal cum stain(s)."
    elseif idx == 3
        return "Triggers when the actor has at least {param1} oral cum stain(s)."
    elseif idx == 4
        return "Triggers when the actor has at least {param1} anal cum stain(s)."
    elseif idx == 5
        return "Triggers when the actor's lifetime vaginal experience is at or above {param1}."
    elseif idx == 6
        return "Triggers when the actor's lifetime anal experience is at or above {param1}."
    elseif idx == 7
        return "Triggers when the actor's lifetime oral experience is at or above {param1}."
    elseif idx == 8
        return "Triggers when the actor's purity score is at or above {param1} (positive = pure, negative = lewd)."
    elseif idx == 9
        return "Triggers when the actor has a strapon equipped."
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    if idx == 8
        ; v0.1.17: purity is a signed delta — negative = lewd, positive = pure.
        ; -500 covers extreme degenerate-leaning characters; the underlying
        ; GetPurity = (Pure-Lewd)*1.5 can theoretically reach ±750 but values
        ; past ±500 are vanishingly rare in normal play.
        return -500
    endif
    return 0
EndFunction

int Function GetConditionParamMax(int idx)
    if idx <= 4
        return 30
    elseif idx >= 5 && idx <= 8
        ; Skill XP (Vaginal/Anal/Oral) and Purity stat on direct 0..500 (or
        ; -500..500 for Purity) scale, step 1. Skill XP was previously
        ; param×10 — re-scaled per user feedback so the slider value matches
        ; the underlying value 1:1.
        return 500
    endif
    return 100
EndFunction

int Function GetConditionParamDefault(int idx)
    if idx == 1
        return 1
    elseif idx >= 2 && idx <= 4
        return 1
    elseif idx >= 5 && idx <= 7
        ; Was 5 (×10 = 50) before the scale change. Preserve equivalent
        ; default threshold under the new direct 1:1 scale.
        return 50
    elseif idx == 8
        ; Purity default = 0 (neutral). User can pull negative for "is lewd"
        ; or positive for "is pure" thresholds.
        return 0
    endif
    return 0
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None || SexLab == None
        return false
    endif
    if idx == 0
        return SexLab.IsActorActive(target)
    elseif idx == 1
        return SexLab.CountCumFx(target, -1) >= param
    elseif idx == 2
        return SexLab.CountCumVaginal(target) >= param
    elseif idx == 3
        return SexLab.CountCumOral(target) >= param
    elseif idx == 4
        return SexLab.CountCumAnal(target) >= param
    elseif idx == 5
        if SLStats == None
            return false
        endif
        return SLStats.GetSkill(target, "Vaginal") >= (param as float)
    elseif idx == 6
        if SLStats == None
            return false
        endif
        return SLStats.GetSkill(target, "Anal") >= (param as float)
    elseif idx == 7
        if SLStats == None
            return false
        endif
        return SLStats.GetSkill(target, "Oral") >= (param as float)
    elseif idx == 8
        if SLStats == None
            return false
        endif
        ; GetPurity returns float = (Pure - Lewd) * 1.5. Negative = lewd-
        ; leaning, 0 = neutral, positive = pure-leaning.
        return SLStats.GetPurity(target) >= (param as float)
    elseif idx == 9
        return SexLab.HasStrapon(target)
    endif
    return false
EndFunction

; ── Effects ───────────────────────────────────────────────────────────────────

int Function GetEffectCount()
    return 3
EndFunction

string Function GetEffectId(int idx)
    if idx == 0
        return "cum.apply"
    elseif idx == 1
        return "cum.remove"
    elseif idx == 2
        return "skill.add.xp"
    endif
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    if idx == 0
        return "[!] Apply Cum"
    elseif idx == 1
        return "[!] Remove Cum"
    elseif idx == 2
        return "[!] Add Skill XP"
    endif
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    if idx == 0
        return "Cum type"
    elseif idx == 1
        return "Cum type to remove"
    elseif idx == 2
        return "XP amount"
    endif
    return ""
EndFunction

string Function GetEffectDescription(int idx)
    if idx == 0
        return "Burst — splatters {param2} {param1} cum stain(s) on the actor."
    elseif idx == 1
        return "Burst — wipes off {param1} cum stains from the actor."
    elseif idx == 2
        return "Burst — gives the actor {param1} experience in her {param2} skill."
    endif
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    if idx == 1
        return -1
    endif
    return 0
EndFunction

int Function GetEffectParamMax(int idx)
    if idx == 0 || idx == 1
        return 2
    endif
    return 100
EndFunction

int Function GetEffectParamDefault(int idx)
    if idx == 0
        return 0
    elseif idx == 1
        return -1
    elseif idx == 2
        return 10
    endif
    return 0
EndFunction

; ── Param2 ──────────────────────────────────────────────────────────────────

string Function GetEffectParam2Label(int idx)
    if idx == 0
        return "Layer count"
    elseif idx == 2
        return "Skill (0=vag, 1=anal, 2=oral, 3=foreplay)"
    endif
    return ""
EndFunction

int Function GetEffectParam2Min(int idx)
    if idx == 0
        return 1
    endif
    return 0
EndFunction

int Function GetEffectParam2Max(int idx)
    if idx == 0
        return 5
    elseif idx == 2
        return 3
    endif
    return 0
EndFunction

int Function GetEffectParam2Default(int idx)
    if idx == 0
        return 1
    endif
    return 0
EndFunction

; ── Param dropdowns ─────────────────────────────────────────────────────────

int Function GetEffectParamMenuOptionCount(int idx)
    if idx == 0
        return 3
    elseif idx == 1
        return 4
    endif
    return 0
EndFunction

int Function GetEffectParamMenuOptionValue(int idx, int optionIdx)
    if idx == 0
        if optionIdx == 0
            return 0
        elseif optionIdx == 1
            return 1
        elseif optionIdx == 2
            return 2
        endif
    elseif idx == 1
        if optionIdx == 0
            return -1
        elseif optionIdx == 1
            return 0
        elseif optionIdx == 2
            return 1
        elseif optionIdx == 3
            return 2
        endif
    endif
    return 0
EndFunction

string Function GetEffectParamMenuOptionLabel(int idx, int optionIdx)
    if idx == 0
        if optionIdx == 0
            return "Vaginal"
        elseif optionIdx == 1
            return "Oral"
        elseif optionIdx == 2
            return "Anal"
        endif
    elseif idx == 1
        if optionIdx == 0
            return "All"
        elseif optionIdx == 1
            return "Vaginal"
        elseif optionIdx == 2
            return "Oral"
        elseif optionIdx == 3
            return "Anal"
        endif
    endif
    return ""
EndFunction

int Function GetEffectParam2MenuOptionCount(int idx)
    if idx == 2
        return 4
    endif
    return 0
EndFunction

int Function GetEffectParam2MenuOptionValue(int idx, int optionIdx)
    if idx == 2
        return optionIdx
    endif
    return 0
EndFunction

string Function GetEffectParam2MenuOptionLabel(int idx, int optionIdx)
    if idx == 2
        if optionIdx == 0
            return "Vaginal"
        elseif optionIdx == 1
            return "Anal"
        elseif optionIdx == 2
            return "Oral"
        elseif optionIdx == 3
            return "Foreplay"
        endif
    endif
    return ""
EndFunction

; ── Dispatch ────────────────────────────────────────────────────────────────

Function onActivate(int idx, Actor target, int param, int param2)
    if SexLab == None || target == None
        return
    endif
    if idx == 0
        ; cum.apply: param = type (0/1/2), param2 = layers (1..5)
        int layers = param2
        if layers <= 0
            layers = 1
        endif
        if layers == 1
            SexLab.AddCumFx(target, param)
        else
            SexLab.AddCumFxLayers(target, param, layers)
        endif
    elseif idx == 1
        ; cum.remove: param = type (-1 / 0 / 1 / 2)
        SexLab.RemoveCumFx(target, param)
    elseif idx == 2
        ; skill.add.xp: param = amount, param2 = skill enum
        if SLStats == None || param <= 0
            return
        endif
        float amt = param as float
        if param2 == 0
            SLStats.AddSkillXP(target, 0.0, amt, 0.0, 0.0)
        elseif param2 == 1
            SLStats.AddSkillXP(target, 0.0, 0.0, amt, 0.0)
        elseif param2 == 2
            SLStats.AddSkillXP(target, 0.0, 0.0, 0.0, amt)
        elseif param2 == 3
            SLStats.AddSkillXP(target, amt, 0.0, 0.0, 0.0)
        endif
    endif
EndFunction
