Scriptname MTF_Plugin_SlaveTats extends MTF_Plugin
{Universal SlaveTats bridge: ghost-writes MTF tattoos into JFormDB.SlaveTats.applied so polling consumers (has_tattoo/query_applied_tattoos) see them. See onActivate body for the safety rationale.}

; ══════════════════════════════════════════════════════════════════════════
; SAFETY RATIONALE (verified by reading SlaveTats.psc):
;
; 1. query_applied_tattoos / has_tattoo / has_applied_tattoos_with_attribute
;    read .SlaveTats.applied from JFormDB directly. They don't touch
;    overlays. Texture-field format is irrelevant — they just return what's
;    in the JMap.
; 2. synchronize_tattoos (the only function that re-renders entries) is
;    guarded by ".SlaveTats.updated == 1" early-return. We never flip
;    "updated". SlaveTats flips it itself from add_tattoo / remove_tattoos
;    / mark_actor.
; 3. If a consumer DOES flip "updated" and synchronize runs, it first calls
;    external_slots() per area. external_slots walks NiOverride and marks
;    any slot whose live overlay path doesn't start with
;    "Actors\Character\slavetats\" as external. synchronize then skips
;    external slots in both apply pass (SlaveTats.psc ~L1610/1635/1660/1685)
;    and the empty-slot-clear pass (~L1702/1712/1722/1732). MTF paints
;    first, so non-slavetats slots are automatically external and SlaveTats
;    refuses to write or clear them.
; 4. For slavetats-rooted packs (LewdMarks SlaveTats variant), MTF's live
;    path IS under the slavetats prefix → external_slots does NOT mark it
;    external. If synchronize runs, we stay safe by storing a
;    prefix-stripped path so SlaveTats's "PREFIX() + entry.texture"
;    reconstructs the same path MTF already painted (last-writer-wins, same
;    pixels, invisible).
;
; HAZARD WE MITIGATE: upgrade_tattoos (SlaveTats.psc ~L1167) REPLACES
; .SlaveTats.applied with an empty JArray when actor's .SlaveTats.version
; is "". upgrade_tattoos is called eagerly from add_and_get_tattoo /
; remove_tattoos / synchronize_tattoos. So any consumer's first mutation
; on a never-touched-by-SlaveTats actor wipes our ghosts. Fix:
; _ensureSlaveTatsVersion pre-sets .SlaveTats.version = "1.0.0" (matches
; SlaveTats VERSION()) on first activate. upgrade_tattoos then matches and
; returns fast.
;
; STORED TEXTURE FIELD:
;   * Slavetats-rooted packs: prefix-stripped path.
;   * Other packs: full path verbatim.
;
; LOCK PROTECTION:
; Ghost entries carry locked=1. For slavetats-rooted packs the slot isn't
; external (live path matches the prefix), so SlaveTats MCM would otherwise
; treat the ghost as a normal editable SlaveTats tattoo — letting the user
; swap pattern, change to "[No Tattoo]", etc. SlaveTats's lock check
; (_remove_tattoos and add_tattoo's pre-remove) refuses those operations
; with the "tattoo resists" notification. Non-slavetats slots are already
; protected by external_slots; the lock is just defense in depth there.
;
; STATE TOUCHED PER ACTOR:
;   * .SlaveTats.version = "1.0.0" (set once, never read by us again)
;   * .SlaveTats.applied JArray (we add/remove our own section="MTF" entries)
;   * .SlaveTats.updated NEVER touched.
;
; KNOWN LIMITATION — pack swap while slot active.
; If the user changes the slot's pack/entry in MCM while the slot is
; actively painting, no MTF onActivate/onDeactivate fires for the swap,
; so cleanup doesn't run. The stale ghost persists until the next tier
; change. Acceptable for the polling-consumer use case — at worst a
; polling mod sees a slightly outdated tattoo name for one cycle.
;
; REQUIREMENTS: JContainers SE + SlaveTats SE (or compatible fork). Both
; detected at runtime — soft-master pattern (like FMR / BFNG).
; ══════════════════════════════════════════════════════════════════════════

bool Property _depsResolved = false Auto Hidden

; ── Identity ────────────────────────────────────────────────────────────────
string Function GetPluginId()
    return "mtf.slavetats"
EndFunction

; ── Soft-dep resolution ─────────────────────────────────────────────────────
; _host() lifted to MTF_Plugin base class.

bool Function _resolveDeps()
    if _depsResolved
        return true
    endif
    ; JContainers must be installed (DLL — no plugin-master probe, so we
    ; call APIVersion() and trust the return).
    if JContainers.APIVersion() < 1
        return false
    endif
    ; SlaveTats.esp must be loaded — needed because the consumers we're
    ; bridging to are SlaveTats-aware mods that won't function without it.
    if Game.GetModByName("SlaveTats.esp") == 255
        return false
    endif
    _depsResolved = true
    return true
EndFunction

; _tryRegister lifted to MTF_Plugin base class. _resolveDeps above is the
; only thing this plugin customises.

; ── Helpers ─────────────────────────────────────────────────────────────────
string Function _areaToString(int areaIdx)
    if areaIdx == 1
        return "Face"
    elseif areaIdx == 2
        return "Hands"
    elseif areaIdx == 3
        return "Feet"
    endif
    return "Body"
EndFunction

string Function _buildName(string packId, string entryId)
    if packId == "" && entryId == ""
        return ""
    endif
    return packId + ":" + entryId
EndFunction

; SlaveTats's PREFIX() is "Actors\Character\slavetats\" — capital A/C,
; lowercase rest. Our catalog JSONs use all-lowercase "actors\character\
; slavetats\". Both refer to the same Windows path (case-insensitive). We
; detect the prefix in either casing and strip 27 characters
; ("actors\character\slavetats\" is 27 chars).
bool Function _isSlaveTatsTexture(string texture)
    if texture == ""
        return false
    endif
    if StringUtil.GetLength(texture) < 27
        return false
    endif
    string head = StringUtil.SubString(texture, 0, 27)
    return head == "actors\\character\\slavetats\\" || head == "Actors\\Character\\slavetats\\"
EndFunction

string Function _stripSlaveTatsPrefix(string texture)
    return StringUtil.SubString(texture, 27)
EndFunction

; Sweep all MTF ghost entries on (area, [baseSlot, baseSlot+layerSpan)).
; Caller passes layerSpan = MAX_LAYERS_PER_SLOT() so we catch every layer
; the bridge might have ghosted on this base, including stale entries from
; a prior larger-layer-count pack binding. Drops the earlier name-keyed
; remove approach.
;
; Does NOT flip ".SlaveTats.updated" — see file docstring.
Function _ghostSweepRange(Actor target, string area, int baseSlot, int layerSpan)
    int applied = JFormDB.getObj(target, ".SlaveTats.applied")
    if applied == 0
        return
    endif
    int hi = baseSlot + layerSpan
    int i = JArray.count(applied)
    while i > 0
        i -= 1
        int entry = JArray.getObj(applied, i)
        if entry != 0
            if JMap.getStr(entry, "section") == "MTF"
                int entrySlot = JMap.getInt(entry, "slot")
                string entryArea = JMap.getStr(entry, "area")
                ; Three match cases:
                ;   1. Our active range — area matches and slot is within
                ;      [baseSlot, baseSlot+layerSpan).
                ;   2. ANY area with slot==99 — leftover from a discarded
                ;      earlier revision that used PHANTOM_SLOT=99 hoping
                ;      NiOverride would no-op on a nonexistent node. That
                ;      didn't actually prevent the render, so these entries
                ;      can paint missing-texture (purple/blue/white) on
                ;      whatever overlay slot they land on. Sweep them across
                ;      ALL areas — the user might not activate the affected
                ;      area for a long time and the leak would persist.
                if (entryArea == area && entrySlot >= baseSlot && entrySlot < hi) || entrySlot == 99
                    JArray.eraseIndex(applied, i)
                endif
            endif
        endif
    endwhile
EndFunction

; Pre-set ".SlaveTats.version" so upgrade_tattoos() returns fast without
; replacing .SlaveTats.applied with an empty JArray. VERSION() in
; SlaveTats.psc is hardcoded to "1.0.0" and the wipe-and-import branch
; only fires when actor_version == "" (line ~1167 of SlaveTats.psc).
; Idempotent; safe to call every onActivate.
Function _ensureSlaveTatsVersion(Actor target)
    if JFormDB.getStr(target, ".SlaveTats.version") == ""
        JFormDB.setStr(target, ".SlaveTats.version", "1.0.0")
    endif
EndFunction

; ── Lifecycle ───────────────────────────────────────────────────────────────
; v0.2.10: dispatch context (slot/effectIdx/useScratch/baseSlot/area) comes
; in as explicit params — see MTF_Plugin.psc entry-point docstring for the
; race rationale.
Function onActivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if eid != "slavetats.mirror" || target == None
        return
    endif
    if !_resolveDeps()
        return
    endif
    MTF_MainQuest h = _host()
    if h == None || slot < 0
        return
    endif
    string packId = h.ResolveSlotPackId(slot)
    string entryId = h.ResolveSlotEntryId(slot)
    string name = _buildName(packId, entryId)
    if name == ""
        ; No texture bound to this slot (effects-only slot). Nothing to mirror.
        return
    endif
    string areaStr = _areaToString(area)
    int layerN = h.GetEntryLayerCount(packId, entryId)
    int sweepSpan = MTF_MainQuest.MAX_LAYERS_PER_SLOT()

    Debug.Trace("MTF.STB onActivate: slot=" + slot + " area=" + areaStr + " baseSlot=" + baseSlot + " packId=" + packId + " entryId=" + entryId + " layerN=" + layerN)

    ; Pre-clean: evict any prior MTF entries across the full possible layer
    ; range. Wider than this activation's layerN so we also catch stale
    ; ghosts from a previously bound larger-layer-count pack.
    _ghostSweepRange(target, areaStr, baseSlot, sweepSpan)

    ; Block upgrade_tattoos from wiping .SlaveTats.applied on first
    ; consumer touch. Must run BEFORE the JArray.addObj below — otherwise
    ; a concurrent third-party add_tattoo can interleave and lose our
    ; ghost in the upgrade-wipe path.
    _ensureSlaveTatsVersion(target)

    int applied = JFormDB.getObj(target, ".SlaveTats.applied")
    if applied == 0
        applied = JValue.addToPool(JArray.object(), "MTFSlaveTatsBridge")
        JFormDB.setObj(target, ".SlaveTats.applied", applied)
    endif

    ; Write one ghost per non-empty layer. MTF's visual.draw paints each
    ; layer to baseSlot+layer, so the SlaveTats MCM display lines up with
    ; the actual painted overlay slots. Polling consumers calling
    ; get_applied_tattoo_in_slot per slot see ALL of MTF's painted layers
    ; as tattoos (one per slot) rather than just the base.
    int layer = 0
    while layer < layerN
        string rawLayerTex = h.GetEntryLayerTexture(packId, entryId, layer)
        if rawLayerTex != ""
            ; Choose stored texture field per pack root. See file header
            ; SAFETY RATIONALE for why both formats are safe.
            string storedTexture = rawLayerTex
            bool isST = _isSlaveTatsTexture(rawLayerTex)
            if isST
                storedTexture = _stripSlaveTatsPrefix(rawLayerTex)
            endif
            int targetSlot = baseSlot + layer

            ; Build the per-layer tattoo JMap.
            int tattoo = JValue.addToPool(JMap.object(), "MTFSlaveTatsBridge")
            JMap.setStr(tattoo, "section", "MTF")
            JMap.setStr(tattoo, "name", name)
            JMap.setStr(tattoo, "area", areaStr)
            JMap.setStr(tattoo, "texture", storedTexture)
            JMap.setInt(tattoo, "slot", targetSlot)
            JMap.setInt(tattoo, "color", 0xFFFFFF)
            JMap.setInt(tattoo, "glow", 0x000000)
            ; locked=1 blocks edits from SlaveTats's own MCM. See header
            ; LOCK PROTECTION section for full rationale.
            JMap.setInt(tattoo, "locked", 1)

            JArray.addObj(applied, tattoo)

            Debug.Trace("MTF.STB GHOSTED: name=" + name + " area=" + areaStr + " slot=" + targetSlot + " layer=" + layer + " texture=" + storedTexture + " isST=" + isST)
        endif
        layer += 1
    endwhile

    JValue.cleanPool("MTFSlaveTatsBridge")
EndFunction

Function onDeactivate(Actor target, int param, int param2, string eid, int slot, int effectIdx, bool useScratch, int baseSlot, int area, string presetName)
    if eid != "slavetats.mirror" || target == None
        return
    endif
    if !_resolveDeps()
        return
    endif
    if slot < 0
        return
    endif
    string areaStr = _areaToString(area)
    int sweepSpan = MTF_MainQuest.MAX_LAYERS_PER_SLOT()
    Debug.Trace("MTF.STB onDeactivate: slot=" + slot + " area=" + areaStr + " baseSlot=" + baseSlot + " span=" + sweepSpan)
    ; Sweep the full layer span — covers every per-layer ghost onActivate
    ; wrote regardless of the current pack's layer count.
    _ghostSweepRange(target, areaStr, baseSlot, sweepSpan)
EndFunction
