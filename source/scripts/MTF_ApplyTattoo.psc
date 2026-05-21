Scriptname MTF_ApplyTattoo extends ActiveMagicEffect
{Attached to MTF_Spell_ApplyTattoo. On cast, opens a UIListMenu of saved
 presets. Target = actor under the caster's crosshair, or the caster
 themselves if no actor is targeted. Selection applies the preset to the
 subject's mtf.presets stack, or removes a currently-applied entry when
 a [REMOVE] row is chosen. Q4: same preset cannot be applied twice to
 the same subject. Pattern borrowed from OBody Next Generation's
 ShowPresetMenu.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    MTF_MainQuest mq = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if mq == None
        Debug.Notification("MTF: MainQuest lookup failed")
        return
    endif

    ; Self-cast spell, so akTarget == akCaster. Resolve actual subject via
    ; the crosshair; fall back to the caster (self-apply) if nothing aimed at.
    Actor subject = Game.GetCurrentCrosshairRef() as Actor
    if subject == None
        subject = akCaster
    endif

    _showPresetMenu(mq, subject)
EndEvent

Function _showPresetMenu(MTF_MainQuest mq, Actor subject)
    string[] presets = mq.ListPresets()
    int count = mq.ListPresetsCount()
    if count <= 0
        Debug.Notification("MTF: no presets — save one in MCM first")
        return
    endif

    bool isSelf = (subject == Game.GetPlayer())
    string subjectName = subject.GetDisplayName()

    ; Build applied/fresh split. mtf.presets is an ordered StringList per
    ; subject; we walk the saved-preset catalog and partition by membership.
    int appliedN = mq.GetActorPresetCount(subject)
    string[] applied = new string[64]
    int aN = 0
    int i = 0
    while i < appliedN && aN < 64
        string nm = mq.GetActorPresetAt(subject, i)
        if nm != ""
            applied[aN] = nm
            aN += 1
        endif
        i += 1
    endwhile

    string[] fresh = new string[64]
    int fN = 0
    i = 0
    while i < count && fN < 64
        string nm = presets[i]
        if nm != "" && !mq.HasActorPreset(subject, nm)
            fresh[fN] = nm
            fN += 1
        endif
        i += 1
    endwhile

    UIListMenu m = UIExtensions.GetMenu("UIListMenu") as UIListMenu
    if m == None
        Debug.Notification("MTF: UIExtensions unavailable")
        return
    endif
    m.ResetMenu()

    ; Header lines. The first HEADER_COUNT entries are non-actionable; a
    ; selection index below HEADER_COUNT cancels.
    int HEADER_COUNT = 3
    if isSelf
        m.AddEntryItem("-   MTF: Apply / Remove Tattoo (Self)   -")
    else
        m.AddEntryItem("-   MTF: Apply / Remove Tattoo   -")
    endif
    m.AddEntryItem("Target: " + subjectName + " (" + aN + " applied)")
    m.AddEntryItem("-----------------------")

    ; Body row 1: applied presets shown as [REMOVE] — tapping one removes it.
    int APPLIED_BASE = HEADER_COUNT
    int idxRow = 0
    while idxRow < aN
        m.AddEntryItem("[REMOVE] " + mq.GetPresetDisplayName(applied[idxRow]))
        idxRow += 1
    endwhile

    ; Optional separator between sections.
    int FRESH_BASE = APPLIED_BASE + aN
    if aN > 0 && fN > 0
        m.AddEntryItem("- - - - - - - - - - - -")
        FRESH_BASE += 1
    endif

    ; Body row 2: fresh presets — tapping one applies it.
    idxRow = 0
    while idxRow < fN
        m.AddEntryItem(mq.GetPresetDisplayName(fresh[idxRow]))
        idxRow += 1
    endwhile

    m.OpenMenu(subject)
    int idx = m.GetResultInt()
    if idx < APPLIED_BASE
        return
    endif

    if idx < APPLIED_BASE + aN
        ; Remove row
        string removeName = applied[idx - APPLIED_BASE]
        mq.RemoveAppliedPreset(subject, removeName)
        Debug.Notification("MTF: removed '" + mq.GetPresetDisplayName(removeName) + "' from " + subjectName)
        return
    endif

    int freshIdx = idx - FRESH_BASE
    if freshIdx < 0 || freshIdx >= fN
        return  ; separator row or out of bounds
    endif
    string chosen = fresh[freshIdx]
    if chosen == ""
        return
    endif
    _apply(mq, subject, chosen)
EndFunction

Function _apply(MTF_MainQuest mq, Actor subject, string presetName)
    string nm = subject.GetDisplayName()
    int rc = mq.AddAppliedPreset(subject, presetName)
    string disp = mq.GetPresetDisplayName(presetName)
    if rc == 1
        Debug.Notification("MTF: applied '" + disp + "' to " + nm)
    elseif rc == 0
        Debug.Notification("MTF: '" + disp + "' already on " + nm)
    elseif rc == -3
        Debug.Notification("MTF: tracked-subject cap reached")
    elseif rc == -5
        Debug.Notification("MTF: preset '" + presetName + "' invalid")
    elseif rc == -6
        Debug.Notification("MTF: no overlay slots free on " + nm)
    elseif rc == -7
        Debug.Notification("MTF: '" + disp + "' would render truncated on " + nm + " — free overlay slots first")
    endif
EndFunction
