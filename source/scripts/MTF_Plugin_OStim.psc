Scriptname MTF_Plugin_OStim extends MTF_Plugin
{Conditions and effects backed by OStim Standalone. Soft-master: lookup at
 runtime; if OStim isn't loaded the plugin skips registration entirely.

 Metadata loaded from mtf.ostim.json by the base class.

 OStim exposes its actor API through the `OActor` global script — every
 method is `Global Native` so no instance acquisition is needed. We probe
 the OStim.esp file's `OStimFinishedFadeToBlack` GlobalVariable (FormID
 0xECB) to decide if OStim is loaded; if the form resolves, the OActor
 natives are callable.

 Conditions:
   0  in.scene           — currently in an OStim scene (IsInOStim)
   1  excitement         — OActor excitement >= param
   2  times.climaxed     — per-scene climax count >= param
   3  climax.stalled     — IsClimaxStalled flag matches (param 0/1)
   4  has.schlong        — HasSchlong

 Effects:
   0  trigger.climax        — Climax(target, ignoreStall). param2 = 1 bypass
   1  excitement.modify     — ModifyExcitement(target, param). param2 = mult
   2  excitement.set        — SetExcitement(target, param)
   3  climax.stall          — toggle: StallClimax while active, PermitClimax on deactivate
   4  excitement.mult.set   — SetExcitementMultiplier(target, param)}

GlobalVariable Property OStimProbe Auto Hidden

string Function GetPluginId()
    return "mtf.ostim"
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

; ── Behaviour ───────────────────────────────────────────────────────────────
bool Function checkCondition(int idx, Actor target, int param)
    if target == None
        return false
    endif
    ; in.scene + has.schlong are valid regardless of scene state.
    if idx == 0
        return OActor.IsInOStim(target)
    elseif idx == 4
        return OActor.HasSchlong(target)
    endif
    ; Everything else (excitement, times.climaxed, climax.stalled) is
    ; per-scene state in OStim. Outside a scene the underlying natives
    ; return 0/false, which would falsely satisfy threshold-zero presets
    ; (e.g. `excitement >= 0`) or "not stalled" (`climax.stalled == 0`)
    ; every slow-tick. Gate hard on IsInOStim.
    if !OActor.IsInOStim(target)
        return false
    endif
    if idx == 1
        return OActor.GetExcitement(target) >= (param as float)
    elseif idx == 2
        return OActor.GetTimesClimaxed(target) >= param
    elseif idx == 3
        bool stalled = OActor.IsClimaxStalled(target, true)
        if param == 1
            return stalled
        endif
        return !stalled
    endif
    return false
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
    ; ALL current OStim effects mutate per-scene state — Climax,
    ; Modify/SetExcitement, StallClimax. Outside an active scene the
    ; natives are no-ops at best, silently corrupt at worst. Skip the
    ; whole dispatch if the actor isn't in a scene. Callers should pair
    ; these effects with `in.scene` (cond idx 0) so the tier never
    ; activates outside a scene in the first place — this is a defensive
    ; backstop for misconfigured presets.
    if !OActor.IsInOStim(target)
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
    elseif idx == 4
        ; excitement.mult.set: integer multiplier mapped to float (param=3 → 3.0×)
        OActor.SetExcitementMultiplier(target, param as float)
    endif
EndFunction

Function onDeactivate(int idx, Actor target, int param, int param2)
    if target == None
        return
    endif
    if idx == 3
        ; PermitClimax outside a scene is a safe no-op (the engine
        ; clears stall state when scenes end), so don't gate it on
        ; IsInOStim — we still want to undo any stall we set while the
        ; scene was running, even if the actor has since left.
        OActor.PermitClimax(target)
    endif
EndFunction
