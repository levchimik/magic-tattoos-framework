#pragma once

#include <RE/Skyrim.h>

namespace MTFPulse {

    // Global TESHitEvent sink. Drives flash dispatch for EVERY actor
    // (player + NPCs) by classifying the hit's weapon/spell source into
    // one of the seven built-in combat tags (blunt, bladed, ranged, fire,
    // frost, shock, any) and triggering flash on every roster entry
    // matching the hit's target actor.
    //
    // The Papyrus-side MTF_HitListener.OnHit still fires for the player
    // and increments the combat.hit.* condition counters, but its flash
    // dispatch branch is removed — this sink replaces it AND adds NPC
    // coverage for free, since the engine fires TESHitEvent globally.
    //
    // External mods that want to fire CUSTOM tags ("sla.aroused.over80",
    // "fmr.bleeding.tick", etc.) still call MTFPulse.TriggerActorFlash
    // from Papyrus — that path is independent of this sink.
    class HitSink : public RE::BSTEventSink<RE::TESHitEvent>
    {
    public:
        static HitSink* GetSingleton();

        // Called once at PostLoad after natives are registered.
        static void Install();

        // BSTEventSink interface.
        RE::BSEventNotifyControl ProcessEvent(
            const RE::TESHitEvent*                       a_event,
            RE::BSTEventSource<RE::TESHitEvent>* /*src*/) override;

    private:
        HitSink() = default;
        HitSink(const HitSink&) = delete;
        HitSink(HitSink&&)      = delete;

        // Looked up at Install() time, cached for the rest of the
        // session. nullptr-safe — if a keyword isn't present in the
        // current load order, the corresponding classification branch
        // falls through to "any".
        RE::BGSKeyword* kw_warhammer_  { nullptr };
        RE::BGSKeyword* kw_magicfire_  { nullptr };
        RE::BGSKeyword* kw_magicfrost_ { nullptr };
        RE::BGSKeyword* kw_magicshock_ { nullptr };
        bool            installed_     { false };
    };

}  // namespace MTFPulse
