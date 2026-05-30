Scriptname MTF_Plugin_SexLab extends MTF_Plugin
{Conditions and effects backed by SexLab Framework P+. Soft-master: lookup
 at runtime; if SexLab isn't loaded the plugin skips registration entirely.

 Metadata loaded from mtf.sexlab.json by the base class.

 Conditions:
   0  in.scene       — IsActorActive (in a scene)
   1  scene.partner  — in a scene with an actor whose name matches one of a
                       comma-separated list (param1 text); SexLab P+
                       GetActorController -> sslThreadController.GetPositions()
   2..4  skill.*     — GetSkill("Vaginal"/"Anal"/"Oral")
   5  purity         — GetPurity (signed, -500..500)

 Effects:
   0  skill.add.xp   — AddSkillXP (param = amount, param2 = skill enum)

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
    elseif cid == "scene.partner"
        ; in a scene with an actor whose display name is in a comma-separated
        ; list (param1 free-text, e.g. "Lydia,Serana"). Roster comes from the
        ; actor's SexLab thread controller; exclude self so it matches a partner.
        if !SexLab.IsActorActive(target)
            return false
        endif
        sslThreadController tc = SexLab.GetActorController(target)
        if tc == None
            return false
        endif
        return _matchPartnerName(_host().GetEvalParamStr(), tc.GetPositions(), target)
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
    endif
    return false
EndFunction

Function onActivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if SexLab == None || target == None
        return
    endif
    if eid == "skill.add.xp"
        ; v0.2.9: param1 = amount (slider int), param2 = menu id
        ; (vaginal/anal/oral/foreplay). The pre-refactor enum was
        ; 0=Vaginal, 1=Anal, 2=Oral, 3=Foreplay -- preserve that mapping
        ; via the AddSkillXP positional args (vaginal, anal, oral, foreplay).
        if SLStats == None || param <= 0
            return
        endif
        float amt = param as float
        string skillId = _paramNStrEx(slot, effectIdx, useScratch, presetName, 2)
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

; ── scene.partner name match ────────────────────────────────────────────────
; Returns true if any scene actor other than `self` has a display name equal to
; one of the comma-separated names in `csv`. Papyrus string == is case-
; insensitive, so "lydia" matches "Lydia". Each CSV token is trimmed so
; "General Tullius, Lydia" works.
bool Function _matchPartnerName(string csv, Actor[] roster, Actor selfActor)
    if csv == "" || roster == None
        return false
    endif
    string[] names = StringUtil.Split(csv, ",")
    if names.Length < 1
        return false
    endif
    int i = 0
    while i < roster.Length
        Actor a = roster[i]
        if a != None && a != selfActor
            string dn = a.GetDisplayName()
            int j = 0
            while j < names.Length
                string want = _trim(names[j])
                if want != "" && want == dn
                    return true
                endif
                j += 1
            endwhile
        endif
        i += 1
    endwhile
    return false
EndFunction

; Strips leading/trailing spaces. StringUtil.Substring's len arg must be > 0
; here (guarded by last >= start) to dodge PapyrusUtil's "len == 0 means
; to-end-of-string" quirk.
string Function _trim(string s)
    int n = StringUtil.GetLength(s)
    if n <= 0
        return ""
    endif
    int start = 0
    while start < n && StringUtil.GetNthChar(s, start) == " "
        start += 1
    endwhile
    int last = n - 1
    while last >= start && StringUtil.GetNthChar(s, last) == " "
        last -= 1
    endwhile
    if last < start
        return ""
    endif
    return StringUtil.Substring(s, start, last - start + 1)
EndFunction
