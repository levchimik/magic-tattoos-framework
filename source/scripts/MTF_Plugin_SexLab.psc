Scriptname MTF_Plugin_SexLab extends MTF_Plugin
{Conditions and effects backed by SexLab Framework P+. Soft-master: lookup
 at runtime; if SexLab isn't loaded the plugin skips registration entirely.

 Metadata loaded from mtf.sexlab.json by the base class.

 Conditions:
   0  in.scene       — IsActorActive (in a scene)
   1  cum.total      — CountCumFx -1
   2  cum.vaginal    — CountCumVaginal
   3  cum.oral       — CountCumOral
   4  cum.anal       — CountCumAnal
   5..7  skill.*     — GetSkill("Vaginal"/"Anal"/"Oral")
   8  purity         — GetPurity (signed, -500..500)
   9  has.strapon    — HasStrapon

 Effects:
   0  cum.apply      — AddCumFx / AddCumFxLayers (param = type, param2 = layers)
   1  cum.remove     — RemoveCumFx (param = type, -1 = all)
   2  skill.add.xp   — AddSkillXP (param = amount, param2 = skill enum)

 Soft-dep probe: Game.GetFormFromFile(0xD62, "SexLab.esm"). The same form is
 simultaneously SexLabFramework AND sslActorStats (legacy SL quirk —
 sslActorStats extends sslSystemLibrary which the quest also attaches), so
 one probe covers both APIs.}

SexLabFramework Property SexLab Auto Hidden
sslActorStats   Property SLStats Auto Hidden

string Function GetPluginId()
    return "mtf.sexlab"
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

; _tryRegister + _host lifted to MTF_Plugin base class. _resolveDeps above is
; the only thing this plugin customises.

; ── Behaviour ───────────────────────────────────────────────────────────────
bool Function checkCondition(Actor target, int param, string cid)
    if target == None || SexLab == None
        return false
    endif
    if cid == "in.scene"
        return SexLab.IsActorActive(target)
    elseif cid == "cum.total"
        return SexLab.CountCumFx(target, -1) >= param
    elseif cid == "cum.vaginal"
        return SexLab.CountCumVaginal(target) >= param
    elseif cid == "cum.oral"
        return SexLab.CountCumOral(target) >= param
    elseif cid == "cum.anal"
        return SexLab.CountCumAnal(target) >= param
    elseif cid == "skill.vaginal"
        if SLStats == None
            return false
        endif
        return SLStats.GetSkill(target, "Vaginal") >= (param as float)
    elseif cid == "skill.anal"
        if SLStats == None
            return false
        endif
        return SLStats.GetSkill(target, "Anal") >= (param as float)
    elseif cid == "skill.oral"
        if SLStats == None
            return false
        endif
        return SLStats.GetSkill(target, "Oral") >= (param as float)
    elseif cid == "purity"
        if SLStats == None
            return false
        endif
        ; GetPurity returns float = (Pure - Lewd) * 1.5. Negative = lewd-
        ; leaning, 0 = neutral, positive = pure-leaning.
        return SLStats.GetPurity(target) >= (param as float)
    elseif cid == "has.strapon"
        return SexLab.HasStrapon(target)
    endif
    return false
EndFunction

Function onActivate(Actor target, int param, int param2, string eid)
    if SexLab == None || target == None
        return
    endif
    if eid == "cum.apply"
        ; param = type (0/1/2), param2 = layers (1..5)
        int layers = param2
        if layers <= 0
            layers = 1
        endif
        if layers == 1
            SexLab.AddCumFx(target, param)
        else
            SexLab.AddCumFxLayers(target, param, layers)
        endif
    elseif eid == "cum.remove"
        ; param = type (-1 / 0 / 1 / 2)
        SexLab.RemoveCumFx(target, param)
    elseif eid == "skill.add.xp"
        ; param = amount, param2 = skill enum
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
