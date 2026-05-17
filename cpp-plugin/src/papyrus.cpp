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
                Roster::Instance().Clear(actor);
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
            for (std::int32_t i = 0; i < e.layer_count && i < static_cast<std::int32_t>(em_mults.size()); ++i) {
                e.layer_base_em_mult[static_cast<std::size_t>(i)] = em_mults[static_cast<std::size_t>(i)];
            }
            if (wave_lut.size() == PulseEntry::kWaveLUTSize) {
                std::copy(wave_lut.begin(), wave_lut.end(), e.wave_lut.begin());
                e.has_wave_lut = true;
            } else {
                e.has_wave_lut = false;
            }
            Roster::Instance().Set(actor, e);
        }

        void ClearActor(RE::StaticFunctionTag* /*tag*/, RE::Actor* actor)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().Clear(actor);
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
        vm->RegisterFunction("SetActorPulse", kClassName, SetActorPulse);
        vm->RegisterFunction("ClearActor",    kClassName, ClearActor);
        vm->RegisterFunction("ClearAll",      kClassName, ClearAll);
        vm->RegisterFunction("SetEnabled",    kClassName, SetEnabled);
        vm->RegisterFunction("Size",          kClassName, Size);
        spdlog::info("Papyrus natives registered under '{}'", kClassName);
        return true;
    }

}  // namespace MTFPulse::Papyrus
