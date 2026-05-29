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
   0  scene.composition  — in a scene; param menu picks the composition
                           (any/solo/1m1f/2f/2m/mmf/mff/4p). "any" == legacy
                           in.scene (IsInOStim). Composition options resolve
                           OActor.GetThreadID -> OThread.GetActors and count
                           males by HasSchlong; need OStim API 7.3.5c+.
   1  excitement         — OActor excitement >= param
   2  times.climaxed     — per-scene climax count >= param
   3  climax.stalled     — IsClimaxStalled flag matches (param 0/1)
   4  has.schlong        — HasSchlong

 Effects:
   0  trigger.climax        — Climax(target, ignoreStall). param = 1 bypass
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

; _tryRegister + _host lifted to MTF_Plugin base class. _resolveDeps above is
; the only thing this plugin customises.

; ── Behaviour ───────────────────────────────────────────────────────────────
bool Function checkCondition(Actor target, int param, string cid)
    if target == None
        return false
    endif
    ; has.schlong is valid regardless of scene state.
    if cid == "has.schlong"
        return OActor.HasSchlong(target)
    endif
    ; scene.composition: "any" == legacy in.scene (just in a scene). Specific
    ; compositions walk the thread roster; see _matchComposition. Gated on
    ; IsInOStim first so the GetThreadID/GetActors natives (OStim 7.3.5c+) only
    ; fire for actors actually in a scene.
    if cid == "scene.composition"
        if !OActor.IsInOStim(target)
            return false
        endif
        string want = _host().GetEvalParamStr()
        if want == "" || want == "any"
            return true
        endif
        int tid = OActor.GetThreadID(target)
        if tid < 0
            return false
        endif
        Actor[] acts = OThread.GetActors(tid)
        int n = acts.Length
        if n < 1
            return false
        endif
        int males = 0
        int i = 0
        while i < n
            if acts[i] != None && OActor.HasSchlong(acts[i])
                males += 1
            endif
            i += 1
        endwhile
        return _matchComposition(want, n, males, n - males)
    endif
    ; Everything else (excitement, times.climaxed, climax.stalled) is
    ; per-scene state in OStim. Outside a scene the underlying natives
    ; return 0/false, which would falsely satisfy threshold-zero presets
    ; (e.g. `excitement >= 0`) or "not stalled" (`climax.stalled == 0`)
    ; every slow-tick. Gate hard on IsInOStim.
    if !OActor.IsInOStim(target)
        return false
    endif
    if cid == "excitement"
        return OActor.GetExcitement(target) >= (param as float)
    elseif cid == "times.climaxed"
        return OActor.GetTimesClimaxed(target) >= param
    elseif cid == "climax.stalled"
        ; v0.2.9: param1 is now a menu id ("stalled" / "not_stalled"), fetched
        ; via host.GetEvalParamStr(). Int param ignored on this branch.
        bool stalled = OActor.IsClimaxStalled(target, true)
        if _host().GetEvalParamStr() == "stalled"
            return stalled
        endif
        return !stalled
    endif
    return false
EndFunction

; Maps a roster headcount + male/female tally onto the menu ids declared in
; mtf.ostim.json. Sex is schlong-based (OStim assigns scene positions the same
; way), so a futa fills a male slot — 1m1f, not 2f. 4p is any scene of 4+
; actors (foursome or larger), any mix — covers 5-actor scenes like 4f1m.
bool Function _matchComposition(string want, int n, int males, int females)
    if want == "solo"
        return n == 1
    elseif want == "1m1f"
        return n == 2 && males == 1 && females == 1
    elseif want == "2f"
        return n == 2 && females == 2
    elseif want == "2m"
        return n == 2 && males == 2
    elseif want == "mmf"
        return n == 3 && males == 2 && females == 1
    elseif want == "mff"
        return n == 3 && males == 1 && females == 2
    elseif want == "4p"
        return n >= 4
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

Function onActivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if target == None
        return
    endif
    ; ALL current OStim effects mutate per-scene state — Climax,
    ; Modify/SetExcitement, StallClimax. Outside an active scene the
    ; natives are no-ops at best, silently corrupt at worst. Skip the
    ; whole dispatch if the actor isn't in a scene. Callers should pair
    ; these effects with the `scene.composition` condition (any value gates
    ; on IsInOStim) so the tier never activates outside a scene in the first
    ; place — this is a defensive
    ; backstop for misconfigured presets.
    if !OActor.IsInOStim(target)
        return
    endif
    if eid == "trigger.climax"
        ; v0.2.6: catalog renamed param2 → param1 (was non-contiguous).
        ; param = 0 honor stall, 1 bypass.
        OActor.Climax(target, param == 1)
    elseif eid == "excitement.modify"
        ; param = delta, param2 = respect mult
        OActor.ModifyExcitement(target, param as float, param2 == 1)
    elseif eid == "excitement.set"
        ; param = absolute
        OActor.SetExcitement(target, param as float)
    elseif eid == "climax.stall"
        ; hold the stall until deactivate
        OActor.StallClimax(target)
    elseif eid == "excitement.mult.set"
        ; integer multiplier mapped to float (param=3 → 3.0×)
        OActor.SetExcitementMultiplier(target, param as float)
    endif
EndFunction

Function onDeactivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if target == None
        return
    endif
    if eid == "climax.stall"
        ; PermitClimax outside a scene is a safe no-op (the engine
        ; clears stall state when scenes end), so don't gate it on
        ; IsInOStim — we still want to undo any stall we set while the
        ; scene was running, even if the actor has since left.
        OActor.PermitClimax(target)
    endif
EndFunction
