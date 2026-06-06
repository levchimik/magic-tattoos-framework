Scriptname MTF_SpidApply extends ActiveMagicEffect
{Carrier for SPID-style NPC preset distribution (optional addon). Distributed to
 NPCs as an ability via a SPID _DISTR.ini; on apply it asks MTF_MainQuest to
 evaluate the distribution rules for this actor, then removes itself so it
 leaves no lingering effect (mirrors SlaveTats-SPID / Overlay-Distribution-
 Framework: the distributed form is only a trigger, all selection is MTF JSON).
 Removal is deferred to OnUpdate so we never RemoveSpell mid-OnEffectStart.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    MTF_MainQuest mq = Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
    if mq != None && akTarget != None
        mq.DistributeToActor(akTarget)
    endif
    RegisterForSingleUpdate(0.1)
EndEvent

Event OnUpdate()
    Actor a = GetTargetActor()
    Spell carrier = Game.GetFormFromFile(0x927, "MagicTattoosFramework.esp") as Spell
    if a != None && carrier != None
        a.RemoveSpell(carrier)
    endif
EndEvent
