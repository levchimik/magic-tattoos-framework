Scriptname sd_LME_ConditionPlugin extends Quest
{Abstract base for LewdMarksEffects condition plugins.
 Override the methods marked OVERRIDE in your derived script.
 Built-in plugins live in this ESP; external plugins live in their own ESP/ESL
 and discover the host via Game.GetFormFromFile(0x803, "LewdMarksEffects.esp").}

; ── Lifecycle ────────────────────────────────────────────────────────────────
Event OnInit()
    _registerWithHost()
EndEvent

Function _registerWithHost()
    sd_LME_MainQuest host = Game.GetFormFromFile(0x803, "LewdMarksEffects.esp") as sd_LME_MainQuest
    if host == None
        return
    endif
    host.RegisterPlugin(self)
EndFunction

; ── OVERRIDE: identity ───────────────────────────────────────────────────────
string Function GetPluginId()
{Unique stable identifier — used in saves. Convention: "author.name".}
    return ""
EndFunction

string Function GetLabel()
{User-facing label shown in MCM condition-type dropdown.}
    return ""
EndFunction

string Function GetParamLabel()
{Label for the integer parameter slider (e.g. "Arousal threshold").
 Return empty string if this plugin takes no parameter.}
    return ""
EndFunction

int Function GetParamMin()
    return 0
EndFunction

int Function GetParamMax()
    return 100
EndFunction

int Function GetParamDefault()
    return 0
EndFunction

; ── OVERRIDE: evaluation ─────────────────────────────────────────────────────
bool Function check(Actor target, int param)
{Return true when this condition is currently active on `target`.
 `param` is the slot's configured int parameter (see GetParamLabel).}
    return false
EndFunction
