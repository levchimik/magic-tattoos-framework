Scriptname MTF_Plugin_SkyrimNet extends MTF_Plugin
{SkyrimNet integration bridge. See _setupBridge body for the safety rationale.}

; ══════════════════════════════════════════════════════════════════════════
; ARCHITECTURE (v0.1.23 — StorageUtil-bypass refactor)
;
; PROBLEM SOLVED:
;   SkyrimNet's Inja PromptEngine deduplicates decorator results by
;   (function_name, args_hash). A `mtf_active_tattoos(actorUUID)` decorator
;   call therefore caches forever for a given actor — the Papyrus function
;   only runs ~3 times per session (each dialogue-warmup), regardless of how
;   often the bio is rendered. Mid-session tier changes never reflect in the
;   bio because the cached JSON is reused.
;
; SOLUTION (the IntelEngine / SeverActions pattern):
;   On every state mutation, BUILD the final Markdown ourselves in Papyrus
;   and WRITE it to StorageUtil under per-actor key "mtf.bio.rendered".
;   The prompt reads the string directly via the built-in `papyrus_util`
;   decorator (cache key includes the actor UUID + storage key, so it
;   reads through every time). Zero decorator caching — always current.
;
; TWO INTEGRATION CHANNELS WITH SKYRIMNET:
;
;   1. SHORT-LIVED EVENT (scene context, TTL-bounded).
;      On every MTF_TierChanged for ANY actor (v0.1.24: was player-only),
;      fire SkyrimNetApi.RegisterShortLivedEvent with a per-preset eventId.
;      TTL 30s. Per-preset eventId means concurrent stacked presets don't
;      dedupe each other's transition lines. Schema is registered with
;      shortLivedEnabled=true so mtf_tattoo_change shows up in SkyrimNet's
;      Event Settings UI — that's the SINGLE source of truth for whether
;      NPCs should react, how often, and whether reactions can interrupt.
;
;   2. RENDERED MARKDOWN VIA STORAGEUTIL (the bio context channel).
;      _rebuildRenderedFor(Actor) composes the full "## Magic Tattoos" block
;      and writes it to StorageUtil. Called from HandleTierChange (every
;      tier transition for any actor) and from the alias's OnPlayerLoadGame
;      (seeds the player's string on load so the bio is populated before
;      any tier evaluation fires). NO decorator registration — we deleted
;      mtf_active_tattoos entirely. Bias toward writing slightly stale state
;      is impossible because every mutation funnels through _emitTierChanged
;      (MainQuest broadcasts unconditionally; bridge listens via the alias).
;
; SOFT-MASTER PATTERN
;   Detect SkyrimNet.esp at runtime via Game.GetModByName. If absent, skip
;   the host registration entirely so the bridge has zero footprint when
;   the user doesn't have SkyrimNet installed.
;
; SCOPE
;   * Short-lived events: player only (scene-context audience model would
;     route NPC tier changes to the wrong scene).
;   * Rendered Markdown bio: any actor (player + NPCs). StorageUtil is
;     per-actor and the prompt reads with the right UUID.
;
; KNOWN LIMITATION
;   * Actor name in rendered Markdown comes from Actor.GetDisplayName(),
;     not SkyrimNet's `decnpc(actorUUID).name`. We lose OmniSight /
;     gender-aware name customization that the template path had. The
;     trade-off is worth it for guaranteed freshness — the customization
;     was only relevant when narrating the bio, not when stating bare facts.
;
; STATE TOUCHED
;   * Soft-detects SkyrimNet.esp via Game.GetModByName.
;   * Calls SkyrimNetApi.RegisterEventSchema once per session.
;   * Calls SkyrimNetApi.RegisterShortLivedEvent on every player tier
;     change (deduped per-preset; SkyrimNet handles TTL).
;   * Writes StorageUtil.SetStringValue(actor, "mtf.bio.rendered", text)
;     on every tier change and on player load-game.
; ══════════════════════════════════════════════════════════════════════════

bool Property _depsResolved Auto Hidden
; NOTE: no _bridgeSetup property. SkyrimNet's RegisterEventSchema state
; lives in C++ memory that resets every game launch. A persistent guard
; would silently lose registration after the first save reload.
; _setupBridge is called from both _tryRegister (first-session path) AND
; MTF_AliasSkyrimNet.OnPlayerLoadGame (every-load path). Re-registering is
; idempotent on SkyrimNet's side.

; StorageUtil key for the pre-rendered Markdown bio block. Per-actor.
; Pulled by the prompt template via
;   {% set s = papyrus_util("GetStringValue", actorUUID, "mtf.bio.rendered", "") %}
; Empty string means "no Magic Tattoos block in the bio for this actor".
string Function _RENDERED_KEY() global
    return "mtf.bio.rendered"
EndFunction

; v0.3.x: external-observer bio variant. Same body as _RENDERED_KEY but
; with the "Active effects in this state:" block replaced by a single
; "Active effects in this state: unknown to observers." line. Used by
; the prompt template when render_mode is external (dialogue_target /
; bio_appearance) — bearer's own first_person modes (thoughts / full /
; transform) keep using _RENDERED_KEY. Lore-consistent: the bearer
; knows what their tattoos do; observers see only the visual.
string Function _RENDERED_EXT_KEY() global
    return "mtf.bio.rendered.external"
EndFunction

; ── Identity ────────────────────────────────────────────────────────────────
string Function GetPluginId()
    return "mtf.skyrimnet"
EndFunction
string Function GetPluginLabel()
    return "SkyrimNet Bridge"
EndFunction

; ── Soft-dep resolution ─────────────────────────────────────────────────────
; _host() + _tryRegister lifted to MTF_Plugin base class. We customise
; _resolveDeps (soft-master probe) and _onRegistered (post-register bridge
; setup) — the base's _tryRegister calls them at the right points.

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

Function _onRegistered()
    _setupBridge()
EndFunction

Function _setupBridge()
    ; Register the event schema and seed the player's rendered bio string.
    ; Idempotent on SkyrimNet's side; safe to call from both _tryRegister
    ; (first-session) and MTF_AliasSkyrimNet.OnPlayerLoadGame (every load).
    ;
    ; CRITICAL: SkyrimNet's API state resets every game launch — no
    ; persistent guard. See module-level comment.
    ;
    ; Listener registration (RegisterForModEvent) is handled by
    ; MTF_AliasSkyrimNet on the host alias. Quest scripts can't call
    ; RegisterForModEvent (the native is on Alias/AMF) and Caprica
    ; forbids non-native scripts from declaring new Event types.
    _registerTattooChangeSchema()
    ; Seed the player's rendered bio. Without this, the bio shows nothing
    ; until the first tier change fires — which means on a fresh load with
    ; no impending mutation, the LLM never sees the tattoos. The rebuild is
    ; cheap (a few StorageUtil reads + string concat) so doing it on every
    ; bridge setup is fine.
    _rebuildRenderedFor(Game.GetPlayer())
    Debug.Trace("MTF.SkyrimNet: bridge ready (schema registered; player bio seeded)")
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
    ; shortLivedEnabled=false (REVERTED in v0.1.24 second pass): empirically
    ; setting this true makes SkyrimNet auto-create a scene-context entry
    ; using the schema description as content, on top of our manual
    ; RegisterShortLivedEvent call — producing two events per transition
    ; (one with our descLine, one with the schema description). The original
    ; dev's comment was right. We keep false and rely on the manual call;
    ; the trade-off is the schema may not appear in SkyrimNet's "Event
    ; Configuration" UI page (it does appear in "Player Reactions
    ; Configuration", which is enough to wire NPC reactions).
    SkyrimNetApi.RegisterEventSchema("mtf_tattoo_change", "Magic Tattoo Change", \
        "Fires when a Magic Tattoos Framework preset transitions between conditional slots (dormant <-> triggered, or condition shifts).", \
        fields, templates, true, 30000, false, false)
EndFunction

; ── Conditions: none ────────────────────────────────────────────────────────
int Function GetConditionCount()
    return 0
EndFunction

; ── Effects: JSON-driven via base class (v0.3.x) ───────────────────────────
; The plugin now ships a catalog at
;   Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.skyrimnet.json
; containing a single "Text" effect with a free-form text param so
; roleplayers can attach custom narrative copy to a tier. The text is
; surfaced verbatim in the rendered Markdown bio (see _resolveParamValueLabel
; and _substDescPlaceholders below) so the LLM reads it on every tier
; transition. No engine-side effect — onActivate/onDeactivate stay base
; no-ops; the visible "effect" IS the bio entry.

; (v0.2.1: plugin-level settings system removed framework-wide — the
; legacy `GetSettingCount() = 0` override is no longer needed because
; the base class doesn't declare the method. Historically this plugin
; would have hosted a "Narrate tattoo changes" toggle, but that ship
; sailed in v0.1.24 in favor of SkyrimNet's per-event-type controls.)

; ── Listener callback (invoked by MTF_AliasSkyrimNet) ──────────────────────
; Called from MTF_AliasSkyrimNet.OnMTFTierChanged. Two effects per call:
;   1. _rebuildRenderedFor(sender) — refresh that actor's Markdown bio
;      string in StorageUtil. ANY actor (player + NPCs). This is the bypass-
;      cache freshness path.
;   2. For player only: fire SkyrimNetApi.RegisterShortLivedEvent so the
;      scene-context picks up the transition with a verb-led sentence.
Function HandleTierChange(string strArg, float numArg, Form sender)
    Actor target = sender as Actor
    if target == None
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
        return
    endif

    ; Always refresh the StorageUtil bio string — that's the bypass-cache
    ; freshness path. ANY actor (player + NPCs).
    _rebuildRenderedFor(target)

    ; Classify the (prev, new) edge.
    string verb = _classifyTransition(prevTier, newTier)
    if verb == ""
        return
    endif

    MTF_MainQuest host = _host()
    string displayName = ""
    if presetName != "" && host != None
        displayName = host.GetPresetDisplayName(presetName)
    endif
    string subject = _subjectFor(displayName)

    ; ── Short-lived scene-context event (any actor, v0.1.24) ──────────────
    ; v0.1.24 widened scope: was player-only on the rationale that NPC events
    ; would route to "the wrong scene". With the schema's shortLivedEnabled
    ; flag now true, SkyrimNet's Event Settings UI exposes Enabled / Allow
    ; NPC Reaction / NPC Reaction Cooldown / Interrupt per event type, and
    ; those gates fire against the sourceActor's vicinity — so passing the
    ; bearer as sourceActor routes correctly whether bearer is player or NPC.
    ;
    ; All gating + throttling for whether NPCs comment lives in SkyrimNet's
    ; UI now. No MTF-side toggle, no MTF-side throttle.
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
; rendered Markdown bio (StorageUtil) when it needs to narrate.
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

; ══════════════════════════════════════════════════════════════════════════
; STORAGEUTIL-BYPASS BIO BUILDERS
;
; All functions below cooperate to produce the "## Magic Tattoos" Markdown
; block that lives in StorageUtil(actor, "mtf.bio.rendered"). The prompt
; template reads it via `papyrus_util("GetStringValue", ...)` with zero
; caching. Empty string = no bio block.
; ══════════════════════════════════════════════════════════════════════════

; Entry point. Composes the Markdown bio block for `a` and writes it to
; StorageUtil. Writes an empty string when nothing is active (template
; gates on `{% if rendered != "" %}` and elides the section).
;
; Performance: per-call cost is dominated by per-effect resolve through
; MTF_Plugin.GetEffectDescription etc., which is cheap in-process. Called
; only on mutations (tier change, load-game seed), never on dialogue
; render, so this can be heavier than the old decorator without affecting
; conversation latency.
Function _rebuildRenderedFor(Actor a) global
    if a == None
        return
    endif
    MTF_MainQuest host = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if host == None
        return
    endif
    ; Two variants: bearer's first_person view (full effects) and external
    ; observer view (effects redacted to "unknown"). Prompt template picks
    ; based on render_mode. See _RENDERED_EXT_KEY docstring.
    string text = _buildRenderedMarkdown(host, a, false)
    StorageUtil.SetStringValue(a, _RENDERED_KEY(), text)
    string textExt = _buildRenderedMarkdown(host, a, true)
    StorageUtil.SetStringValue(a, _RENDERED_EXT_KEY(), textExt)
EndFunction

; Build the full Markdown block. Returns "" when no preset (base or
; stacked) is active on the actor.
;
; externalView=false → bearer's POV (first_person render_modes); effects
; block shows full per-effect bullets.
; externalView=true  → observer POV (dialogue_target / bio_appearance);
; effects block is replaced by a single "unknown to observers" line.
; The rest of the bio (visual / placement / color / pulse / condition)
; is identical — observers can see everything except WHAT the tattoos do.
String Function _buildRenderedMarkdown(MTF_MainQuest host, Actor a, bool externalView) global
    string body = ""
    string actorName = a.GetDisplayName()
    if actorName == ""
        actorName = "The actor"
    endif

    ; Player base preset (MCM-driven). Only exists on the player.
    if a == Game.GetPlayer()
        int baseTier = host.GetCurrentTier()
        if baseTier >= 0
            string part = _renderBasePresetMd(host, baseTier, actorName, externalView)
            if part != ""
                body = body + part
            endif
        endif
    endif

    ; Stacked presets — ANY actor.
    int n = StorageUtil.StringListCount(a, "mtf.presets")
    int i = 0
    while i < n
        string nm = StorageUtil.StringListGet(a, "mtf.presets", i)
        if nm != ""
            int tier = StorageUtil.GetIntValue(a, "mtf.preset." + nm + ".tier", -1)
            if tier >= 0
                string part = _renderStackedPresetMd(host, a, nm, tier, actorName, externalView)
                if part != ""
                    if body != ""
                        body = body + "\n"
                    endif
                    body = body + part
                endif
            endif
        endif
        i += 1
    endwhile

    if body == ""
        return ""
    endif
    return "## Magic Tattoos\n\n" + body
EndFunction

; Player base preset Markdown block. Reads from MainQuest's cond arrays +
; live runtime state.
String Function _renderBasePresetMd(MTF_MainQuest host, int tier, string actorName, bool externalView) global
    string packId = host.ResolveSlotPackId(tier)
    string entryId = host.ResolveSlotEntryId(tier)
    string packLabel = ""
    int pi = host.FindVisualPackIndex(packId)
    if pi >= 0
        packLabel = host.visualPackLabels[pi]
    endif
    string entryLabel = _findEntryLabel(host, packId, entryId)
    string visualDesc = host.GetEntryDescription(packId, entryId)
    string placement = host.GetEntryPlacement(packId, entryId)
    float pulseRate = host.GetCondPulseRate(tier)
    int pulseDepth = host.GetCondPulseDepth(tier)
    string layersMd = _renderBaseLayersMd(host, tier, packId, entryId)
    string effectsMd = _renderBaseEffectsMd(host, tier)
    ; v0.3.2: render ALL conditions configured on the slot (multi-condition
    ; support), joined by the slot's AND/OR operator. Was single-condition.
    string conditionMd = _renderBaseConditionsMd(host, tier)
    return _composePresetMd("", tier, packLabel, entryLabel, visualDesc, placement, pulseRate, pulseDepth, layersMd, effectsMd, conditionMd, actorName, externalView)
EndFunction

; Stacked preset Markdown block. Reads from the preset JSON file directly
; via JsonUtil.
String Function _renderStackedPresetMd(MTF_MainQuest host, Actor a, string presetName, int tier, string actorName, bool externalView) global
    string f = host._presetFile(presetName)
    if f == ""
        return ""
    endif
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
    string placement = host.GetEntryPlacement(packId, entryId)
    float pulseRate = JsonUtil.GetPathFloatValue(f, ".slot[" + tier + "].pulse.rate", 0.0)
    int pulseDepth = JsonUtil.GetPathIntValue(f, ".slot[" + tier + "].pulse.depth", 0)
    string layersMd = _renderStackedLayersMd(host, f, tier, packId, entryId)
    string effectsMd = _renderStackedEffectsMd(host, f, tier)
    string displayName = host.GetPresetDisplayName(presetName)
    ; v0.3.2: render ALL conditions from the slot's .cond.items[] array,
    ; joined by .cond.op (0=AND, 1=OR). Was items[0]-only narration.
    string conditionMd = _renderStackedConditionsMd(host, f, tier)
    return _composePresetMd(displayName, tier, packLabel, entryLabel, visualDesc, placement, pulseRate, pulseDepth, layersMd, effectsMd, conditionMd, actorName, externalView)
EndFunction

; Shared composition for both base and stacked presets. Output mirrors the
; old Inja template's structure:
;
;   **DisplayName** — currently triggered.    (or "— dormant"; omitted if no display name)
;   <Actor> bears <visual_description>.       (fallback: "<actor> bears a <entry> tattoo from the <pack> set")
;   Color:
;   - Layer 1: tint #..., emissive #... (intensity X.X), alpha X%
;   It pulses with light <rate_word> and <depth_word>.
;   Triggered by: **<label>** — <description> (<param>: <value>).
;   Active effects in this state:
;   - **<label>**: <description> (<param>: <value>)
;
; Each subsection elides when its inputs are empty. Returns "" when ALL
; subsections elide (so the caller doesn't emit a phantom blank block).
String Function _composePresetMd(string displayName, int tier, string packLabel, string entryLabel, string visualDesc, string placement, float pulseRate, int pulseDepth, string layersMd, string effectsMd, string conditionMd, string actorName, bool externalView) global
    string md = ""
    ; Header line
    if displayName != ""
        ; `state` is a Papyrus reserved keyword (state blocks); use a
        ; different local name to avoid Caprica's "Expected Identifier
        ; got 'State'" parse error.
        string stateWord = "dormant"
        if tier > 0
            stateWord = "currently triggered"
        endif
        md = md + "**" + displayName + "** — " + stateWord + ".\n"
    endif
    ; Visual / fallback descriptor
    string visualLine = ""
    if visualDesc != ""
        visualLine = actorName + " bears " + visualDesc + "."
    elseif packLabel != "" && entryLabel != ""
        visualLine = actorName + " bears a " + entryLabel + " tattoo from the " + packLabel + " set."
    elseif entryLabel != ""
        visualLine = actorName + " bears a " + entryLabel + " tattoo."
    endif
    if visualLine != ""
        md = md + visualLine + "\n"
    endif
    ; v0.3.x: explicit anatomical placement. Structured so the LLM reliably
    ; knows WHERE the tattoo sits even when visualDesc omits it; near-universal
    ; across content packs (read from the entry's tags.placement).
    if placement != ""
        md = md + "Placement: " + placement + ".\n"
    endif
    ; Color block
    if layersMd != ""
        md = md + "Color:\n" + layersMd
    endif
    ; Pulse sentence
    if pulseRate > 0.0
        md = md + "It pulses with light " + _rateWord(pulseRate) + " and " + _depthWord(pulseDepth) + ".\n"
    endif
    ; Condition predicate
    if conditionMd != ""
        md = md + conditionMd
    endif
    ; Effects block. The bearer's POV shows the full per-effect bullet list;
    ; observer POV gets a single redaction line (effects exist but aren't
    ; visible to onlookers — they can SEE the tattoo, can't tell what it
    ; does). The detection still gates on effectsMd != "" so an actor with
    ; no active effects gets no "unknown" line either.
    if effectsMd != ""
        if externalView
            md = md + "Active effects in this state: unknown to observers.\n"
        else
            md = md + "Active effects in this state:\n" + effectsMd
        endif
    endif
    return md
EndFunction

; Layers block (base preset). One bullet per layer; reads tint/emissive
; from cond* property arrays so MCM slider edits show up here once the
; bridge gets re-poked.
String Function _renderBaseLayersMd(MTF_MainQuest host, int slot, string packId, string entryId) global
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
        ; v0.2.8: route through unified (slot, L) accessors instead of flat lidx.
        int tint = host.GetCondLayerTint(slot, i)
        int emissive = host.GetCondLayerEmissive(slot, i)
        float emMult = host.GetCondLayerEmissiveMult(slot, i)
        int alpha = host.GetCondLayerAlpha(slot, i)
        acc = acc + "- Layer " + (i + 1) + ": tint " + host._intToHex(tint) \
            + ", emissive " + host._intToHex(emissive) + " (intensity " + emMult \
            + "), alpha " + alpha + "%\n"
        i += 1
    endwhile
    return acc
EndFunction

; Layers block (stacked preset). Reads from the preset JSON file — colors
; are stored as hex strings, copied verbatim.
String Function _renderStackedLayersMd(MTF_MainQuest host, string presetFile, int slot, string packId, string entryId) global
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
        acc = acc + "- Layer " + (i + 1) + ": tint " + tint \
            + ", emissive " + emissive + " (intensity " + emMult \
            + "), alpha " + alpha + "%\n"
        i += 1
    endwhile
    return acc
EndFunction

; Effects block (base). One bullet per active effect in the slot.
String Function _renderBaseEffectsMd(MTF_MainQuest host, int slot) global
    int maxE = MTF_MainQuest.MAX_EFFECTS_PER_SLOT()
    string acc = ""
    int e = 0
    while e < maxE
        string key = host._readFxKey(slot, e, false)
        if key != ""
            int    p1  = host._readFxParam(slot, e, false)
            int    p2  = host._readFxParam2(slot, e, false)
            string p1s = host._readFxParamNStr(slot, e, 1, false)   ; v0.2.9
            string p2s = host._readFxParamNStr(slot, e, 2, false)
            string line = _renderOneEffectMd(host, key, p1s, p1, p2s, p2)
            if line != ""
                acc = acc + line
            endif
        endif
        e += 1
    endwhile
    return acc
EndFunction

; Effects block (stacked).
String Function _renderStackedEffectsMd(MTF_MainQuest host, string presetFile, int slot) global
    int n = JsonUtil.PathCount(presetFile, ".slot[" + slot + "].effect")
    if n <= 0
        return ""
    endif
    string acc = ""
    int i = 0
    while i < n
        string base = ".slot[" + slot + "].effect[" + i + "]"
        string key = JsonUtil.GetPathStringValue(presetFile, base + ".key", "")
        if key != ""
            ; v0.2.9: read both shapes; resolver dispatches via catalog probe.
            int    p1  = JsonUtil.GetPathIntValue(presetFile,    base + ".param1", 0)
            int    p2  = JsonUtil.GetPathIntValue(presetFile,    base + ".param2", 0)
            string p1s = JsonUtil.GetPathStringValue(presetFile, base + ".param1", "")
            string p2s = JsonUtil.GetPathStringValue(presetFile, base + ".param2", "")
            string line = _renderOneEffectMd(host, key, p1s, p1, p2s, p2)
            if line != ""
                acc = acc + line
            endif
        endif
        i += 1
    endwhile
    return acc
EndFunction

; Single effect bullet. Output:
;   - **<label>**: <description with {param1}/{param2} substituted>
;
; Param values appear ONLY via {param1}/{param2} placeholder substitution
; in the plugin-authored description. The previous trailing
;   "(<paramLabel>: <valueLabel>, <param2Label>: <value2Label>)"
; was dropped because every parameterised effect description in the MTF
; ecosystem now references its values through placeholders, making the
; parenthetical pure duplication. Plugin authors who want a value visible
; must reference it in the description — empty placeholder = author chose
; not to expose that param to the LLM.
String Function _renderOneEffectMd(MTF_MainQuest host, string key, string p1s, int p1, string p2s, int p2) global
    ; v0.2.9: p1s/p2s carry the string-id form for menu params; p1/p2 carry
    ; the int form for sliders. Resolver dispatches via catalog probe.
    MTF_Plugin p = host.ResolvePluginByKey(key)
    string label = ""
    string desc = ""
    string p1Val = ""
    string p2Val = ""
    bool p1Declared = false
    bool p2Declared = false
    if p != None
        int itemIdx = host._effectIdxFor(p, host._keyItemId(key))
        if itemIdx >= 0
            label = p.GetEffectLabel(itemIdx)
            desc = p.GetEffectDescription(itemIdx)
            ; Capture resolved value labels for description {param1}/{param2}
            ; substitution. Empty label = effect doesn't use that param slot.
            ; v0.3.x: track declared-ness separately so text params with empty
            ; user copy still substitute "{paramN}" -> "" (not left literal).
            if p.GetEffectParamLabel(itemIdx, 1) != ""
                p1Declared = true
                p1Val = _resolveParamValueLabel(p, itemIdx, 1, p1s, p1)
            endif
            if p.GetEffectParamLabel(itemIdx, 2) != ""
                p2Declared = true
                p2Val = _resolveParamValueLabel(p, itemIdx, 2, p2s, p2)
            endif
        endif
    endif
    desc = _substDescPlaceholders(desc, p1Declared, p1Val, p2Declared, p2Val)
    if label == "" && desc == ""
        ; Unknown plugin / removed effect — emit a debug-friendly stub so
        ; the user can see the orphan key in the bio.
        return "- (unknown effect: " + key + ")\n"
    endif
    string line = "- **" + label + "**"
    if desc != ""
        line = line + ": " + desc
    endif
    return line + "\n"
EndFunction

; ── Condition predicate Markdown (v0.3.2: multi-condition) ──────────────────
; A slot can carry up to MAX_CONDS_PER_SLOT conditions combined by an AND/OR
; operator. These builders render EVERY configured condition, not just the
; first. Output:
;   single:  "Triggered by: **<label>** — <desc>.\n"
;   multi:   "Triggered when all of: **<L1>** — <d1>; **<L2>** — <d2>.\n"
;            (op 0 = AND -> "all of"; op 1 = OR -> "any of")
; Returns "" when the slot has no resolvable condition.

; BASE (MCM) preset: reads the slot's cond.* StorageUtil accessors via the
; indexed *At APIs. GetCondCount reports the effective condition count
; (legacy single-condition slots report 1).
String Function _renderBaseConditionsMd(MTF_MainQuest host, int slot) global
    int n = host.GetCondCount(slot)
    if n < 1
        return ""
    endif
    int op = host.GetCondOp(slot)
    string acc = ""
    int rendered = 0
    int j = 0
    while j < n
        string key = host.GetCondPluginIdAt(slot, j)
        if key != ""
            string clause = _renderConditionClause(host, key, \
                host.GetCondParamStrAt(slot, j), host.GetCondParamAt(slot, j), \
                host.GetCondParam2StrAt(slot, j), host.GetCondParam2At(slot, j))
            if clause != ""
                if rendered > 0
                    acc = acc + "; "
                endif
                acc = acc + clause
                rendered += 1
            endif
        endif
        j += 1
    endwhile
    return _finishConditionLine(acc, rendered, op)
EndFunction

; STACKED preset: reads the preset JSON's .cond.items[] array directly. op at
; .cond.op (default 0 = AND). Mirrors _slotCondsMetJson's traversal so the
; narrated conditions exactly match what the evaluator checks.
String Function _renderStackedConditionsMd(MTF_MainQuest host, string f, int slot) global
    string sp = ".slot[" + slot + "]"
    int n = JsonUtil.PathCount(f, sp + ".cond.items")
    if n < 1
        return ""
    endif
    int op = JsonUtil.GetPathIntValue(f, sp + ".cond.op", 0)
    string acc = ""
    int rendered = 0
    int j = 0
    while j < n
        string ip = sp + ".cond.items[" + j + "]"
        string key = JsonUtil.GetPathStringValue(f, ip + ".pluginid", "")
        if key != ""
            int    p1  = JsonUtil.GetPathIntValue(f,    ip + ".param",  0)
            int    p2  = JsonUtil.GetPathIntValue(f,    ip + ".param2", 0)
            string p1s = JsonUtil.GetPathStringValue(f, ip + ".param",  "")
            string p2s = JsonUtil.GetPathStringValue(f, ip + ".param2", "")
            string clause = _renderConditionClause(host, key, p1s, p1, p2s, p2)
            if clause != ""
                if rendered > 0
                    acc = acc + "; "
                endif
                acc = acc + clause
                rendered += 1
            endif
        endif
        j += 1
    endwhile
    return _finishConditionLine(acc, rendered, op)
EndFunction

; Frame accumulated clause(s) into the final line. One clause keeps the bare
; "Triggered by:" phrasing; two or more get an "all of"/"any of" lead so the
; LLM understands the combine semantics. Exactly ONE trailing period is added
; here — the per-clause builder must NOT end clauses with a period (this is
; what fixes the historic ".." double-period when a condition description
; ended in its own full stop).
String Function _finishConditionLine(string acc, int rendered, int op) global
    if rendered < 1 || acc == ""
        return ""
    endif
    if rendered == 1
        return "Triggered by: " + acc + ".\n"
    endif
    string lead = "all of"
    if op == 1
        lead = "any of"
    endif
    return "Triggered when " + lead + ": " + acc + ".\n"
EndFunction

; One condition clause: "**<label>** — <desc with {paramN} substituted>".
; Returns "" when the plugin/condition can't be resolved. NO prefix and NO
; trailing punctuation — the caller frames the line and adds the period.
;
; Same parenthetical-drop rationale as _renderOneEffectMd: every parameterised
; condition description references its values via {param1}/{param2}, so a
; trailing "(<label>: <value>)" would be pure duplication.
String Function _renderConditionClause(MTF_MainQuest host, string key, string p1s, int p1, string p2s, int p2) global
    if key == ""
        return ""
    endif
    MTF_Plugin p = host.ResolvePluginByKey(key)
    string label = ""
    string desc = ""
    string p1Val = ""
    string p2Val = ""
    bool p1Declared = false
    bool p2Declared = false
    if p != None
        int itemIdx = host._condIdxFor(p, host._keyItemId(key))
        if itemIdx >= 0
            label = p.GetConditionLabel(itemIdx)
            desc = p.GetConditionDescription(itemIdx)
            if p.GetConditionParamLabel(itemIdx) != ""
                p1Declared = true
                p1Val = _resolveConditionParamValueLabel(p, itemIdx, false, p1s, p1)
            endif
            if p.GetConditionParam2Label(itemIdx) != ""
                p2Declared = true
                p2Val = _resolveConditionParamValueLabel(p, itemIdx, true, p2s, p2)
            endif
        endif
    endif
    desc = _substDescPlaceholders(desc, p1Declared, p1Val, p2Declared, p2Val)
    if label == "" && desc == ""
        return ""
    endif
    string clause = "**" + label + "**"
    if desc != ""
        clause = clause + " — " + desc
    endif
    return clause
EndFunction

; ── Shared utility helpers ─────────────────────────────────────────────────

; Pulse rate bucket. Input is Hz (pulses per second).
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

; Pulse depth bucket. Input is 0-100%.
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

; Pack-entry label lookup. Linear scan over pack entries; small N (typically
; <20 per pack) so cheaper than building a lookup table.
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

; Resolve a param value to its display label. Dropdown params resolve to
; the matching option's label; numeric params apply the plugin's format
; string ("{0}", "{0}%", "{0}s"). Off-list values fall back to "Custom: N".
; v0.2.1: n is the param index (1..5) under the uniform paramN scheme;
; replaced the old bool isParam2 (which only addressed param1 vs param2).
; v0.2.9: menu params dispatch on id string; sliders on int. Caller passes
; both — the catalog menu count tells us which to use. `sId` empty + menu
; present = unset → return "(unset)".
String Function _resolveParamValueLabel(MTF_Plugin p, int itemIdx, int n, string sId, int value) global
    ; v0.3.x: text-param branch FIRST — raw user copy passes through verbatim.
    ; Empty text is legitimate (the user simply hasn't filled it in yet); the
    ; bio template gets an empty substitution rather than "(unset)" so the
    ; effect bullet doesn't leak "(unset)" into the LLM prompt. The
    ; declared-vs-empty distinction is handled by _renderOneEffectMd which
    ; substitutes unconditionally for declared params (see callers).
    if p.GetEffectParamIsText(itemIdx, n)
        return sId
    endif
    int optCount = p.GetEffectParamMenuOptionCount(itemIdx, n)
    if optCount > 0
        if sId == ""
            return "(unset)"
        endif
        int oi = 0
        while oi < optCount
            string ov = p.GetEffectParamMenuOptionId(itemIdx, n, oi)
            if ov == sId
                return p.GetEffectParamMenuOptionLabel(itemIdx, n, oi)
            endif
            oi += 1
        endwhile
        return "Custom: " + sId
    endif
    string fmt = p.GetEffectParamFormat(itemIdx, n)
    if fmt == ""
        fmt = "{0}"
    endif
    return _formatNum(fmt, value)
EndFunction

; Condition-side mirror of _resolveParamValueLabel.
String Function _resolveConditionParamValueLabel(MTF_Plugin p, int itemIdx, bool isParam2, string sId, int value) global
    int optCount = 0
    if isParam2
        optCount = p.GetConditionParam2MenuOptionCount(itemIdx)
    else
        optCount = p.GetConditionParamMenuOptionCount(itemIdx)
    endif
    if optCount > 0
        if sId == ""
            return "(unset)"
        endif
        int oi = 0
        while oi < optCount
            string ov = ""
            if isParam2
                ov = p.GetConditionParam2MenuOptionId(itemIdx, oi)
            else
                ov = p.GetConditionParamMenuOptionId(itemIdx, oi)
            endif
            if ov == sId
                if isParam2
                    return p.GetConditionParam2MenuOptionLabel(itemIdx, oi)
                else
                    return p.GetConditionParamMenuOptionLabel(itemIdx, oi)
                endif
            endif
            oi += 1
        endwhile
        return "Custom: " + sId
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

; Apply a printf-ish format string ("{0}", "{0}%", "Heartbeat: {0}/min") to
; a numeric value.
;
; The PapyrusUtil StringUtil.Substring(s, startIndex, howManyChars=0) trap:
; passing howManyChars=0 means "to end of string", NOT "zero chars". So
; the naive splitter `Substring(fmt, 0, sep)` returns the full format
; whenever sep==0 (and our format strings always have "{0}" at position
; 0: "{0}", "{0}%", "{0}s"). Symptom: descriptions like
;   "drops below {param1}%."
; render as
;   "drops below {0}50%."
; because the broken value_label "{0}50%" gets substituted in for "{param1}".
;
; Guarding with `if sep > 0` before the head Substring is the fix.
String Function _formatNum(string fmt, int value) global
    if fmt == ""
        return value as string
    endif
    int sep = StringUtil.Find(fmt, "{0}")
    if sep < 0
        return fmt
    endif
    string head = ""
    if sep > 0
        head = StringUtil.Substring(fmt, 0, sep)
    endif
    string tail = StringUtil.Substring(fmt, sep + 3)
    return head + (value as string) + tail
EndFunction

; Substitute `{param1}` / `{param2}` placeholders in `desc` with the
; already-resolved value labels. Substitution is gated on DECLARED-ness,
; not on value-non-empty:
;   - Param declared, value "" -> substitute "" (text params with empty
;     user copy elide cleanly instead of leaving "{param1}" literal).
;   - Param undeclared (label "")            -> leave placeholder alone
;     so the author can see they referenced an unused slot.
String Function _substDescPlaceholders(string desc, bool p1Declared, string p1Val, bool p2Declared, string p2Val) global
    if desc == ""
        return desc
    endif
    if p1Declared
        desc = _replaceAll(desc, "{param1}", p1Val)
    endif
    if p2Declared
        desc = _replaceAll(desc, "{param2}", p2Val)
    endif
    return desc
EndFunction

; Replace all non-overlapping occurrences of `needle` with `repl` in `s`.
; Papyrus has no native string Replace — StringUtil only does Find /
; Substring.
;
; Guards against the PapyrusUtil StringUtil.Substring(s, 0, 0) trap (see
; _formatNum docstring): when the needle is at position 0 of the
; remaining string, the naive `Substring(remaining, 0, idx)` returns the
; full string instead of "" because howManyChars=0 means "to end". This
; broke `{param1}` substitution whenever the description STARTED with
; the placeholder.
String Function _replaceAll(string s, string needle, string repl) global
    if s == "" || needle == ""
        return s
    endif
    int nl = StringUtil.GetLength(needle)
    string remaining = s
    string out = ""
    int idx = StringUtil.Find(remaining, needle)
    while idx >= 0
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

; JSON string escaper. Used for the short-lived event's structured `data`
; payload. Handles ", \, \n, \t. Caprica REJECTS \r in source literals so
; we don't escape carriage returns — author content shouldn't contain
; them on Windows save files anyway.
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
