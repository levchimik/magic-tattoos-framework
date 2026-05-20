#include "death_sink.h"
#include "log.h"
#include "pulse_roster.h"

namespace MTFPulse {

    DeathSink* DeathSink::GetSingleton()
    {
        static DeathSink s;
        return &s;
    }

    void DeathSink::Install()
    {
        auto* sink = GetSingleton();
        if (sink->installed_) {
            return;
        }
        auto* src = RE::ScriptEventSourceHolder::GetSingleton();
        if (src) {
            src->AddEventSink<RE::TESDeathEvent>(sink);
            sink->installed_ = true;
            spdlog::info("DeathSink: TESDeathEvent sink installed");
        } else {
            spdlog::error("DeathSink::Install: ScriptEventSourceHolder not available");
        }
    }

    RE::BSEventNotifyControl DeathSink::ProcessEvent(
        const RE::TESDeathEvent*               a_event,
        RE::BSTEventSource<RE::TESDeathEvent>* /*src*/)
    {
        if (!a_event || !a_event->actorDying) {
            return RE::BSEventNotifyControl::kContinue;
        }
        auto* dyingActor = a_event->actorDying.get()
            ? a_event->actorDying.get()->As<RE::Actor>()
            : nullptr;
        if (!dyingActor) {
            return RE::BSEventNotifyControl::kContinue;
        }
        // Player IS allowed to fade on actual death — Skyrim's bleedout
        // for essential/protected actors doesn't fire TESDeathEvent, so
        // bleedout-recovery naturally doesn't trigger fade. Only a real
        // death fires the event; that ends in a reload screen for the
        // player, so the fade animation plays briefly during the death
        // anim. The Papyrus side stops recreating roster entries for
        // dead actors (PlayerRef.IsDead() gate in _applyPulse) so the
        // alpha=0 doesn't get stuck if anything tries to recreate the
        // entry after the deferred-removal eviction.
        //
        // No tag matching here — fade is a one-shot keyed off death
        // alone. The roster gates: only entries with fade_armed=true
        // start a fade, and StartFade clamps re-fires via
        // !fade_active, so the dying-then-dead double-event collapses
        // to one animation per death.
        Roster::Instance().TriggerFadeAllSlotsForActor(dyingActor);
        return RE::BSEventNotifyControl::kContinue;
    }

}  // namespace MTFPulse
