#pragma once

#include <RE/Skyrim.h>

namespace MTFPulse {

    // Global TESDeathEvent sink. Drives fade-on-death dispatch for
    // every actor (player + NPCs) that has at least one roster entry
    // armed with mtf.base:ondeath.fade.
    //
    // TESDeathEvent fires TWICE per death in vanilla: once with
    // dead=false at the start of the dying animation, once with
    // dead=true after the body settles. We fire on the first event so
    // the fade visual aligns with the death animation. The roster's
    // StartFade() gates on !fade_active, so the second event (or any
    // double-fire from concurrent script/engine paths) is a no-op.
    //
    // Player death: Skyrim fires TESDeathEvent for the player but the
    // player actor isn't destroyed — the death screen waits for the
    // user to reload. If they reload, the loaded save's MTF state
    // re-applies onActivate/onTick and re-arms fade if the preset
    // still binds it. If they don't reload (alt-f4), the in-memory
    // fade animation just runs to completion and disappears.
    class DeathSink : public RE::BSTEventSink<RE::TESDeathEvent>
    {
    public:
        static DeathSink* GetSingleton();

        // Called once at kDataLoaded after natives + hit sink are up.
        static void Install();

        // BSTEventSink interface.
        RE::BSEventNotifyControl ProcessEvent(
            const RE::TESDeathEvent*                       a_event,
            RE::BSTEventSource<RE::TESDeathEvent>* /*src*/) override;

    private:
        DeathSink() = default;
        DeathSink(const DeathSink&) = delete;
        DeathSink(DeathSink&&)      = delete;

        bool installed_{ false };
    };

}  // namespace MTFPulse
