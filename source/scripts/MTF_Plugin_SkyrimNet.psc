Scriptname MTF_Plugin_SkyrimNet extends MTF_Plugin
{SkyrimNet integration bridge. See _setupBridge body for the safety rationale.}

; ══════════════════════════════════════════════════════════════════════════
; ARCHITECTURE (v0.1.20)
;
; Two integration channels with SkyrimNet, mirroring the
; "scene-context vs. ambient-context" split documented in SkyrimNet's
; WORKFLOW_MOD_INTEGRATION.md:
;
;   1. SHORT-LIVED EVENT (scene context, TTL-bounded).
;      On every MTF_TierChanged for the player, fire
;      SkyrimNetApi.RegisterShortLivedEvent with a single deduped
;      eventId ("mtf_tattoo_state"). TTL 30s — long enough to outlive
;      one LLM cycle, short enough to expire silently if the user
;      changes the tattoo and walks away. The eventId is intentionally
;      stable so a fast cascade of transitions only leaves the LATEST
;      description in scene context (SkyrimNet dedupes by id).
;
;   2. DECORATOR (always-on bio context).
;      Register a `mtf_active_tattoos(actorUUID)` decorator that
;      prompt templates can call to inject the current visible-tattoo
;      description at render time. Function is `global` per SkyrimNet's
;      decorator contract; queries MainQuest via GetFormFromFile so it
;      needs no instance state.
;
; SOFT-MASTER PATTERN
; Detect SkyrimNet.esp at runtime via Game.GetModByName. If absent, skip
; the host registration entirely so the bridge has zero footprint when
; the user doesn't have SkyrimNet installed. Same pattern as the FMR /
; BFNG / SlaveTats bridges.
;
; SCOPE OF v0.1.20
;   * Player-visible state only. NPC preset tier changes ARE emitted by
;     MainQuest but the bridge ignores them — SkyrimNet's audience model
;     would route per-NPC tattoo changes to the wrong scene context
;     (the NPC's, not the player's). Deferred to a future revision.
;   * Decorator returns description of the currently winning slot's
;     pack/entry + every active effect's description. Pack/entry
;     descriptions fall back to "<entry label>" then "an unnamed tattoo"
;     when authors haven't filled in the optional `description` field.
;   * RegisterShortLivedEvent payload is the same prose the decorator
;     produces — so prompts get consistent wording whether they receive
;     it via scene-context or via the decorator call.
;
; STATE TOUCHED
;   * Soft-detects SkyrimNet.esp via Game.GetModByName.
;   * Calls SkyrimNetApi.RegisterDecorator once per session.
;   * Calls SkyrimNetApi.RegisterShortLivedEvent on every player tier
;     change (deduped on a stable eventId — SkyrimNet handles TTL).
; ══════════════════════════════════════════════════════════════════════════

bool Property _depsResolved Auto Hidden
; NOTE: no _bridgeSetup property anymore — SkyrimNet's RegisterDecorator /
; RegisterEventSchema state lives in C++ memory that resets every game
; launch. A persistent guard would leave us thinking we'd registered when
; SkyrimNet sees no decorator. _setupBridge is called from both
; _tryRegister (first-session path) AND MTF_AliasSkyrimNet.OnPlayerLoadGame
; (every-load path). Re-registering is cheap and idempotent on SkyrimNet's side.

; ── Identity ────────────────────────────────────────────────────────────────
string Function GetPluginId()
    return "mtf.skyrimnet"
EndFunction
string Function GetPluginLabel()
    return "SkyrimNet Bridge"
EndFunction

; ── Soft-dep resolution ─────────────────────────────────────────────────────
MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

bool Function _resolveDeps()
    if _depsResolved
        return true
    endif
    if Game.GetModByName("SkyrimNet.esp") == 255
        return false
    endif
    _depsResolved = true
    return true
EndFunction

Function _tryRegister()
    if _registered
        return
    endif
    if !_resolveDeps()
        ; Re-arm. Without this we'd silently stay unregistered (late load
        ; order / late init scenarios).
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
    _setupBridge()
EndFunction

Function _setupBridge()
    ; Register the decorator + event schema with SkyrimNet. Decorator
    ; function must be a `global` function on this script (per SkyrimNet's
    ; contract — see skynet_ExampleScript.psc reference). Both calls are
    ; idempotent on SkyrimNet's side, so callers don't need to guard.
    ;
    ; CRITICAL: SkyrimNet's API state (registered decorators, schemas) is
    ; held in C++ memory that resets every game launch. A persistent
    ; Auto Hidden "_bridgeSetup" guard would silently lose the registration
    ; after the first save reload — the player would see the bio render
    ; rendered without the Magic Tattoos section. This is invoked from:
    ;   - _tryRegister() (first-session path)
    ;   - MTF_AliasSkyrimNet.OnPlayerLoadGame() (every reload thereafter)
    ;
    ; Listener registration (RegisterForModEvent) is handled by
    ; MTF_AliasSkyrimNet on the host alias — Quest scripts can't call
    ; RegisterForModEvent (the native is on Alias/AMF) and Caprica
    ; forbids non-native scripts from declaring new Event types.
    SkyrimNetApi.RegisterDecorator("mtf_active_tattoos", "MTF_Plugin_SkyrimNet", "MTF_ActiveTattoosDecorator")
    _registerTattooChangeSchema()
    Debug.Trace("MTF.SkyrimNet: bridge ready (decorator + schema registered; alias hosts listener)")
EndFunction

; Register the mtf_tattoo_change event schema. Makes the event introspectable
; to SkyrimNet's analytics / diary / memory pipelines — without a schema,
; structured-event consumers see `data` as an opaque string.
Function _registerTattooChangeSchema()
    string fields = "["                                                                                                  \
        + "{\"name\":\"verb\",\"type\":0,\"required\":true,\"description\":\"Transition kind: appeared_dormant | appeared_triggered | triggered | shifted | dormant\"},"  \
        + "{\"name\":\"subject\",\"type\":0,\"required\":true,\"description\":\"Display subject: the preset's display_name, or 'Magic' for the player's MCM base preset\"},"  \
        + "{\"name\":\"preset_name\",\"type\":0,\"required\":false,\"description\":\"Internal preset name; empty for the player's MCM base preset\"},"  \
        + "{\"name\":\"prev_tier\",\"type\":1,\"required\":true,\"description\":\"Previous slot (-1 none, 0 dormant, 1-7 conditional)\"},"  \
        + "{\"name\":\"new_tier\",\"type\":1,\"required\":true,\"description\":\"New slot (0 dormant, 1-7 conditional)\"}"  \
        + "]"
    string templates = "{"                                                                                                                                   \
        + "\"recent_events\":\"{{subject}} tattoo {{verb}} ({{time_desc}})\","                                                                              \
        + "\"raw\":\"{{subject}} tattoo {{verb}}\","                                                                                                        \
        + "\"compact\":\"{{subject}} tattoo {{verb}}\","                                                                                                    \
        + "\"verbose\":\"{{subject}} tattoo transitioned slot {{prev_tier}} -> {{new_tier}} ({{verb}})\""                                                   \
        + "}"
    ; isEphemeral=true, ttl=30s (matches the short-lived event TTL).
    ; CRITICAL: shortLivedEnabled=false — we manually fire the scene-context
    ; entry via RegisterShortLivedEvent in HandleTierChange with a hand-
    ; crafted verb-led sentence. Setting this true causes SkyrimNet to ALSO
    ; auto-create a scene-context entry from the schema description, producing
    ; two redundant events per transition (one with our prose, one with the
    ; schema's docs text). interrupt=false — tattoo changes shouldn't preempt
    ; active speech.
    SkyrimNetApi.RegisterEventSchema("mtf_tattoo_change", "Magic Tattoo Change", \
        "Fires when a Magic Tattoos Framework preset transitions between conditional slots (dormant <-> triggered, or condition shifts).", \
        fields, templates, true, 30000, false, false)
EndFunction

; ── Conditions: none ────────────────────────────────────────────────────────
int Function GetConditionCount()
    return 0
EndFunction

; ── Effects: none ───────────────────────────────────────────────────────────
int Function GetEffectCount()
    return 0
EndFunction

; ── Listener callback (invoked by MTF_AliasSkyrimNet) ──────────────────────
; The alias script catches the mod event and calls this. We can't
; RegisterForModEvent directly here because Quest scripts don't have the
; Alias/AMF native and Caprica won't let us declare new Events. Plain
; Function call from the alias is the portable path.
;
; v0.1.21: emits a minimal verb-led scene-context sentence + a structured
; `data` payload matching the mtf_tattoo_change schema (registered in
; _registerTattooChangeSchema). The decorator carries the full current
; state — this event just announces WHAT CHANGED so the LLM can react
; to the transition. Detail lookups (visual / pulse / effects) belong
; in the decorator path.
;
; Scope: player only (target == PlayerRef). Stacked presets ARE handled
; (presetName non-empty paths through, with per-preset eventId so
; concurrent presets don't dedupe each other). NPC tier changes still
; early-out — SkyrimNet's scene-context audience model would route them
; to the wrong scene.
Function HandleTierChange(string strArg, float numArg, Form sender)
    Debug.Trace("MTF.SkyrimNet HandleTierChange enter: strArg=" + strArg)
    Actor target = sender as Actor
    if target == None
        Debug.Trace("MTF.SkyrimNet HandleTierChange: sender not Actor, dropped")
        return
    endif
    if target != Game.GetPlayer()
        Debug.Trace("MTF.SkyrimNet HandleTierChange: target is NPC, dropped (v0.1.20 player-only)")
        return
    endif
    ; PapyrusUtil's StringUtil.Split COLLAPSES empty fields between
    ; consecutive delimiters. So MainQuest's "<scope>|<presetName>|<prev>|<new>"
    ; format produces:
    ;   "player|MyPreset|1|0"  -> ["player","MyPreset","1","0"]  (4 parts)
    ;   "player||1|0"          -> ["player","1","0"]             (3 parts, base preset)
    ; Both shapes are legal; only the empty-presetName case loses a field
    ; in the split.
    string[] parts = StringUtil.Split(strArg, "|")
    string presetName = ""
    int prevTier
    int newTier
    if parts.Length == 4
        presetName = parts[1]
        prevTier = parts[2] as int
        newTier = parts[3] as int
    elseif parts.Length == 3
        prevTier = parts[1] as int
        newTier = parts[2] as int
    else
        Debug.Trace("MTF.SkyrimNet HandleTierChange: unexpected strArg parts=" + parts.Length + ", dropped")
        return
    endif

    string verb = _classifyTransition(prevTier, newTier)
    if verb == ""
        Debug.Trace("MTF.SkyrimNet HandleTierChange: same-tier or invalid (prev=" + prevTier + " new=" + newTier + "), dropped")
        return
    endif
    Debug.Trace("MTF.SkyrimNet HandleTierChange: firing event preset='" + presetName + "' verb=" + verb + " prev=" + prevTier + " new=" + newTier)

    MTF_MainQuest host = _host()
    string displayName = ""
    if presetName != "" && host != None
        displayName = host.GetPresetDisplayName(presetName)
    endif
    string subject = _subjectFor(displayName)
    string descLine = subject + " tattoo " + _verbPhrase(verb) + "."

    ; Structured payload matches the registered schema's fields.
    string data = "{"                                                          \
        + "\"verb\":\"" + verb + "\""                                          \
        + ",\"subject\":\"" + _jsonEsc(subject) + "\""                         \
        + ",\"preset_name\":\"" + _jsonEsc(presetName) + "\""                  \
        + ",\"prev_tier\":" + prevTier                                         \
        + ",\"new_tier\":" + newTier                                           \
        + "}"

    ; Per-preset eventId so multiple stacked presets don't dedupe each
    ; other's transition lines. Base preset keeps the original key for
    ; cross-session continuity (event history queries from save reloads).
    string eventId = "mtf_tattoo_state"
    if presetName != ""
        eventId = "mtf_tattoo_state:" + presetName
    endif

    SkyrimNetApi.RegisterShortLivedEvent( \
        eventId, \
        "mtf_tattoo_change", \
        descLine, \
        data, \
        30000, \
        target, \
        None \
    )
EndFunction

; Classify a (prev, new) tier pair into a verb. Returns "" for no-op
; (same tier) or invalid input.
String Function _classifyTransition(int prevTier, int newTier) global
    if newTier < 0 || newTier == prevTier
        return ""
    endif
    if prevTier < 0
        if newTier == 0
            return "appeared_dormant"
        endif
        return "appeared_triggered"
    endif
    if prevTier == 0 && newTier > 0
        return "triggered"
    endif
    if prevTier > 0 && newTier == 0
        return "dormant"
    endif
    if prevTier > 0 && newTier > 0
        return "shifted"
    endif
    return ""
EndFunction

; Verb → sentence-fragment predicate. Keep these short and self-contained
; — the LLM reads them in scene context and pulls full detail from the
; decorator when it needs to narrate visuals/effects.
String Function _verbPhrase(string verb) global
    if verb == "appeared_dormant"
        return "appeared on the skin in a dormant state"
    elseif verb == "appeared_triggered"
        return "appeared on the skin with its condition triggered"
    elseif verb == "triggered"
        return "had its condition triggered"
    elseif verb == "shifted"
        return "shifted to a different condition"
    elseif verb == "dormant"
        return "became dormant"
    endif
    return "changed state"
EndFunction

; Subject phrase for the scene-context line and the structured `subject`
; field. Base preset has no display name → use a generic noun. Stacked
; presets get their display name verbatim.
String Function _subjectFor(string displayName) global
    if displayName == ""
        return "Magic"
    endif
    return displayName
EndFunction

; ── Decorator (called by SkyrimNet prompt engine) ──────────────────────────
; SkyrimNet's `RegisterDecorator` contract: function takes exactly one
; `Actor` parameter (SkyrimNet resolves the prompt's `actorUUID` to an
; Actor before invoking) and returns a String that the Inja runtime
; parses as JSON, exposing field accessors like `mtf.presets[i].name`.
; Earlier signature `(string decoratorId, Actor)` made the Papyrus
; dispatcher silently fail to bind → SkyrimNet returned its
; "Result was not a string" sentinel.
;
; Payload shape (v0.1.21):
;   { "present": bool, "presets": [ { ...preset... }, ... ] }
; Each preset:
;   { name, display_name, tier, tier_kind, pack_label, entry_label,
;     visual_description, pulse: {rate,depth}|null, effects: [...] }
; Each effect:
;   { key, label, description, params: [ {label,value,value_label}, ... ] }
; Empty for unused param slots; pulse is null when rate==0.
;
; Scope: per actor.
;   - Player: MCM-driven base preset (emitted with name="" per project
;     convention — base has no internal name) + every applied preset in
;     `mtf.presets` (StringList per actor).
;   - NPC: applied presets only.
String Function MTF_ActiveTattoosDecorator(Actor akActor) global
    if akActor == None
        return "{\"present\":false,\"presets\":[]}"
    endif
    MTF_MainQuest host = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if host == None
        return "{\"present\":false,\"presets\":[]}"
    endif
    string presetsJson = ""
    bool any = false

    ; Player base preset (MCM-driven). Only exists on the player.
    if akActor == Game.GetPlayer()
        int baseTier = host.GetCurrentTier()
        if baseTier >= 0
            string s = _buildBasePresetJson(host, baseTier)
            if s != ""
                presetsJson = s
                any = true
            endif
        endif
    endif

    ; Applied (stacked) presets. ANY actor can carry these.
    int n = StorageUtil.StringListCount(akActor, "mtf.presets")
    int i = 0
    while i < n
        string nm = StorageUtil.StringListGet(akActor, "mtf.presets", i)
        if nm != ""
            int tier = StorageUtil.GetIntValue(akActor, "mtf.preset." + nm + ".tier", -1)
            if tier >= 0
                string s = _buildStackedPresetJson(host, nm, tier)
                if s != ""
                    if any
                        presetsJson = presetsJson + ","
                    endif
                    presetsJson = presetsJson + s
                    any = true
                endif
            endif
        endif
        i += 1
    endwhile

    if !any
        return "{\"present\":false,\"presets\":[]}"
    endif
    string out = "{\"present\":true,\"presets\":[" + presetsJson + "]}"
    ; Debug trace gated to non-trivial output. Helpful for diagnosing
    ; "effects don't display" / "tattoo not visible" reports — copy the
    ; line from Papyrus.0.log and re-render to confirm the payload SkyrimNet
    ; actually receives.
    Debug.Trace("MTF.SkyrimNet decorator: " + out)
    return out
EndFunction

; ── JSON builders (decorator path) ─────────────────────────────────────────

; Base preset: live runtime state. Reads from MTF_MainQuest script-level
; cond arrays + StorageUtil pulse keys (`GetCondPulseRate/Depth`). Does
; NOT touch the scratch namespace — the main MTF tick owns that and a
; concurrent read would race (see project memory: scratch-namespace
; clobber in dispatch loops).
String Function _buildBasePresetJson(MTF_MainQuest host, int tier) global
    string packId = host.ResolveSlotPackId(tier)
    string entryId = host.ResolveSlotEntryId(tier)
    string packLabel = ""
    int pi = host.FindVisualPackIndex(packId)
    if pi >= 0
        packLabel = host.visualPackLabels[pi]
    endif
    string entryLabel = _findEntryLabel(host, packId, entryId)
    string visualDesc = host.GetEntryDescription(packId, entryId)
    float pulseRate = host.GetCondPulseRate(tier)
    int pulseDepth = host.GetCondPulseDepth(tier)
    string layersJson = _buildBaseLayersJson(host, tier, packId, entryId)
    string effectsJson = _buildBaseEffectsJson(host, tier)
    ; Condition predicate that activated this slot. Empty/null for slot 0
    ; (dormant — no predicate, just the always-on default state).
    string condKey = host.condPluginId[tier]
    int condP1 = host.condParam[tier]
    int condP2 = host.GetCondParam2(tier)
    string conditionJson = _buildConditionJson(host, condKey, condP1, condP2)
    return _composePresetJson("", "", tier, packLabel, entryLabel, visualDesc, pulseRate, pulseDepth, layersJson, effectsJson, conditionJson)
EndFunction

; Stacked preset: reads from the preset JSON file directly via JsonUtil
; (not from scratch arrays). Same scratch-race rationale as above.
String Function _buildStackedPresetJson(MTF_MainQuest host, string presetName, int tier) global
    string f = host._presetFile(presetName)
    if f == ""
        return ""
    endif
    ; Visual = slot's own pack/entry, fallback to slot 0 (mirrors
    ; ResolveSlotPackId / ResolveSlotEntryId fallback rule).
    string packId = JsonUtil.GetPathStringValue(f, ".slot[" + tier + "].cond.packid", "")
    string entryId = JsonUtil.GetPathStringValue(f, ".slot[" + tier + "].cond.entryid", "")
    if packId == "" && tier > 0
        packId = JsonUtil.GetPathStringValue(f, ".slot[0].cond.packid", "")
        entryId = JsonUtil.GetPathStringValue(f, ".slot[0].cond.entryid", "")
    endif
    string packLabel = ""
    int pi = host.FindVisualPackIndex(packId)
    if pi >= 0
        packLabel = host.visualPackLabels[pi]
    endif
    string entryLabel = _findEntryLabel(host, packId, entryId)
    string visualDesc = host.GetEntryDescription(packId, entryId)
    float pulseRate = JsonUtil.GetPathFloatValue(f, ".slot[" + tier + "].pulse.rate", 0.0)
    int pulseDepth = JsonUtil.GetPathIntValue(f, ".slot[" + tier + "].pulse.depth", 0)
    string layersJson = _buildStackedLayersJson(host, f, tier, packId, entryId)
    string effectsJson = _buildStackedEffectsJson(host, f, tier)
    string displayName = host.GetPresetDisplayName(presetName)
    ; Condition predicate from the preset JSON (stacked presets store this
    ; directly in the slot block; we don't touch scratch arrays — see the
    ; scratch-race comment on _buildStackedPresetJson).
    string condKey = JsonUtil.GetPathStringValue(f, ".slot[" + tier + "].cond.pluginid", "")
    int condP1 = JsonUtil.GetPathIntValue(f, ".slot[" + tier + "].cond.param", 0)
    int condP2 = JsonUtil.GetPathIntValue(f, ".slot[" + tier + "].cond.param2", 0)
    string conditionJson = _buildConditionJson(host, condKey, condP1, condP2)
    return _composePresetJson(presetName, displayName, tier, packLabel, entryLabel, visualDesc, pulseRate, pulseDepth, layersJson, effectsJson, conditionJson)
EndFunction

String Function _composePresetJson(string name, string displayName, int tier, string packLabel, string entryLabel, string visualDesc, float pulseRate, int pulseDepth, string layersJson, string effectsJson, string conditionJson) global
    string tierKind = "dormant"
    if tier > 0
        tierKind = "triggered"
    endif
    string j = "{"
    j = j + "\"name\":\"" + _jsonEsc(name) + "\""
    j = j + ",\"display_name\":\"" + _jsonEsc(displayName) + "\""
    j = j + ",\"tier\":" + tier
    j = j + ",\"tier_kind\":\"" + tierKind + "\""
    j = j + ",\"pack_label\":\"" + _jsonEsc(packLabel) + "\""
    j = j + ",\"entry_label\":\"" + _jsonEsc(entryLabel) + "\""
    j = j + ",\"visual_description\":\"" + _jsonEsc(visualDesc) + "\""
    if pulseRate > 0.0
        ; rate_word / depth_word give the LLM natural prose without parsing
        ; the raw numerics. rate Hz -> non-frequently / frequently / very
        ; frequently. depth % -> non-deeply / moderately deeply / deeply
        ; (depth is "how far down from peak emission the dip travels" —
        ; high depth = strong pulsing, low depth = barely-noticeable shimmer).
        j = j + ",\"pulse\":{"
        j = j + "\"rate\":" + pulseRate
        j = j + ",\"depth\":" + pulseDepth
        j = j + ",\"rate_word\":\"" + _rateWord(pulseRate) + "\""
        j = j + ",\"depth_word\":\"" + _depthWord(pulseDepth) + "\""
        j = j + "}"
    else
        j = j + ",\"pulse\":null"
    endif
    j = j + ",\"layers\":[" + layersJson + "]"
    j = j + ",\"effects\":[" + effectsJson + "]"
    ; conditionJson is either "" (dormant / no predicate) or a JSON object
    ; literal — embed as "null" sentinel when empty so templates can
    ; reliably check `{% if p.condition %}`.
    if conditionJson == ""
        j = j + ",\"condition\":null"
    else
        j = j + ",\"condition\":" + conditionJson
    endif
    j = j + "}"
    return j
EndFunction

; Condition JSON for the slot that's currently winning. Returns "" if the
; slot has no predicate (dormant / unconfigured). Otherwise builds:
;   { "key", "label", "description", "params": [ {label,value,value_label}, ... ] }
; Mirrors the effect-side `_buildEffectJson` shape so templates can reuse
; the same `{{ x.label }}` / `{{ x.description }}` / `{{ p.label }}: {{ p.value_label }}`
; rendering pattern.
String Function _buildConditionJson(MTF_MainQuest host, string key, int p1, int p2) global
    if key == ""
        return ""
    endif
    MTF_Plugin p = host.ResolvePluginByKey(key)
    string label = ""
    string desc = ""
    string paramsJson = ""
    string p1Val = ""
    string p2Val = ""
    if p != None
        int itemIdx = host._condIdxFor(p, host._keyItemId(key))
        if itemIdx >= 0
            label = p.GetConditionLabel(itemIdx)
            desc = p.GetConditionDescription(itemIdx)
            paramsJson = _buildConditionParamsJson(p, itemIdx, p1, p2)
            ; Resolve value labels for {param1}/{param2} substitution in
            ; the description — same richness as effect descriptions:
            ; dropdown options resolve to their label, numeric params apply
            ; the plugin's Format string. Unused slots leave the placeholder
            ; verbatim so authoring mistakes stay visible.
            if p.GetConditionParamLabel(itemIdx) != ""
                p1Val = _resolveConditionParamValueLabel(p, itemIdx, false, p1)
            endif
            if p.GetConditionParam2Label(itemIdx) != ""
                p2Val = _resolveConditionParamValueLabel(p, itemIdx, true, p2)
            endif
        endif
    endif
    desc = _substDescPlaceholders(desc, p1Val, p2Val)
    string j = "{"
    j = j + "\"key\":\"" + _jsonEsc(key) + "\""
    j = j + ",\"label\":\"" + _jsonEsc(label) + "\""
    j = j + ",\"description\":\"" + _jsonEsc(desc) + "\""
    j = j + ",\"params\":[" + paramsJson + "]"
    j = j + "}"
    return j
EndFunction

; Build the condition's params array. Conditions now mirror the effect-side
; pipeline: both param slots resolve their value_label through the shared
; _resolveConditionParamValueLabel helper (dropdown options → label, numeric
; params → Format-string applied). Templates can render `{{ p.label }}: {{
; p.value_label }}` and get unit-aware text for both slots.
String Function _buildConditionParamsJson(MTF_Plugin p, int itemIdx, int p1, int p2) global
    string p1Json = _buildOneConditionParamJson(p, itemIdx, false, p1)
    string p2Json = _buildOneConditionParamJson(p, itemIdx, true, p2)
    if p1Json == "" && p2Json == ""
        return ""
    elseif p2Json == ""
        return p1Json
    elseif p1Json == ""
        return p2Json
    endif
    return p1Json + "," + p2Json
EndFunction

String Function _buildOneConditionParamJson(MTF_Plugin p, int itemIdx, bool isParam2, int value) global
    string lbl = ""
    if isParam2
        lbl = p.GetConditionParam2Label(itemIdx)
    else
        lbl = p.GetConditionParamLabel(itemIdx)
    endif
    if lbl == ""
        return ""
    endif
    string valLabel = _resolveConditionParamValueLabel(p, itemIdx, isParam2, value)
    string j = "{"
    j = j + "\"label\":\"" + _jsonEsc(lbl) + "\""
    j = j + ",\"value\":" + value
    j = j + ",\"value_label\":\"" + _jsonEsc(valLabel) + "\""
    j = j + "}"
    return j
EndFunction

; Pulse rate bucket. Input is Hz (pulses per second). Empty string when
; pulse is disabled (rate==0) — the caller already gates on that, this is
; defensive.
String Function _rateWord(float rate) global
    if rate <= 0.0
        return ""
    elseif rate < 0.5
        return "non-frequently"
    elseif rate < 2.0
        return "frequently"
    endif
    return "very frequently"
EndFunction

; Pulse depth bucket. Input is 0-100% — "how much below peak emission the
; dim end of the cycle reaches". depth=10 means the pulse barely dips
; (10% below peak); depth=80 means strong on/off-style pulsing.
String Function _depthWord(int depth) global
    if depth <= 0
        return ""
    elseif depth < 30
        return "non-deeply"
    elseif depth < 70
        return "moderately deeply"
    endif
    return "deeply"
EndFunction

; Layers JSON — per-layer color/alpha/emissive. Base preset reads from
; the player's cond arrays (live runtime state — picks up MCM slider
; changes). Hex codes as "#RRGGBB". emissive_mult scales the base
; emissive intensity (higher = brighter glow).
String Function _buildBaseLayersJson(MTF_MainQuest host, int slot, string packId, string entryId) global
    int layerN = host.GetEntryLayerCount(packId, entryId)
    if layerN <= 0
        return ""
    endif
    int maxL = MTF_MainQuest.MAX_LAYERS_PER_SLOT()
    if layerN > maxL
        layerN = maxL
    endif
    string acc = ""
    int i = 0
    while i < layerN
        int lidx = slot * maxL + i
        int tint = host.condLayerTint[lidx]
        int emissive = host.condLayerEmissive[lidx]
        float emMult = host.condLayerEmissiveMult[lidx]
        int alpha = host.condLayerAlpha[lidx]
        if i > 0
            acc = acc + ","
        endif
        acc = acc + "{"
        acc = acc + "\"tint\":\"" + host._intToHex(tint) + "\""
        acc = acc + ",\"emissive\":\"" + host._intToHex(emissive) + "\""
        acc = acc + ",\"emissive_mult\":" + emMult
        acc = acc + ",\"alpha\":" + alpha
        acc = acc + "}"
        i += 1
    endwhile
    return acc
EndFunction

; Stacked preset layers — same shape as base, but the source is the
; preset's JSON (slot[N].layer[L].*) instead of live cond arrays. Color
; values in the preset JSON are already hex strings, so we copy them
; through verbatim.
String Function _buildStackedLayersJson(MTF_MainQuest host, string presetFile, int slot, string packId, string entryId) global
    int layerN = host.GetEntryLayerCount(packId, entryId)
    if layerN <= 0
        return ""
    endif
    int maxL = MTF_MainQuest.MAX_LAYERS_PER_SLOT()
    if layerN > maxL
        layerN = maxL
    endif
    string acc = ""
    int i = 0
    while i < layerN
        string lp = ".slot[" + slot + "].layer[" + i + "]"
        string tint = JsonUtil.GetPathStringValue(presetFile, lp + ".tint", "#FFFFFF")
        string emissive = JsonUtil.GetPathStringValue(presetFile, lp + ".emissive", "#000000")
        float emMult = JsonUtil.GetPathFloatValue(presetFile, lp + ".emissivemult", 1.0)
        int alpha = JsonUtil.GetPathIntValue(presetFile, lp + ".alpha", 100)
        if i > 0
            acc = acc + ","
        endif
        acc = acc + "{"
        acc = acc + "\"tint\":\"" + _jsonEsc(tint) + "\""
        acc = acc + ",\"emissive\":\"" + _jsonEsc(emissive) + "\""
        acc = acc + ",\"emissive_mult\":" + emMult
        acc = acc + ",\"alpha\":" + alpha
        acc = acc + "}"
        i += 1
    endwhile
    return acc
EndFunction

String Function _findEntryLabel(MTF_MainQuest host, string packId, string entryId) global
    if packId == "" || entryId == ""
        return ""
    endif
    int n = host.GetPackEntryCount(packId)
    int i = 0
    while i < n
        if host.GetPackEntryIdAt(packId, i) == entryId
            return host.GetPackEntryLabelAt(packId, i)
        endif
        i += 1
    endwhile
    return ""
EndFunction

String Function _buildBaseEffectsJson(MTF_MainQuest host, int slot) global
    int maxE = MTF_MainQuest.MAX_EFFECTS_PER_SLOT()
    string acc = ""
    bool any = false
    int e = 0
    while e < maxE
        string key = host._readFxKey(slot, e, false)
        if key != ""
            int p1 = host._readFxParam(slot, e, false)
            int p2 = host._readFxParam2(slot, e, false)
            string s = _buildEffectJson(host, key, p1, p2)
            if s != ""
                if any
                    acc = acc + ","
                endif
                acc = acc + s
                any = true
            endif
        endif
        e += 1
    endwhile
    return acc
EndFunction

String Function _buildStackedEffectsJson(MTF_MainQuest host, string presetFile, int slot) global
    int n = JsonUtil.PathCount(presetFile, ".slot[" + slot + "].effect")
    if n <= 0
        return ""
    endif
    string acc = ""
    bool any = false
    int i = 0
    while i < n
        string base = ".slot[" + slot + "].effect[" + i + "]"
        string key = JsonUtil.GetPathStringValue(presetFile, base + ".key", "")
        if key != ""
            int p1 = JsonUtil.GetPathIntValue(presetFile, base + ".param", 0)
            int p2 = JsonUtil.GetPathIntValue(presetFile, base + ".param2", 0)
            string s = _buildEffectJson(host, key, p1, p2)
            if s != ""
                if any
                    acc = acc + ","
                endif
                acc = acc + s
                any = true
            endif
        endif
        i += 1
    endwhile
    return acc
EndFunction

; v0.1.22: effect descriptions can embed `{param1}` and `{param2}`
; placeholders which the bridge substitutes with the param's resolved
; value_label (e.g. "75%", "Heartbeat", "5 seconds"). Plugin authors
; write natural prose like `"Sets spell cost to {param1} of original."`
; and the LLM receives the substituted text — no separate parenthetical
; param list needed downstream. Placeholders for unused param slots are
; left intact (which is harmless when the description doesn't reference
; them).
String Function _buildEffectJson(MTF_MainQuest host, string key, int p1, int p2) global
    MTF_Plugin p = host.ResolvePluginByKey(key)
    string label = ""
    string desc = ""
    string paramsJson = ""
    string p1Val = ""
    string p2Val = ""
    if p != None
        int itemIdx = host._effectIdxFor(p, host._keyItemId(key))
        if itemIdx >= 0
            label = p.GetEffectLabel(itemIdx)
            desc = p.GetEffectDescription(itemIdx)
            paramsJson = _buildParamsJson(p, itemIdx, p1, p2)
            ; Capture resolved value labels for description substitution.
            ; Empty label = effect doesn't use that param slot — leave the
            ; placeholder verbatim so authoring mistakes are visible.
            if p.GetEffectParamLabel(itemIdx) != ""
                p1Val = _resolveParamValueLabel(p, itemIdx, false, p1)
            endif
            if p.GetEffectParam2Label(itemIdx) != ""
                p2Val = _resolveParamValueLabel(p, itemIdx, true, p2)
            endif
        endif
    endif
    desc = _substDescPlaceholders(desc, p1Val, p2Val)
    string j = "{"
    j = j + "\"key\":\"" + _jsonEsc(key) + "\""
    j = j + ",\"label\":\"" + _jsonEsc(label) + "\""
    j = j + ",\"description\":\"" + _jsonEsc(desc) + "\""
    j = j + ",\"params\":[" + paramsJson + "]"
    j = j + "}"
    return j
EndFunction

; Substitute `{param1}` / `{param2}` placeholders with the resolved
; value labels. Either label may be empty (param slot unused on this
; effect) — in that case leave the placeholder alone so the author can
; see they referenced an unused slot.
String Function _substDescPlaceholders(string desc, string p1Val, string p2Val) global
    if desc == ""
        return desc
    endif
    if p1Val != ""
        desc = _replaceAll(desc, "{param1}", p1Val)
    endif
    if p2Val != ""
        desc = _replaceAll(desc, "{param2}", p2Val)
    endif
    return desc
EndFunction

; Replace all non-overlapping occurrences of `needle` with `repl` in `s`.
; Papyrus has no native string Replace — StringUtil only does Find /
; Substring. Cheap to roll our own since descriptions are typically
; <500 chars.
String Function _replaceAll(string s, string needle, string repl) global
    if s == "" || needle == ""
        return s
    endif
    int nl = StringUtil.GetLength(needle)
    string remaining = s
    string out = ""
    int idx = StringUtil.Find(remaining, needle)
    while idx >= 0
        ; Same SKSE Substring(_, 0, 0) quirk as _formatNum: when the needle
        ; starts at position 0, length=0 would return the whole string. Skip
        ; the head Substring call entirely in that case.
        if idx > 0
            out = out + StringUtil.Substring(remaining, 0, idx)
        endif
        out = out + repl
        remaining = StringUtil.Substring(remaining, idx + nl)
        idx = StringUtil.Find(remaining, needle)
    endwhile
    out = out + remaining
    return out
EndFunction

String Function _buildParamsJson(MTF_Plugin p, int itemIdx, int p1, int p2) global
    string p1Json = _buildOneParamJson(p, itemIdx, false, p1)
    string p2Json = _buildOneParamJson(p, itemIdx, true, p2)
    if p1Json == "" && p2Json == ""
        return ""
    elseif p2Json == ""
        return p1Json
    elseif p1Json == ""
        return p2Json
    endif
    return p1Json + "," + p2Json
EndFunction

String Function _buildOneParamJson(MTF_Plugin p, int itemIdx, bool isParam2, int value) global
    string lbl = ""
    if isParam2
        lbl = p.GetEffectParam2Label(itemIdx)
    else
        lbl = p.GetEffectParamLabel(itemIdx)
    endif
    if lbl == ""
        ; This effect doesn't use this param slot — omit entirely.
        return ""
    endif
    string valLabel = _resolveParamValueLabel(p, itemIdx, isParam2, value)
    string j = "{"
    j = j + "\"label\":\"" + _jsonEsc(lbl) + "\""
    j = j + ",\"value\":" + value
    j = j + ",\"value_label\":\"" + _jsonEsc(valLabel) + "\""
    j = j + "}"
    return j
EndFunction

; Condition-side mirror of _resolveParamValueLabel. Resolves dropdown menu
; options when present, otherwise applies the format string. Lets condition
; descriptions use {param1}/{param2} with the same richness as effect
; descriptions — e.g. BFNG cycle phase 1 -> "Ovulating" rather than "1",
; and Above Magicka 50 -> "50%" when GetConditionParamFormat returns "{0}%".
String Function _resolveConditionParamValueLabel(MTF_Plugin p, int itemIdx, bool isParam2, int value) global
    int optCount = 0
    if isParam2
        optCount = p.GetConditionParam2MenuOptionCount(itemIdx)
    else
        optCount = p.GetConditionParamMenuOptionCount(itemIdx)
    endif
    if optCount > 0
        int oi = 0
        while oi < optCount
            int ov = 0
            if isParam2
                ov = p.GetConditionParam2MenuOptionValue(itemIdx, oi)
            else
                ov = p.GetConditionParamMenuOptionValue(itemIdx, oi)
            endif
            if ov == value
                if isParam2
                    return p.GetConditionParam2MenuOptionLabel(itemIdx, oi)
                else
                    return p.GetConditionParamMenuOptionLabel(itemIdx, oi)
                endif
            endif
            oi += 1
        endwhile
        return "Custom: " + value
    endif
    string fmt = "{0}"
    if isParam2
        fmt = p.GetConditionParam2Format(itemIdx)
    else
        fmt = p.GetConditionParamFormat(itemIdx)
    endif
    if fmt == ""
        fmt = "{0}"
    endif
    return _formatNum(fmt, value)
EndFunction

String Function _resolveParamValueLabel(MTF_Plugin p, int itemIdx, bool isParam2, int value) global
    int optCount = 0
    if isParam2
        optCount = p.GetEffectParam2MenuOptionCount(itemIdx)
    else
        optCount = p.GetEffectParamMenuOptionCount(itemIdx)
    endif
    ; Dropdown param — find the option whose stored value matches.
    if optCount > 0
        int oi = 0
        while oi < optCount
            int ov = 0
            if isParam2
                ov = p.GetEffectParam2MenuOptionValue(itemIdx, oi)
            else
                ov = p.GetEffectParamMenuOptionValue(itemIdx, oi)
            endif
            if ov == value
                if isParam2
                    return p.GetEffectParam2MenuOptionLabel(itemIdx, oi)
                else
                    return p.GetEffectParamMenuOptionLabel(itemIdx, oi)
                endif
            endif
            oi += 1
        endwhile
        ; Off-list value (hand-edited preset JSON, future-incompat plugin).
        return "Custom: " + value
    endif
    ; Numeric param — apply the plugin's format string ("{0}", "{0}s", "{0}%").
    ; Both param and param2 have Format accessors on MTF_Plugin (abstract
    ; defaults to "{0}"); calling them on the wrong slot would just give
    ; back "{0}" which is still correct, but be specific anyway.
    string fmt = "{0}"
    if isParam2
        fmt = p.GetEffectParam2Format(itemIdx)
    else
        fmt = p.GetEffectParamFormat(itemIdx)
    endif
    if fmt == ""
        fmt = "{0}"
    endif
    return _formatNum(fmt, value)
EndFunction

String Function _formatNum(string fmt, int value) global
    int sep = StringUtil.Find(fmt, "{0}")
    if sep < 0
        return fmt
    endif
    ; SKSE quirk: StringUtil.Substring(str, 0, 0) returns the ENTIRE string,
    ; not "" — length=0 is interpreted as "default = to end" rather than
    ; zero chars. So guard the head explicitly when sep is 0.
    string head = ""
    if sep > 0
        head = StringUtil.Substring(fmt, 0, sep)
    endif
    string tail = StringUtil.Substring(fmt, sep + 3)
    return head + value + tail
EndFunction

; JSON string escaper. Handles ", \, and the four standard control
; escapes. Author-supplied descriptions can contain any of these.
String Function _jsonEsc(string s) global
    if s == ""
        return ""
    endif
    int n = StringUtil.GetLength(s)
    string out = ""
    int i = 0
    while i < n
        string c = StringUtil.Substring(s, i, 1)
        if c == "\""
            out = out + "\\\""
        elseif c == "\\"
            out = out + "\\\\"
        elseif c == "\n"
            out = out + "\\n"
        elseif c == "\t"
            out = out + "\\t"
        else
            out = out + c
        endif
        i += 1
    endwhile
    return out
EndFunction

; ── Prose builder ───────────────────────────────────────────────────────────
; Shared by OnMTFTierChanged + MTF_ActiveTattoosDecorator so the LLM gets
; identical wording whether the line came via scene-context or
; decorator-render. Format:
;   "The player has <tattoo description>. Its effect: <effect descriptions>."
String Function MTF_BuildTierProse(Actor akActor, int slot) global
    if akActor == None || slot < 0 || slot >= 8
        return ""
    endif
    MTF_MainQuest host = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if host == None
        return ""
    endif
    string packId  = host.ResolveSlotPackId(slot)
    string entryId = host.ResolveSlotEntryId(slot)
    string tattooDesc = ""
    if packId != "" && entryId != ""
        tattooDesc = host.GetEntryDescription(packId, entryId)
        if tattooDesc == ""
            ; Fallback: synthesize from pack+entry labels. Generic-label
            ; packs (LewdMarks "Mark 042", Obi "Tattoo 7") still get a
            ; readable line — just less narratively rich.
            string entryLabel = ""
            int n = host.GetPackEntryCount(packId)
            int i = 0
            while i < n
                if host.GetPackEntryIdAt(packId, i) == entryId
                    entryLabel = host.GetPackEntryLabelAt(packId, i)
                    i = n
                else
                    i += 1
                endif
            endwhile
            int pi = host.FindVisualPackIndex(packId)
            string packLabel = ""
            if pi >= 0
                packLabel = host.visualPackLabels[pi]
            endif
            if packLabel != "" && entryLabel != ""
                tattooDesc = "a " + entryLabel + " tattoo from the " + packLabel + " set"
            elseif entryLabel != ""
                tattooDesc = "a " + entryLabel + " tattoo"
            else
                tattooDesc = "an unnamed tattoo"
            endif
        endif
    endif
    string effectsDesc = MTF_BuildEffectsProse(host, slot)
    string out = ""
    if tattooDesc != ""
        out = "The player has " + tattooDesc + "."
    endif
    if effectsDesc != ""
        if out != ""
            out = out + " "
        endif
        out = out + "Its effect: " + effectsDesc
    endif
    return out
EndFunction

String Function MTF_BuildEffectsProse(MTF_MainQuest host, int slot) global
    if host == None || slot < 0
        return ""
    endif
    int maxE = MTF_MainQuest.MAX_EFFECTS_PER_SLOT()
    string acc = ""
    int e = 0
    while e < maxE
        string key = host._readFxKey(slot, e, false)
        if key != ""
            MTF_Plugin p = host.ResolvePluginByKey(key)
            if p != None
                int itemIdx = host._effectIdxFor(p, host._keyItemId(key))
                if itemIdx >= 0
                    string d = p.GetEffectDescription(itemIdx)
                    if d == ""
                        ; Fallback to the short MCM label — better than
                        ; silence for effects authored before the
                        ; description override pass.
                        d = p.GetEffectLabel(itemIdx)
                    endif
                    if d != ""
                        if acc != ""
                            acc = acc + " "
                        endif
                        acc = acc + d
                    endif
                endif
            endif
        endif
        e += 1
    endwhile
    return acc
EndFunction
