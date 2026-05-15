Scriptname sd_LME_EffectPlugin extends Quest
{Abstract base for LewdMarksEffects effect plugins.

 An effect plugin script declares one or more effect items via the GetItem*
 methods. Each item is a separately-selectable entry that the user can add to
 a slot's effect list in the MCM. When that slot becomes the active tier the
 host fires onActivate; when it stops being active the host fires onDeactivate;
 onTick fires every script update for the active slot's effects (use for
 stateful effects that need to recompute, e.g. %-of-current AV drains that
 shift with gear); onGameTime fires once per in-game hour for the active
 slot's effects (use for cumulative effects like SLA exposure deltas).

 An effect is globally identified by "<pluginId>:<itemId>". The host stores
 these composite keys in MainQuest.effectKey[] per (slot, effectIdx).

 Override the methods marked OVERRIDE in your derived script. External plugins
 live in their own ESP/ESL and discover the host via
   Game.GetFormFromFile(0x803, "LewdMarksEffects.esp")}

bool Property _registered = false Auto Hidden

; ── Lifecycle ────────────────────────────────────────────────────────────────
Event OnInit()
    RegisterForSingleUpdate(0.5)
EndEvent

Event OnUpdate()
    _tryRegister()
EndEvent

Function _tryRegister()
    if _registered
        return
    endif
    sd_LME_MainQuest host = Game.GetFormFromFile(0x803, "LewdMarksEffects.esp") as sd_LME_MainQuest
    if host == None || host.registeredEffectPlugins == None
        RegisterForSingleUpdate(1.0)
        return
    endif
    host.RegisterEffectPlugin(self)
    _registered = true
EndFunction

; ── OVERRIDE: plugin identity ────────────────────────────────────────────────
string Function GetPluginId()
{Stable unique plugin id. Convention: "<author>.<plugin>.fx", e.g. "lme.base.fx".}
    return ""
EndFunction

string Function GetPluginLabel()
{User-facing plugin name. Used as a prefix in the MCM effect-type dropdown.}
    return ""
EndFunction

; ── OVERRIDE: items ──────────────────────────────────────────────────────────
int Function GetItemCount()
    return 0
EndFunction

string Function GetItemId(int idx)
{Stable per-plugin id for item `idx`. Must not contain a colon.}
    return ""
EndFunction

string Function GetItemLabel(int idx)
    return ""
EndFunction

string Function GetItemParamLabel(int idx)
{Label for the integer parameter slider. Return "" if this item takes no parameter.}
    return ""
EndFunction

int Function GetItemParamMin(int idx)
    return 0
EndFunction

int Function GetItemParamMax(int idx)
    return 100
EndFunction

int Function GetItemParamDefault(int idx)
    return 0
EndFunction

; ── OVERRIDE: lifecycle hooks ────────────────────────────────────────────────
Function onActivate(int idx, Actor target, int param)
{Called when this effect becomes active on `target` (slot just became the
 winning tier, or the user just added this effect to the active slot).}
EndFunction

Function onDeactivate(int idx, Actor target, int param)
{Called when this effect stops being active. Must restore any persistent
 changes (AV mods, applied magic effects, etc.). Should be safe to call
 even if onActivate was never called.}
EndFunction

Function onTick(int idx, Actor target, int param)
{Called every MainQuest update tick (typically every 2s) while this effect
 is active. Use for stateful effects that need to recompute (e.g. %-of-current
 AV drains shifting with gear changes). No-op by default.}
EndFunction

Function onGameTime(int idx, Actor target, int param)
{Called once per in-game hour while this effect is active. Use for
 cumulative effects (e.g. SLA exposure deltas). No-op by default.}
EndFunction

; ── OVERRIDE: plugin-level settings ──────────────────────────────────────────
; Settings are global per-plugin sliders that the MCM renders on the General
; page under the plugin's header. Use for cross-effect knobs (e.g. scan radius
; shared by multiple items in this plugin).

int Function GetSettingCount()
    return 0
EndFunction

string Function GetSettingId(int idx)
{Stable per-plugin id (for documentation; the MCM uses idx).}
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
