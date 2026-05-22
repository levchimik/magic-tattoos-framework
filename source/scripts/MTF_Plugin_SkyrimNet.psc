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
bool Property _bridgeSetup Auto Hidden

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
    if _bridgeSetup
        return
    endif
    ; Register the decorator with SkyrimNet. Decorator function must be a
    ; `global` function on this script (per SkyrimNet's contract — see
    ; skynet_ExampleScript.psc reference). Idempotent on SkyrimNet's side
    ; but we guard with _bridgeSetup anyway.
    ;
    ; Listener registration (RegisterForModEvent) is handled by
    ; MTF_AliasSkyrimNet on the host alias — Quest scripts can't call
    ; RegisterForModEvent (the native is on Alias/AMF) and Caprica
    ; forbids non-native scripts from declaring new Event types.
    SkyrimNetApi.RegisterDecorator("mtf_active_tattoos", "MTF_Plugin_SkyrimNet", "MTF_ActiveTattoosDecorator")
    _bridgeSetup = true
    Debug.Trace("MTF.SkyrimNet: bridge ready (decorator registered; alias hosts listener)")
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
Function HandleTierChange(string strArg, float numArg, Form sender)
    ; strArg = "<scope>|<presetName>|<prevTier>|<newTier>"
    ; numArg = newTier as float
    ; sender = the actor (PlayerRef or NPC)
    Actor target = sender as Actor
    if target == None
        return
    endif
    ; v0.1.20: player-only. NPC preset narration deferred — SkyrimNet's
    ; scene-context routing is player-centric and per-NPC events would
    ; pollute the wrong audience.
    if target != Game.GetPlayer()
        return
    endif
    int newTier = numArg as int
    string sceneProse = MTF_BuildTierProse(target, newTier)
    if sceneProse == ""
        ; newTier < 0 (no slot winning) is normal — the scene-context
        ; entry's natural TTL expiration cleans up the prior tier's
        ; line. Pushing an empty event would clear it immediately,
        ; which is fine but loud; let TTL do it instead.
        return
    endif
    ; Stable eventId across all tier changes — dedupe replaces the prior
    ; line atomically. 30s TTL covers one slow MTF eval cycle + ample
    ; LLM round-trip.
    SkyrimNetApi.RegisterShortLivedEvent( \
        "mtf_tattoo_state", \
        "mtf_tattoo_change", \
        sceneProse, \
        "tier=" + newTier, \
        30000, \
        target, \
        None \
    )
EndFunction

; ── Decorator (called by SkyrimNet prompt engine) ──────────────────────────
; SkyrimNet calls this `global` function whenever a prompt template
; references `{{mtf_active_tattoos(actorUUID)}}`. Returning "" is a clean
; "no tattoos active" — the prompt's Inja template can guard with
; `{% if mtf_active_tattoos(actorUUID) %} … {% endif %}`.
String Function MTF_ActiveTattoosDecorator(string decoratorId, Actor akActor) global
    if akActor == None
        return ""
    endif
    ; v0.1.20: player only (NPC presets deferred). Cheap early-out before
    ; the GetFormFromFile call.
    if akActor != Game.GetPlayer()
        return ""
    endif
    MTF_MainQuest host = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if host == None
        return ""
    endif
    int tier = host.GetCurrentTier()
    if tier < 0
        return ""
    endif
    return MTF_BuildTierProse(akActor, tier)
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
