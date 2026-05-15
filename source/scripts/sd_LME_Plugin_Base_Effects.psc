Scriptname sd_LME_Plugin_Base_Effects extends sd_LME_EffectPlugin
{Built-in side effects that depend only on vanilla AVs.

 Items:
   0  drain.magickaRate  — drain `param`% of current MagickaRateMult
   1  drain.carryWeight  — drain `param`% of current CarryWeight
   2  drain.sneak        — drain `param`% of current Sneak

 Each drain is %-of-CURRENT so it composes with enchantments / gear. onTick
 recomputes every update so the drain stays in sync with gear swaps.}

float Property _appliedMana = 0.0 Auto Hidden     ; absolute amount currently subtracted from MagickaRateMult
float Property _appliedCarry = 0.0 Auto Hidden    ; absolute amount currently subtracted from CarryWeight
float Property _appliedSneak = 0.0 Auto Hidden    ; absolute amount currently subtracted from Sneak

string Function GetPluginId()
    return "lme.base.fx"
EndFunction
string Function GetPluginLabel()
    return "Base"
EndFunction

int Function GetItemCount()
    return 3
EndFunction

string Function GetItemId(int idx)
    if idx == 0
        return "drain.magickaRate"
    elseif idx == 1
        return "drain.carryWeight"
    elseif idx == 2
        return "drain.sneak"
    endif
    return ""
EndFunction

string Function GetItemLabel(int idx)
    if idx == 0
        return "Mana Siphon"
    elseif idx == 1
        return "Carry Weight Penalty"
    elseif idx == 2
        return "Sneak Penalty"
    endif
    return ""
EndFunction

string Function GetItemParamLabel(int idx)
    if idx == 0
        return "Drain % of current MagickaRateMult"
    elseif idx == 1
        return "Drain % of current CarryWeight"
    elseif idx == 2
        return "Drain % of current Sneak"
    endif
    return ""
EndFunction

int Function GetItemParamMin(int idx)
    return 0
EndFunction
int Function GetItemParamMax(int idx)
    return 100
EndFunction
int Function GetItemParamDefault(int idx)
    return 25
EndFunction

string Function _avNameFor(int idx)
    if idx == 0
        return "MagickaRateMult"
    elseif idx == 1
        return "CarryWeight"
    elseif idx == 2
        return "Sneak"
    endif
    return ""
EndFunction

float Function _getApplied(int idx)
    if idx == 0
        return _appliedMana
    elseif idx == 1
        return _appliedCarry
    elseif idx == 2
        return _appliedSneak
    endif
    return 0.0
EndFunction

Function _setApplied(int idx, float v)
    if idx == 0
        _appliedMana = v
    elseif idx == 1
        _appliedCarry = v
    elseif idx == 2
        _appliedSneak = v
    endif
EndFunction

Function _recompute(int idx, Actor target, int param)
{Reverses any previous drain on this AV, then re-applies as param% of current.}
    string av = _avNameFor(idx)
    if av == "" || target == None
        return
    endif
    float prev = _getApplied(idx)
    if prev != 0.0
        target.ModActorValue(av, prev)
    endif
    if param <= 0
        _setApplied(idx, 0.0)
        return
    endif
    float current = target.GetActorValue(av)
    if current <= 0.0
        _setApplied(idx, 0.0)
        return
    endif
    float amt = current * param / 100.0
    target.ModActorValue(av, -amt)
    _setApplied(idx, amt)
EndFunction

Function onActivate(int idx, Actor target, int param)
    _recompute(idx, target, param)
EndFunction

Function onDeactivate(int idx, Actor target, int param)
    _recompute(idx, target, 0)    ; clears by passing param=0
EndFunction

Function onTick(int idx, Actor target, int param)
    ; Re-apply every tick so the drain stays in sync with gear/buff changes.
    _recompute(idx, target, param)
EndFunction
