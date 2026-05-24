Scriptname MTF_Plugin extends Quest
{Abstract base for MagicTattoosFramework plugins. See docs/PLUGIN_AUTHORING.md.}

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

Function _tryRegister()
    if _registered
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
bool Function checkCondition(int idx, Actor target, int param)
{Return true when condition `idx` is currently satisfied for `target`. Use
 `_host().GetEvalParam2()` to read the second per-slot parameter when your
 condition declares one.}
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

string Function GetEffectDescription(int idx)
{One-sentence prose description of what this effect DOES while active.
 Consumed by LLM-integration bridges (e.g. SkyrimNet) so an AI narrator
 can explain a tattoo's effect without per-prompt copy.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].description", "")
EndFunction

string Function GetEffectParamLabel(int idx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param.label", "")
EndFunction

int Function GetEffectParamMin(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param.min", 0)
EndFunction

int Function GetEffectParamMax(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param.max", 100)
EndFunction

int Function GetEffectParamDefault(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param.default", 0)
EndFunction

int Function GetEffectParamStep(int idx)
{SkyUI slider interval. Defaults to 1. Override per-idx via JSON for coarser steps.}
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param.step", 1)
EndFunction

string Function GetEffectParamFormat(int idx)
{SkyUI slider format string. Defaults to raw integer. Override per-idx via
 JSON for units (e.g. "0%", "0 s").}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param.format", "{0}")
EndFunction

string Function GetEffectParam2Label(int idx)
{Slider label for the optional 2nd param. Empty when not used.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param2.label", "")
EndFunction

int Function GetEffectParam2Min(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param2.min", 0)
EndFunction

int Function GetEffectParam2Max(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param2.max", 100)
EndFunction

int Function GetEffectParam2Default(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param2.default", 0)
EndFunction

int Function GetEffectParam2Step(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param2.step", 1)
EndFunction

string Function GetEffectParam2Format(int idx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param2.format", "{0}")
EndFunction

; Effect param dropdowns.
int Function GetEffectParamMenuOptionCount(int idx)
    return JsonUtil.PathCount(_catalogFile(), ".effects[" + idx + "].param.menu")
EndFunction

int Function GetEffectParamMenuOptionValue(int idx, int optionIdx)
{The int value to store on the slot when option `optionIdx` is picked.}
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param.menu[" + optionIdx + "].value", 0)
EndFunction

string Function GetEffectParamMenuOptionLabel(int idx, int optionIdx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param.menu[" + optionIdx + "].label", "")
EndFunction

int Function GetEffectParam2MenuOptionCount(int idx)
    return JsonUtil.PathCount(_catalogFile(), ".effects[" + idx + "].param2.menu")
EndFunction

int Function GetEffectParam2MenuOptionValue(int idx, int optionIdx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].param2.menu[" + optionIdx + "].value", 0)
EndFunction

string Function GetEffectParam2MenuOptionLabel(int idx, int optionIdx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].param2.menu[" + optionIdx + "].label", "")
EndFunction

; ── Effect extras ───────────────────────────────────────────────────────────
; Extras values are stored as floats keyed by (slot, effectIdx, fieldName)
; via MainQuest.GetSlotEffectExtra / SetSlotEffectExtra. When the bound
; effect changes on a slot, MainQuest populates the new effect's extras
; with the declared defaults and wipes the old.
;
; Field names MUST be lowercase ASCII without spaces — PapyrusUtil lowercases
; JSON keys on read (project_papyrusutil_lowercase). Keep ≤ 12 chars; label
; is the user-facing text.

int Function GetEffectExtraFieldCount(int idx)
{Number of extra fields effect `idx` declares (0..3).}
    return JsonUtil.PathCount(_catalogFile(), ".effects[" + idx + "].extras")
EndFunction

string Function GetEffectExtraFieldName(int idx, int fieldIdx)
{Lowercase ASCII name (used as the StorageUtil sub-key for the value).}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].name", "")
EndFunction

string Function GetEffectExtraFieldLabel(int idx, int fieldIdx)
{User-facing label rendered as the MCM slider's text.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].label", "")
EndFunction

int Function GetEffectExtraFieldMin(int idx, int fieldIdx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].min", 0)
EndFunction

int Function GetEffectExtraFieldMax(int idx, int fieldIdx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].max", 100)
EndFunction

int Function GetEffectExtraFieldStep(int idx, int fieldIdx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].step", 1)
EndFunction

int Function GetEffectExtraFieldDefault(int idx, int fieldIdx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].default", 0)
EndFunction

int Function GetEffectExtraFieldMenuOptionCount(int idx, int fieldIdx)
    return JsonUtil.PathCount(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].menu")
EndFunction

int Function GetEffectExtraFieldMenuOptionValue(int idx, int fieldIdx, int optionIdx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].menu[" + optionIdx + "].value", 0)
EndFunction

string Function GetEffectExtraFieldMenuOptionLabel(int idx, int fieldIdx, int optionIdx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".effects[" + idx + "].extras[" + fieldIdx + "].menu[" + optionIdx + "].label", "")
EndFunction

; ── OVERRIDE: effect behaviour (stays in Papyrus) ───────────────────────────
Function onActivate(int idx, Actor target, int param, int param2)
{Called when effect `idx` becomes active (slot just became the winning tier).}
EndFunction

Function onDeactivate(int idx, Actor target, int param, int param2)
{Called when effect `idx` stops being active. Must restore any persistent
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

Function onTick(int idx, Actor target, int param, int param2)
{Called every MainQuest update tick (typically every 2s) while effect `idx`
 is active. Use for stateful effects that need to recompute (e.g. %-of-
 current AV drains shifting with gear changes). No-op by default.}
EndFunction

Function onGameTime(int idx, Actor target, int param, int param2)
{Called once per in-game hour while effect `idx` is active. Use for
 cumulative effects (e.g. SLA exposure deltas). No-op by default.}
EndFunction

; ── Settings (JSON-driven metadata; behaviour overridable) ──────────────────
int Function GetSettingCount()
    return JsonUtil.PathCount(_catalogFile(), ".settings")
EndFunction

string Function GetSettingId(int idx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".settings[" + idx + "].id", "")
EndFunction

string Function GetSettingLabel(int idx)
    return JsonUtil.GetPathStringValue(_catalogFile(), ".settings[" + idx + "].label", "")
EndFunction

string Function GetSettingInfo(int idx)
{Tooltip text shown when the slider is highlighted.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".settings[" + idx + "].info", "")
EndFunction

int Function GetSettingMin(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".settings[" + idx + "].min", 0)
EndFunction

int Function GetSettingMax(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".settings[" + idx + "].max", 100)
EndFunction

int Function GetSettingDefault(int idx)
    return JsonUtil.GetPathIntValue(_catalogFile(), ".settings[" + idx + "].default", 0)
EndFunction

string Function GetSettingFormat(int idx)
{SkyUI slider format string. Defaults to raw integer.}
    return JsonUtil.GetPathStringValue(_catalogFile(), ".settings[" + idx + "].format", "{0}")
EndFunction

; ── OVERRIDE: setting value get/set (state lives in the derived plugin) ─────
int Function GetSettingValue(int idx)
    return 0
EndFunction

Function SetSettingValue(int idx, int v)
EndFunction
