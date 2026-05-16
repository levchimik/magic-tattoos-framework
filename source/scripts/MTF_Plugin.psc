Scriptname MTF_Plugin extends Quest
{Abstract base for MagicTattoosFramework plugins.

 A plugin script can declare any combination of:
   - Conditions: tier-evaluation predicates, picked per-slot in the MCM.
   - Effects:    lifecycle hooks fired while a slot is active.
   - Settings:   plugin-wide knobs rendered on the MCM Plugins page.

 Conditions and effects share the plugin's identity (pluginId / label) so
 a logical "mod" (e.g. base game, SLA, FMR) is one plugin script with all
 its items together.

 Globally each item is identified by "<pluginId>:<itemId>" — keys are
 stored in MainQuest.condPluginId[] (conditions) and MainQuest.effectKey[]
 (effects). Condition itemIds and effect itemIds share no namespace; a
 plugin can have a condition and an effect with the same itemId without
 conflict.

 Override the methods marked OVERRIDE in your derived script. External
 plugins live in their own ESP/ESL and discover the host via
   Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp")}

bool Property _registered = false Auto Hidden

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
{Stable unique plugin id. Convention: "<author>.<plugin>", e.g. "mtf.base".}
    return ""
EndFunction

string Function GetPluginLabel()
{User-facing plugin name shown in the MCM dropdowns and Plugins page.}
    return ""
EndFunction

; ── OVERRIDE: conditions ─────────────────────────────────────────────────────
int Function GetConditionCount()
    return 0
EndFunction

string Function GetConditionId(int idx)
{Stable per-plugin id for condition `idx`. Must not contain a colon.}
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
{Slider label. Return "" if this condition takes no parameter.}
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    return 0
EndFunction

int Function GetConditionParamMax(int idx)
    return 100
EndFunction

int Function GetConditionParamDefault(int idx)
    return 0
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
{Return true when condition `idx` is currently satisfied for `target`.}
    return false
EndFunction

; ── OVERRIDE: effects ────────────────────────────────────────────────────────
int Function GetEffectCount()
    return 0
EndFunction

string Function GetEffectId(int idx)
{Stable per-plugin id for effect `idx`. Must not contain a colon.}
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    return 0
EndFunction

int Function GetEffectParamMax(int idx)
    return 100
EndFunction

int Function GetEffectParamDefault(int idx)
    return 0
EndFunction

int Function GetEffectParamStep(int idx)
{SkyUI slider interval. Defaults to 1. Override for coarser steps.}
    return 1
EndFunction

Function onActivate(int idx, Actor target, int param)
{Called when effect `idx` becomes active (slot just became the winning tier).}
EndFunction

Function onDeactivate(int idx, Actor target, int param)
{Called when effect `idx` stops being active. Must restore any persistent
 changes (AV mods, applied magic effects, etc.). Safe to call even if
 onActivate was never called.}
EndFunction

Function onTick(int idx, Actor target, int param)
{Called every MainQuest update tick (typically every 2s) while effect `idx`
 is active. Use for stateful effects that need to recompute (e.g. %-of-
 current AV drains shifting with gear changes). No-op by default.}
EndFunction

Function onGameTime(int idx, Actor target, int param)
{Called once per in-game hour while effect `idx` is active. Use for
 cumulative effects (e.g. SLA exposure deltas). No-op by default.}
EndFunction

; ── OVERRIDE: plugin-level settings ──────────────────────────────────────────
; Global per-plugin sliders rendered on the MCM Plugins page under the
; plugin's header. Use for cross-item knobs.

int Function GetSettingCount()
    return 0
EndFunction
string Function GetSettingId(int idx)
    return ""
EndFunction
string Function GetSettingLabel(int idx)
    return ""
EndFunction
string Function GetSettingInfo(int idx)
{Tooltip text shown when the slider is highlighted.}
    return ""
EndFunction
int Function GetSettingMin(int idx)
    return 0
EndFunction
int Function GetSettingMax(int idx)
    return 100
EndFunction
int Function GetSettingDefault(int idx)
    return 0
EndFunction
string Function GetSettingFormat(int idx)
{SkyUI slider format string. Default is the plain integer format.}
    return "{0}"
EndFunction
int Function GetSettingValue(int idx)
    return 0
EndFunction
Function SetSettingValue(int idx, int v)
EndFunction
