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

string Function GetConditionDescription(int idx)
{One-sentence prose description of what this condition CHECKS. Consumed by
 LLM-integration bridges (e.g. SkyrimNet) so an AI narrator can explain
 WHEN a tattoo will activate without the user authoring per-prompt copy.
 Plain language, no jargon: "Triggers when the actor's arousal exceeds the
 threshold." Default empty — override per plugin.}
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

; Optional 2nd per-slot parameter. Conditions that need a second knob
; (e.g. time.range with from/till hours) override these. If
; GetConditionParam2Label returns "", the MCM hides the 2nd slider and
; checkCondition can ignore param2 (it'll be 0).

string Function GetConditionParam2Label(int idx)
{Slider label for the optional 2nd param. Return "" if condition has no 2nd param.}
    return ""
EndFunction
int Function GetConditionParam2Min(int idx)
    return 0
EndFunction
int Function GetConditionParam2Max(int idx)
    return 100
EndFunction
int Function GetConditionParam2Default(int idx)
    return 0
EndFunction
int Function GetConditionParam2Step(int idx)
    return 1
EndFunction
string Function GetConditionParam2Format(int idx)
    return "{0}"
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
{Return true when condition `idx` is currently satisfied for `target`.
 Use `_host().GetEvalParam2()` to read the second per-slot parameter when
 your condition declares one via GetConditionParam2Label.}
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

string Function GetEffectDescription(int idx)
{One-sentence prose description of what this effect DOES while active.
 Consumed by LLM-integration bridges (e.g. SkyrimNet) so an AI narrator
 can explain a tattoo's effect to NPCs without the user authoring per-
 prompt copy. Plain language: "Drains the actor's magicka faster, making
 spellcasting riskier." Default empty — override per plugin.}
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

; Optional 2nd per-slot parameter. Effects that need a second knob
; (e.g. Pheromone Aura's radius) override these. If GetEffectParam2Label
; returns "", the MCM hides the 2nd slider and dispatch passes 0.

string Function GetEffectParam2Label(int idx)
{Slider label for the optional 2nd param. Return "" if effect has no 2nd param.}
    return ""
EndFunction
int Function GetEffectParam2Min(int idx)
    return 0
EndFunction
int Function GetEffectParam2Max(int idx)
    return 100
EndFunction
int Function GetEffectParam2Default(int idx)
    return 0
EndFunction
int Function GetEffectParam2Step(int idx)
    return 1
EndFunction
string Function GetEffectParam2Format(int idx)
    return "{0}"
EndFunction

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
 call to avoid the two-stack apply race (see
 project_papyrus_storage_before_suspend memory note).}
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

; ── OVERRIDE: dropdown rendering for param / param2 (v0.1.3) ────────────────
; Effects whose param represents a discrete choice (rather than a number)
; can opt into a MCM dropdown menu by returning a non-empty options list.
; The slider Min/Max/Default/Step hooks become inert when menu options are
; present.
;
; Options use "intValue|label" pipe-delimited strings. The intValue is what
; gets stored in effectParam / effectParam2. Values outside the option list
; still load (MCM shows "Custom: N") — useful for hand-edited presets that
; want non-preset values.
;
; Example for a hit-class bitmask:
;   "0|Disabled"
;   "1|Any hit"
;   "6|Melee (Blunt + Bladed)"
;   "112|Magic (Fire + Frost + Shock)"
;
; Default (empty array) keeps the slider behavior. Existing plugins need
; no changes.

; NOTE: indexed writes to a `new string[N]` local in a Quest-script function
; silently no-op on this VM (the array comes back zero-filled). And
; StringUtil.Split returns arrays whose .Length sometimes reads as 0 even
; when populated. To dodge both quirks we expose count + per-index getters
; for value AND label separately — no array round-trips, no split parsing.

int Function GetEffectParamMenuOptionCount(int idx)
    return 0
EndFunction

int Function GetEffectParamMenuOptionValue(int idx, int optionIdx)
{The int value to store on the slot when option `optionIdx` is picked.}
    return 0
EndFunction

string Function GetEffectParamMenuOptionLabel(int idx, int optionIdx)
{The display label for option `optionIdx`.}
    return ""
EndFunction

int Function GetEffectParam2MenuOptionCount(int idx)
    return 0
EndFunction

int Function GetEffectParam2MenuOptionValue(int idx, int optionIdx)
    return 0
EndFunction

string Function GetEffectParam2MenuOptionLabel(int idx, int optionIdx)
    return ""
EndFunction

; ── OVERRIDE: per-effect "extras" (v0.1.3) ──────────────────────────────────
; Effects that need more than the two stock params (param/param2) can declare
; up to 3 extra fields. The MCM renders one slider per extra below param2,
; and the preset I/O round-trips them through slot[s].effect[e].extras.<name>.
;
; Extras values are stored as floats keyed by (slot, effectIdx, fieldName)
; via MainQuest.GetSlotEffectExtra / SetSlotEffectExtra. When the bound
; effect changes on a slot, MainQuest populates the new effect's extras
; with the declared defaults and wipes the old.
;
; Field names MUST be lowercase ASCII without spaces (PapyrusUtil's JsonUtil
; lowercases keys on write — mixed case would read back blank). Keep them
; short (≤ 12 chars); the label string is the user-facing text.
;
; v0.1.3 changed the spec API from a populated `string[]` + pipe-delimited
; spec string to count + per-field typed getters, to dodge two VM quirks:
; (a) indexed writes to a `new string[N]` local in a Quest-script function
;     silently no-op, so the array comes back empty.
; (b) StringUtil.Split inside a cross-script call loop reads parts.Length
;     as 0 from iteration 2+ onward, so the pipe-delimited spec failed past
;     the first field.
; Each getter below is a flat `if fieldIdx == N return X endif` ladder.

int Function GetEffectExtraFieldCount(int idx)
{Number of extra fields effect `idx` declares (0..3).}
    return 0
EndFunction

string Function GetEffectExtraFieldName(int idx, int fieldIdx)
{Lowercase ASCII name (used as the StorageUtil sub-key for the value).}
    return ""
EndFunction

string Function GetEffectExtraFieldLabel(int idx, int fieldIdx)
{User-facing label rendered as the MCM slider's text.}
    return ""
EndFunction

int Function GetEffectExtraFieldMin(int idx, int fieldIdx)
    return 0
EndFunction

int Function GetEffectExtraFieldMax(int idx, int fieldIdx)
    return 100
EndFunction

int Function GetEffectExtraFieldStep(int idx, int fieldIdx)
    return 1
EndFunction

int Function GetEffectExtraFieldDefault(int idx, int fieldIdx)
    return 0
EndFunction

; Optional dropdown rendering for an extra field. When OptionCount > 0 the
; MCM renders the extra as a menu with named options instead of a slider; the
; stored value is whichever int the picked option's Value resolves to. Lets
; plugins surface enums (e.g. a sound catalog) on extras without overloading
; param/param2. Defaults make this opt-in — existing extras keep rendering
; as sliders.

int Function GetEffectExtraFieldMenuOptionCount(int idx, int fieldIdx)
    return 0
EndFunction

int Function GetEffectExtraFieldMenuOptionValue(int idx, int fieldIdx, int optionIdx)
    return 0
EndFunction

string Function GetEffectExtraFieldMenuOptionLabel(int idx, int fieldIdx, int optionIdx)
    return ""
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
