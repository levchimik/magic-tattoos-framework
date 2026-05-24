Scriptname MTF_Plugin_FMR extends MTF_Plugin
{Conditions and effects backed by Fertility Mode (original or Reloaded).
 Soft-master: lookup at runtime; if Fertility Mode isn't loaded the plugin
 skips registration. Reads the _JSW_BB_Storage script directly so it works
 on both the original Fertility Mode and FMR — the FMR pregnancy faction
 (0x02666B) doesn't exist in the original mod.

 Catalog (ids, labels, descriptions, param specs) is loaded from
   Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.fmr.json
 at runtime. Behaviour (checkCondition, onActivate) stays in Papyrus —
 it can't be data. Pattern intended to migrate the larger MTF_Plugin_Base
 next.

 Conditions: read FMR's `ImmersiveEffectsFaction` rank on the actor —
 FMR's poll loop encodes the full fertility state into that single rank
 (1..100 = pregnancy stage, 118 = ovulation, etc.). Faction ranks live
 ON THE ACTOR, sidestepping the array-property quirks that made direct
 Storage.LastConception[i]/LastOvulation[i] reads unreliable.

   0  pregnancy  — rank in (0, 100]; the rank itself IS the belly stage.
                    Min belly stage param = minimum rank to fire.
   1  ovulation  — rank == 118 (egg present OR in cycle ovulation window).
                    Pregnancy ranks (1..100) take precedence, so this is
                    naturally false during pregnancy with no extra gate.

 Effects:
   0  trigger.ovulation  — one-shot: set LastOvulation[index] = 0.001
                            (no-op if currently pregnant)}

_JSW_BB_Storage Property FMR_Storage Auto Hidden
GlobalVariable Property FMR_EggLife Auto Hidden
GlobalVariable Property FMR_PregnancyDuration Auto Hidden
; FMR's "ImmersiveEffectsFaction" — exists on FMR only, not original Fertility
; Mode. The actor's rank in this faction encodes her full fertility state:
;   0          = cleared / no effect
;   1..100     = pregnancy stage (1 = just conceived, 100 = full term)
;   101..115   = post-birth recovery
;   116        = menstruation
;   117        = follicular (between menstruation and ovulation)
;   118        = ovulation (egg present OR in ovulation window)
;   119        = luteal / PMS
;   120        = labor
; This is set by FMR's poll loop (_JSW_BB_HandlerQuestAliasScript:1080..1096
; for cycle phases, :1395..1405 for pregnancy) and is the source of truth.
; Reading it via Actor.GetFactionRank() sidesteps the array-property quirks
; that make Storage.LastOvulation[i]/LastConception[i] reads unreliable
; (project_papyrus_array_none_cast_noise).
Faction Property FMR_IEFaction Auto Hidden

; ── JSON catalog cache (script-level vars, NOT properties) ──────────────────
; Loaded once per session via _ensureLoaded() on first Get* call. PapyrusUtil
; lowercases JSON keys on read, so the source file uses lowercase keys
; exclusively (project_papyrusutil_lowercase memory note).
;
; Deliberately script-level vars rather than Auto Hidden properties: adding
; Auto properties to a script that's already in a save doesn't always create
; backing storage (project_papyrus_property_attach memory note), so existing
; FMR users would silently get empty catalogs after a script update. Plain
; vars allocate fresh each session — no VMAD attach step.
bool   _catalogLoaded = false
string _catalogPluginLabel = ""

int      _condN = 0
string[] _condIds
string[] _condLabels
string[] _condDescriptions
string[] _condParamLabels
int[]    _condParamMins
int[]    _condParamMaxes
int[]    _condParamDefaults

int      _effectN = 0
string[] _effectIds
string[] _effectLabels
string[] _effectDescriptions

string Function _catalogFile() Global
    ; JsonUtil paths are relative to Data/SKSE/Plugins/StorageUtilData/.
    return "MagicTattoosFramework/plugins/mtf.fmr"
EndFunction

Function _loadCatalog()
    string f = _catalogFile()
    _catalogPluginLabel = JsonUtil.GetPathStringValue(f, ".pluginlabel", "Fertility Mode (v3 / Reloaded)")

    int cN = JsonUtil.PathCount(f, ".conditions")
    _condN = cN
    ; Utility.CreateStringArray/CreateIntArray avoids the empty-`new T[N]`
    ; init quirks documented in project_papyrus_long_ifelse_chains and is
    ; safe up to 128 elements (project_papyrus_128_array_limit).
    string[] cid  = Utility.CreateStringArray(cN, "")
    string[] clab = Utility.CreateStringArray(cN, "")
    string[] cdes = Utility.CreateStringArray(cN, "")
    string[] cpl  = Utility.CreateStringArray(cN, "")
    int[]    cpmn = Utility.CreateIntArray(cN, 0)
    int[]    cpmx = Utility.CreateIntArray(cN, 100)
    int[]    cpdf = Utility.CreateIntArray(cN, 0)
    int i = 0
    while i < cN
        string base = ".conditions[" + i + "]"
        cid[i]  = JsonUtil.GetPathStringValue(f, base + ".id", "")
        clab[i] = JsonUtil.GetPathStringValue(f, base + ".label", "")
        cdes[i] = JsonUtil.GetPathStringValue(f, base + ".description", "")
        cpl[i]  = JsonUtil.GetPathStringValue(f, base + ".param.label", "")
        cpmn[i] = JsonUtil.GetPathIntValue(f, base + ".param.min", 0)
        cpmx[i] = JsonUtil.GetPathIntValue(f, base + ".param.max", 100)
        cpdf[i] = JsonUtil.GetPathIntValue(f, base + ".param.default", 0)
        i += 1
    endwhile
    _condIds = cid
    _condLabels = clab
    _condDescriptions = cdes
    _condParamLabels = cpl
    _condParamMins = cpmn
    _condParamMaxes = cpmx
    _condParamDefaults = cpdf

    int eN = JsonUtil.PathCount(f, ".effects")
    _effectN = eN
    string[] eid  = Utility.CreateStringArray(eN, "")
    string[] elab = Utility.CreateStringArray(eN, "")
    string[] edes = Utility.CreateStringArray(eN, "")
    int j = 0
    while j < eN
        string ebase = ".effects[" + j + "]"
        eid[j]  = JsonUtil.GetPathStringValue(f, ebase + ".id", "")
        elab[j] = JsonUtil.GetPathStringValue(f, ebase + ".label", "")
        edes[j] = JsonUtil.GetPathStringValue(f, ebase + ".description", "")
        j += 1
    endwhile
    _effectIds = eid
    _effectLabels = elab
    _effectDescriptions = edes

    _catalogLoaded = true
EndFunction

Function _ensureLoaded()
    if !_catalogLoaded
        _loadCatalog()
    endif
EndFunction

; ── Plugin identity ──────────────────────────────────────────────────────────
string Function GetPluginId()
    return "mtf.fmr"
EndFunction
string Function GetPluginLabel()
    _ensureLoaded()
    return _catalogPluginLabel
EndFunction

; ── FMR dependency wiring ────────────────────────────────────────────────────
bool Function _resolveDeps()
    if FMR_Storage != None && FMR_EggLife != None && FMR_PregnancyDuration != None && FMR_IEFaction != None
        return true
    endif
    if FMR_Storage == None
        FMR_Storage = Game.GetFormFromFile(0x000D62, "Fertility Mode.esm") as _JSW_BB_Storage
    endif
    if FMR_EggLife == None
        FMR_EggLife = Game.GetFormFromFile(0x0125F1, "Fertility Mode.esm") as GlobalVariable
    endif
    if FMR_PregnancyDuration == None
        FMR_PregnancyDuration = Game.GetFormFromFile(0x000D66, "Fertility Mode.esm") as GlobalVariable
    endif
    if FMR_IEFaction == None
        FMR_IEFaction = Game.GetFormFromFile(0x02666B, "Fertility Mode.esm") as Faction
    endif
    ; FMR_Storage is the only hard requirement (effect-activate still writes
    ; directly to the array; FMR's own Force Ovulation MCM button does the same
    ; and we've confirmed the write sticks via readback). FMR_IEFaction is
    ; FMR-only — original Fertility Mode v3 lacks it, in which case
    ; conditions read False as a graceful degradation.
    return FMR_Storage != None
EndFunction

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        ; Deps not yet loaded (Fertility Mode may not be active, or its forms
        ; aren't resolvable yet). Re-arm; without this the bail is silent and
        ; nothing ever retries — we'd stay unregistered for the session.
        RegisterForSingleUpdate(2.0)
        return
    endif
    MTF_MainQuest host = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if host == None || host.registeredPlugins == None
        RegisterForSingleUpdate(1.0)
        return
    endif
    _ensureLoaded()
    host.RegisterPlugin(self)
    _registered = true
EndFunction

; ── Conditions (catalog-driven) ──────────────────────────────────────────────
int Function GetConditionCount()
    _ensureLoaded()
    return _condN
EndFunction

string Function GetConditionId(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _condN
        return ""
    endif
    return _condIds[idx]
EndFunction

string Function GetConditionLabel(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _condN
        return ""
    endif
    return _condLabels[idx]
EndFunction

string Function GetConditionDescription(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _condN
        return ""
    endif
    return _condDescriptions[idx]
EndFunction

string Function GetConditionParamLabel(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _condN
        return ""
    endif
    return _condParamLabels[idx]
EndFunction

int Function GetConditionParamMin(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _condN
        return 0
    endif
    return _condParamMins[idx]
EndFunction

int Function GetConditionParamMax(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _condN
        return 100
    endif
    return _condParamMaxes[idx]
EndFunction

int Function GetConditionParamDefault(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _condN
        return 0
    endif
    return _condParamDefaults[idx]
EndFunction

; ── Effects (catalog-driven) ─────────────────────────────────────────────────
int Function GetEffectCount()
    _ensureLoaded()
    return _effectN
EndFunction

string Function GetEffectId(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _effectN
        return ""
    endif
    return _effectIds[idx]
EndFunction

string Function GetEffectLabel(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _effectN
        return ""
    endif
    return _effectLabels[idx]
EndFunction

string Function GetEffectParamLabel(int idx)
    return ""
EndFunction

string Function GetEffectDescription(int idx)
    _ensureLoaded()
    if idx < 0 || idx >= _effectN
        return ""
    endif
    return _effectDescriptions[idx]
EndFunction

; ── Behaviour (stays in Papyrus — these can't be data) ───────────────────────
int Function _trackedIndex(Actor target)
    if target == None || FMR_Storage == None || FMR_Storage.TrackedActors == None
        return -1
    endif
    return FMR_Storage.TrackedActors.Find(target as Form)
EndFunction

bool Function checkCondition(int idx, Actor target, int param)
    if target == None
        return false
    endif
    ; Inline resolve: the Auto Hidden FMR_IEFaction property doesn't always
    ; backing-attach mid-save (project_papyrus_property_attach), so it can
    ; stay None across reloads even after a successful registration. Re-resolve
    ; on every call when None; GetFormFromFile is cheap and the form is cached
    ; once we successfully fetch it.
    if FMR_IEFaction == None
        FMR_IEFaction = Game.GetFormFromFile(0x02666B, "Fertility Mode.esm") as Faction
    endif
    if FMR_IEFaction == None
        ; Original Fertility Mode v3 lacks ImmersiveEffectsFaction. Graceful
        ; degradation: condition reads false.
        return false
    endif
    ; FMR's poll loop encodes both pregnancy stage (1..100) and cycle phase
    ; (116..119) into ImmersiveEffectsFaction rank. Reading via the actor's
    ; faction rank instead of Storage.LastConception[i]/LastOvulation[i] avoids
    ; the array-property quirks that gave us zeros while FMR's own MCM showed
    ; live values. See faction-rank table in property declaration above.
    int rank = target.GetFactionRank(FMR_IEFaction)
    if idx == 0
        ; Pregnancy: rank 1..100 directly IS the belly-stage percentage.
        return rank >= 1 && rank <= 100 && rank >= param
    elseif idx == 1
        ; Ovulation: rank 118 (egg present OR in ovulation window). FMR's
        ; pregnancy ranks (1..100) take precedence — rank only reaches 118
        ; when not pregnant — so no extra !isPregnant gate needed.
        return rank == 118
    endif
    return false
EndFunction

Function onActivate(int idx, Actor target, int param, int param2)
    if idx != 0 || target == None || FMR_Storage == None
        return
    endif
    int i = _trackedIndex(target)
    if i < 0
        return
    endif
    ; Don't interrupt an in-progress pregnancy, and don't re-trigger if she's
    ; already ovulating. Indexed access (no `== None` guard) — the guard logs
    ; false-positive cast errors on Auto arrays
    ; (project_papyrus_array_none_cast_noise); a truly-None array would
    ; Papyrus-error on the indexed read and abort the function gracefully.
    if FMR_Storage.LastConception[i] > 0.0
        return
    endif
    if FMR_Storage.LastOvulation[i] > 0.0
        return
    endif
    FMR_Storage.LastOvulation[i] = 0.001
EndFunction
