Scriptname sd_LME_Plugin_MagicEffects extends sd_LME_ConditionPlugin

MagicEffect[] Property watchedEffects Auto    ; fill in CK/xEdit

string Function GetPluginId()
    return "lme.magicfx"
EndFunction
string Function GetLabel()
    return "Magic Effects"
EndFunction
string Function GetParamLabel()
    return ""    ; no parameter (selection is the property array)
EndFunction

bool Function check(Actor target, int param)
    if watchedEffects == None || watchedEffects.Length == 0
        return false
    endif
    int j = 0
    while j < watchedEffects.Length
        if watchedEffects[j] && target.HasMagicEffect(watchedEffects[j])
            return true
        endif
        j += 1
    endwhile
    return false
EndFunction
