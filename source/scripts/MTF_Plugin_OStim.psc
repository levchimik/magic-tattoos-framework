Scriptname MTF_Plugin_OStim extends MTF_Plugin
{Conditions and effects backed by OStim Standalone. Soft-master: lookup at
 runtime; if OStim isn't loaded the plugin skips registration entirely.

 OStim exposes its actor API through the `OActor` global script — every
 method is `Global Native` so no instance acquisition is needed. We probe
 the OStim.esp file's `OStimFinishedFadeToBlack` GlobalVariable (FormID
 0xECB) to decide if OStim is loaded; if the form resolves, the OActor
 natives are callable.

 Conditions:
   0  in.scene           — currently in an OStim scene (IsInOStim)
   1  excitement         — OActor excitement >= param
   2  excitement.mult    — OActor excitement multiplier >= param × 0.01
   3  times.climaxed     — per-scene climax count >= param
   4  climax.stalled     — IsClimaxStalled flag matches (param 0/1)
   5  has.schlong        — actor has a schlong equipped (HasSchlong)

 Effects:
   0  trigger.climax     — one-shot: Climax(target, ignoreStall)
                            param2 = 0 honors stall, 1 bypasses stall
   1  excitement.modify  — one-shot: ModifyExcitement(target, param)
                            param2 = 0 ignores mult, 1 respects mult
   2  excitement.set     — one-shot: SetExcitement(target, param)
   3  climax.stall       — toggle: while active StallClimax, restore on deactivate
   4  metadata.add       — one-shot: AddMetadata(target, tag string param2 enum)}

GlobalVariable Property OStimProbe Auto Hidden

MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

string Function GetPluginId()
    return "mtf.ostim"
EndFunction
string Function GetPluginLabel()
    return "OStim Standalone"
EndFunction

bool Function _resolveDeps()
    if OStimProbe != None
        return true
    endif
    OStimProbe = Game.GetFormFromFile(0xECB, "OStim.esp") as GlobalVariable
    return OStimProbe != None
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
    return 6
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "in.scene"
    elseif idx == 1
        return "excitement"
    elseif idx == 2
        return "excitement.mult"
    elseif idx == 3
        return "times.climaxed"
    elseif idx == 4
        return "climax.stalled"
    elseif idx == 5
        return "has.schlong"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "In Scene"
    elseif idx == 1
        return "Excitement"
    elseif idx == 2
        return "Excitement Multiplier"
    elseif idx == 3
        return "Times Climaxed"
    elseif idx == 4
        return "Climax Stalled"
    elseif idx == 5
        return "Has Schlong"
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx == 0
        return ""
    elseif idx == 1
        return "Min excitement"
    elseif idx == 2
        return "Min multiplier (×0.01)"
    elseif idx == 3
        return "Min climax count"
    elseif idx == 4
        return "Stall state (0 = not stalled, 1 = stalled)"
    elseif idx == 5
        return ""
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    return 0
EndFunction

int Function GetConditionParamMax(int idx)
    if idx == 1 || idx == 2
        return 100
    elseif idx == 3
        return 10
    elseif idx == 4
        return 1
    endif
    return 0
EndFunction

int Function GetConditionParamDefault(int idx)
    if idx == 1
        return 50
    elseif idx == 2
        return 100
    elseif idx == 3
        return 1
    elseif idx == 4
        return 1
    endif
    return 0
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None
        return false
    endif
    if idx == 0
        return OActor.IsInOStim(target)
    elseif idx == 1
        return OActor.GetExcitement(target) >= (param as float)
    elseif idx == 2
        return OActor.GetExcitementMultiplier(target) >= ((param as float) * 0.01)
    elseif idx == 3
        return OActor.GetTimesClimaxed(target) >= param
    elseif idx == 4
        bool stalled = OActor.IsClimaxStalled(target, true)
        if param == 1
            return stalled
        endif
        return !stalled
    elseif idx == 5
        return OActor.HasSchlong(target)
    endif
    return false
EndFunction

; ── Effects ───────────────────────────────────────────────────────────────────

int Function GetEffectCount()
    return 4
EndFunction

string Function GetEffectId(int idx)
    if idx == 0
        return "trigger.climax"
    elseif idx == 1
        return "excitement.modify"
    elseif idx == 2
        return "excitement.set"
    elseif idx == 3
        return "climax.stall"
    endif
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    if idx == 0
        return "[!] Trigger Climax"
    elseif idx == 1
        return "[!] Modify Excitement"
    elseif idx == 2
        return "[!] Set Excitement"
    elseif idx == 3
        return "Stall Climax"
    endif
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    if idx == 0
        return ""
    elseif idx == 1
        return "Excitement delta"
    elseif idx == 2
        return "Target excitement"
    elseif idx == 3
        return ""
    endif
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    if idx == 1
        return -100
    endif
    return 0
EndFunction

int Function GetEffectParamMax(int idx)
    if idx == 1 || idx == 2
        return 100
    endif
    return 0
EndFunction

int Function GetEffectParamDefault(int idx)
    if idx == 1
        return 20
    elseif idx == 2
        return 80
    endif
    return 0
EndFunction

; ── Param2 ──────────────────────────────────────────────────────────────────

string Function GetEffectParam2Label(int idx)
    if idx == 0
        return "Bypass stall (0/1)"
    elseif idx == 1
        return "Respect multiplier (0/1)"
    endif
    return ""
EndFunction

int Function GetEffectParam2Min(int idx)
    return 0
EndFunction

int Function GetEffectParam2Max(int idx)
    if idx == 0 || idx == 1
        return 1
    endif
    return 0
EndFunction

int Function GetEffectParam2Default(int idx)
    if idx == 0
        return 0
    elseif idx == 1
        return 1
    endif
    return 0
EndFunction

; ── Dispatch ────────────────────────────────────────────────────────────────
; trigger.*, excitement.* are one-shot bursts on activate — no rolling state
; to clean up. climax.stall is the only effect with rolling state: we issue
; StallClimax on activate and PermitClimax on deactivate. There's no
; explicit reference-counted stall API on OStim — Permit unconditionally
; permits, so two overlapping MTF stall effects would race; document the
; limitation, don't try to manage refcount.

Function onActivate(int idx, Actor target, int param, int param2)
    if target == None
        return
    endif
    if idx == 0
        ; trigger.climax: param2 = 0 honor stall, 1 bypass
        OActor.Climax(target, param2 == 1)
    elseif idx == 1
        ; excitement.modify: param = delta, param2 = respect mult
        OActor.ModifyExcitement(target, param as float, param2 == 1)
    elseif idx == 2
        ; excitement.set: param = absolute
        OActor.SetExcitement(target, param as float)
    elseif idx == 3
        ; climax.stall: hold the stall until deactivate
        OActor.StallClimax(target)
    endif
EndFunction

Function onDeactivate(int idx, Actor target, int param, int param2)
    if target == None
        return
    endif
    if idx == 3
        OActor.PermitClimax(target)
    endif
EndFunction
