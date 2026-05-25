Scriptname MTF_Plugin extends Quest
{Abstract base for MagicTattoosFramework plugins. See docs/INTEGRATION_PLUGINS.md.}

; ── IMPORTANT: ZERO NEW SCRIPT-LEVEL VARS IN THIS BASE CLASS. ───────────────
; This base is the parent of 9 derived plugin scripts (Base, FMR, BFNG,
; OStim, SLA, SexLab, SlaveTats, PresetEventsTest, SkyrimNet). Every saved
; game has a persisted instance of each. Adding ~30 script-level vars here
; in v0.2.0 hung save load — 30 vars × 9 instances = 270 var-attach events
; that cascaded into None-cast errors and froze the VM
; (project_papyrus_bulk_var_add memory note — base-class amplifier section).
;
; All metadata getters below read from JSON on demand via JsonUtil. JsonUtil
; loads each file once into PapyrusUtil's internal cache; subsequent reads
; are SKSE-native map lookups (microseconds). MCM open does ~200 reads =
; sub-millisecond total. checkCondition/onActivate never fetch metadata.
;
; A derived plugin that genuinely needs cached arrays for hot-path reads
; CAN add them on its OWN script (impact contained to one saved-instance —
; threshold well below the bulk-var cliff). See MTF_Plugin_FMR for the
; opt-in caching pattern.

bool Property _registered = false Auto Hidden

; ── Catalog path ────────────────────────────────────────────────────────────
string Function _catalogFile()
    {Override only for non-conventional paths. Default derives from
     GetPluginId(): "MagicTattoosFramework/plugins/<pluginId>". JsonUtil
     paths are relative to Data/SKSE/Plugins/StorageUtilData/.}
    return "MagicTattoosFramework/plugins/" + GetPluginId()
EndFunction

; ── Lifecycle ────────────────────────────────────────────────────────────────
Event OnInit()
    ; Delay so MainQuest.OnInit has a chance to allocate its registry array.
    RegisterForSingleUpdate(0.5)
EndEvent

Event OnUpdate()
    _tryRegister()
EndEvent

; Resolve the framework host quest. Identical body across every plugin —
; lifted here so derived classes don't have to repeat the FormID/master.
MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

; Lifted registration loop. Every integration plugin used to repeat this
; ~15-line shape verbatim (deps gate + host gate + register + post-hook).
; Two override hooks below let plugins customise without re-declaring the
; whole function:
;
;   _resolveDeps() — probe for the target mod's forms / API; return false
;                    until the deps are ready, then cache+true. Default
;                    returns true (no soft-dep — e.g. MTF_Plugin_Base).
;
;   _onRegistered() — called once, after the host accepted the plugin.
;                     Use for one-shot per-session bridge setup (e.g.
;                     SkyrimNet schema registration). Default no-op.
;
; Re-arm cadence: 2s when waiting for deps (mod may still be loading), 1s
; when waiting for host (registry array allocates during MainQuest.OnInit).
; Both bail silently otherwise — without the re-arms the plugin would
; stay unregistered for the rest of the session.
Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        RegisterForSingleUpdate(2.0)
        return
    endif
    MTF_MainQuest host = _host()
    if host == None || host.registeredPlugins == None
        RegisterForSingleUpdate(1.0)
        return
    endif
    host.RegisterPlugin(self)
    _registered = true
    _onRegistered()
EndFunction

; ── OVERRIDE: dependency gate ───────────────────────────────────────────────
bool Function _resolveDeps()
{Return false until the plugin's target mod is loaded and its forms/APIs
 are resolvable; return true once dependencies are satisfied. Plugins with
 no soft-dep leave the default (always-true) alone. Implementations should
 cache resolved Form properties on first success so subsequent calls are
 a no-cost early-out.}
    return true
EndFunction

; ── OVERRIDE: post-registration hook ────────────────────────────────────────
Function _onRegistered()
{Called once when registration succeeds. Default no-op. Override for
 first-session bridge setup that requires the host to know about us — e.g.
 SkyrimNet schema registration, seeding a default StorageUtil entry, etc.
 Reload-time setup should NOT live here (this fires only on the OnInit
 path); use the plugin's host-alias OnPlayerLoadGame for every-load work.}
EndFunction

; ── OVERRIDE: plugin identity ────────────────────────────────────────────────
string Function GetPluginId()
{Stable unique plugin id, e.g. "mtf.base". Must match the JSON catalog
 file basename at Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/
 plugins/<pluginId>.json.}
    return ""
EndFunction

string Function GetPluginLabel()
{User-facing plugin name. Sourced from JSON `.pluginlabel`. Override only if
 the catalog isn't available (e.g. infrastructure plugins with no JSON).}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".pluginlabel", "")
EndFunction

; ── Conditions (JSON-driven; no overrides expected in derived classes) ──────
int Function GetConditionCount()
    return JsonUtil.PathCount(_catalogFile(), ".conditions")
EndFunction

string Function GetConditionId(int idx)
{Stable per-plugin id for condition `idx`. Must not contain a colon.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].id", "")
EndFunction

string Function GetConditionLabel(int idx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].label", "")
EndFunction

string Function GetConditionDescription(int idx)
{One-sentence prose description of what this condition CHECKS. Consumed by
 LLM-integration bridges (e.g. SkyrimNet) so an AI narrator can explain
 WHEN a tattoo will activate without per-prompt copy.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].description", "")
EndFunction

string Function GetConditionParamLabel(int idx)
{Slider label. Empty when the condition takes no parameter.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].param.label", "")
EndFunction

int Function GetConditionParamMin(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param.min", 0)
EndFunction

int Function GetConditionParamMax(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param.max", 100)
EndFunction

int Function GetConditionParamDefault(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param.default", 0)
EndFunction

string Function GetConditionParamFormat(int idx)
{SkyUI slider format string for param1 substitution in descriptions.
 Default raw integer. Override per-idx via JSON for units (e.g. "0%").}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].param.format", "{0}")
EndFunction

string Function GetConditionParam2Label(int idx)
{Slider label for the optional 2nd param. Empty when not used.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].param2.label", "")
EndFunction

int Function GetConditionParam2Min(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param2.min", 0)
EndFunction

int Function GetConditionParam2Max(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param2.max", 100)
EndFunction

int Function GetConditionParam2Default(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param2.default", 0)
EndFunction

int Function GetConditionParam2Step(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param2.step", 1)
EndFunction

string Function GetConditionParam2Format(int idx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].param2.format", "{0}")
EndFunction

; Condition param dropdowns.
int Function GetConditionParamMenuOptionCount(int idx)
    return JsonUtil.PathCount(_catalogFile(), ".conditions[" + idx + "].param.menu")
EndFunction

int Function GetConditionParamMenuOptionValue(int idx, int optionIdx)
{The int value stored on the slot when option `optionIdx` is picked.}
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param.menu[" + optionIdx + "].value", 0)
EndFunction

string Function GetConditionParamMenuOptionLabel(int idx, int optionIdx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].param.menu[" + optionIdx + "].label", "")
EndFunction

int Function GetConditionParam2MenuOptionCount(int idx)
    return JsonUtil.PathCount(_catalogFile(), ".conditions[" + idx + "].param2.menu")
EndFunction

int Function GetConditionParam2MenuOptionValue(int idx, int optionIdx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".conditions[" + idx + "].param2.menu[" + optionIdx + "].value", 0)
EndFunction

string Function GetConditionParam2MenuOptionLabel(int idx, int optionIdx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".conditions[" + idx + "].param2.menu[" + optionIdx + "].label", "")
EndFunction

; ── OVERRIDE: condition behaviour (stays in Papyrus) ────────────────────────
bool Function checkCondition(Actor target, int param, string cid)
{Return true when condition `cid` is currently satisfied for `target`. Use
 `_host().GetEvalParam2()` to read the second per-slot parameter when your
 condition declares one.

 `cid` is the catalog id string (e.g. "loc.playerHouse"). Stable across
 catalog reorders; identical to what the save data stores. If your branch
 needs to read other catalog metadata (e.g. param defaults), resolve the
 array index lazily with `_host()._condIdxFor(self, cid)`.}
    return false
EndFunction

; ── Effects (JSON-driven) ───────────────────────────────────────────────────
int Function GetEffectCount()
    return JsonUtil.PathCount(_catalogFile(), ".effects")
EndFunction

string Function GetEffectId(int idx)
{Stable per-plugin id for effect `idx`. Must not contain a colon.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].id", "")
EndFunction

string Function GetEffectLabel(int idx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].label", "")
EndFunction

string Function GetEffectKind(int idx)
{Effect lifecycle classifier — semantic, not cosmetic.
 Returns:
   "burst"      — fires once on activate; no rolling state. onDeactivate
                  and onTick are no-ops. Lifecycle audit can ignore these.
   "continuous" — default; active while the tier is on. Must clean up
                  in onDeactivate.
 MCM uses this to prepend a "[!] " badge to burst labels at render time —
 don't hand-prefix labels in the JSON.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].kind", "continuous")
EndFunction

string Function GetEffectDisplayLabel(int idx)
{User-facing decorated label for MCM / preset diagnostics. Prepends a
 "[!] " badge when the effect is a burst, otherwise returns the raw
 label. SkyrimNet / LLM bridges and any structured-data consumer should
 call GetEffectLabel + GetEffectKind instead of this so the kind stays
 a discrete field rather than getting lexically embedded.}
    string l = JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].label", "")
    if GetEffectKind(idx) == "burst"
        return "[!] " + l
    endif
    return l
EndFunction

string Function GetEffectDescription(int idx)
{One-sentence prose description of what this effect DOES while active.
 Consumed by LLM-integration bridges (e.g. SkyrimNet) so an AI narrator
 can explain a tattoo's effect without per-prompt copy.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].description", "")
EndFunction

; ── Effect params (v0.2.1 uniform schema) ──────────────────────────────────
; Each effect declares up to 5 numbered params under `.effects[i].paramN`
; (N = 1..5). The framework probes each paramN.label — when non-empty, the
; param is "declared" and gets a slot in the MCM render and in serialized
; presets. Replaces the v0.2.0 split between `param` / `param2` / `extras[]`.
;
; Plugin behaviour code reads param1 + param2 from the onActivate signature
; (positional, by convention — most effects need just 1-2 controls). For
; param3-5 use the MainQuest dispatch-context accessor:
;
;   int v = host.GetSlotEffectParam(slot, eff, n)  ; n in {3, 4, 5}
;
; (slot + eff are available via host._getDispatchSlot/_getDispatchEffectIdx
; while a dispatch is in flight.)

string Function GetEffectParamLabel(int idx, int n)
{Slider/menu label for param `n` (1..5). Empty when not declared.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param" + n + ".label", "")
EndFunction

int Function GetEffectParamMin(int idx, int n)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param" + n + ".min", 0)
EndFunction

int Function GetEffectParamMax(int idx, int n)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param" + n + ".max", 100)
EndFunction

int Function GetEffectParamDefault(int idx, int n)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param" + n + ".default", 0)
EndFunction

int Function GetEffectParamStep(int idx, int n)
{SkyUI slider interval. Defaults to 1. Override per-idx/per-n via JSON for coarser steps.}
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param" + n + ".step", 1)
EndFunction

string Function GetEffectParamFormat(int idx, int n)
{SkyUI slider format string. Defaults to raw integer. Override per-idx/per-n
 via JSON for units (e.g. "0%", "0 s").}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param" + n + ".format", "{0}")
EndFunction

int Function GetEffectParamMenuOptionCount(int idx, int n)
    return JsonUtil.PathCount(_catalogFile(), ".effects[" + idx + "].param" + n + ".menu")
EndFunction

int Function GetEffectParamMenuOptionValue(int idx, int n, int optionIdx)
{The int value to store on the slot when option `optionIdx` is picked.}
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param" + n + ".menu[" + optionIdx + "].value", 0)
EndFunction

string Function GetEffectParamMenuOptionLabel(int idx, int n, int optionIdx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param" + n + ".menu[" + optionIdx + "].label", "")
EndFunction

; ── OVERRIDE: effect behaviour (stays in Papyrus) ───────────────────────────
; All four lifecycle hooks take `string eid` as the dispatch key — the
; catalog id (e.g. "flash.onhit"). It's stable across catalog reorders and
; identical to what the save data stores. If your branch needs to read
; other catalog metadata (param defaults, kind, etc.), resolve the array
; index lazily with `_host()._effectIdxFor(self, eid)`.

Function onActivate(Actor target, int param, int param2, string eid)
{Called when effect `eid` becomes active (slot just became the winning tier).}
EndFunction

Function onDeactivate(Actor target, int param, int param2, string eid)
{Called when effect `eid` stops being active. Must restore any persistent
 changes (AV mods, applied magic effects, etc.). Safe to call even if
 onActivate was never called.

 WARNING — silent footgun: the default is a no-op. If your effect mutates
 persistent engine state in onActivate (ModActorValue, AddSpell,
 SetNthEffectMagnitude on a stored Spell, persistent shader effects, etc.)
 and you forget to override onDeactivate, removing the tattoo will SILENTLY
 LEAVE THE STATE APPLIED — no compile error, no log line, no visible signal
 until a player reports "removing the tattoo doesn't actually remove the
 buff". There is no framework-side rescue: MTF doesn't know what state
 your onActivate touched.

 Two cases where the no-op default IS correct, so you can leave it alone:
   1. Transient one-shot effects (bursts, stagger, alerts, bounty bumps) —
      they finish during onActivate and have no rolling state.
   2. State that lives in another framework's storage and is meant to
      decay/expire naturally (SLA exposure deltas, FMR ovulation timers).
      Symmetric cleanup would either be wrong (refund could push to
      negative) or impossible (no cancel API on the other side).

 If your effect mutates a Skyrim AV directly via ModActorValue, you almost
 certainly want to mirror the MTF_Plugin_Base pattern: store the applied
 delta in StorageUtil under a per-actor key, revert by -delta in
 onDeactivate, and write the storage BEFORE the suspending ModActorValue
 call to avoid the two-stack apply race
 (project_papyrus_storage_before_suspend).}
EndFunction

Function onTick(Actor target, int param, int param2, string eid)
{Called every MainQuest update tick (typically every 2s) while effect `eid`
 is active. Use for stateful effects that need to recompute (e.g. %-of-
 current AV drains shifting with gear changes). No-op by default.}
EndFunction

Function onGameTime(Actor target, int param, int param2, string eid)
{Called once per in-game hour while effect `eid` is active. Use for
 cumulative effects (e.g. SLA exposure deltas). No-op by default.}
EndFunction

; ── Plugin-level settings: REMOVED in v0.2.1 ────────────────────────────────
; Per-plugin settings sliders (GetSettingCount/Id/Label/Value etc) were
; dropped to free 8 MCM named-state slots (the SETTING_1..8 pool) — needed
; to stay under SkyUI's 127 per-script cap as the MCM gained features. No
; plugin ever shipped a non-zero GetSettingCount, so the cut is a clean
; deletion rather than a migration. Plugins that need user-adjustable knobs
; should expose them via JSON (under a custom path the plugin reads itself)
; or hook into another mod's MCM. The `.settings` catalog key is reserved
; if we ever want to bring this back differently.
