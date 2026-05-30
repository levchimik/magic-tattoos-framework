scriptname MTF_MCMQuest extends SKI_ConfigBase

import Debug

; ── Runtime ───────────────────────────────────────────────────────────────────
int selectedCondition = 0

MTF_MainQuest Property MainQuest Auto

; ── Versioning ────────────────────────────────────────────────────────────────
int Function GetVersion()
    return 23
EndFunction

string Function _slotLabel(int idx)
    ; v0.2.9: user-authored slot names (slot 0 included). Empty fallback = the
    ; canonical "Default" / "Condition N" labels. Defensive None-guard on
    ; MainQuest so this is safe to call before _ensureMainQuest.
    if MainQuest != None
        string custom = MainQuest.GetCondName(idx)
        if custom != ""
            return custom
        endif
    endif
    if idx == 0
        return "Default"
    endif
    return "Condition " + idx
endFunction

string Function _condTypeLabel(string key)
    if key == "" || MainQuest == None
        return "Not set"
    endif
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return "Unknown (" + key + ")"
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return "Unknown (" + key + ")"
    endif
    string pl = p.GetPluginLabel()
    string il = p.GetConditionLabel(itemIdx)
    if pl == ""
        return il
    endif
    return pl + " — " + il
endFunction

event OnConfigInit()
    ModName = "Magic Tattoos Framework"
    Pages = new String[3]
    Pages[0] = "General"
    Pages[1] = "Preset editor"
    Pages[2] = "Plugins"
    _ensureMainQuest()
endEvent

function _ensureMainQuest()
    if MainQuest == None
        Quest q = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as Quest
        MainQuest = q as MTF_MainQuest
    endif
    if MainQuest != None
        MainQuest.EnsureArrays()
    endif
endFunction

event OnVersionUpdate(int Version)
    if MainQuest == None
        return
    endif
    ; SkyUI's CurrentVersion isn't persisting reliably in this install, so
    ; OnVersionUpdate would fire on every page reset and re-run the wipe
    ; below. Guard with a persistent counter on MainQuest (which IS persistent
    ; via StartGameEnabled).
    ;
    ; v0.0.27 collapsed the 11-block pre-release migration ladder into a
    ; single fresh-init wipe. v0.0.29 bumped to ml=19 so the Pages array gets
    ; rewritten (Presets folded into General). Anyone upgrading from an older
    ; pre-release (ml<19) gets all arrays reallocated and all defaults
    ; applied. Once we ship, the next migration must be a non-destructive
    ; ml<20 block added below this one.
    int ml = MainQuest._migrationLevel
    if ml >= 39
        return
    endif
    ; ml=39 (v0.2.1): Subjects MCM page removed. Existing saves still have
    ; a 4-element Pages array with "Subjects" at index 2 — rewrite to the
    ; 3-page layout so the dead tab disappears. mtf.tracked FormList is
    ; preserved (used by NPC dispatch + lifecycle audit); only the UI
    ; surface is gone. Tracked-actor cleanup is now Apply-Tattoo-spell only.
    if ml >= 38
        Pages = new String[3]
        Pages[0] = "General"
        Pages[1] = "Preset editor"
        Pages[2] = "Plugins"
        MainQuest._migrationLevel = 39
        return
    endif
    ; ml=38: backend for IsItemEnabled / SetItemEnabled moved from the Auto
    ; Hidden `disabledItems[]` array Property to a StorageUtil StringList at
    ; `mtf.disabled`. The Property suffered the indexed-write transient-copy
    ; bug, so toggles set via the MCM never persisted to the cosave — every
    ; re-open re-read the empty initial state. Copy any surviving entries
    ; from the Property into the StringList. The Property itself stays in
    ; cosave (harmless; new code never reads it).
    if ml >= 37
        if MainQuest.disabledItems != None
            int di = 0
            while di < MainQuest.disabledItems.Length
                string dk = MainQuest.disabledItems[di]
                if dk != ""
                    if StorageUtil.StringListFind(MainQuest, "mtf.disabled", dk) < 0
                        StorageUtil.StringListAdd(MainQuest, "mtf.disabled", dk, false)
                    endif
                endif
                di += 1
            endwhile
        endif
        MainQuest._migrationLevel = 38
        return
    endif
    ; ml=37: "Menu Options" page removed. Per-item enable/disable was retired
    ; in favour of per-plugin toggles on the Plugins page. Rewrite the Pages
    ; array so upgraders drop the dead 5th page; the per-item disabledItems[]
    ; entries are left in cosave — harmless, they just never match anything
    ; the new code checks. (Plugin-level disables use a "plugin:<pid>" key in
    ; the same array, separate keyspace.)
    if ml >= 36
        ; Legacy 4-page layout (Subjects @ idx 2) — ml=39 above rewrites
        ; to 3-page. We still produce the 4-page shape here so OLD saves
        ; (ml < 38) get a coherent transient state before the ml=39 pass
        ; runs on the same boot. The 3-page rewrite happens once ml=38 is set.
        Pages = new String[4]
        Pages[0] = "General"
        Pages[1] = "Preset editor"
        Pages[2] = "Subjects"
        Pages[3] = "Plugins"
        MainQuest._migrationLevel = 37
        return
    endif
    ; v0.1.3 refactor (ml=36): Flash on Hit moved from sibling-to-Pulse
    ; (per-slot `mtf.cond.flash.*` StorageUtil keys + dedicated MCM block)
    ; to an effect-framework binding (mtf.base:flash.onhit at effect[N]
    ; with extras keyed by `mtf.fx.<slot>.<effectIdx>.ex.<field>`). The
    ; old per-slot keys still sit in cosaves but nothing reads them
    ; anymore — they'll naturally age out. New saves never touch them.
    if ml >= 35 || ml >= 34
        MainQuest._migrationLevel = 36
        return
    endif
    ; v0.1.2 (ml=34): non-destructive. The "Conditions" page was renamed to
    ; "Preset editor" — rewrite the Pages array so existing saves pick up
    ; the new label. (Pages doesn't auto-refresh on script update; same
    ; reason the older ml=19 defensive block exists below.)
    if ml >= 33
        Pages = new String[5]
        Pages[0] = "General"
        Pages[1] = "Preset editor"
        Pages[2] = "Subjects"
        Pages[3] = "Plugins"
        Pages[4] = "Menu Options"
        MainQuest._migrationLevel = 34
        return
    endif
    ; (v0.2.4: removed ml=33 / ml=20 / ml=19 ladder rungs. They handled the
    ;  v0.0.32 → v0.0.33 transition — backing out per-quest applied
    ;  magnitudes on Plugin_Base. Anyone on a save that old is long gone;
    ;  _ensureScratchArrays is still called defensively from inside
    ;  _loadPresetToScratch so dropping the migration call doesn't strand
    ;  pre-v0.0.33 saves' scratch arrays anyway.)

    ; Pages: 3-page layout (also set by OnConfigInit; redundant here for the
    ; sake of upgraders whose Pages array predates the current shape).
    Pages = new String[3]
    Pages[0] = "General"
    Pages[1] = "Preset editor"
    Pages[2] = "Plugins"

    ; Make sure every state array is allocated at the CURRENT
    ; MAX_EFFECTS_PER_SLOT size. Previously this block hardcoded
    ; `new string[32]` for the effect arrays (8 slots × 4 effects), which
    ; silently shrank them after EnsureArrays correctly sized them — the
    ; next EnsureArrays call then hit the 128-element ceiling trying to
    ; migrate 32 → 128 inside one VM tick and the loop never settled.
    MainQuest.EnsureArrays()

    ; v0.2.8: enabled by default on fresh install. Mirrors the explicit
    ; MainQuest.OnInit `ModActive = true` test-branch convenience — keeping
    ; both in lockstep so neither location overwrites the other on first
    ; save load.
    MainQuest.ModActive          = true
    MainQuest.updateInterval     = 0.1
    MainQuest.OverlaySlot        = 2
    MainQuest.CurrentOverlaySlot = 2

    ; Default slot (idx 0): leave empty so the player sees no tattoo until
    ; they explicitly pick one in MCM. Loading visual catalogs is still
    ; required so the per-slot pickers can populate when opened.
    MainQuest.LoadVisualCatalogs()
    MainQuest.SetCondPackId(0,  "")
    MainQuest.SetCondEntryId(0, "")

    ; Per-layer defaults: layer 0 = opaque white mark, no glow.
    ;                     layer 1 = warm glow (off by default — emissiveMult=0
    ;                                          on Default, 2.5 on condition slots).
    int s = 0
    while s < 8
        if s > 0
            ; slots 1-7 inherit Default's pack+entry until user overrides
            MainQuest.SetCondPackId(s,  "")
            MainQuest.SetCondEntryId(s, "")
        endif

        ; Layer 0 (base mark)
        MainQuest.SetCondLayerTint(s, 0, 16777215)
        MainQuest.SetCondLayerEmissive(s, 0, 16777215)
        MainQuest.SetCondLayerEmissiveMult(s, 0, 0.0)
        MainQuest.SetCondLayerAlpha(s, 0, 100)

        ; Layer 1 (glow halo)
        MainQuest.SetCondLayerTint(s, 1, 16777215)
        MainQuest.SetCondLayerEmissive(s, 1, 11337843)   ; warm amber
        MainQuest.SetCondLayerAlpha(s, 1, 80)
        if s > 0
            MainQuest.SetCondLayerEmissiveMult(s, 1, 2.5)
        else
            MainQuest.SetCondLayerEmissiveMult(s, 1, 0.0)
        endif

        ; Layers 2-3 fully opaque-transparent so trailing-slot clear is moot
        int Li = 2
        while Li < 4
            MainQuest.SetCondLayerTint(s, Li, 16777215)
            MainQuest.SetCondLayerEmissive(s, Li, 16777215)
            MainQuest.SetCondLayerEmissiveMult(s, Li, 0.0)
            MainQuest.SetCondLayerAlpha(s, Li, 100)
            Li += 1
        endwhile

        s += 1
    endwhile

    MainQuest._migrationLevel = 39
endEvent

; ── SkyrimNet bio refresh on MCM close ────────────────────────────────────────
; The SkyrimNet bridge pre-renders the player's "## Magic Tattoos" bio block
; to StorageUtil and only re-renders on tier transitions (HandleTierChange).
; MCM mutations to effect text params, menu picks, slider values, condition
; params, layer colors, pulse, etc. don't change the tier, so the bridge
; never re-renders and the bio stays stale until the next state change.
;
; Audit-clean catch-all: rebuild on MCM close. One hook, all paths covered.
; Cost is a few StorageUtil reads + string concat per close. See the
; project_skyrimnet_decorator_cache memory's "audit ALL mutation paths" rule.
Function OnConfigClose()
    MTF_Plugin_SkyrimNet._rebuildRenderedFor(Game.GetPlayer())
EndFunction

; ── Page rendering ────────────────────────────────────────────────────────────
event OnPageReset(string page)
    _ensureMainQuest()
    if page == "General"
        drawGeneralPage()
    elseIf page == "Preset editor"
        drawPresetEditorPage()
    elseif page == "Plugins"
        drawPluginsPage()
    endif
endEvent

; Plugin toggle pool: 16 PLUGIN_TOGGLE_N states map (via _bindPluginToggle)
; to plugins on the CURRENT page (16 per page). v0.2.1 added pagination so
; the page is no longer hard-capped at 16 plugins — PLUGIN_PAGE_PREV/NEXT
; advance _pluginsPage and the slot→plugin map shifts by _pluginsPage*16.
;
; Replaces the legacy 32-slot per-item TOGGLE_N pool (and the "Menu Options"
; page that drove it). Per-item granularity was almost never used and made
; the page unwieldy as plugin counts grew. Per-plugin is sufficient for the
; main use case: silencing an integration while keeping bound slots intact.

int Function PLUGINS_PAGE_SIZE() global
    return 16
EndFunction

int _pluginsPage = 0

string Function _pluginToggleStateId(int slot)
    return "PLUGIN_TOGGLE_" + (slot + 1)
EndFunction

string _scratchPluginId
string _scratchPluginLabel

bool Function _bindPluginToggle(int slot)
{Writes the plugin id + label into scratch fields. Returns true if slot resolved.
 `slot` is the page-relative row (0..15); we offset by _pluginsPage * 16 to
 get the absolute plugin index.}
    int abs = _pluginsPage * PLUGINS_PAGE_SIZE() + slot
    if slot < 0 || slot >= PLUGINS_PAGE_SIZE() || abs >= MainQuest.pluginCount
        return false
    endif
    MTF_Plugin p = MainQuest.GetPluginAt(abs)
    if p == None
        return false
    endif
    _scratchPluginId    = p.GetPluginId()
    _scratchPluginLabel = p.GetPluginLabel()
    return true
EndFunction

Function _selectPluginToggle(int slot)
    if !_bindPluginToggle(slot)
        return
    endif
    bool now = !MainQuest.IsPluginEnabled(_scratchPluginId)
    MainQuest.SetPluginEnabled(_scratchPluginId, now)
    SetToggleOptionValueST(now)
EndFunction

Function _defaultPluginToggle(int slot)
    if !_bindPluginToggle(slot)
        return
    endif
    MainQuest.SetPluginEnabled(_scratchPluginId, true)
    SetToggleOptionValueST(true)
EndFunction

Function _highlightPluginToggle(int slot)
    if !_bindPluginToggle(slot)
        SetInfoText("")
        return
    endif
    SetInfoText("Show " + _scratchPluginLabel + "'s conditions and effects in slot dropdowns. Disabling hides them all; existing bindings stay visible so you can clear them.")
EndFunction

function drawGeneralPage()
    SetCursorFillMode(TOP_TO_BOTTOM)

    ; Single-column engine/global settings. Preset management (Save / Pick /
    ; Delete) lives on the Preset editor page next to the per-preset content
    ; it operates on.
    AddHeaderOption("General")
    AddToggleOptionST("GEN_MOD_ACTIVE",      "Enable",                MainQuest.ModActive)
    AddSliderOptionST("GEN_UPDATE_INTERVAL", "Update interval (sec)", MainQuest.updateInterval, "{2}")
    AddSliderOptionST("SLOT_OVERLAY_SLOT",   "Overlay slot (Body)",   MainQuest.OverlaySlot)
    ; v0.1.17 Phase 2 (multi-area): per-area base slot sliders. Defaults
    ; sit at 0 so face/hand/feet packs paint into ovl0 upward by default.
    AddSliderOptionST("SLOT_FACE_OVERLAY_SLOT", "Overlay slot (Face)", MainQuest.FaceOverlaySlot)
    AddSliderOptionST("SLOT_HAND_OVERLAY_SLOT", "Overlay slot (Hand)", MainQuest.HandOverlaySlot)
    AddSliderOptionST("SLOT_FEET_OVERLAY_SLOT", "Overlay slot (Feet)", MainQuest.FeetOverlaySlot)
    AddTextOptionST("GEN_RELOAD_VISUALS", "Reload visual packs", "(" + MainQuest.GetVisualPackCount() + " loaded)")
    AddToggleOptionST("GEN_DEBUG_MODE",      "Debug mode",             MainQuest.DebugMode)
    ; Lifecycle audit lives on MTF_MainQuest as `DumpLifecycleAudit` /
    ; `ResetLifecycleAudit` (console: `cqf MTF_MainQuest DumpLifecycleAudit`).
    ; Not wired into MCM because this script is at the engine's 127 named-
    ; state cap; the audit is debug-only and the console reaches it fine.
endFunction

function drawPluginsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)

    int total = MainQuest.pluginCount
    int pageSize = PLUGINS_PAGE_SIZE()
    int maxPage = 0
    if total > 0
        maxPage = (total - 1) / pageSize
    endif
    if _pluginsPage > maxPage
        _pluginsPage = maxPage
    endif
    if _pluginsPage < 0
        _pluginsPage = 0
    endif

    AddHeaderOption("Plugins (" + total + ", " + MainQuest.GetTotalConditionItemCount() + " conditions, " + MainQuest.GetTotalEffectItemCount() + " effects)")

    ; Page controls on one row (col 1 = Prev, col 2 = Next). Disabled at
    ; the ends so users don't get a confusing "click does nothing"
    ; interaction. Always rendered so the page-of-N counter is visible
    ; even when only one page exists. Flip fill mode to LEFT_TO_RIGHT
    ; for this row only — SkyUI's default font doesn't render the
    ; unicode arrows (←/→) we tried in v0.2.2, so labels are plain text.
    int prevFlag = OPTION_FLAG_NONE
    int nextFlag = OPTION_FLAG_NONE
    if _pluginsPage == 0
        prevFlag = OPTION_FLAG_DISABLED
    endif
    if _pluginsPage >= maxPage
        nextFlag = OPTION_FLAG_DISABLED
    endif
    SetCursorFillMode(LEFT_TO_RIGHT)
    AddTextOptionST("PLUGIN_PAGE_PREV", "Previous page", "(page " + (_pluginsPage + 1) + " of " + (maxPage + 1) + ")", prevFlag)
    AddTextOptionST("PLUGIN_PAGE_NEXT", "Next page", "", nextFlag)
    SetCursorFillMode(TOP_TO_BOTTOM)

    ; Per-plugin "Show in selectors" toggle. Replaces the old per-item
    ; Menu Options page — disabling hides every condition and effect this
    ; plugin contributes from the slot dropdowns. The currently-bound key
    ; stays visible (handled host-side in _isKeyVisible) so existing
    ; bindings remain editable.
    int rowStart = _pluginsPage * pageSize
    int slot = 0
    while slot < pageSize
        int absIdx = rowStart + slot
        if absIdx < total
            MTF_Plugin p = MainQuest.GetPluginAt(absIdx)
            if p != None
                int cn  = p.GetConditionCount()
                int en  = p.GetEffectCount()
                string pid = p.GetPluginId()
                AddToggleOptionST(_pluginToggleStateId(slot), p.GetPluginLabel() + "  (" + pid + ", " + cn + "c, " + en + "e)", MainQuest.IsPluginEnabled(pid))
            endif
        endif
        slot += 1
    endwhile
endFunction

; (v0.2.1: per-plugin setting sliders + SETTING_1..8 state pool +
; _openSetting/_acceptSetting/_defaultSetting/_highlightSetting/_bindSetting
; dispatchers removed — no plugin ever shipped a non-zero GetSettingCount,
; and the 8 freed named-state slots leave room for new MCM features without
; bumping into SkyUI's 127-named-state cap.)

function drawPresetEditorPage()
    SetCursorFillMode(TOP_TO_BOTTOM)

    ; Defensive: EnsureArrays now lazy-allocates post-release arrays even
    ; when _arraysReady is true, but call it here explicitly so any stale
    ; instance gets patched before we read any of them.
    MainQuest.EnsureArrays()

    int idx = selectedCondition

    ; ── LEFT COLUMN: preset management + transition + visual config ─────────
    ; Preset header groups file lifecycle (Editing status + Save / Save as /
    ; Load / Delete / New). Transition has its own header (preset-wide
    ; animation timing, distinct from file management). Visuals/Layers/Pulse
    ; below the live-preview hint are per-slot (driven by the slot picker on
    ; the right).
    _refreshPresetNames()
    AddHeaderOption("Preset")
    AddTextOptionST("PRESET_EDITING_STATUS", "Editing", _editingLabel(), OPTION_FLAG_DISABLED)
    int saveFlag = OPTION_FLAG_NONE
    if _editingPresetName == ""
        saveFlag = OPTION_FLAG_DISABLED
    endif
    AddTextOptionST("PRESET_SAVE",     "Save",          "", saveFlag)
    AddInputOptionST("PRESET_SAVE_AS", "Save as...",    "(type a name)")
    AddMenuOptionST("PRESET_PICK",     "Load preset",   "")
    AddMenuOptionST("PRESET_DEL",      "Delete preset", "")
    AddMenuOptionST("PRESET_NEW",      "New preset",    "")

    AddHeaderOption("Transition")
    AddSliderOptionST("PRESET_TRANSITION_DUR", "Duration", MainQuest.GetTransitionDuration(), "{1} s")

    ; v0.2.9: Visuals + Layers + Pulse are only meaningful on slots 0..MCM_CAP.
    ; Backend slots (slot > MCM_CAP) inherit pack/entry from Default and don't
    ; have per-slot visual storage exposed in the MCM — render a single
    ; disabled placeholder so the page layout stays stable.
    if idx <= MTF_MainQuest.MAX_CONDITIONS_MCM()
        AddHeaderOption("Visuals")
        AddMenuOptionST("SLOT_PACK_PICK",     "Visual pack", _slotPackLabel(idx))
        AddMenuOptionST("SLOT_VISUAL_ENTRY",  "Texture",     _slotEntryLabel(idx))

        ; Determine layer count from the resolved (slot or inherited) entry.
        ; When the slot's pack resolves to "(no texture)" (sentinel "<none>" or,
        ; for Default with no packs installed, ""), hide all layer sliders —
        ; there's nothing to tint. Otherwise default to MAX_LAYERS so the user
        ; can pre-tweak even before an entry resolves.
        string resPack  = MainQuest.ResolveSlotPackId(idx)
        string resEntry = MainQuest.ResolveSlotEntryId(idx)
        int layerN = MTF_MainQuest.MAX_LAYERS_PER_SLOT()
        if resPack == "" || resPack == "<none>"
            layerN = 0
        elseif resEntry != ""
            int lc = MainQuest.GetEntryLayerCount(resPack, resEntry)
            if lc > 0 && lc < layerN
                layerN = lc
            endif
        endif
        ; Per-layer visuals always read from the LAYOUT slot (idx), not the
        ; inheritance target — letting a condition slot keep its own colors
        ; even when it inherits pack+entry.
        int L = 0
        while L < layerN
            AddHeaderOption("Layer " + L)
            AddColorOptionST("SLOT_L" + L + "_TINT",      "Tint",              MainQuest.GetCondLayerTint(idx, L))
            AddColorOptionST("SLOT_L" + L + "_EMISSIVE",  "Emission color",    MainQuest.GetCondLayerEmissive(idx, L))
            AddSliderOptionST("SLOT_L" + L + "_EM_MULT",  "Emission strength", MainQuest.GetCondLayerEmissiveMult(idx, L), "{1}")
            AddSliderOptionST("SLOT_L" + L + "_ALPHA",    "Opacity",           MainQuest.GetCondLayerAlpha(idx, L), "{0}%")
            L += 1
        endwhile

        ; ── Pulse (animated emissive) ───────────────────────────────────────
        ; Only meaningful when the slot has emissive layers to modulate.
        ; Shown unconditionally so users can dial it in even with pack="<none>"
        ; (effects-only mode shows no overlay, so pulse is a no-op there).
        AddHeaderOption("Pulse")
        AddSliderOptionST("SLOT_PULSE_RATE",  "Rate",  MainQuest.GetCondPulseRate(idx), "{2} Hz")
        AddSliderOptionST("SLOT_PULSE_DEPTH", "Depth", MainQuest.GetCondPulseDepth(idx), "{0}%")
        AddSliderOptionST("SLOT_PULSE_PAUSE", "Pause", MainQuest.GetCondPulsePause(idx), "{1} s")
        AddMenuOptionST("SLOT_PULSE_WAVEFORM", "Waveform", _waveformLabel(MainQuest.GetCondWaveform(idx)))
    else
        AddHeaderOption("Visuals")
        AddTextOption("Inherits Default", "", OPTION_FLAG_DISABLED)
    endif

    ; Per-preset fade on death (v0.1.4). One menu picks "Off" or one of the
    ; three modes; Duration is greyed out when Off. We use a single 4-entry
    ; menu instead of a separate toggle + mode menu to stay under the SkyUI
    ; engine's 127-named-state limit (the script is already at the ceiling).
    ; v0.1.24: moved to the bottom of the left column (was between Transition
    ; and Visuals) so the page reads Preset → Transition → Visuals → Layers
    ; → Pulse → Fade on death.
    AddHeaderOption("Fade on death")
    AddMenuOptionST("PRESET_FADE_MODE",     "Mode",     _fadeModeMenuLabel(MainQuest.GetFadeOnDeathEnabled(), MainQuest.GetFadeOnDeathMode()))
    int fadeFlag = OPTION_FLAG_NONE
    if !MainQuest.GetFadeOnDeathEnabled()
        fadeFlag = OPTION_FLAG_DISABLED
    endif
    AddSliderOptionST("PRESET_FADE_DURATION", "Duration", MainQuest.GetFadeOnDeathDurationMs() / 1000.0, "{1} s", fadeFlag)

    ; ── RIGHT COLUMN: slot picker + condition definition + cooldown + effects ──
    SetCursorPosition(1)

    AddMenuOptionST("COND_SELECTOR", "Configure slot", _slotLabel(selectedCondition))
    ; v0.2.9 rename + swap controls. Rename available on ALL slots including
    ; Default (the slot-0 engine role is unchanged — only its display label).
    ; Swap available on slots 1..MAX_CONDITIONS only; the Default slot has
    ; architectural meaning as the inheritance source so swapping it would
    ; reassign which slot every backend slot's visuals inherit from.
    AddInputOptionST("COND_RENAME", "Slot name", _slotLabel(idx))
    if idx >= 1
        AddMenuOptionST("COND_SWAP_TARGET", "Swap with slot…", "")
    endif

    if idx == 0
        AddHeaderOption("Default slot")
    else
        string key = MainQuest.GetCondPluginId(idx)
        MTF_Plugin p = None
        int itemIdx = -1
        if key != ""
            p = MainQuest.ResolvePluginByKey(key)
            if p != None
                itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            endif
        endif

        AddHeaderOption("Condition " + idx)
        AddMenuOptionST("SLOT_COND_TYPE", "Condition type", _condTypeLabel(key))

        if p != None && itemIdx >= 0
            string paramLabel = p.GetConditionParamLabel(itemIdx)
            if paramLabel != ""
                if p.GetConditionParamMenuOptionCount(itemIdx) > 0
                    ; v0.2.9: menu params read string id; sliders read int.
                    AddMenuOptionST("SLOT_COND_PARAM", paramLabel, \
                        _menuLabelForCondParam(p, itemIdx, MainQuest.GetCondParamStr(idx)))
                elseif p.GetConditionParamIsText(itemIdx)
                    ; v0.3.2: free-text condition param (scene.tag, scene.partner).
                    AddInputOptionST("SLOT_COND_PARAM", paramLabel, _textRowLabel(MainQuest.GetCondParamStr(idx)))
                else
                    AddSliderOptionST("SLOT_COND_PARAM", paramLabel, MainQuest.GetCondParam(idx), p.GetConditionParamFormat(itemIdx))
                endif
            else
                AddTextOption(p.GetConditionLabel(itemIdx), "(no parameter)", OPTION_FLAG_DISABLED)
            endif
            string param2Label = p.GetConditionParam2Label(itemIdx)
            if param2Label != ""
                if p.GetConditionParam2MenuOptionCount(itemIdx) > 0
                    AddMenuOptionST("SLOT_COND_PARAM2", param2Label, \
                        _menuLabelForCondParam2(p, itemIdx, MainQuest.GetCondParam2Str(idx)))
                else
                    AddSliderOptionST("SLOT_COND_PARAM2", param2Label, MainQuest.GetCondParam2(idx), p.GetConditionParam2Format(itemIdx))
                endif
            endif
        endif

        ; v0.3.0: optional SECOND condition + match mode. MCM exposes up to 2
        ; (the backend supports N via the .At accessors / GetCondCount). Only
        ; offered once condition 1 is set; the match mode appears once cond 2 is.
        if key != ""
            string key2 = MainQuest.GetCondPluginIdAt(idx, 1)
            AddMenuOptionST("SLOT_COND2_TYPE", "Condition 2 type", _condTypeLabel(key2))
            if key2 != ""
                MTF_Plugin p2 = MainQuest.ResolvePluginByKey(key2)
                int itemIdx2 = -1
                if p2 != None
                    itemIdx2 = MainQuest._condIdxFor(p2, MainQuest._keyItemId(key2))
                endif
                if p2 != None && itemIdx2 >= 0
                    string paramLabel2 = p2.GetConditionParamLabel(itemIdx2)
                    if paramLabel2 != ""
                        if p2.GetConditionParamMenuOptionCount(itemIdx2) > 0
                            AddMenuOptionST("SLOT_COND2_PARAM", paramLabel2, \
                                _menuLabelForCondParam(p2, itemIdx2, MainQuest.GetCondParamStrAt(idx, 1)))
                        elseif p2.GetConditionParamIsText(itemIdx2)
                            AddInputOptionST("SLOT_COND2_PARAM", paramLabel2, _textRowLabel(MainQuest.GetCondParamStrAt(idx, 1)))
                        else
                            AddSliderOptionST("SLOT_COND2_PARAM", paramLabel2, MainQuest.GetCondParamAt(idx, 1), p2.GetConditionParamFormat(itemIdx2))
                        endif
                    endif
                    string param2Label2 = p2.GetConditionParam2Label(itemIdx2)
                    if param2Label2 != ""
                        if p2.GetConditionParam2MenuOptionCount(itemIdx2) > 0
                            AddMenuOptionST("SLOT_COND2_PARAM2", param2Label2, \
                                _menuLabelForCondParam2(p2, itemIdx2, MainQuest.GetCondParam2StrAt(idx, 1)))
                        else
                            AddSliderOptionST("SLOT_COND2_PARAM2", param2Label2, MainQuest.GetCondParam2At(idx, 1), p2.GetConditionParam2Format(itemIdx2))
                        endif
                    endif
                endif
                AddMenuOptionST("SLOT_COND_OP", "Match mode", _condOpLabel(MainQuest.GetCondOp(idx)))
            endif
        endif

        ; v0.1.24 cooldown rework. Five controls, replacing the old
        ; mode-dropdown + hours/minutes pair:
        ;   Persist h/m — once activated, slot stays on for hours:minutes
        ;                 regardless of condition (0:0 = off).
        ;   Override    — toggle: when ON, higher-priority slots can take over
        ;                 during the persist window; when OFF, slot is locked
        ;                 solid until persist + cool both expire.
        ;   Cool h/m    — after persist ends (or after a normal deactivation
        ;                 when persist=0), slot can't re-arm for hours:minutes.
        ; v0.2.8: persistMin / allowOverride / persistUntilGT are now
        ; StorageUtil-backed via GetCondPersistMin / GetCondAllowOverride /
        ; GetCondPersistUntilGT. coolMin still lives at mtf.cool.min.<slot>
        ; via _getCoolMin. Hours capped at 168 (1 week); max total =
        ; 168*60+59 = 10139 minutes.
        ; State budget: this 5-state cooldown block lands the MCM script
        ; AT the 127-named-state ceiling. Adding more here means freeing
        ; something elsewhere first.
        int persistTotal = MainQuest.GetCondPersistMin(idx)
        int coolTotal    = MainQuest._getCoolMin(idx)
        AddHeaderOption("Cooldown")
        AddSliderOptionST("SLOT_PERSIST_HOURS", "Persist hours",   persistTotal / 60, "{0} h")
        AddSliderOptionST("SLOT_PERSIST_MIN",   "Persist minutes", persistTotal % 60, "{0} m")
        AddTextOptionST("SLOT_OVERRIDE",        "Allow override",  _allowOverrideLabel(MainQuest.GetCondAllowOverride(idx)))
        AddSliderOptionST("SLOT_COOL_HOURS",    "Cool hours",      coolTotal / 60,    "{0} h")
        AddSliderOptionST("SLOT_COOL_MIN",      "Cool minutes",    coolTotal % 60,    "{0} m")
    endif

    AddHeaderOption("Effects")
    ; Progressive disclosure: row N is shown only after row N-1 has a key
    ; set. Row 0 is always visible. The trailing visible row is always the
    ; first "Not set" slot, so the user sees exactly one selector beyond
    ; their last bound effect. Clearing a row in the middle is handled by
    ; CompactEffectsAfter (see _acceptEffectType) so no row stays orphaned
    ; out of view.
    ;
    ; Storage cap (MAX_EFFECTS_PER_SLOT) is larger than the MCM cap below
    ; — JSON-authored presets can hold up to that many effects. Hidden
    ; effects beyond row 4 still dispatch at runtime; we surface a count
    ; so the user knows they're there (clear a visible row to promote one
    ; into view via the compact-shift).
    _drawEffectRow(idx, 0, "SLOT_EFFECT_1_TYPE", "SLOT_EFFECT_1_P1", "SLOT_EFFECT_1_P2", \
                   "SLOT_EFFECT_1_P3", "SLOT_EFFECT_1_P4", "SLOT_EFFECT_1_P5")
    if MainQuest.GetSlotEffectKey(idx, 0) != ""
        _drawEffectRow(idx, 1, "SLOT_EFFECT_2_TYPE", "SLOT_EFFECT_2_P1", "SLOT_EFFECT_2_P2", \
                       "SLOT_EFFECT_2_P3", "SLOT_EFFECT_2_P4", "SLOT_EFFECT_2_P5")
        if MainQuest.GetSlotEffectKey(idx, 1) != ""
            _drawEffectRow(idx, 2, "SLOT_EFFECT_3_TYPE", "SLOT_EFFECT_3_P1", "SLOT_EFFECT_3_P2", \
                           "SLOT_EFFECT_3_P3", "SLOT_EFFECT_3_P4", "SLOT_EFFECT_3_P5")
            if MainQuest.GetSlotEffectKey(idx, 2) != ""
                _drawEffectRow(idx, 3, "SLOT_EFFECT_4_TYPE", "SLOT_EFFECT_4_P1", "SLOT_EFFECT_4_P2", \
                               "SLOT_EFFECT_4_P3", "SLOT_EFFECT_4_P4", "SLOT_EFFECT_4_P5")
                if MainQuest.GetSlotEffectKey(idx, 3) != ""
                    ; Rows 5-8 reached parity with 1-4 in v0.2.2 once the MCM
                    ; state-budget recovery (subjects-page drop + plugin
                    ; pagination + plugin-level settings drop) freed enough
                    ; named-state slots to add P3/P4/P5 here too.
                    _drawEffectRow(idx, 4, "SLOT_EFFECT_5_TYPE", "SLOT_EFFECT_5_P1", "SLOT_EFFECT_5_P2", \
                                   "SLOT_EFFECT_5_P3", "SLOT_EFFECT_5_P4", "SLOT_EFFECT_5_P5")
                    if MainQuest.GetSlotEffectKey(idx, 4) != ""
                        _drawEffectRow(idx, 5, "SLOT_EFFECT_6_TYPE", "SLOT_EFFECT_6_P1", "SLOT_EFFECT_6_P2", \
                                       "SLOT_EFFECT_6_P3", "SLOT_EFFECT_6_P4", "SLOT_EFFECT_6_P5")
                        if MainQuest.GetSlotEffectKey(idx, 5) != ""
                            _drawEffectRow(idx, 6, "SLOT_EFFECT_7_TYPE", "SLOT_EFFECT_7_P1", "SLOT_EFFECT_7_P2", \
                                           "SLOT_EFFECT_7_P3", "SLOT_EFFECT_7_P4", "SLOT_EFFECT_7_P5")
                            if MainQuest.GetSlotEffectKey(idx, 6) != ""
                                _drawEffectRow(idx, 7, "SLOT_EFFECT_8_TYPE", "SLOT_EFFECT_8_P1", "SLOT_EFFECT_8_P2", \
                                               "SLOT_EFFECT_8_P3", "SLOT_EFFECT_8_P4", "SLOT_EFFECT_8_P5")
                            endif
                        endif
                    endif
                endif
            endif
        endif
    endif
    ; Count bound effects beyond the MCM cap and surface a hint when any
    ; exist. They're dispatched but invisible in the editor; clearing a
    ; visible row promotes one of them into view via CompactEffectsAfter.
    int hidden = 0
    int hi = MTF_MainQuest.MAX_EFFECTS_PER_SLOT_MCM()
    int storageMax = MTF_MainQuest.MAX_EFFECTS_PER_SLOT()
    while hi < storageMax
        if MainQuest.GetSlotEffectKey(idx, hi) != ""
            hidden += 1
        endif
        hi += 1
    endwhile
    if hidden > 0
        AddTextOption("  (+" + hidden + " more — not editable here)", "", OPTION_FLAG_DISABLED)
    endif
endFunction

string Function _waveformLabel(string name)
    if name == ""
        return "Cosine (built-in)"
    endif
    return name
EndFunction

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  GENERAL PAGE STATES                                                    ║
; ╚══════════════════════════════════════════════════════════════════════════╝

state GEN_MOD_ACTIVE
    event OnSelectST()
        bool v = !MainQuest.ModActive
        MainQuest.ModActive = v
        SetToggleOptionValueST(v)
        if v
            MainQuest.setRedraw()
            MainQuest.Rearm()
        endif
    endEvent
    event OnDefaultST()
        MainQuest.ModActive = false
        SetToggleOptionValueST(false)
    endEvent
    event OnHighlightST()
        SetInfoText("Enable or disable the mod.")
    endEvent
endState

state GEN_UPDATE_INTERVAL
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.updateInterval)
        SetSliderDialogDefaultValue(0.1)
        SetSliderDialogRange(0.1, 45.0)
        SetSliderDialogInterval(0.1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.updateInterval = value
        SetSliderOptionValueST(value, "{2}")
    endEvent
    event OnDefaultST()
        MainQuest.updateInterval = 0.1
        SetSliderOptionValueST(0.1, "{2}")
    endEvent
    event OnHighlightST()
        SetInfoText("How often in seconds the script checks conditions. Lower = more responsive, higher = better performance.")
    endEvent
endState

state GEN_RELOAD_VISUALS
    event OnSelectST()
        MainQuest.ForceReloadVisualCatalogs()
        SetTextOptionValueST("(" + MainQuest.GetVisualPackCount() + " loaded)")
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Re-scan Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/ for pack JSONs.")
    endEvent
endState

state GEN_DEBUG_MODE
    event OnSelectST()
        bool v = !MainQuest.DebugMode
        MainQuest.DebugMode = v
        SetToggleOptionValueST(v)
    endEvent
    event OnDefaultST()
        MainQuest.DebugMode = false
        SetToggleOptionValueST(false)
    endEvent
    event OnHighlightST()
        SetInfoText("Show a corner-notification toast whenever the active condition tier changes, listing what's being drained. Useful for verifying that conditions and side effects are firing correctly. Also enables the lifecycle audit counters — dump via `cqf MTF_MainQuest DumpLifecycleAudit`.")
    endEvent
endState

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  CONDITIONS PAGE STATES                                                 ║
; ╚══════════════════════════════════════════════════════════════════════════╝

state COND_SELECTOR
    event OnMenuOpenST()
        ; v0.2.9: dropdown now spans all 32 backend slots (was hardcoded 8) and
        ; renders custom slot names from MainQuest.GetCondName. Use
        ; CreateStringArray for the alloc — direct `new string[N]` with a
        ; computed N would fail at compile (Papyrus allows only literal sizes).
        ; MAX_CONDITIONS is a `global` function on MTF_MainQuest, so it's
        ; called on the class, not the instance (mirrors MAX_LAYERS_PER_SLOT
        ; pattern at line ~457).
        int total = MTF_MainQuest.MAX_CONDITIONS() + 1
        string[] opts = Utility.CreateStringArray(total, "")
        int i = 0
        while i < total
            opts[i] = _slotLabel(i)
            i += 1
        endwhile
        SetMenuDialogStartIndex(selectedCondition)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index < 0
            return
        endif
        selectedCondition = index
        SetMenuOptionValueST(_slotLabel(index))
        ForcePageReset()
    endEvent
    event OnDefaultST()
        selectedCondition = 0
        SetMenuOptionValueST(_slotLabel(0))
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Select which slot to configure. Default is the fallback that always renders when no Condition's predicate matches. Slots 1-MAX are checked in order — first satisfied wins. Slot names can be customized via the 'Slot name' input below.")
    endEvent
endState

; v0.2.9: per-slot display name. Empty input clears back to the canonical
; "Default" / "Condition N" label. Sanitized via the same allowed-charset
; helper as preset names ([A-Za-z0-9_-], cap 32).
state COND_RENAME
    event OnInputOpenST()
        ; Pre-fill with the current label so the user can tweak rather than
        ; retype. Empty stored name → falls back to canonical label.
        SetInputDialogStartText(_slotLabel(selectedCondition))
    endEvent
    event OnInputAcceptST(string a_input)
        ; Empty input clears the override (back to canonical label).
        if a_input == ""
            MainQuest.SetCondName(selectedCondition, "")
            ForcePageReset()
            return
        endif
        string sanitized = MainQuest._sanitizePresetName(a_input)
        if sanitized == ""
            Debug.Notification("MTF: invalid slot name (use letters/digits/_/-)")
            return
        endif
        MainQuest.SetCondName(selectedCondition, sanitized)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Rename this slot for clarity (e.g. 'Magicka draught' instead of 'Condition 3'). Letters/digits/_/-, max 32 chars. Empty input restores the default 'Condition N' label. Save the preset to persist.")
    endEvent
endState

; v0.2.9: swap this slot's cond + effects + cooldown + name with another slot.
; Visuals (tint/emissive/em.mult/alpha/pulse) stay tied to slot index per
; design — see MTF_MainQuest.SwapSlots docstring. Slot 0 (Default) is omitted
; from the picker since it's the inheritance source and not swappable.
state COND_SWAP_TARGET
    event OnMenuOpenST()
        ; Build [Cancel, slot 1, slot 2, ..., slot MAX] minus the currently
        ; selected slot. Using a single Cancel entry at index 0 (mirrors
        ; PRESET_PICK's pattern at MCMQuest.psc:3823).
        ; Total entries = Cancel(1) + (maxC slots) - 1 self = maxC.
        int maxC = MTF_MainQuest.MAX_CONDITIONS()
        int total = maxC
        string[] opts = Utility.CreateStringArray(total, "")
        opts[0] = "Cancel"
        int i = 1
        int outIdx = 1
        while i <= maxC
            if i != selectedCondition
                opts[outIdx] = "Swap with " + _slotLabel(i)
                outIdx += 1
            endif
            i += 1
        endwhile
        SetMenuDialogStartIndex(0)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int a_index)
        if a_index <= 0
            return   ; Cancel or invalid
        endif
        ; Reconstruct which slot was at output index a_index (same skip-self
        ; iteration as OnMenuOpenST).
        int maxC = MTF_MainQuest.MAX_CONDITIONS()
        int i = 1
        int outIdx = 1
        int pickedSlot = -1
        while i <= maxC && pickedSlot < 0
            if i != selectedCondition
                if outIdx == a_index
                    pickedSlot = i
                endif
                outIdx += 1
            endif
            i += 1
        endwhile
        if pickedSlot < 1
            return
        endif
        if MainQuest.SwapSlots(_editingPresetName, selectedCondition, pickedSlot)
            Debug.Notification("MTF: swapped slot " + selectedCondition + " ↔ slot " + pickedSlot)
            ; Stay on the originally-selected slot index — the user picked
            ; THAT slot to configure, and its content is now whatever was
            ; in the picked slot before the swap.
            ForcePageReset()
        else
            Debug.Notification("MTF: swap failed (invalid slot)")
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Swap this slot's condition, effects, cooldown, and name with another slot. Visuals (tint/emissive/alpha/pulse) stay tied to slot index. Both slots' active timers are cleared; NPCs revalidate on next slow tick. Default slot is not swappable.")
    endEvent
endState

state SLOT_OVERLAY_SLOT
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.OverlaySlot)
        SetSliderDialogDefaultValue(2)
        SetSliderDialogRange(0, 30)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.OverlaySlot = value as int
        SetSliderOptionValueST(value as int)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.OverlaySlot = 2
        SetSliderOptionValueST(2)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Body base NiOverride overlay slot. Two consecutive slots are used: this slot (mark) and slot+1 (halo). Avoid conflicts with other overlay mods (SlaveTats, RaceMenu overlays).")
    endEvent
endState

; v0.1.17 Phase 2 (multi-area): per-area base slot sliders. Each defaults
; to 0 (paint into ovl0 upward) — there's no SlaveTats-equivalent body
; convention for face/hand/feet, so 0 is the natural floor. NiOverride's
; iNumOverlays for non-Body pools is typically 3 (skee64.ini default), so
; the range 0..6 covers reasonable user setups.
state SLOT_FACE_OVERLAY_SLOT
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.FaceOverlaySlot)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 6)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.FaceOverlaySlot = value as int
        SetSliderOptionValueST(value as int)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.FaceOverlaySlot = 0
        SetSliderOptionValueST(0)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Face base NiOverride overlay slot. Only meaningful when a Condition slot picks a pack with area=Face. Avoid conflicts with vanilla warpaints / face-overlay mods.")
    endEvent
endState

state SLOT_HAND_OVERLAY_SLOT
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.HandOverlaySlot)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 6)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.HandOverlaySlot = value as int
        SetSliderOptionValueST(value as int)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.HandOverlaySlot = 0
        SetSliderOptionValueST(0)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Hand base NiOverride overlay slot. Only meaningful when a Condition slot picks a pack with area=Hand.")
    endEvent
endState

state SLOT_FEET_OVERLAY_SLOT
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.FeetOverlaySlot)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 6)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.FeetOverlaySlot = value as int
        SetSliderOptionValueST(value as int)
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.FeetOverlaySlot = 0
        SetSliderOptionValueST(0)
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Feet base NiOverride overlay slot. Only meaningful when a Condition slot picks a pack with area=Feet.")
    endEvent
endState

state SLOT_COND_TYPE
    event OnMenuOpenST()
        string curKey = MainQuest.GetCondPluginId(selectedCondition)
        MainQuest.BuildVisibleConditionMenu(curKey)
        string[] keys   = MainQuest.menuKeys
        string[] labels = MainQuest.menuLabels
        int n = MainQuest.menuCount
        int sz = n + 1
        if sz > 127
            sz = 127
        endif
        string[] opts = _newOpts(sz)
        opts[0] = "Not set"
        int curIdx = 0
        int i = 0
        while i < n && (i + 1) < sz
            opts[i + 1] = labels[i]
            if keys[i] == curKey
                curIdx = i + 1
            endif
            i += 1
        endwhile
        SetMenuDialogStartIndex(curIdx)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index < 0
            return
        endif
        int slot = selectedCondition
        string newKey = ""
        if index > 0
            string[] keys = MainQuest.menuKeys
            int n = MainQuest.menuCount
            if (index - 1) < n && keys != None
                newKey = keys[index - 1]
            endif
        endif
        MainQuest.SetCondPluginId(slot, newKey)
        ; v0.3.2: clear the param STRING slot too. The inline reset only zeroes
        ; the int params, leaving stale menu ids (e.g. "mff") or text in the
        ; shared param-string slot when the condition type is swapped.
        MainQuest.SetCondParamStr(slot, "")
        MainQuest.SetCondParam2Str(slot, "")
        if newKey == ""
            MainQuest.SetCondParam(slot, 0)
            MainQuest.SetCondParam2(slot, 0)
        else
            MTF_Plugin p = MainQuest.ResolvePluginByKey(newKey)
            int itemIdx = -1
            if p != None
                itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(newKey))
            endif
            if itemIdx >= 0
                MainQuest.SetCondParam(slot, p.GetConditionParamDefault(itemIdx))
                MainQuest.SetCondParam2(slot, p.GetConditionParam2Default(itemIdx))
            else
                MainQuest.SetCondParam(slot, 0)
                MainQuest.SetCondParam2(slot, 0)
            endif
        endif
        SetMenuOptionValueST(_condTypeLabel(newKey))
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPluginId(selectedCondition, "")
        MainQuest.SetCondParam(selectedCondition, 0)
        MainQuest.SetCondParam2(selectedCondition, 0)
        MainQuest.SetCondParamStr(selectedCondition, "")
        MainQuest.SetCondParam2Str(selectedCondition, "")
        SetMenuOptionValueST(_condTypeLabel(""))
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Which condition must be satisfied for this slot to activate. The list is built from registered plugins.")
    endEvent
endState

state SLOT_COND_PARAM
    event OnSliderOpenST()
        string key = MainQuest.GetCondPluginId(selectedCondition)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p == None
            return
        endif
        int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx < 0
            return
        endif
        SetSliderDialogStartValue(MainQuest.GetCondParam(selectedCondition))
        SetSliderDialogDefaultValue(p.GetConditionParamDefault(itemIdx))
        SetSliderDialogRange(p.GetConditionParamMin(itemIdx), p.GetConditionParamMax(itemIdx))
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        string key = MainQuest.GetCondPluginId(selectedCondition)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        string fmt = "{0}"
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                fmt = p.GetConditionParamFormat(itemIdx)
            endif
        endif
        MainQuest.SetCondParam(selectedCondition, value as int)
        SetSliderOptionValueST(value as int, fmt)
    endEvent
    event OnMenuOpenST()
        _openCondParamMenu()
    endEvent
    event OnMenuAcceptST(int index)
        _acceptCondParamMenu(index)
    endEvent
    event OnInputOpenST()
        SetInputDialogStartText(MainQuest.GetCondParamStr(selectedCondition))
    endEvent
    event OnInputAcceptST(string a_input)
        MainQuest.SetCondParamStr(selectedCondition, a_input)
        SetInputOptionValueST(_textRowLabel(a_input))
    endEvent
    event OnDefaultST()
        string key = MainQuest.GetCondPluginId(selectedCondition)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        int defVal = 0
        int menuCnt = 0
        string fmt = "{0}"
        int itemIdx = -1
        if p != None
            itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                defVal = p.GetConditionParamDefault(itemIdx)
                menuCnt = p.GetConditionParamMenuOptionCount(itemIdx)
                fmt = p.GetConditionParamFormat(itemIdx)
            endif
        endif
        if menuCnt > 0 && p != None && itemIdx >= 0
            ; v0.2.9: menu default writes the id string; slider default writes int.
            string defId = p.GetConditionParamDefaultId(itemIdx)
            MainQuest.SetCondParamStr(selectedCondition, defId)
            MainQuest.SetCondParam(selectedCondition, 0)
            SetMenuOptionValueST(_menuLabelForCondParam(p, itemIdx, defId))
        else
            MainQuest.SetCondParam(selectedCondition, defVal)
            MainQuest.SetCondParamStr(selectedCondition, "")
            SetSliderOptionValueST(defVal, fmt)
        endif
    endEvent
    event OnHighlightST()
        string key = MainQuest.GetCondPluginId(selectedCondition)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                SetInfoText(p.GetConditionParamLabel(itemIdx))
                return
            endif
        endif
        SetInfoText("Threshold value for the selected condition.")
    endEvent
endState

state SLOT_COND_PARAM2
    event OnSliderOpenST()
        string key = MainQuest.GetCondPluginId(selectedCondition)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p == None
            return
        endif
        int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx < 0
            return
        endif
        SetSliderDialogStartValue(MainQuest.GetCondParam2(selectedCondition))
        SetSliderDialogDefaultValue(p.GetConditionParam2Default(itemIdx))
        SetSliderDialogRange(p.GetConditionParam2Min(itemIdx), p.GetConditionParam2Max(itemIdx))
        SetSliderDialogInterval(p.GetConditionParam2Step(itemIdx))
    endEvent
    event OnSliderAcceptST(float value)
        string key = MainQuest.GetCondPluginId(selectedCondition)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        string fmt = "{0}"
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                fmt = p.GetConditionParam2Format(itemIdx)
            endif
        endif
        MainQuest.SetCondParam2(selectedCondition, value as int)
        SetSliderOptionValueST(value as int, fmt)
    endEvent
    event OnMenuOpenST()
        _openCondParam2Menu()
    endEvent
    event OnMenuAcceptST(int index)
        _acceptCondParam2Menu(index)
    endEvent
    event OnDefaultST()
        string key = MainQuest.GetCondPluginId(selectedCondition)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        int defVal = 0
        string fmt = "{0}"
        int menuCnt = 0
        int itemIdx = -1
        if p != None
            itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                defVal = p.GetConditionParam2Default(itemIdx)
                fmt = p.GetConditionParam2Format(itemIdx)
                menuCnt = p.GetConditionParam2MenuOptionCount(itemIdx)
            endif
        endif
        if menuCnt > 0 && p != None && itemIdx >= 0
            string defId2 = p.GetConditionParam2DefaultId(itemIdx)
            MainQuest.SetCondParam2Str(selectedCondition, defId2)
            MainQuest.SetCondParam2(selectedCondition, 0)
            SetMenuOptionValueST(_menuLabelForCondParam2(p, itemIdx, defId2))
        else
            MainQuest.SetCondParam2(selectedCondition, defVal)
            MainQuest.SetCondParam2Str(selectedCondition, "")
            SetSliderOptionValueST(defVal, fmt)
        endif
    endEvent
    event OnHighlightST()
        string key = MainQuest.GetCondPluginId(selectedCondition)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                SetInfoText(p.GetConditionParam2Label(itemIdx))
                return
            endif
        endif
        SetInfoText("Second parameter for the selected condition.")
    endEvent
endState

; ── Per-slot entry picker (texture choice within the active visual pack) ────
string Function _slotEntryLabel(int slot)
    ; When the slot is in "(no texture)" mode (resolved at the pack level)
    ; the entry row is informational only.
    string resPack = MainQuest.ResolveSlotPackId(slot)
    if resPack == "<none>" || resPack == ""
        return "—"
    endif
    string entryId = MainQuest.GetCondEntryId(slot)
    if entryId == ""
        if slot == 0
            return "(not set)"
        endif
        return "(inherit Default)"
    endif
    string pid = MainQuest.ResolveSlotPackId(slot)
    if pid == ""
        return entryId
    endif
    string lbl = ""
    int n = MainQuest.GetPackEntryCount(pid)
    int i = 0
    while i < n
        if MainQuest.GetPackEntryIdAt(pid, i) == entryId
            lbl = MainQuest.GetPackEntryLabelAt(pid, i)
            i = n
        else
            i += 1
        endif
    endwhile
    if lbl == ""
        return entryId
    endif
    return lbl
EndFunction

string Function _slotPackLabel(int slot)
    string pid = MainQuest.GetCondPackId(slot)
    if pid == "<none>"
        return "(no texture)"
    endif
    if pid == ""
        if slot == 0
            if MainQuest.GetVisualPackCount() == 0
                return "(no packs found)"
            endif
            return "(no texture)"
        endif
        return "(inherit Default)"
    endif
    int idx = MainQuest.FindVisualPackIndex(pid)
    if idx < 0
        return "Unknown (" + pid + ")"
    endif
    return MainQuest.GetVisualPackLabelAt(idx)
EndFunction

state SLOT_PACK_PICK
    event OnMenuOpenST()
        int n = MainQuest.GetVisualPackCount()
        bool allowInherit = (selectedCondition > 0)
        ; Options layout: [(inherit Default) if slot>0], (no texture), packs...
        int total = n + 1   ; +1 for "(no texture)"
        if allowInherit
            total += 1
        endif
        string[] opts = _newOpts(total)
        int sel = 0
        int writeIdx = 0
        string curPack = MainQuest.GetCondPackId(selectedCondition)
        if allowInherit
            opts[writeIdx] = "(inherit Default)"
            if curPack == ""
                sel = writeIdx
            endif
            writeIdx += 1
        endif
        opts[writeIdx] = "(no texture)"
        if curPack == "<none>" || (selectedCondition == 0 && curPack == "")
            sel = writeIdx
        endif
        writeIdx += 1
        int i = 0
        while i < n
            opts[writeIdx] = MainQuest.GetVisualPackLabelAt(i)
            if MainQuest.GetVisualPackIdAt(i) == curPack
                sel = writeIdx
            endif
            writeIdx += 1
            i += 1
        endwhile
        SetMenuDialogStartIndex(sel)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        bool allowInherit = (selectedCondition > 0)
        if index < 0
            return
        endif
        int cursor = 0
        string newPack = ""
        bool resolved = false
        if allowInherit
            if index == cursor
                newPack = ""
                resolved = true
            endif
            cursor += 1
        endif
        if !resolved && index == cursor
            ; "(no texture)" — for slot 0 we just clear (no inheritance possible);
            ; for 1-7 we store the explicit sentinel.
            if selectedCondition == 0
                newPack = ""
            else
                newPack = "<none>"
            endif
            resolved = true
        endif
        cursor += 1
        if !resolved
            int packIdx = index - cursor
            if packIdx >= 0 && packIdx < MainQuest.GetVisualPackCount()
                newPack = MainQuest.GetVisualPackIdAt(packIdx)
            endif
        endif
        ; Switching packs invalidates the entry pick — reset to first entry
        ; of the new pack (or clear if inheriting / no-texture).
        if newPack != MainQuest.GetCondPackId(selectedCondition)
            MainQuest.SetCondPackId(selectedCondition, newPack)
            if newPack == "" || newPack == "<none>"
                MainQuest.SetCondEntryId(selectedCondition, "")
            elseif MainQuest.GetPackEntryCount(newPack) > 0
                MainQuest.SetCondEntryId(selectedCondition, MainQuest.GetPackEntryIdAt(newPack, 0))
            else
                MainQuest.SetCondEntryId(selectedCondition, "")
            endif
        endif
        SetMenuOptionValueST(_slotPackLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnDefaultST()
        ; Default for every slot is "no tattoo" — leave pack + entry empty.
        ; User must pick a pack explicitly to enable a visual.
        MainQuest.SetCondPackId(selectedCondition, "")
        MainQuest.SetCondEntryId(selectedCondition, "")
        SetMenuOptionValueST(_slotPackLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnHighlightST()
        if selectedCondition == 0
            SetInfoText("Visual pack used by the Default slot. Pick (no texture) for effects-only operation with no overlay. Packs are JSON files under Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/.")
        else
            SetInfoText("Visual pack for this condition slot. (inherit Default) falls back to the Default slot's pack + texture; (no texture) renders nothing and runs effects only.")
        endif
    endEvent
endState

state SLOT_VISUAL_ENTRY
    event OnMenuOpenST()
        string pid = MainQuest.ResolveSlotPackId(selectedCondition)
        ; If the slot is in "(no texture)" / no-pack mode, the entry picker
        ; is a no-op — render a single read-only label.
        if pid == "" || pid == "<none>"
            string[] na = new string[1]
            na[0] = "—"
            SetMenuDialogStartIndex(0)
            SetMenuDialogDefaultIndex(0)
            SetMenuDialogOptions(na)
            return
        endif
        int n = MainQuest.GetPackEntryCount(pid)
        ; Condition slots get a leading "(inherit Default)" option at index 0
        ; ONLY when they also inherit the pack — picking a different pack means
        ; the slot has its own (pack, entry) and entry inheritance is moot.
        bool allowInherit = (selectedCondition > 0) && (MainQuest.GetCondPackId(selectedCondition) == "")
        int total = n
        if allowInherit
            total += 1
        endif
        if total <= 0
            string[] empty = new string[1]
            empty[0] = "(no entries)"
            SetMenuDialogStartIndex(0)
            SetMenuDialogDefaultIndex(0)
            SetMenuDialogOptions(empty)
            return
        endif
        string[] opts = _newOpts(total)
        int sel = 0
        int writeIdx = 0
        if allowInherit
            opts[0] = "(inherit Default)"
            if MainQuest.GetCondEntryId(selectedCondition) == ""
                sel = 0
            endif
            writeIdx = 1
        endif
        int i = 0
        while i < n
            opts[writeIdx] = MainQuest.GetPackEntryLabelAt(pid, i)
            if MainQuest.GetPackEntryIdAt(pid, i) == MainQuest.GetCondEntryId(selectedCondition)
                sel = writeIdx
            endif
            writeIdx += 1
            i += 1
        endwhile
        SetMenuDialogStartIndex(sel)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        string pid = MainQuest.ResolveSlotPackId(selectedCondition)
        if pid == "" || pid == "<none>"
            ; No-pack mode — picker is informational; ignore selection.
            return
        endif
        bool allowInherit = (selectedCondition > 0) && (MainQuest.GetCondPackId(selectedCondition) == "")
        if index < 0
            return
        endif
        if allowInherit && index == 0
            MainQuest.SetCondEntryId(selectedCondition, "")
        else
            int entryIdx = index
            if allowInherit
                entryIdx -= 1
            endif
            if entryIdx >= 0 && entryIdx < MainQuest.GetPackEntryCount(pid)
                MainQuest.SetCondEntryId(selectedCondition, MainQuest.GetPackEntryIdAt(pid, entryIdx))
            endif
        endif
        SetMenuOptionValueST(_slotEntryLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnDefaultST()
        ; Default for every slot is "no entry" — same as the pack picker;
        ; user picks explicitly. Slot 0 was the odd one out previously.
        MainQuest.SetCondEntryId(selectedCondition, "")
        SetMenuOptionValueST(_slotEntryLabel(selectedCondition))
        MainQuest.setRedraw()
        ForcePageReset()
    endEvent
    event OnHighlightST()
        if selectedCondition == 0
            SetInfoText("Texture used by the Default slot. To run effects-only with no overlay, set Visual pack to (no texture).")
        else
            SetInfoText("Texture used by this condition slot. (inherit Default) falls back to Default's pick. To disable the overlay entirely, set Visual pack to (no texture).")
        endif
    endEvent
endState

; v0.1.24 cooldown rework — replaces SLOT_CD_MODE/HOURS/MINUTES with three
; single-slider/toggle states. allowOverride uses Set/SetTextOptionValueST
; with a toggle action on the AddTextOption widget (true plain-toggle MCM
; widgets cost OPTION_FLAG and a state name we already spent). Each duration
; is a single 0-1440 minute slider; format string keeps the display tidy.
string Function _allowOverrideLabel(int v)
    if v == 0
        return "No (locked)"
    endif
    return "Yes"
EndFunction

; ── Persist + Cool component helpers ────────────────────────────────────────
; Hours 0-168 (1 week = 7*24), minutes 0-59. Storage is a single total-minutes
; int per duration (persistMin in cooldownMin[]; coolMin via _set/_getCoolMin),
; so each component setter reads the existing total, replaces its component,
; clamps the combined value, and writes back. Whole-array reassign on
; cooldownMin per the Auto-array-indexed-write quirk.
int Function PERSIST_COOL_MAX_HOURS() global
    return 168
EndFunction
int Function PERSIST_COOL_MAX_TOTAL_MIN() global
    return PERSIST_COOL_MAX_HOURS() * 60 + 59
EndFunction

Function _setPersistComponents(int hours, int minutes)
    if hours < 0
        hours = 0
    elseif hours > PERSIST_COOL_MAX_HOURS()
        hours = PERSIST_COOL_MAX_HOURS()
    endif
    if minutes < 0
        minutes = 0
    elseif minutes > 59
        minutes = 59
    endif
    int total = hours * 60 + minutes
    if total > PERSIST_COOL_MAX_TOTAL_MIN()
        total = PERSIST_COOL_MAX_TOTAL_MIN()
    endif
    MainQuest.SetCondPersistMin(selectedCondition, total)
EndFunction

Function _setCoolComponents(int hours, int minutes)
    if hours < 0
        hours = 0
    elseif hours > PERSIST_COOL_MAX_HOURS()
        hours = PERSIST_COOL_MAX_HOURS()
    endif
    if minutes < 0
        minutes = 0
    elseif minutes > 59
        minutes = 59
    endif
    int total = hours * 60 + minutes
    if total > PERSIST_COOL_MAX_TOTAL_MIN()
        total = PERSIST_COOL_MAX_TOTAL_MIN()
    endif
    MainQuest._setCoolMin(selectedCondition, total)
EndFunction

state SLOT_PERSIST_HOURS
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetCondPersistMin(selectedCondition) / 60)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, PERSIST_COOL_MAX_HOURS())
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        int minutes = MainQuest.GetCondPersistMin(selectedCondition) % 60
        _setPersistComponents(value as int, minutes)
        SetSliderOptionValueST(MainQuest.GetCondPersistMin(selectedCondition) / 60, "{0} h")
        ForcePageReset()
    endEvent
    event OnDefaultST()
        _setPersistComponents(0, MainQuest.GetCondPersistMin(selectedCondition) % 60)
        SetSliderOptionValueST(0, "{0} h")
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Persistence duration (hours component). Once activated, the slot stays active for hours:minutes regardless of whether the condition keeps firing. 0 disables persistence.")
    endEvent
endState

state SLOT_PERSIST_MIN
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetCondPersistMin(selectedCondition) % 60)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 59)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        int hours = MainQuest.GetCondPersistMin(selectedCondition) / 60
        _setPersistComponents(hours, value as int)
        SetSliderOptionValueST(MainQuest.GetCondPersistMin(selectedCondition) % 60, "{0} m")
        ForcePageReset()
    endEvent
    event OnDefaultST()
        _setPersistComponents(MainQuest.GetCondPersistMin(selectedCondition) / 60, 0)
        SetSliderOptionValueST(0, "{0} m")
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Persistence duration (minutes component, added to hours).")
    endEvent
endState

state SLOT_OVERRIDE
    event OnSelectST()
        ; v0.2.8: allowOverride is StorageUtil-backed via GetCondAllowOverride.
        int cur = MainQuest.GetCondAllowOverride(selectedCondition)
        int newV = 1
        if cur != 0
            newV = 0
        endif
        MainQuest.SetCondAllowOverride(selectedCondition, newV)
        SetTextOptionValueST(_allowOverrideLabel(newV))
    endEvent
    event OnDefaultST()
        MainQuest.SetCondAllowOverride(selectedCondition, 1)
        SetTextOptionValueST(_allowOverrideLabel(1))
    endEvent
    event OnHighlightST()
        SetInfoText("While the persist window is active, can a higher-priority slot take over? Yes (default): the slot still wins via persistence, but a higher-priority condition firing will steal the tier. No (locked): the slot wins outright — higher-priority conditions are blocked until persist + cool both expire.")
    endEvent
endState

state SLOT_COOL_HOURS
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest._getCoolMin(selectedCondition) / 60)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, PERSIST_COOL_MAX_HOURS())
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        int minutes = MainQuest._getCoolMin(selectedCondition) % 60
        _setCoolComponents(value as int, minutes)
        SetSliderOptionValueST(MainQuest._getCoolMin(selectedCondition) / 60, "{0} h")
        ForcePageReset()
    endEvent
    event OnDefaultST()
        _setCoolComponents(0, MainQuest._getCoolMin(selectedCondition) % 60)
        SetSliderOptionValueST(0, "{0} h")
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Cooldown duration (hours component). After persistence ends (or after a normal deactivation when persist=0), the slot can't re-arm for hours:minutes. 0 disables cooldown.")
    endEvent
endState

state SLOT_COOL_MIN
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest._getCoolMin(selectedCondition) % 60)
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 59)
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        int hours = MainQuest._getCoolMin(selectedCondition) / 60
        _setCoolComponents(hours, value as int)
        SetSliderOptionValueST(MainQuest._getCoolMin(selectedCondition) % 60, "{0} m")
        ForcePageReset()
    endEvent
    event OnDefaultST()
        _setCoolComponents(MainQuest._getCoolMin(selectedCondition) / 60, 0)
        SetSliderOptionValueST(0, "{0} m")
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Cooldown duration (minutes component, added to hours).")
    endEvent
endState

; ── Per-slot pulse (animated emissive) ──────────────────────────────────────
; Modulates each layer's emissive intensity as base * (1 + depth% * sin(2π·rate·t)).
; Rate is in cycles per second; 0 disables pulse for the slot.

state SLOT_PULSE_RATE
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetCondPulseRate(selectedCondition))
        SetSliderDialogDefaultValue(0.0)
        SetSliderDialogRange(0.0, 5.0)
        SetSliderDialogInterval(0.05)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetCondPulseRate(selectedCondition, value)
        SetSliderOptionValueST(value, "{2} Hz")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPulseRate(selectedCondition, 0.0)
        SetSliderOptionValueST(0.0, "{2} Hz")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Pulse cycles per second. 0 disables the animation.")
    endEvent
endState

state SLOT_PULSE_DEPTH
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetCondPulseDepth(selectedCondition))
        SetSliderDialogDefaultValue(0)
        SetSliderDialogRange(0, 100)
        SetSliderDialogInterval(5)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetCondPulseDepth(selectedCondition, value as int)
        SetSliderOptionValueST(value as int, "{0}%")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPulseDepth(selectedCondition, 0)
        SetSliderOptionValueST(0, "{0}%")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("How far the glow dims from peak. 0% = no pulse, 100% = full off at the trough. Emission strength is the peak.")
    endEvent
endState

state SLOT_PULSE_PAUSE
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetCondPulsePause(selectedCondition))
        SetSliderDialogDefaultValue(0.0)
        SetSliderDialogRange(0.0, 10.0)
        SetSliderDialogInterval(0.1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetCondPulsePause(selectedCondition, value)
        SetSliderOptionValueST(value, "{1} s")
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPulsePause(selectedCondition, 0.0)
        SetSliderOptionValueST(0.0, "{1} s")
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Seconds of hold at the trough (dim) between pulse cycles. 0 = continuous.")
    endEvent
endState

; ── Preset-wide settings (rendered above the slot picker) ────────────────────

state PRESET_TRANSITION_DUR
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetTransitionDuration())
        SetSliderDialogDefaultValue(1.0)
        SetSliderDialogRange(0.0, 10.0)
        SetSliderDialogInterval(0.1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetTransitionDuration(value)
        SetSliderOptionValueST(value, "{1} s")
    endEvent
    event OnDefaultST()
        MainQuest.SetTransitionDuration(1.0)
        SetSliderOptionValueST(1.0, "{1} s")
    endEvent
    event OnHighlightST()
        SetInfoText("Seconds to cross-fade tattoo visuals (alpha, tint, emissive color, emission strength) when the active tier changes. 0 = snap instantly. Saved with the preset.")
    endEvent
endState

; ── Fade on death (v0.1.4) ──────────────────────────────────────────────
; Mode menu carries the on/off toggle as item 0 ("Off"); items 1-3 each
; pick a mode AND enable fade. Duration slider greys out when "Off".
; Combined into 2 states (not 3) to stay under the 127 named-state limit.

state PRESET_FADE_MODE
    event OnMenuOpenST()
        ; "Off" + 3 modes. SkyUI's "None" sentinel bug means we never put
        ; the literal string "None" in this array — use "Off" instead.
        string[] opts = Utility.CreateStringArray(4, "")
        opts[0] = "Off"
        opts[1] = "Overlay (full disappear)"
        opts[2] = "Emissive (dim glow only)"
        opts[3] = "Inverted (dip then recover)"
        int cur = 0
        if MainQuest.GetFadeOnDeathEnabled()
            cur = MainQuest.GetFadeOnDeathMode() + 1
            if cur < 1 || cur > 3
                cur = 1
            endif
        endif
        SetMenuDialogStartIndex(cur)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index <= 0
            MainQuest.SetFadeOnDeathEnabled(false)
        else
            MainQuest.SetFadeOnDeathMode(index - 1)
            MainQuest.SetFadeOnDeathEnabled(true)
        endif
        SetMenuOptionValueST(_fadeModeMenuLabel(MainQuest.GetFadeOnDeathEnabled(), MainQuest.GetFadeOnDeathMode()))
        ; Repaint the page so the Duration slider's disabled flag tracks
        ; the new enabled state.
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetFadeOnDeathEnabled(false)
        SetMenuOptionValueST(_fadeModeMenuLabel(false, 0))
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Fade the tattoo when the actor dies. One-shot animation, then the entry stops animating.\n* Off: no fade on death.\n* Overlay: alpha to 0, tattoo disappears.\n* Emissive: emission strength to 0, art stays but stops glowing.\n* Inverted: dip to 0 then recover — a final flicker.\nSaved with the preset.")
    endEvent
endState

state PRESET_FADE_DURATION
    event OnSliderOpenST()
        SetSliderDialogStartValue(MainQuest.GetFadeOnDeathDurationMs() / 1000.0)
        SetSliderDialogDefaultValue(2.0)
        SetSliderDialogRange(0.1, 10.0)
        SetSliderDialogInterval(0.1)
    endEvent
    event OnSliderAcceptST(float value)
        MainQuest.SetFadeOnDeathDurationMs((value * 1000.0) as int)
        SetSliderOptionValueST(value, "{1} s")
    endEvent
    event OnDefaultST()
        MainQuest.SetFadeOnDeathDurationMs(2000)
        SetSliderOptionValueST(2.0, "{1} s")
    endEvent
    event OnHighlightST()
        SetInfoText("Full duration of the fade animation in seconds. For Inverted mode the dip and recovery each take half of this. Saved with the preset.")
    endEvent
endState

string Function _fadeModeMenuLabel(bool enabled, int mode)
    if !enabled
        return "Off"
    elseif mode == 1
        return "Emissive"
    elseif mode == 2
        return "Inverted"
    endif
    return "Overlay"
EndFunction

state SLOT_PULSE_WAVEFORM
    event OnMenuOpenST()
        string[] files = MainQuest.ListWaveforms()
        int fileCount = MainQuest.ListWaveformsCount()
        ; Size the option array EXACTLY to the count we have. Padding with
        ; duplicate labels (a prior approach to dodge the SkyUI "None"
        ; sentinel quirk) ends up showing 27 phantom rows in the dropdown.
        int total = fileCount + 1
        string[] opts = Utility.CreateStringArray(total, "")
        opts[0] = "Cosine (built-in)"
        int i = 0
        while i < fileCount
            opts[i + 1] = files[i]
            i += 1
        endwhile

        ; Pre-select the currently saved waveform.
        string cur = MainQuest.GetCondWaveform(selectedCondition)
        int startIdx = 0
        if cur != ""
            int k = 1
            while k < total && opts[k] != cur
                k += 1
            endwhile
            if k < total
                startIdx = k
            endif
        endif
        SetMenuDialogStartIndex(startIdx)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        string[] files = MainQuest.ListWaveforms()
        int fileCount = MainQuest.ListWaveformsCount()
        string chosen = ""
        if index >= 1 && (index - 1) < fileCount
            chosen = files[index - 1]
        endif
        MainQuest.SetCondWaveform(selectedCondition, chosen)
        SetMenuOptionValueST(_waveformLabel(chosen))
        MainQuest.setRedraw()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondWaveform(selectedCondition, "")
        SetMenuOptionValueST(_waveformLabel(""))
        MainQuest.setRedraw()
    endEvent
    event OnHighlightST()
        SetInfoText("Curve shape for one pulse cycle. Built-in cosine is the default; JSON files under MagicTattoosFramework/waveforms/ are listed here.")
    endEvent
endState

; ── Per-slot effect list (4 effects × 2 controls each + optional extras) ───

string Function _effectTypeLabel(int effectIdx)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    if key == ""
        return "Not set"
    endif
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return "Unknown (" + key + ")"
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return "Unknown (" + key + ")"
    endif
    string pl = p.GetPluginLabel()
    string il = p.GetEffectDisplayLabel(itemIdx)
    if pl == ""
        return il
    endif
    return pl + " — " + il
EndFunction

Function _drawEffectRow(int slot, int effectIdx, string typeStateId, string p1StateId, string p2StateId, string p3StateId, string p4StateId, string p5StateId)
{Render one effect row: the type picker plus one MCM widget per declared
 paramN slot (N = 1..5). The "is declared" probe is `GetEffectParamLabel(idx, n) != ""`
 — same convention the JSON catalog uses to mark slots as active.
 As of v0.2.2 all 8 rows have full paramN parity; callers should always
 pass real state IDs for p1..p5 (empty strings still safely no-op).}
    AddMenuOptionST(typeStateId, "Effect " + (effectIdx + 1), _effectTypeLabel(effectIdx))
    string key = MainQuest.GetSlotEffectKey(slot, effectIdx)
    if key == ""
        return
    endif
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    string[] paramIds = new string[5]
    paramIds[0] = p1StateId
    paramIds[1] = p2StateId
    paramIds[2] = p3StateId
    paramIds[3] = p4StateId
    paramIds[4] = p5StateId
    int n = 1
    while n <= 5
        string lbl = p.GetEffectParamLabel(itemIdx, n)
        string sid = paramIds[n - 1]
        if lbl != "" && sid != ""
            ; v0.3.x: three param types — text (input), menu (string id), slider (int).
            ; Text takes priority over menu so a misconfigured "text+menu" catalog
            ; doesn't silently fall through to menu render (validator catches it).
            if p.GetEffectParamIsText(itemIdx, n)
                string curText = MainQuest.GetSlotEffectParamNStr(slot, effectIdx, n)
                AddInputOptionST(sid, "  " + lbl, _textRowLabel(curText))
            elseif p.GetEffectParamMenuOptionCount(itemIdx, n) > 0
                string curId = MainQuest.GetSlotEffectParamNStr(slot, effectIdx, n)
                AddMenuOptionST(sid, "  " + lbl, _menuLabelForParam(p, itemIdx, n, curId))
            else
                int curVal = MainQuest.GetSlotEffectParamN(slot, effectIdx, n)
                AddSliderOptionST(sid, "  " + lbl, curVal, p.GetEffectParamFormat(itemIdx, n))
            endif
        endif
        n += 1
    endwhile
EndFunction

Function _openEffectTypeMenu(int effectIdx)
    string curKey = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    ; Build the menu cache ONCE on the host (single plugin walk inside),
    ; then snapshot the cache locally so the build loop is pure-local —
    ; no per-effect cross-script calls.
    MainQuest.BuildVisibleEffectMenu(curKey)
    string[] keys   = MainQuest.menuKeys
    string[] labels = MainQuest.menuLabels
    int n = MainQuest.menuCount
    int sz = n + 1
    if sz > 127
        sz = 127
    endif
    string[] opts = _newOpts(sz)
    opts[0] = "Not set"
    int curSel = 0
    int i = 0
    while i < n && (i + 1) < sz
        opts[i + 1] = labels[i]
        if keys[i] == curKey
            curSel = i + 1
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(curSel)
    SetMenuDialogDefaultIndex(0)
    SetMenuDialogOptions(opts)
EndFunction

Function _acceptEffectType(int effectIdx, int index)
    if index < 0
        return
    endif
    string newKey = ""
    int defParam = 0
    int defParam2 = 0
    if index > 0
        ; Read from the menu cache populated by _openEffectTypeMenu in the
        ; preceding open event. Avoids re-walking plugins for an O(N)
        ; cross-script lookup per pick.
        string[] keys = MainQuest.menuKeys
        int n = MainQuest.menuCount
        if (index - 1) < n && keys != None
            newKey = keys[index - 1]
        endif
        MTF_Plugin p = MainQuest.ResolvePluginByKey(newKey)
        if p != None
            int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(newKey))
            if itemIdx >= 0
                defParam  = p.GetEffectParamDefault(itemIdx, 1)
                defParam2 = p.GetEffectParamDefault(itemIdx, 2)
            endif
        endif
    endif
    MainQuest.SetSlotEffectFull(selectedCondition, effectIdx, newKey, defParam, defParam2)
    ; Progressive-disclosure UI: if the user just CLEARED this row, shift
    ; any subsequent configured rows up so nothing stays orphaned beyond
    ; the trailing "Not set" slot.
    if newKey == ""
        MainQuest.CompactEffectsAfter(selectedCondition, effectIdx)
    endif
EndFunction

; ── Unified effect-param dispatcher family (v0.2.1) ────────────────────────
; Single set of handlers for paramN (n = 1..5). Replaces the previous three
; parallel families (param / param2 / extras × open/accept/default/highlight/
; menu-open/menu-accept). MCM state blocks pass their position index n to
; these and we read the right .paramN.* fields off the plugin via the
; unified MTF_Plugin getters.

string Function _menuLabelForParam(MTF_Plugin p, int itemIdx, int n, string curId)
{v0.2.9: look up the menu label whose `id` matches `curId` for paramN of
 effect `itemIdx`. Falls back to "Custom: <id>" when no match — supports
 hand-edited preset JSONs with unknown ids.}
    int cnt = p.GetEffectParamMenuOptionCount(itemIdx, n)
    int i = 0
    while i < cnt
        if p.GetEffectParamMenuOptionId(itemIdx, n, i) == curId
            return p.GetEffectParamMenuOptionLabel(itemIdx, n, i)
        endif
        i += 1
    endwhile
    if curId == ""
        return "(unset)"
    endif
    return "Custom: " + curId
EndFunction

Function _openEffectParam(int effectIdx, int n)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    SetSliderDialogStartValue(MainQuest.GetSlotEffectParamN(selectedCondition, effectIdx, n))
    SetSliderDialogDefaultValue(p.GetEffectParamDefault(itemIdx, n))
    SetSliderDialogRange(p.GetEffectParamMin(itemIdx, n), p.GetEffectParamMax(itemIdx, n))
    int step = p.GetEffectParamStep(itemIdx, n)
    if step < 1
        step = 1
    endif
    SetSliderDialogInterval(step)
EndFunction

Function _acceptEffectParam(int effectIdx, int n, float value)
    MainQuest.SetSlotEffectParamN(selectedCondition, effectIdx, n, value as int)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    string fmt = "{0}"
    if p != None
        int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            fmt = p.GetEffectParamFormat(itemIdx, n)
        endif
    endif
    SetSliderOptionValueST(value as int, fmt)
EndFunction

Function _defaultEffectParam(int effectIdx, int n)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    int menuCnt = 0
    bool isText = false
    int itemIdx = -1
    string fmt = "{0}"
    if p != None
        itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            isText  = p.GetEffectParamIsText(itemIdx, n)
            menuCnt = p.GetEffectParamMenuOptionCount(itemIdx, n)
            fmt     = p.GetEffectParamFormat(itemIdx, n)
        endif
    endif
    if isText && p != None && itemIdx >= 0
        ; v0.3.x: text default is a string (may be empty).
        string defText = p.GetEffectParamDefaultId(itemIdx, n)
        MainQuest.SetSlotEffectParamNStr(selectedCondition, effectIdx, n, defText)
        MainQuest.SetSlotEffectParamN(selectedCondition, effectIdx, n, 0)
        SetInputOptionValueST(_textRowLabel(defText))
    elseif menuCnt > 0 && p != None && itemIdx >= 0
        ; v0.2.9: menu default is a string id.
        string defId = p.GetEffectParamDefaultId(itemIdx, n)
        MainQuest.SetSlotEffectParamNStr(selectedCondition, effectIdx, n, defId)
        MainQuest.SetSlotEffectParamN(selectedCondition, effectIdx, n, 0)
        SetMenuOptionValueST(_menuLabelForParam(p, itemIdx, n, defId))
    else
        int defVal = 0
        if p != None && itemIdx >= 0
            defVal = p.GetEffectParamDefault(itemIdx, n)
        endif
        MainQuest.SetSlotEffectParamN(selectedCondition, effectIdx, n, defVal)
        MainQuest.SetSlotEffectParamNStr(selectedCondition, effectIdx, n, "")
        SetSliderOptionValueST(defVal, fmt)
    endif
EndFunction

; ── v0.3.x: text-input param helpers ───────────────────────────────────────
; Free-text params open SkyUI's input dialog (Skyrim's on-screen keyboard +
; controller-friendly text entry). The text is stored as the string-id
; variant via SetSlotEffectParamNStr — same storage slot menu params use.
; The int slot is cleared so a switch from text → slider doesn't leave a
; stale numeric residue.

Function _openEffectParamInput(int effectIdx, int n)
    SetInputDialogStartText(MainQuest.GetSlotEffectParamNStr(selectedCondition, effectIdx, n))
EndFunction

Function _acceptEffectParamInput(int effectIdx, int n, string text)
    MainQuest.SetSlotEffectParamNStr(selectedCondition, effectIdx, n, text)
    MainQuest.SetSlotEffectParamN(selectedCondition, effectIdx, n, 0)
    SetInputOptionValueST(_textRowLabel(text))
EndFunction

; Truncate long text for the MCM row display. Empty -> "(empty)" so the
; row visibly reads as unset rather than a blank widget. Soft cap matches
; the menu-label width budget (no widget word-wrap; SkyUI clips silently).
string Function _textRowLabel(string s) global
    if s == ""
        return "(empty)"
    endif
    int maxL = 40
    if StringUtil.GetLength(s) > maxL
        return StringUtil.Substring(s, 0, maxL - 3) + "..."
    endif
    return s
EndFunction

Function _openEffectParamMenu(int effectIdx, int n)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int cnt = p.GetEffectParamMenuOptionCount(itemIdx, n)
    if cnt <= 0
        return
    endif
    ; v0.2.9: menu params store id strings (was int positions).
    string curId      = MainQuest.GetSlotEffectParamNStr(selectedCondition, effectIdx, n)
    string defaultId  = p.GetEffectParamDefaultId(itemIdx, n)
    string[] labels   = _newOpts(cnt)
    int curSel = 0
    int defaultSel = 0
    int i = 0
    while i < cnt
        string optId = p.GetEffectParamMenuOptionId(itemIdx, n, i)
        labels[i]    = p.GetEffectParamMenuOptionLabel(itemIdx, n, i)
        if optId == curId
            curSel = i
        endif
        if optId == defaultId
            defaultSel = i
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(curSel)
    SetMenuDialogDefaultIndex(defaultSel)
    SetMenuDialogOptions(labels)
EndFunction

Function _acceptEffectParamMenu(int effectIdx, int n, int index)
    if index < 0
        return
    endif
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int cnt = p.GetEffectParamMenuOptionCount(itemIdx, n)
    if index >= cnt
        return
    endif
    string newId = p.GetEffectParamMenuOptionId(itemIdx, n, index)
    string label = p.GetEffectParamMenuOptionLabel(itemIdx, n, index)
    MainQuest.SetSlotEffectParamNStr(selectedCondition, effectIdx, n, newId)
    MainQuest.SetSlotEffectParamN(selectedCondition, effectIdx, n, 0)  ; clear int slot
    SetMenuOptionValueST(label)
EndFunction

Function _highlightEffectParam(int effectIdx, int n)
    string key = MainQuest.GetSlotEffectKey(selectedCondition, effectIdx)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p != None
        int itemIdx = MainQuest._effectIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx >= 0
            SetInfoText(p.GetEffectParamLabel(itemIdx, n))
            return
        endif
    endif
    SetInfoText("Effect parameter " + n + ".")
EndFunction

; ── Per-condition param menu helpers ─────────────────────────────────────────
; Mirror the effect-side helpers above. Lets conditions declare dropdowns
; via GetConditionParamMenuOption* and have the MCM render them as menus
; (matching how the SkyrimNet bridge already resolves them in descriptions).

string Function _menuLabelForCondParam(MTF_Plugin p, int itemIdx, string curId)
    int n = p.GetConditionParamMenuOptionCount(itemIdx)
    int i = 0
    while i < n
        if p.GetConditionParamMenuOptionId(itemIdx, i) == curId
            return p.GetConditionParamMenuOptionLabel(itemIdx, i)
        endif
        i += 1
    endwhile
    if curId == ""
        return "(unset)"
    endif
    return "Custom: " + curId
EndFunction

string Function _menuLabelForCondParam2(MTF_Plugin p, int itemIdx, string curId)
    int n = p.GetConditionParam2MenuOptionCount(itemIdx)
    int i = 0
    while i < n
        if p.GetConditionParam2MenuOptionId(itemIdx, i) == curId
            return p.GetConditionParam2MenuOptionLabel(itemIdx, i)
        endif
        i += 1
    endwhile
    if curId == ""
        return "(unset)"
    endif
    return "Custom: " + curId
EndFunction

; ── v0.3.0 second-condition (index 1) MCM support ───────────────────────────
string Function _condOpLabel(int op)
    if op == 1
        return "OR (any)"
    endif
    return "AND (all)"
endFunction

; Index-1 mirrors of the cond param-menu helpers. Same logic, but read/write
; through the .At(slot, 1) accessors and compute the dialog start index inline.
Function _openCond2ParamMenu()
    string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetConditionParamMenuOptionCount(itemIdx)
    if n <= 0
        return
    endif
    string curId = MainQuest.GetCondParamStrAt(selectedCondition, 1)
    string[] opts = _newOpts(n)
    int cur = 0
    int i = 0
    while i < n
        opts[i] = p.GetConditionParamMenuOptionLabel(itemIdx, i)
        if p.GetConditionParamMenuOptionId(itemIdx, i) == curId
            cur = i
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(cur)
    SetMenuDialogDefaultIndex(0)
    SetMenuDialogOptions(opts)
EndFunction

Function _acceptCond2ParamMenu(int index)
    if index < 0
        return
    endif
    string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetConditionParamMenuOptionCount(itemIdx)
    if index >= n
        return
    endif
    string newId = p.GetConditionParamMenuOptionId(itemIdx, index)
    MainQuest.SetCondParamStrAt(selectedCondition, 1, newId)
    MainQuest.SetCondParamAt(selectedCondition, 1, 0)
    SetMenuOptionValueST(p.GetConditionParamMenuOptionLabel(itemIdx, index))
EndFunction

Function _openCond2Param2Menu()
    string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetConditionParam2MenuOptionCount(itemIdx)
    if n <= 0
        return
    endif
    string curId = MainQuest.GetCondParam2StrAt(selectedCondition, 1)
    string[] opts = _newOpts(n)
    int cur = 0
    int i = 0
    while i < n
        opts[i] = p.GetConditionParam2MenuOptionLabel(itemIdx, i)
        if p.GetConditionParam2MenuOptionId(itemIdx, i) == curId
            cur = i
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(cur)
    SetMenuDialogDefaultIndex(0)
    SetMenuDialogOptions(opts)
EndFunction

Function _acceptCond2Param2Menu(int index)
    if index < 0
        return
    endif
    string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetConditionParam2MenuOptionCount(itemIdx)
    if index >= n
        return
    endif
    string newId = p.GetConditionParam2MenuOptionId(itemIdx, index)
    MainQuest.SetCondParam2StrAt(selectedCondition, 1, newId)
    MainQuest.SetCondParam2At(selectedCondition, 1, 0)
    SetMenuOptionValueST(p.GetConditionParam2MenuOptionLabel(itemIdx, index))
EndFunction

; Condition #2 type picker. Mirrors SLOT_COND_TYPE but writes index 1 and
; maintains the slot's condition count (1 ⇄ 2).
state SLOT_COND2_TYPE
    event OnMenuOpenST()
        string curKey = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
        MainQuest.BuildVisibleConditionMenu(curKey)
        string[] keys   = MainQuest.menuKeys
        string[] labels = MainQuest.menuLabels
        int n = MainQuest.menuCount
        int sz = n + 1
        if sz > 127
            sz = 127
        endif
        string[] opts = _newOpts(sz)
        opts[0] = "Not set"
        int curIdx = 0
        int i = 0
        while i < n && (i + 1) < sz
            opts[i + 1] = labels[i]
            if keys[i] == curKey
                curIdx = i + 1
            endif
            i += 1
        endwhile
        SetMenuDialogStartIndex(curIdx)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(opts)
    endEvent
    event OnMenuAcceptST(int index)
        if index < 0
            return
        endif
        int slot = selectedCondition
        string newKey = ""
        if index > 0
            string[] keys = MainQuest.menuKeys
            int n = MainQuest.menuCount
            if (index - 1) < n && keys != None
                newKey = keys[index - 1]
            endif
        endif
        MainQuest.SetCondPluginIdAt(slot, 1, newKey)
        ; v0.3.2: clear cond2's param string slot too (see SLOT_COND_TYPE).
        MainQuest.SetCondParamStrAt(slot, 1, "")
        MainQuest.SetCondParam2StrAt(slot, 1, "")
        MainQuest.SetCondParamStrAt(slot, 1, "")
        MainQuest.SetCondParam2StrAt(slot, 1, "")
        if newKey == ""
            MainQuest.SetCondParamAt(slot, 1, 0)
            MainQuest.SetCondParam2At(slot, 1, 0)
            MainQuest.SetCondCount(slot, 1)
        else
            MTF_Plugin p = MainQuest.ResolvePluginByKey(newKey)
            int itemIdx = -1
            if p != None
                itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(newKey))
            endif
            if itemIdx >= 0
                MainQuest.SetCondParamAt(slot, 1, p.GetConditionParamDefault(itemIdx))
                MainQuest.SetCondParam2At(slot, 1, p.GetConditionParam2Default(itemIdx))
            else
                MainQuest.SetCondParamAt(slot, 1, 0)
                MainQuest.SetCondParam2At(slot, 1, 0)
            endif
            MainQuest.SetCondCount(slot, 2)
        endif
        SetMenuOptionValueST(_condTypeLabel(newKey))
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetCondPluginIdAt(selectedCondition, 1, "")
        MainQuest.SetCondParamStrAt(selectedCondition, 1, "")
        MainQuest.SetCondParam2StrAt(selectedCondition, 1, "")
        MainQuest.SetCondParamAt(selectedCondition, 1, 0)
        MainQuest.SetCondParam2At(selectedCondition, 1, 0)
        MainQuest.SetCondParamStrAt(selectedCondition, 1, "")
        MainQuest.SetCondParam2StrAt(selectedCondition, 1, "")
        MainQuest.SetCondCount(selectedCondition, 1)
        SetMenuOptionValueST(_condTypeLabel(""))
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Optional second condition for this slot. Combined with condition 1 via the Match mode setting.")
    endEvent
endState

state SLOT_COND2_PARAM
    event OnSliderOpenST()
        string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p == None
            return
        endif
        int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx < 0
            return
        endif
        SetSliderDialogStartValue(MainQuest.GetCondParamAt(selectedCondition, 1))
        SetSliderDialogDefaultValue(p.GetConditionParamDefault(itemIdx))
        SetSliderDialogRange(p.GetConditionParamMin(itemIdx), p.GetConditionParamMax(itemIdx))
        SetSliderDialogInterval(1)
    endEvent
    event OnSliderAcceptST(float value)
        string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        string fmt = "{0}"
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                fmt = p.GetConditionParamFormat(itemIdx)
            endif
        endif
        MainQuest.SetCondParamAt(selectedCondition, 1, value as int)
        SetSliderOptionValueST(value as int, fmt)
    endEvent
    event OnMenuOpenST()
        _openCond2ParamMenu()
    endEvent
    event OnMenuAcceptST(int index)
        _acceptCond2ParamMenu(index)
    endEvent
    event OnInputOpenST()
        SetInputDialogStartText(MainQuest.GetCondParamStrAt(selectedCondition, 1))
    endEvent
    event OnInputAcceptST(string a_input)
        MainQuest.SetCondParamStrAt(selectedCondition, 1, a_input)
        SetInputOptionValueST(_textRowLabel(a_input))
    endEvent
    event OnDefaultST()
        string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        int defVal = 0
        int menuCnt = 0
        string fmt = "{0}"
        int itemIdx = -1
        if p != None
            itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                defVal = p.GetConditionParamDefault(itemIdx)
                menuCnt = p.GetConditionParamMenuOptionCount(itemIdx)
                fmt = p.GetConditionParamFormat(itemIdx)
            endif
        endif
        if menuCnt > 0 && p != None && itemIdx >= 0
            string defId = p.GetConditionParamDefaultId(itemIdx)
            MainQuest.SetCondParamStrAt(selectedCondition, 1, defId)
            MainQuest.SetCondParamAt(selectedCondition, 1, 0)
            SetMenuOptionValueST(_menuLabelForCondParam(p, itemIdx, defId))
        else
            MainQuest.SetCondParamAt(selectedCondition, 1, defVal)
            MainQuest.SetCondParamStrAt(selectedCondition, 1, "")
            SetSliderOptionValueST(defVal, fmt)
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Threshold value for condition 2.")
    endEvent
endState

state SLOT_COND2_PARAM2
    event OnSliderOpenST()
        string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        if p == None
            return
        endif
        int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
        if itemIdx < 0
            return
        endif
        SetSliderDialogStartValue(MainQuest.GetCondParam2At(selectedCondition, 1))
        SetSliderDialogDefaultValue(p.GetConditionParam2Default(itemIdx))
        SetSliderDialogRange(p.GetConditionParam2Min(itemIdx), p.GetConditionParam2Max(itemIdx))
        SetSliderDialogInterval(p.GetConditionParam2Step(itemIdx))
    endEvent
    event OnSliderAcceptST(float value)
        string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        string fmt = "{0}"
        if p != None
            int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                fmt = p.GetConditionParam2Format(itemIdx)
            endif
        endif
        MainQuest.SetCondParam2At(selectedCondition, 1, value as int)
        SetSliderOptionValueST(value as int, fmt)
    endEvent
    event OnMenuOpenST()
        _openCond2Param2Menu()
    endEvent
    event OnMenuAcceptST(int index)
        _acceptCond2Param2Menu(index)
    endEvent
    event OnDefaultST()
        string key = MainQuest.GetCondPluginIdAt(selectedCondition, 1)
        MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
        int defVal = 0
        int menuCnt = 0
        string fmt = "{0}"
        int itemIdx = -1
        if p != None
            itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
            if itemIdx >= 0
                defVal = p.GetConditionParam2Default(itemIdx)
                menuCnt = p.GetConditionParam2MenuOptionCount(itemIdx)
                fmt = p.GetConditionParam2Format(itemIdx)
            endif
        endif
        if menuCnt > 0 && p != None && itemIdx >= 0
            string defId2 = p.GetConditionParam2DefaultId(itemIdx)
            MainQuest.SetCondParam2StrAt(selectedCondition, 1, defId2)
            MainQuest.SetCondParam2At(selectedCondition, 1, 0)
            SetMenuOptionValueST(_menuLabelForCondParam2(p, itemIdx, defId2))
        else
            MainQuest.SetCondParam2At(selectedCondition, 1, defVal)
            MainQuest.SetCondParam2StrAt(selectedCondition, 1, "")
            SetSliderOptionValueST(defVal, fmt)
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Second threshold for condition 2 (if it has one).")
    endEvent
endState

state SLOT_COND_OP
    event OnMenuOpenST()
        string[] opts = _newOpts(2)
        opts[0] = "AND (all)"
        opts[1] = "OR (any)"
        SetMenuDialogOptions(opts)
        SetMenuDialogStartIndex(MainQuest.GetCondOp(selectedCondition))
        SetMenuDialogDefaultIndex(0)
    endEvent
    event OnMenuAcceptST(int index)
        if index < 0
            return
        endif
        MainQuest.SetCondOp(selectedCondition, index)
        SetMenuOptionValueST(_condOpLabel(index))
    endEvent
    event OnDefaultST()
        MainQuest.SetCondOp(selectedCondition, 0)
        SetMenuOptionValueST(_condOpLabel(0))
    endEvent
    event OnHighlightST()
        SetInfoText("AND = every condition in this slot must pass. OR = any one passing activates the slot.")
    endEvent
endState

Function _openCondParamMenu()
    string key = MainQuest.GetCondPluginId(selectedCondition)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetConditionParamMenuOptionCount(itemIdx)
    if n <= 0
        return
    endif
    ; v0.2.9: menu params store id strings.
    string curId     = MainQuest.GetCondParamStr(selectedCondition)
    string defaultId = p.GetConditionParamDefaultId(itemIdx)
    string[] labels = _newOpts(n)
    int curSel = 0
    int defaultSel = 0
    int i = 0
    while i < n
        string optId = p.GetConditionParamMenuOptionId(itemIdx, i)
        string label = p.GetConditionParamMenuOptionLabel(itemIdx, i)
        labels[i] = label
        if optId == curId
            curSel = i
        endif
        if optId == defaultId
            defaultSel = i
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(curSel)
    SetMenuDialogDefaultIndex(defaultSel)
    SetMenuDialogOptions(labels)
EndFunction

Function _acceptCondParamMenu(int index)
    if index < 0
        return
    endif
    string key = MainQuest.GetCondPluginId(selectedCondition)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetConditionParamMenuOptionCount(itemIdx)
    if index >= n
        return
    endif
    string newId = p.GetConditionParamMenuOptionId(itemIdx, index)
    string label = p.GetConditionParamMenuOptionLabel(itemIdx, index)
    MainQuest.SetCondParamStr(selectedCondition, newId)
    MainQuest.SetCondParam(selectedCondition, 0)
    SetMenuOptionValueST(label)
EndFunction

Function _openCondParam2Menu()
    string key = MainQuest.GetCondPluginId(selectedCondition)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetConditionParam2MenuOptionCount(itemIdx)
    if n <= 0
        return
    endif
    string curId     = MainQuest.GetCondParam2Str(selectedCondition)
    string defaultId = p.GetConditionParam2DefaultId(itemIdx)
    string[] labels = _newOpts(n)
    int curSel = 0
    int defaultSel = 0
    int i = 0
    while i < n
        string optId = p.GetConditionParam2MenuOptionId(itemIdx, i)
        string label = p.GetConditionParam2MenuOptionLabel(itemIdx, i)
        labels[i] = label
        if optId == curId
            curSel = i
        endif
        if optId == defaultId
            defaultSel = i
        endif
        i += 1
    endwhile
    SetMenuDialogStartIndex(curSel)
    SetMenuDialogDefaultIndex(defaultSel)
    SetMenuDialogOptions(labels)
EndFunction

Function _acceptCondParam2Menu(int index)
    if index < 0
        return
    endif
    string key = MainQuest.GetCondPluginId(selectedCondition)
    MTF_Plugin p = MainQuest.ResolvePluginByKey(key)
    if p == None
        return
    endif
    int itemIdx = MainQuest._condIdxFor(p, MainQuest._keyItemId(key))
    if itemIdx < 0
        return
    endif
    int n = p.GetConditionParam2MenuOptionCount(itemIdx)
    if index >= n
        return
    endif
    string newId = p.GetConditionParam2MenuOptionId(itemIdx, index)
    string label = p.GetConditionParam2MenuOptionLabel(itemIdx, index)
    MainQuest.SetCondParam2Str(selectedCondition, newId)
    MainQuest.SetCondParam2(selectedCondition, 0)
    SetMenuOptionValueST(label)
EndFunction

; (v0.2.1: old _openEffectParam[Menu] / _acceptEffectParam[Menu] /
; _highlightEffectParam / _openEffectParam2[Menu] / _acceptEffectParam2[Menu] /
; _defaultEffectParam2 / _highlightEffectParam2 — all 9 functions — removed.
; State blocks now call into the unified _openEffectParam(slot, n) family
; defined above with n=1 for the legacy primary slider and n=2 for the
; legacy secondary slider.)

state SLOT_EFFECT_1_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(0)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(0, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 0, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins. The effect fires while this slot is the winning tier.")
    endEvent
endState

state SLOT_EFFECT_1_P1
    event OnSliderOpenST()
        _openEffectParam(0, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(0, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(0, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(0, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(0, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(0, 1)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(0, 1)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(0, 1, text)
    endEvent
endState

state SLOT_EFFECT_2_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(1, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 1, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_2_P1
    event OnSliderOpenST()
        _openEffectParam(1, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(1, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(1, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(1, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(1, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(1, 1)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(1, 1)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(1, 1, text)
    endEvent
endState

state SLOT_EFFECT_3_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(2, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 2, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_3_P1
    event OnSliderOpenST()
        _openEffectParam(2, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(2, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(2, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(2, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(2, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(2, 1)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(2, 1)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(2, 1, text)
    endEvent
endState

state SLOT_EFFECT_4_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(3, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 3, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_4_P1
    event OnSliderOpenST()
        _openEffectParam(3, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(3, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(3, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(3, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(3, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(3, 1)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(3, 1)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(3, 1, text)
    endEvent
endState

; ── Per-effect param2 states (only shown when effect declares param2) ───────
state SLOT_EFFECT_1_P2
    event OnSliderOpenST()
        _openEffectParam(0, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(0, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(0, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(0, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(0, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(0, 2)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(0, 2)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(0, 2, text)
    endEvent
endState

state SLOT_EFFECT_2_P2
    event OnSliderOpenST()
        _openEffectParam(1, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(1, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(1, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(1, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(1, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(1, 2)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(1, 2)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(1, 2, text)
    endEvent
endState

state SLOT_EFFECT_3_P2
    event OnSliderOpenST()
        _openEffectParam(2, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(2, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(2, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(2, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(2, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(2, 2)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(2, 2)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(2, 2, text)
    endEvent
endState

state SLOT_EFFECT_4_P2
    event OnSliderOpenST()
        _openEffectParam(3, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(3, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(3, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(3, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(3, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(3, 2)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(3, 2)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(3, 2, text)
    endEvent
endState

; ── Rows 5-8 TYPE/P1/P2 (v0.1.24, parity completed v0.2.2) ─────────────────
; Added in v0.1.24 to raise MAX_EFFECTS_PER_SLOT_MCM from 4 to 8.
; Originally shipped without P3/P4/P5 because of the SkyUI 127-named-state
; ceiling; the P3-P5 blocks for these rows now live further down (after
; SLOT_EFFECT_4_P5) and rows 5-8 are at full parity with 1-4.

state SLOT_EFFECT_5_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(4, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 4, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_5_P1
    event OnSliderOpenST()
        _openEffectParam(4, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(4, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(4, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(4, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(4, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(4, 1)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(4, 1)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(4, 1, text)
    endEvent
endState

state SLOT_EFFECT_5_P2
    event OnSliderOpenST()
        _openEffectParam(4, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(4, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(4, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(4, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(4, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(4, 2)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(4, 2)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(4, 2, text)
    endEvent
endState

state SLOT_EFFECT_6_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(5, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 5, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_6_P1
    event OnSliderOpenST()
        _openEffectParam(5, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(5, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(5, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(5, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(5, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(5, 1)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(5, 1)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(5, 1, text)
    endEvent
endState

state SLOT_EFFECT_6_P2
    event OnSliderOpenST()
        _openEffectParam(5, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(5, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(5, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(5, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(5, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(5, 2)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(5, 2)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(5, 2, text)
    endEvent
endState

state SLOT_EFFECT_7_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(6)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(6, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 6, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_7_P1
    event OnSliderOpenST()
        _openEffectParam(6, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(6, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(6, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(6, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(6, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(6, 1)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(6, 1)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(6, 1, text)
    endEvent
endState

state SLOT_EFFECT_7_P2
    event OnSliderOpenST()
        _openEffectParam(6, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(6, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(6, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(6, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(6, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(6, 2)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(6, 2)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(6, 2, text)
    endEvent
endState

state SLOT_EFFECT_8_TYPE
    event OnMenuOpenST()
        _openEffectTypeMenu(7)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectType(7, index)
        ForcePageReset()
    endEvent
    event OnDefaultST()
        MainQuest.SetSlotEffect(selectedCondition, 7, "", 0)
        ForcePageReset()
    endEvent
    event OnHighlightST()
        SetInfoText("Pick an effect from the registered effect plugins.")
    endEvent
endState

state SLOT_EFFECT_8_P1
    event OnSliderOpenST()
        _openEffectParam(7, 1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(7, 1, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(7, 1)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(7, 1, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(7, 1)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(7, 1)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(7, 1)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(7, 1, text)
    endEvent
endState

state SLOT_EFFECT_8_P2
    event OnSliderOpenST()
        _openEffectParam(7, 2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(7, 2, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(7, 2)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(7, 2, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(7, 2)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(7, 2)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(7, 2)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(7, 2, text)
    endEvent
endState

; (v0.2.1: old _openEffectExtra / _acceptEffectExtra / _defaultEffectExtra /
; _highlightEffectExtra / _openEffectExtraMenu / _acceptEffectExtraMenu /
; _getEffectExtraFieldName / _menuLabelForExtra — 8 functions — removed.
; The former EX1/EX2/EX3 state blocks now route to the unified
; _openEffectParam(slot, n) family with n=3/4/5 — see uniform paramN
; refactor at top of file.)

state SLOT_EFFECT_1_P3
    event OnSliderOpenST()
        _openEffectParam(0, 3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(0, 3, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(0, 3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(0, 3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(0, 3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(0, 3)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(0, 3)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(0, 3, text)
    endEvent
endState

state SLOT_EFFECT_1_P4
    event OnSliderOpenST()
        _openEffectParam(0, 4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(0, 4, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(0, 4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(0, 4, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(0, 4)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(0, 4)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(0, 4)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(0, 4, text)
    endEvent
endState

state SLOT_EFFECT_1_P5
    event OnSliderOpenST()
        _openEffectParam(0, 5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(0, 5, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(0, 5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(0, 5, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(0, 5)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(0, 5)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(0, 5)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(0, 5, text)
    endEvent
endState

state SLOT_EFFECT_2_P3
    event OnSliderOpenST()
        _openEffectParam(1, 3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(1, 3, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(1, 3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(1, 3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(1, 3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(1, 3)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(1, 3)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(1, 3, text)
    endEvent
endState

state SLOT_EFFECT_2_P4
    event OnSliderOpenST()
        _openEffectParam(1, 4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(1, 4, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(1, 4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(1, 4, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(1, 4)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(1, 4)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(1, 4)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(1, 4, text)
    endEvent
endState

state SLOT_EFFECT_2_P5
    event OnSliderOpenST()
        _openEffectParam(1, 5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(1, 5, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(1, 5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(1, 5, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(1, 5)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(1, 5)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(1, 5)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(1, 5, text)
    endEvent
endState

state SLOT_EFFECT_3_P3
    event OnSliderOpenST()
        _openEffectParam(2, 3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(2, 3, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(2, 3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(2, 3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(2, 3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(2, 3)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(2, 3)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(2, 3, text)
    endEvent
endState

state SLOT_EFFECT_3_P4
    event OnSliderOpenST()
        _openEffectParam(2, 4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(2, 4, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(2, 4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(2, 4, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(2, 4)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(2, 4)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(2, 4)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(2, 4, text)
    endEvent
endState

state SLOT_EFFECT_3_P5
    event OnSliderOpenST()
        _openEffectParam(2, 5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(2, 5, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(2, 5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(2, 5, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(2, 5)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(2, 5)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(2, 5)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(2, 5, text)
    endEvent
endState

state SLOT_EFFECT_4_P3
    event OnSliderOpenST()
        _openEffectParam(3, 3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(3, 3, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(3, 3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(3, 3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(3, 3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(3, 3)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(3, 3)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(3, 3, text)
    endEvent
endState

state SLOT_EFFECT_4_P4
    event OnSliderOpenST()
        _openEffectParam(3, 4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(3, 4, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(3, 4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(3, 4, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(3, 4)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(3, 4)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(3, 4)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(3, 4, text)
    endEvent
endState

state SLOT_EFFECT_4_P5
    event OnSliderOpenST()
        _openEffectParam(3, 5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(3, 5, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(3, 5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(3, 5, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(3, 5)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(3, 5)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(3, 5)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(3, 5, text)
    endEvent
endState

; ── Rows 5-8 paramN states (P3/P4/P5) ───────────────────────────────────────
; Added in v0.2.2 once the MCM state budget recovery (subjects-page drop +
; plugin pagination + plugin-level settings drop) opened enough headroom to
; bring slots 5-8 to parity with 1-4. Pure mechanical copies of the slot
; 1-4 P3/P4/P5 blocks at different slot indices (4..7).

state SLOT_EFFECT_5_P3
    event OnSliderOpenST()
        _openEffectParam(4, 3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(4, 3, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(4, 3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(4, 3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(4, 3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(4, 3)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(4, 3)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(4, 3, text)
    endEvent
endState

state SLOT_EFFECT_5_P4
    event OnSliderOpenST()
        _openEffectParam(4, 4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(4, 4, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(4, 4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(4, 4, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(4, 4)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(4, 4)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(4, 4)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(4, 4, text)
    endEvent
endState

state SLOT_EFFECT_5_P5
    event OnSliderOpenST()
        _openEffectParam(4, 5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(4, 5, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(4, 5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(4, 5, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(4, 5)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(4, 5)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(4, 5)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(4, 5, text)
    endEvent
endState

state SLOT_EFFECT_6_P3
    event OnSliderOpenST()
        _openEffectParam(5, 3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(5, 3, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(5, 3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(5, 3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(5, 3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(5, 3)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(5, 3)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(5, 3, text)
    endEvent
endState

state SLOT_EFFECT_6_P4
    event OnSliderOpenST()
        _openEffectParam(5, 4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(5, 4, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(5, 4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(5, 4, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(5, 4)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(5, 4)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(5, 4)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(5, 4, text)
    endEvent
endState

state SLOT_EFFECT_6_P5
    event OnSliderOpenST()
        _openEffectParam(5, 5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(5, 5, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(5, 5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(5, 5, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(5, 5)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(5, 5)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(5, 5)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(5, 5, text)
    endEvent
endState

state SLOT_EFFECT_7_P3
    event OnSliderOpenST()
        _openEffectParam(6, 3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(6, 3, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(6, 3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(6, 3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(6, 3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(6, 3)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(6, 3)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(6, 3, text)
    endEvent
endState

state SLOT_EFFECT_7_P4
    event OnSliderOpenST()
        _openEffectParam(6, 4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(6, 4, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(6, 4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(6, 4, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(6, 4)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(6, 4)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(6, 4)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(6, 4, text)
    endEvent
endState

state SLOT_EFFECT_7_P5
    event OnSliderOpenST()
        _openEffectParam(6, 5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(6, 5, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(6, 5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(6, 5, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(6, 5)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(6, 5)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(6, 5)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(6, 5, text)
    endEvent
endState

state SLOT_EFFECT_8_P3
    event OnSliderOpenST()
        _openEffectParam(7, 3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(7, 3, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(7, 3)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(7, 3, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(7, 3)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(7, 3)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(7, 3)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(7, 3, text)
    endEvent
endState

state SLOT_EFFECT_8_P4
    event OnSliderOpenST()
        _openEffectParam(7, 4)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(7, 4, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(7, 4)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(7, 4, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(7, 4)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(7, 4)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(7, 4)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(7, 4, text)
    endEvent
endState

state SLOT_EFFECT_8_P5
    event OnSliderOpenST()
        _openEffectParam(7, 5)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptEffectParam(7, 5, value)
    endEvent
    event OnMenuOpenST()
        _openEffectParamMenu(7, 5)
    endEvent
    event OnMenuAcceptST(int index)
        _acceptEffectParamMenu(7, 5, index)
    endEvent
    event OnDefaultST()
        _defaultEffectParam(7, 5)
    endEvent
    event OnHighlightST()
        _highlightEffectParam(7, 5)
    endEvent
    event OnInputOpenST()
        _openEffectParamInput(7, 5)
    endEvent
    event OnInputAcceptST(string text)
        _acceptEffectParamInput(7, 5, text)
    endEvent
endState

; ── Per-layer visual states (slot * MAX_LAYERS + layer indexing) ─────────────
; Each layer of the picked entry gets its own Tint/Emissive/EmissiveMult/Alpha.
; State blocks below are mechanical wrappers around 4 helper functions that
; route through the StorageUtil-backed (slot, L) accessors on MainQuest
; (v0.2.8 — the legacy _layerArrIdx flat-index helper was retired).

Function _openLayerTint(int L)
    SetColorDialogStartColor(MainQuest.GetCondLayerTint(selectedCondition, L))
    SetColorDialogDefaultColor(16777215)
EndFunction
Function _acceptLayerTint(int L, int color)
    MainQuest.SetCondLayerTint(selectedCondition, L, color)
    SetColorOptionValueST(color)
    MainQuest.setRedraw()
EndFunction
Function _defaultLayerTint(int L)
    MainQuest.SetCondLayerTint(selectedCondition, L, 16777215)
    SetColorOptionValueST(16777215)
    MainQuest.setRedraw()
EndFunction

Function _openLayerEmissive(int L)
    SetColorDialogStartColor(MainQuest.GetCondLayerEmissive(selectedCondition, L))
    SetColorDialogDefaultColor(16777215)
EndFunction
Function _acceptLayerEmissive(int L, int color)
    MainQuest.SetCondLayerEmissive(selectedCondition, L, color)
    SetColorOptionValueST(color)
    MainQuest.setRedraw()
EndFunction
Function _defaultLayerEmissive(int L)
    MainQuest.SetCondLayerEmissive(selectedCondition, L, 16777215)
    SetColorOptionValueST(16777215)
    MainQuest.setRedraw()
EndFunction

Function _openLayerEmMult(int L)
    SetSliderDialogStartValue(MainQuest.GetCondLayerEmissiveMult(selectedCondition, L))
    SetSliderDialogDefaultValue(0.0)
    SetSliderDialogRange(0.0, 25.0)
    ; v0.3.3: 0.25 interval (was 0.5) — finer control in the 0-3 glow band
    ; where it matters; the em≈0 -> invisible/black quirk makes the low end
    ; sensitive, so smaller steps help dial in a faint glow.
    SetSliderDialogInterval(0.25)
EndFunction
Function _acceptLayerEmMult(int L, float value)
    MainQuest.SetCondLayerEmissiveMult(selectedCondition, L, value)
    SetSliderOptionValueST(value, "{1}")
    MainQuest.setRedraw()
EndFunction
Function _defaultLayerEmMult(int L)
    MainQuest.SetCondLayerEmissiveMult(selectedCondition, L, 0.0)
    SetSliderOptionValueST(0.0, "{1}")
    MainQuest.setRedraw()
EndFunction

Function _openLayerAlpha(int L)
    SetSliderDialogStartValue(MainQuest.GetCondLayerAlpha(selectedCondition, L))
    SetSliderDialogDefaultValue(100)
    SetSliderDialogRange(0, 100)
    SetSliderDialogInterval(1)
EndFunction
Function _acceptLayerAlpha(int L, float value)
    MainQuest.SetCondLayerAlpha(selectedCondition, L, value as int)
    SetSliderOptionValueST(value, "{0}%")
    MainQuest.setRedraw()
EndFunction
Function _defaultLayerAlpha(int L)
    MainQuest.SetCondLayerAlpha(selectedCondition, L, 100)
    SetSliderOptionValueST(100, "{0}%")
    MainQuest.setRedraw()
EndFunction

; ── Layer 0 ──────────────────────────────────────────────────────────────────
state SLOT_L0_TINT
    event OnColorOpenST()
        _openLayerTint(0)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerTint(0, color)
    endEvent
    event OnDefaultST()
        _defaultLayerTint(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for layer 0 (typically the base mark texture).")
    endEvent
endState
state SLOT_L0_EMISSIVE
    event OnColorOpenST()
        _openLayerEmissive(0)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerEmissive(0, color)
    endEvent
    event OnDefaultST()
        _defaultLayerEmissive(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Emission (glow) color for layer 0.")
    endEvent
endState
state SLOT_L0_EM_MULT
    event OnSliderOpenST()
        _openLayerEmMult(0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerEmMult(0, value)
    endEvent
    event OnDefaultST()
        _defaultLayerEmMult(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for layer 0. 0 = no glow.")
    endEvent
endState
state SLOT_L0_ALPHA
    event OnSliderOpenST()
        _openLayerAlpha(0)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerAlpha(0, value)
    endEvent
    event OnDefaultST()
        _defaultLayerAlpha(0)
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity for layer 0.")
    endEvent
endState

; ── Layer 1 ──────────────────────────────────────────────────────────────────
state SLOT_L1_TINT
    event OnColorOpenST()
        _openLayerTint(1)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerTint(1, color)
    endEvent
    event OnDefaultST()
        _defaultLayerTint(1)
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for layer 1 (typically the glow layer).")
    endEvent
endState
state SLOT_L1_EMISSIVE
    event OnColorOpenST()
        _openLayerEmissive(1)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerEmissive(1, color)
    endEvent
    event OnDefaultST()
        _defaultLayerEmissive(1)
    endEvent
    event OnHighlightST()
        SetInfoText("Emission (glow) color for layer 1.")
    endEvent
endState
state SLOT_L1_EM_MULT
    event OnSliderOpenST()
        _openLayerEmMult(1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerEmMult(1, value)
    endEvent
    event OnDefaultST()
        _defaultLayerEmMult(1)
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for layer 1. 0 = no glow.")
    endEvent
endState
state SLOT_L1_ALPHA
    event OnSliderOpenST()
        _openLayerAlpha(1)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerAlpha(1, value)
    endEvent
    event OnDefaultST()
        _defaultLayerAlpha(1)
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity for layer 1.")
    endEvent
endState

; ── Layer 2 ──────────────────────────────────────────────────────────────────
state SLOT_L2_TINT
    event OnColorOpenST()
        _openLayerTint(2)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerTint(2, color)
    endEvent
    event OnDefaultST()
        _defaultLayerTint(2)
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for layer 2.")
    endEvent
endState
state SLOT_L2_EMISSIVE
    event OnColorOpenST()
        _openLayerEmissive(2)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerEmissive(2, color)
    endEvent
    event OnDefaultST()
        _defaultLayerEmissive(2)
    endEvent
    event OnHighlightST()
        SetInfoText("Emission color for layer 2.")
    endEvent
endState
state SLOT_L2_EM_MULT
    event OnSliderOpenST()
        _openLayerEmMult(2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerEmMult(2, value)
    endEvent
    event OnDefaultST()
        _defaultLayerEmMult(2)
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for layer 2.")
    endEvent
endState
state SLOT_L2_ALPHA
    event OnSliderOpenST()
        _openLayerAlpha(2)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerAlpha(2, value)
    endEvent
    event OnDefaultST()
        _defaultLayerAlpha(2)
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity for layer 2.")
    endEvent
endState

; ── Layer 3 ──────────────────────────────────────────────────────────────────
state SLOT_L3_TINT
    event OnColorOpenST()
        _openLayerTint(3)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerTint(3, color)
    endEvent
    event OnDefaultST()
        _defaultLayerTint(3)
    endEvent
    event OnHighlightST()
        SetInfoText("Tint color for layer 3.")
    endEvent
endState
state SLOT_L3_EMISSIVE
    event OnColorOpenST()
        _openLayerEmissive(3)
    endEvent
    event OnColorAcceptST(int color)
        _acceptLayerEmissive(3, color)
    endEvent
    event OnDefaultST()
        _defaultLayerEmissive(3)
    endEvent
    event OnHighlightST()
        SetInfoText("Emission color for layer 3.")
    endEvent
endState
state SLOT_L3_EM_MULT
    event OnSliderOpenST()
        _openLayerEmMult(3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerEmMult(3, value)
    endEvent
    event OnDefaultST()
        _defaultLayerEmMult(3)
    endEvent
    event OnHighlightST()
        SetInfoText("Glow intensity for layer 3.")
    endEvent
endState
state SLOT_L3_ALPHA
    event OnSliderOpenST()
        _openLayerAlpha(3)
    endEvent
    event OnSliderAcceptST(float value)
        _acceptLayerAlpha(3, value)
    endEvent
    event OnDefaultST()
        _defaultLayerAlpha(3)
    endEvent
    event OnHighlightST()
        SetInfoText("Opacity for layer 3.")
    endEvent
endState

; ── Helpers ───────────────────────────────────────────────────────────────────
string[] Function _newOpts(int n)
{Returns a fresh string[] sized n (or 1 if n<=1).
 Previously a literal-size dispatcher with 100+ elseif branches — that
 silently returned length-0 arrays on this VM build once the chain
 crossed ~40 branches (the same VM bug that breaks sub-function
 trampolining). With 60+ registered effects we trip the threshold and
 every Effect/Condition dropdown ends up empty.

 SKSE's Utility.CreateStringArray(n, default) handles runtime-sized
 allocation natively — same primitive we use for the per-slot effect
 arrays. Single call, no branches.}
    if n <= 1
        return new string[1]
    endif
    return Utility.CreateStringArray(n, "")
EndFunction




state PLUGIN_PAGE_PREV
    event OnSelectST()
        if _pluginsPage > 0
            _pluginsPage -= 1
            ForcePageReset()
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Previous page of registered plugins.")
    endEvent
endState

state PLUGIN_PAGE_NEXT
    event OnSelectST()
        int total = MainQuest.pluginCount
        int maxPage = 0
        if total > 0
            maxPage = (total - 1) / PLUGINS_PAGE_SIZE()
        endif
        if _pluginsPage < maxPage
            _pluginsPage += 1
            ForcePageReset()
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Next page of registered plugins.")
    endEvent
endState

state PLUGIN_TOGGLE_1
    event OnSelectST()
        _selectPluginToggle(0)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(0)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(0)
    endEvent
endState
state PLUGIN_TOGGLE_2
    event OnSelectST()
        _selectPluginToggle(1)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(1)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(1)
    endEvent
endState
state PLUGIN_TOGGLE_3
    event OnSelectST()
        _selectPluginToggle(2)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(2)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(2)
    endEvent
endState
state PLUGIN_TOGGLE_4
    event OnSelectST()
        _selectPluginToggle(3)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(3)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(3)
    endEvent
endState
state PLUGIN_TOGGLE_5
    event OnSelectST()
        _selectPluginToggle(4)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(4)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(4)
    endEvent
endState
state PLUGIN_TOGGLE_6
    event OnSelectST()
        _selectPluginToggle(5)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(5)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(5)
    endEvent
endState
state PLUGIN_TOGGLE_7
    event OnSelectST()
        _selectPluginToggle(6)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(6)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(6)
    endEvent
endState
state PLUGIN_TOGGLE_8
    event OnSelectST()
        _selectPluginToggle(7)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(7)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(7)
    endEvent
endState
state PLUGIN_TOGGLE_9
    event OnSelectST()
        _selectPluginToggle(8)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(8)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(8)
    endEvent
endState
state PLUGIN_TOGGLE_10
    event OnSelectST()
        _selectPluginToggle(9)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(9)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(9)
    endEvent
endState
state PLUGIN_TOGGLE_11
    event OnSelectST()
        _selectPluginToggle(10)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(10)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(10)
    endEvent
endState
state PLUGIN_TOGGLE_12
    event OnSelectST()
        _selectPluginToggle(11)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(11)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(11)
    endEvent
endState
state PLUGIN_TOGGLE_13
    event OnSelectST()
        _selectPluginToggle(12)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(12)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(12)
    endEvent
endState
state PLUGIN_TOGGLE_14
    event OnSelectST()
        _selectPluginToggle(13)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(13)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(13)
    endEvent
endState
state PLUGIN_TOGGLE_15
    event OnSelectST()
        _selectPluginToggle(14)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(14)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(14)
    endEvent
endState
state PLUGIN_TOGGLE_16
    event OnSelectST()
        _selectPluginToggle(15)
    endEvent
    event OnDefaultST()
        _defaultPluginToggle(15)
    endEvent
    event OnHighlightST()
        _highlightPluginToggle(15)
    endEvent
endState

; ── Presets page ─────────────────────────────────────────────────────────────
; A single MenuOption lists the saved presets; the user picks one with the
; dropdown, then clicks Load or Delete. Save creates a new preset from the
; current config. JSON files at
;   Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/<name>.json

string[] _scratchPresetNames
int      _scratchPresetCount = 0
int      _selectedPresetIdx = -1

; Tracks the preset (if any) the editor is currently editing. Set on
; successful Load and Save-as; cleared by New preset and by deleting the
; same name we were editing. Display version preserves original casing.
string _editingPresetName    = ""
string _editingPresetDisplay = ""

function _refreshPresetNames()
    ; Visible-only: load-test/diagnostic presets flagged ".hidden": 1 are
    ; kept out of the editor's Load/Delete picker (they remain runnable via
    ; the test runner, which uses the unfiltered ListPresets).
    _scratchPresetNames = MainQuest.ListVisiblePresets()
    _scratchPresetCount = MainQuest.ListVisiblePresetsCount()
    if _scratchPresetCount == 0
        _selectedPresetIdx = -1
        return
    endif
    if _selectedPresetIdx < 0 || _selectedPresetIdx >= _scratchPresetCount
        _selectedPresetIdx = 0
    endif
endFunction

string function _currentPresetLabel()
    if _scratchPresetCount == 0 || _selectedPresetIdx < 0 || _selectedPresetIdx >= _scratchPresetCount
        return "(none)"
    endif
    return MainQuest.GetPresetDisplayName(_scratchPresetNames[_selectedPresetIdx])
endFunction

string function _editingLabel()
    if _editingPresetName == ""
        return "(unsaved)"
    endif
    return _editingPresetDisplay
endFunction

Function _setEditing(string sanitized, string display)
    _editingPresetName = sanitized
    _editingPresetDisplay = display
EndFunction

Function _clearEditing()
    _editingPresetName = ""
    _editingPresetDisplay = ""
EndFunction

; Returns -1 if no preset with this sanitized filename exists.
int Function _findPresetIndex(string sanitized)
    int i = 0
    while i < _scratchPresetCount
        if _scratchPresetNames[i] == sanitized
            return i
        endif
        i += 1
    endwhile
    return -1
EndFunction

; Loads the named preset, refreshes editor state, and refreshes the page.
; Returns false on JSON read failure.
bool Function _doLoadPreset(string sanitized)
    if !MainQuest.LoadPreset(sanitized)
        return false
    endif
    string disp = MainQuest.GetPresetDisplayName(sanitized)
    _setEditing(sanitized, disp)
    MainQuest.setRedraw()
    ForcePageReset()
    return true
EndFunction

; "Editing: <name>" status row (disabled). Hover text reflects whether a
; preset is loaded for in-place save.
state PRESET_EDITING_STATUS
    event OnHighlightST()
        if _editingPresetName == ""
            SetInfoText("No preset is loaded for editing. Use Save as... to commit current edits as a new preset, or Load preset to bring in an existing one.")
        else
            SetInfoText("Currently editing '" + _editingPresetDisplay + "'. Click Save to overwrite, or Save as... to fork to a new name.")
        endif
    endEvent
endState

; In-place save: overwrites the currently-loaded preset. Disabled in the
; draw fn when nothing is loaded.
state PRESET_SAVE
    event OnSelectST()
        if _editingPresetName == ""
            return
        endif
        if MainQuest.SavePreset(_editingPresetDisplay)
            Debug.Notification("MTF: saved '" + _editingPresetDisplay + "'")
            ForcePageReset()
        else
            Debug.Notification("MTF: failed to save '" + _editingPresetDisplay + "'")
        endif
    endEvent
    event OnHighlightST()
        if _editingPresetName == ""
            SetInfoText("No preset is loaded. Use Save as... to create one.")
        else
            SetInfoText("Overwrite '" + _editingPresetDisplay + "' on disk with the current editor state.")
        endif
    endEvent
endState

; Save as: always creates a NEW preset. Refuses on filename collision —
; user must either pick a different name or use Save (which overwrites the
; loaded preset by its original name).
state PRESET_SAVE_AS
    event OnInputOpenST()
        SetInputDialogStartText("")
    endEvent
    event OnInputAcceptST(string a_input)
        if a_input == ""
            return
        endif
        string sanitized = MainQuest._sanitizePresetName(a_input)
        if sanitized == ""
            Debug.Notification("MTF: invalid preset name")
            return
        endif
        _refreshPresetNames()
        if _findPresetIndex(sanitized) >= 0
            Debug.Notification("MTF: '" + a_input + "' already exists — use Save, or pick another name")
            return
        endif
        if MainQuest.SavePreset(a_input)
            _setEditing(sanitized, a_input)
            Debug.Notification("MTF: saved as '" + a_input + "'")
            ForcePageReset()
        else
            Debug.Notification("MTF: failed to save '" + a_input + "'")
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Save as a NEW preset (letters/digits/_/-, max 32 chars). Fails on existing names — use Save to overwrite the loaded preset.")
    endEvent
endState

; Load picker — confirm is baked into each menu option label so a single
; click both confirms intent and triggers the load.
state PRESET_PICK
    event OnMenuOpenST()
        _refreshPresetNames()
        if _scratchPresetCount == 0
            string[] empty = new string[1]
            empty[0] = "(no presets)"
            SetMenuDialogOptions(empty)
            SetMenuDialogStartIndex(0)
            SetMenuDialogDefaultIndex(0)
            return
        endif
        int total = _scratchPresetCount + 1
        string[] opts = Utility.CreateStringArray(total, "")
        opts[0] = "Cancel"
        bool hasLoaded = (_editingPresetName != "")
        int i = 0
        while i < _scratchPresetCount
            string disp = MainQuest.GetPresetDisplayName(_scratchPresetNames[i])
            if hasLoaded
                opts[i + 1] = "Discard '" + _editingPresetDisplay + "' and load '" + disp + "'"
            else
                opts[i + 1] = "Load '" + disp + "'"
            endif
            i += 1
        endwhile
        SetMenuDialogOptions(opts)
        SetMenuDialogStartIndex(0)
        SetMenuDialogDefaultIndex(0)
    endEvent
    event OnMenuAcceptST(int a_index)
        if a_index <= 0
            return
        endif
        int idx = a_index - 1
        if idx >= _scratchPresetCount
            return
        endif
        string nm = _scratchPresetNames[idx]
        _selectedPresetIdx = idx
        if _doLoadPreset(nm)
            Debug.Notification("MTF: loaded '" + MainQuest.GetPresetDisplayName(nm) + "'")
        else
            Debug.Notification("MTF: failed to load '" + nm + "'")
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Pick a preset to load it into the editor. Current edits are replaced — Save first to keep them. Spell-applied presets stack above this base and are unaffected.")
    endEvent
endState

; Delete picker — confirm baked into each menu option label. Deleting the
; preset currently being edited clears the Editing status.
state PRESET_DEL
    event OnMenuOpenST()
        _refreshPresetNames()
        if _scratchPresetCount == 0
            string[] empty = new string[1]
            empty[0] = "(no presets to delete)"
            SetMenuDialogOptions(empty)
            SetMenuDialogStartIndex(0)
            SetMenuDialogDefaultIndex(0)
            return
        endif
        int total = _scratchPresetCount + 1
        string[] opts = Utility.CreateStringArray(total, "")
        opts[0] = "Cancel"
        int i = 0
        while i < _scratchPresetCount
            opts[i + 1] = "Delete '" + MainQuest.GetPresetDisplayName(_scratchPresetNames[i]) + "'"
            i += 1
        endwhile
        SetMenuDialogOptions(opts)
        SetMenuDialogStartIndex(0)
        SetMenuDialogDefaultIndex(0)
    endEvent
    event OnMenuAcceptST(int a_index)
        if a_index <= 0
            return
        endif
        int idx = a_index - 1
        if idx >= _scratchPresetCount
            return
        endif
        string nm = _scratchPresetNames[idx]
        string disp = MainQuest.GetPresetDisplayName(nm)
        if MainQuest.DeletePreset(nm)
            Debug.Notification("MTF: deleted '" + disp + "'")
            if nm == _editingPresetName
                _clearEditing()
            endif
            _selectedPresetIdx = -1
            ForcePageReset()
        endif
    endEvent
    event OnHighlightST()
        SetInfoText("Permanently delete a preset's JSON file. Editor state and spell-applied presets are unaffected.")
    endEvent
endState

; New preset — clears all slot/layer/effect/cooldown content and resets
; transition duration to 1.0s. Confirm baked into the second menu option.
state PRESET_NEW
    event OnMenuOpenST()
        string[] opts = Utility.CreateStringArray(2, "")
        opts[0] = "Cancel"
        if _editingPresetName == ""
            opts[1] = "Create new empty preset"
        else
            opts[1] = "Discard '" + _editingPresetDisplay + "' and create new"
        endif
        SetMenuDialogOptions(opts)
        SetMenuDialogStartIndex(0)
        SetMenuDialogDefaultIndex(0)
    endEvent
    event OnMenuAcceptST(int a_index)
        if a_index != 1
            return
        endif
        MainQuest.ResetEditor()
        _clearEditing()
        ForcePageReset()
        Debug.Notification("MTF: new empty preset")
    endEvent
    event OnHighlightST()
        SetInfoText("Clear all slot definitions, layers, effects, and transition duration to defaults. Use Save as... to commit the new preset to disk.")
    endEvent
endState

; ─── Subjects page (v0.0.33 - v0.2.0) ──────────────────────────────────────
; Removed v0.2.1 to free 19 named-state slots (SUBJ_PAGE_PREV/NEXT,
; SUBJ_CLEAR_ALL, SUBJ_ROW_0..15) for future MCM growth. Tracked actors
; (mtf.tracked FormList on MainQuest) still drive NPC dispatch and the
; lifecycle audit; cleanup of stale tracked actors now happens only via
; the Apply Tattoo spell on the target (which also adds tracking) or by
; calling MTF_MainQuest.ClearAllTrackedActors() from a script.
