Scriptname MTF_AliasPresetEventsTest extends ReferenceAlias
{Test harness alias for the MTF preset event API. Two responsibilities:

   1. Inbound result listener: receives MTF_ApplyPresetResult,
      MTF_RemovePresetResult, MTF_RemoveAllPresetsResult and forwards
      them to the owning test plugin Quest for toast-rendering.

   2. Hotkey trigger: registers DX scan code F9 (67) to open a
      UIListMenu of saved presets and fire the corresponding inbound
      MTF_ApplyPreset / MTF_RemovePreset / MTF_RemoveAllPresets event
      so the tester can drive the round-trip without needing to
      add a spell or formid.

 Hosted on a ReferenceAlias filled with PlayerRef. Standard defensive
 re-register pattern across loads so the listener and hotkey survive a
 .pex rebuild.

 NOTE: change HOTKEY_DX_F9 below if F9 clashes with another mod's
 binding. F9 is the standard "quick save" key in vanilla Skyrim, so the
 tester should re-bind quick save in OS options or pick a different
 scan code here. Defaulted to F9 because tests usually want to be
 fast/loud; testers can patch as needed.}

int Property HOTKEY_DX_F9 = 67 AutoReadOnly

Event OnInit()
    _registerAll()
EndEvent

Event OnPlayerLoadGame()
    _registerAll()
EndEvent

Function _registerAll()
    RegisterForModEvent("MTF_ApplyPresetResult",      "OnApplyResult")
    RegisterForModEvent("MTF_RemovePresetResult",     "OnRemoveResult")
    RegisterForModEvent("MTF_RemoveAllPresetsResult", "OnRemoveAllResult")
    RegisterForKey(HOTKEY_DX_F9)
EndFunction

Event OnKeyDown(int keyCode)
    if keyCode != HOTKEY_DX_F9
        return
    endif
    ; Block-key while menus are open — UIExtensions has its own modal
    ; behavior, but the F9 default collides with Skyrim's quick-save
    ; which would fire during the menu close.
    if Utility.IsInMenuMode()
        return
    endif
    _openMenu()
EndEvent

Function _openMenu()
    MTF_MainQuest mq = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if mq == None
        Debug.Notification("MTF.test: MainQuest lookup failed")
        return
    endif

    ; Crosshair target if any, else player. Mirrors MTF_ApplyTattoo's UX
    ; so the tester can A/B compare the spell-driven path vs this
    ; event-driven path.
    Actor subject = Game.GetCurrentCrosshairRef() as Actor
    if subject == None
        subject = Game.GetPlayer()
    endif

    string[] presets = mq.ListPresets()
    int count = mq.ListPresetsCount()
    if count <= 0
        Debug.Notification("MTF.test: no presets — save one in MCM first")
        return
    endif

    bool isSelf = (subject == Game.GetPlayer())
    string subjectName = subject.GetDisplayName()

    ; API-applied list snapshot
    int appliedN = mq.ApiTrackingCount(subject)
    string[] applied = Utility.CreateStringArray(64, "")
    int aN = 0
    int i = 0
    while i < appliedN && aN < 64
        string nm = mq.ApiTrackingAt(subject, i)
        if nm != ""
            applied[aN] = nm
            aN += 1
        endif
        i += 1
    endwhile

    ; Fresh (not API-applied) list
    string[] fresh = Utility.CreateStringArray(64, "")
    int fN = 0
    i = 0
    while i < count && fN < 64
        string nm = presets[i]
        if nm != "" && !mq.ApiHasTracked(subject, nm)
            fresh[fN] = nm
            fN += 1
        endif
        i += 1
    endwhile

    UIListMenu m = UIExtensions.GetMenu("UIListMenu") as UIListMenu
    if m == None
        Debug.Notification("MTF.test: UIExtensions unavailable")
        return
    endif
    m.ResetMenu()

    int HEADER_COUNT = 3
    if isSelf
        m.AddEntryItem("-   MTF Preset Event API Test (Self)   -")
    else
        m.AddEntryItem("-   MTF Preset Event API Test   -")
    endif
    m.AddEntryItem("Target: " + subjectName + " (" + aN + " applied via API)")
    m.AddEntryItem("-----------------------")

    ; REMOVE ALL row (only if there's anything to remove)
    int REMOVE_ALL_IDX = -1
    if aN > 0
        REMOVE_ALL_IDX = HEADER_COUNT
        m.AddEntryItem("[REMOVE ALL via API] (" + aN + " presets)")
    endif

    ; Per-preset REMOVE rows
    int REMOVE_BASE = HEADER_COUNT
    if REMOVE_ALL_IDX >= 0
        REMOVE_BASE = HEADER_COUNT + 1
    endif
    int idxRow = 0
    while idxRow < aN
        m.AddEntryItem("[REMOVE via API] " + mq.GetPresetDisplayName(applied[idxRow]))
        idxRow += 1
    endwhile

    ; Optional separator between sections
    int APPLY_BASE = REMOVE_BASE + aN
    if aN > 0 && fN > 0
        m.AddEntryItem("- - - - - - - - - - - -")
        APPLY_BASE += 1
    endif

    ; Per-preset APPLY rows
    idxRow = 0
    while idxRow < fN
        m.AddEntryItem("[APPLY via API] " + mq.GetPresetDisplayName(fresh[idxRow]))
        idxRow += 1
    endwhile

    m.OpenMenu(subject)
    int idx = m.GetResultInt()
    if idx < HEADER_COUNT
        return
    endif

    if REMOVE_ALL_IDX >= 0 && idx == REMOVE_ALL_IDX
        _fireRemoveAll(subject)
        return
    endif

    if idx >= REMOVE_BASE && idx < REMOVE_BASE + aN
        string removeName = applied[idx - REMOVE_BASE]
        _fireRemove(subject, removeName)
        return
    endif

    int freshIdx = idx - APPLY_BASE
    if freshIdx < 0 || freshIdx >= fN
        return  ; separator row or out of bounds
    endif
    string chosen = fresh[freshIdx]
    if chosen != ""
        _fireApply(subject, chosen)
    endif
EndFunction

Function _fireApply(Actor target, string presetName)
    int h = ModEvent.Create("MTF_ApplyPreset")
    if h == 0
        Debug.Notification("MTF.test: ModEvent.Create failed")
        return
    endif
    ModEvent.PushString(h, presetName)
    ModEvent.PushFloat(h, 0.0)
    ModEvent.PushForm(h, target as Form)
    ModEvent.Send(h)
    Debug.Notification("MTF.test: fired MTF_ApplyPreset '" + presetName + "'")
EndFunction

Function _fireRemove(Actor target, string presetName)
    int h = ModEvent.Create("MTF_RemovePreset")
    if h == 0
        return
    endif
    ModEvent.PushString(h, presetName)
    ModEvent.PushFloat(h, 0.0)
    ModEvent.PushForm(h, target as Form)
    ModEvent.Send(h)
    Debug.Notification("MTF.test: fired MTF_RemovePreset '" + presetName + "'")
EndFunction

Function _fireRemoveAll(Actor target)
    int h = ModEvent.Create("MTF_RemoveAllPresets")
    if h == 0
        return
    endif
    ModEvent.PushString(h, "")
    ModEvent.PushFloat(h, 0.0)
    ModEvent.PushForm(h, target as Form)
    ModEvent.Send(h)
    Debug.Notification("MTF.test: fired MTF_RemoveAllPresets")
EndFunction

; ── Outbound result forwarders (called when MTF emits result events) ────────

Function OnApplyResult(string strArg, float numArg, Form sender)
    MTF_Plugin_PresetEventsTest host = GetOwningQuest() as MTF_Plugin_PresetEventsTest
    if host != None
        host.HandleApplyResult(strArg, numArg, sender)
    endif
EndFunction

Function OnRemoveResult(string strArg, float numArg, Form sender)
    MTF_Plugin_PresetEventsTest host = GetOwningQuest() as MTF_Plugin_PresetEventsTest
    if host != None
        host.HandleRemoveResult(strArg, numArg, sender)
    endif
EndFunction

Function OnRemoveAllResult(string strArg, float numArg, Form sender)
    MTF_Plugin_PresetEventsTest host = GetOwningQuest() as MTF_Plugin_PresetEventsTest
    if host != None
        host.HandleRemoveAllResult(strArg, numArg, sender)
    endif
EndFunction
