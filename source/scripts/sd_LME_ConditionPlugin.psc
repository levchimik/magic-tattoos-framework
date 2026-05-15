Scriptname sd_LME_ConditionPlugin extends Quest
{Abstract base for LewdMarksEffects condition plugins.

 A plugin script declares one or more condition items via the GetItem*/checkItem
 methods. Each item is a separately-selectable entry in the MCM condition-type
 dropdown. Items within a plugin share the host quest (and any soft-master
 lookups it performs in _tryRegister).

 A condition is globally identified by "<pluginId>:<itemId>". The host stores
 these composite keys in MainQuest.condPluginId[] per slot.

 Override the methods marked OVERRIDE in your derived script. External plugins
 live in their own ESP/ESL and discover the host via
   Game.GetFormFromFile(0x803, "LewdMarksEffects.esp")}

bool Property _registered = false Auto Hidden

; ── Lifecycle ────────────────────────────────────────────────────────────────
Event OnInit()
    ; Delay registration so MainQuest.OnInit has a chance to allocate its registry array first.
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
    if host == None || host.registeredPlugins == None
        RegisterForSingleUpdate(1.0)
        return
    endif
    host.RegisterPlugin(self)
    _registered = true
EndFunction

; ── OVERRIDE: plugin identity ────────────────────────────────────────────────
string Function GetPluginId()
{Stable unique plugin id. Convention: "<author>.<plugin>", e.g. "lme.base".}
    return ""
EndFunction

string Function GetPluginLabel()
{User-facing plugin name. Used as a prefix/header in the MCM dropdown.}
    return ""
EndFunction

; ── OVERRIDE: items ──────────────────────────────────────────────────────────
int Function GetItemCount()
{Number of condition items this plugin exposes in the MCM dropdown.}
    return 0
EndFunction

string Function GetItemId(int idx)
{Stable per-plugin id for item `idx`. Combined with the plugin id as
 "<pluginId>:<itemId>" globally. Must be unique within this plugin and
 must not contain a colon.}
    return ""
EndFunction

string Function GetItemLabel(int idx)
{User-facing label shown in the MCM condition-type dropdown.}
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

; ── OVERRIDE: evaluation ─────────────────────────────────────────────────────
bool Function checkItem(int idx, Actor target, int param)
{Return true when item `idx` is currently satisfied for `target`.
 `param` is the slot's configured int parameter (see GetItemParamLabel).}
    return false
EndFunction
