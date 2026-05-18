Scriptname MTF_ApplyTattoo extends ActiveMagicEffect
{Attached to MTF_Spell_ApplyTattoo. On cast, opens a UIListMenu of saved
 presets. Target = actor under the caster's crosshair, or the caster
 themselves if no actor is targeted. Selection applies the preset:
   - To an NPC: AddTrackedActor (subject system).
   - To self:   LoadPreset (overwrites the player's live MCM config).
 Pattern borrowed from OBody Next Generation's ShowPresetMenu.}

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
    string current = ""
    if !isSelf
        current = mq.GetActorPreset(subject)
        if current == ""
            current = "(none)"
        endif
    endif

    UIListMenu m = UIExtensions.GetMenu("UIListMenu") as UIListMenu
    if m == None
        Debug.Notification("MTF: UIExtensions unavailable")
        return
    endif
    m.ResetMenu()

    ; First 4 entries are headers — selection index < HEADER_COUNT = cancel.
    int HEADER_COUNT = 4
    m.AddEntryItem("-   MTF: Apply Tattoo   -")
    if isSelf
        m.AddEntryItem("Target: " + subjectName + " (Self)")
        m.AddEntryItem("")
    else
        m.AddEntryItem("Target: " + subjectName)
        m.AddEntryItem("Current: " + current)
    endif
    m.AddEntryItem("-----------------------")

    int i = 0
    while i < count
        m.AddEntryItem(presets[i])
        i += 1
    endwhile

    m.OpenMenu(subject)
    int idx = m.GetResultInt()
    if idx < HEADER_COUNT
        return
    endif
    string chosen = m.GetResultString()
    if chosen == ""
        return
    endif
    _apply(mq, subject, chosen, isSelf)
EndFunction

Function _apply(MTF_MainQuest mq, Actor subject, string presetName, bool isSelf)
    if isSelf
        if mq.LoadPreset(presetName)
            Debug.Notification("MTF: applied '" + presetName + "' to self")
        else
            Debug.Notification("MTF: failed to load preset '" + presetName + "'")
        endif
    else
        int rc = mq.AddTrackedActor(subject, presetName)
        string nm = subject.GetDisplayName()
        if rc == 1
            Debug.Notification("MTF: added " + nm + " (" + presetName + ")")
            mq.EvalAndDrawActor(subject)
        elseif rc == 0
            Debug.Notification("MTF: " + nm + " → " + presetName)
            mq.EvalAndDrawActor(subject)
        elseif rc == -3
            Debug.Notification("MTF: tracked-subject cap reached")
        elseif rc == -2
            Debug.Notification("MTF: invalid target")
        endif
    endif
EndFunction
