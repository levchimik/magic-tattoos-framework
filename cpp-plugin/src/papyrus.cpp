#include "papyrus.h"
#include "log.h"
#include "pulse_roster.h"

namespace MTFPulse::Papyrus {

    namespace {

        constexpr std::string_view kClassName = "MTFPulse";

        // Set the pulse parameters for one actor. Caller passes per-layer
        // emissive multipliers as a float array (length == layerN, max 4).
        //
        // Signature mirrors what the Papyrus side already computes — see
        // MTF_MainQuest._rosterAddOrUpdate.
        void SetActorPulse(
            RE::StaticFunctionTag*    /*tag*/,
            RE::Actor*                actor,
            float                     rate,
            std::int32_t              depth_pct,
            float                     pause,
            std::int32_t              layer_count,
            float                     start_time,
            std::vector<float>        em_mults,
            std::int32_t              base_overlay_slot,
            bool                      is_female,
            std::vector<float>        wave_lut)
        {
            if (!actor) {
                spdlog::warn("SetActorPulse called with null actor");
                return;
            }
            if (rate <= 0.0f || depth_pct <= 0 || layer_count <= 0) {
                Roster::Instance().ClearAt(actor, base_overlay_slot);
                return;
            }
            PulseEntry e{};
            e.rate         = rate;
            e.depth        = std::clamp(depth_pct, 0, 100) * 0.01f;
            e.pause        = std::max(0.0f, pause);
            e.start_time   = start_time;
            e.base_slot    = base_overlay_slot;
            e.layer_count  = std::clamp(layer_count, 0, 4);
            e.is_female    = is_female;
            // Legacy entry point doesn't carry alpha/tint, so default the
            // targets to "fully visible, untinted white". If a later
            // SetActorPulseWithTransition arrives on this entry, Tick will
            // have populated last_interp_alpha/tint from these defaults,
            // giving a sensible from-state for the cross-fade.
            for (std::int32_t i = 0; i < e.layer_count; ++i) {
                const auto L = static_cast<std::size_t>(i);
                e.layer_base_em_mult[L] = (i < static_cast<std::int32_t>(em_mults.size()))
                    ? em_mults[L]
                    : 0.0f;
                e.target_alpha[L]    = 1.0f;
                e.target_tint[L]     = static_cast<std::int32_t>(0xFFFFFF);
                e.target_emissive[L] = static_cast<std::int32_t>(0xFFFFFF);
            }
            if (wave_lut.size() == PulseEntry::kWaveLUTSize) {
                std::copy(wave_lut.begin(), wave_lut.end(), e.wave_lut.begin());
                e.has_wave_lut = true;
            } else {
                e.has_wave_lut = false;
            }
            Roster::Instance().Set(actor, e);
        }

        // Set pulse + cross-fade transition in one call. Identical to
        // SetActorPulse except the caller additionally passes:
        //   tintRGBs    — per-layer target tint colors (packed 0x00RRGGBB)
        //                 written via skee_bridge during transition lerp;
        //                 length should match layer_count (extras ignored,
        //                 missing padded with white = 0xFFFFFF)
        //   alphasPct   — per-layer target alpha as 0..100 percent (matches
        //                 Papyrus JSON convention); C++ stores 0..1
        //   transitionDuration — seconds to fade from prior state to the
        //                 new target. 0 or negative behaves as SetActorPulse.
        //
        // C++ snapshots the prior entry's last interpolated em_mult/alpha/
        // tint as the from-state — chained transitions don't snap back.
        // For fresh actors with no prior entry, from = target ⇒ no visible
        // fade on first-ever apply (intentional: per-tier transitions are
        // the interesting case).
        void SetActorPulseWithTransition(
            RE::StaticFunctionTag*    /*tag*/,
            RE::Actor*                actor,
            float                     rate,
            std::int32_t              depth_pct,
            float                     pause,
            std::int32_t              layer_count,
            float                     start_time,
            std::vector<float>        em_mults,
            std::int32_t              base_overlay_slot,
            bool                      is_female,
            std::vector<float>        wave_lut,
            std::vector<std::int32_t> tint_rgbs,
            std::vector<std::int32_t> alphas_pct,
            std::vector<std::int32_t> emissive_rgbs,
            float                     transition_duration)
        {
            if (!actor) {
                spdlog::warn("SetActorPulseWithTransition called with null actor");
                return;
            }
            // v0.1.1 cross-fade: we accept rate=0 / depth_pct=0 entries.
            // The Papyrus side forwards "tier change" events regardless of
            // whether the target tier has a pulse, so the C++ roster has
            // a continuously-live entry to lerp alpha/tint/em_mult across
            // tier boundaries (including tier 1 → tier 0 fade-out). An
            // entry with rate=0 doesn't drive a pulse — Tick computes
            // wave=0, pulsed=1.0, so final_mult collapses to just the
            // (possibly-interpolated) layer ceiling.
            //
            // The only hard-bail case is no layers — nothing to write.
            if (layer_count <= 0) {
                Roster::Instance().ClearAt(actor, base_overlay_slot);
                return;
            }
            PulseEntry e{};
            e.rate                = std::max(0.0f, rate);
            e.depth               = std::clamp(depth_pct, 0, 100) * 0.01f;
            e.pause               = std::max(0.0f, pause);
            e.start_time          = start_time;
            e.base_slot           = base_overlay_slot;
            e.layer_count         = std::clamp(layer_count, 0, 4);
            e.is_female           = is_female;
            e.transition_duration = std::max(0.0f, transition_duration);
            for (std::int32_t i = 0; i < e.layer_count; ++i) {
                const auto L = static_cast<std::size_t>(i);
                e.layer_base_em_mult[L] = (i < static_cast<std::int32_t>(em_mults.size()))
                    ? em_mults[L]
                    : 0.0f;
                const std::int32_t a_pct = (i < static_cast<std::int32_t>(alphas_pct.size()))
                    ? alphas_pct[L]
                    : 100;
                e.target_alpha[L] = std::clamp(a_pct, 0, 100) * 0.01f;
                e.target_tint[L]  = (i < static_cast<std::int32_t>(tint_rgbs.size()))
                    ? tint_rgbs[L]
                    : static_cast<std::int32_t>(0xFFFFFF);
                e.target_emissive[L] = (i < static_cast<std::int32_t>(emissive_rgbs.size()))
                    ? emissive_rgbs[L]
                    : static_cast<std::int32_t>(0xFFFFFF);
            }
            if (wave_lut.size() == PulseEntry::kWaveLUTSize) {
                std::copy(wave_lut.begin(), wave_lut.end(), e.wave_lut.begin());
                e.has_wave_lut = true;
            } else {
                e.has_wave_lut = false;
            }
            Roster::Instance().Set(actor, e);
        }

        // Removes EVERY entry the actor owns (across all base_slots).
        // Use on death / unload / total teardown.
        void ClearActor(RE::StaticFunctionTag* /*tag*/, RE::Actor* actor)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().ClearAllForActor(actor);
        }

        // Removes one entry by (actor, base_slot). Use when a single preset
        // becomes inactive on an actor that still owns other presets.
        void ClearActorAt(RE::StaticFunctionTag* /*tag*/, RE::Actor* actor, std::int32_t base_slot)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().ClearAt(actor, base_slot);
        }

        void ClearAll(RE::StaticFunctionTag* /*tag*/)
        {
            Roster::Instance().ClearAll();
        }

        void SetEnabled(RE::StaticFunctionTag* /*tag*/, bool on)
        {
            Roster::Instance().SetEnabled(on);
        }

        std::int32_t Size(RE::StaticFunctionTag* /*tag*/)
        {
            return static_cast<std::int32_t>(Roster::Instance().Size());
        }

    }  // namespace

    bool Register(RE::BSScript::IVirtualMachine* vm)
    {
        if (!vm) {
            return false;
        }
        vm->RegisterFunction("SetActorPulse",               kClassName, SetActorPulse);
        vm->RegisterFunction("SetActorPulseWithTransition", kClassName, SetActorPulseWithTransition);
        vm->RegisterFunction("ClearActor",                  kClassName, ClearActor);
        vm->RegisterFunction("ClearActorAt",  kClassName, ClearActorAt);
        vm->RegisterFunction("ClearAll",      kClassName, ClearAll);
        vm->RegisterFunction("SetEnabled",    kClassName, SetEnabled);
        vm->RegisterFunction("Size",          kClassName, Size);
        spdlog::info("Papyrus natives registered under '{}'", kClassName);
        return true;
    }

}  // namespace MTFPulse::Papyrus
