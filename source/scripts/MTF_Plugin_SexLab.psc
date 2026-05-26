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
        ; v0.2.9: param1 is now a menu id (vaginal/oral/anal). Map to SexLab's
        ; int enum. param2 = layers (1..5, slider, int).
        int cumType = _cumTypeFromId(_dispPNStr(1))
        if cumType < 0
            return
        endif
        int layers = param2
        if layers <= 0
            layers = 1
        endif
        if layers == 1
            SexLab.AddCumFx(target, cumType)
        else
            SexLab.AddCumFxLayers(target, cumType, layers)
        endif
    elseif eid == "cum.remove"
        ; v0.2.9: param1 is now a menu id (all/vaginal/oral/anal). "all" maps
        ; to SexLab's -1 sentinel; per-orifice ids map to 0/1/2.
        string remId = _dispPNStr(1)
        int removeType = -2
        if remId == "all"
            removeType = -1
        else
            removeType = _cumTypeFromId(remId)
        endif
        if removeType == -2
            return
        endif
        SexLab.RemoveCumFx(target, removeType)
    elseif eid == "skill.add.xp"
        ; v0.2.9: param1 = amount (slider int), param2 = menu id
        ; (vaginal/anal/oral/foreplay). The pre-refactor enum was
        ; 0=Vaginal, 1=Anal, 2=Oral, 3=Foreplay -- preserve that mapping
        ; via the AddSkillXP positional args (vaginal, anal, oral, foreplay).
        if SLStats == None || param <= 0
            return
        endif
        float amt = param as float
        string skillId = _dispPNStr(2)
        ; Positional mapping preserved verbatim from the pre-v0.2.9 int-enum
        ; dispatch: enum 0=Vaginal/1=Anal/2=Oral/3=Foreplay corresponded to
        ; AddSkillXP arg slots (vaginal, anal, oral, foreplay). The SLStats
        ; AddSkillXP signature is (target, foreplay, vaginal, anal, oral) --
        ; i.e. foreplay first, then the three orifice skills.
        if skillId == "vaginal"
            SLStats.AddSkillXP(target, 0.0, amt, 0.0, 0.0)
        elseif skillId == "anal"
            SLStats.AddSkillXP(target, 0.0, 0.0, amt, 0.0)
        elseif skillId == "oral"
            SLStats.AddSkillXP(target, 0.0, 0.0, 0.0, amt)
        elseif skillId == "foreplay"
            SLStats.AddSkillXP(target, amt, 0.0, 0.0, 0.0)
        endif
    endif
EndFunction

; v0.2.9: Cum-type menu id → SexLab's AddCumFx / RemoveCumFx int enum.
; (Vaginal = 0, Oral = 1, Anal = 2 — matches pre-refactor positional ints.)
; Returns -2 on unknown id so callers can detect and bail; "all" is handled
; separately in cum.remove via the -1 sentinel.
int Function _cumTypeFromId(string id)
    if id == "vaginal"
        return 0
    elseif id == "oral"
        return 1
    elseif id == "anal"
        return 2
    endif
    return -2
EndFunction
