// MTFPulse — Magic Tattoos Framework C++ companion plugin.
//
// Single responsibility: a per-frame pulse animation loop driving NiOverride
// emissive intensity, sourced from a roster of (Actor, rate, depth, pause,
// start, layerN, base-em-mults) tuples set via Papyrus natives.
//
// The Papyrus side computes whether an actor should pulse and forwards the
// parameters to MTFPulse via the natives in papyrus.cpp. The hot loop here
// is intentionally ignorant of conditions, presets, cooldowns — those stay
// in Papyrus where they're fine.

#include "log.h"
#include "papyrus.h"
#include "pulse_roster.h"

#include <RE/Skyrim.h>
#include <SKSE/SKSE.h>

using namespace MTFPulse;

namespace {

    // SKSE messaging callback. Hook here for kDataLoaded so the VM is up
    // before we try to register natives.
    void OnSKSEMessage(SKSE::MessagingInterface::Message* msg)
    {
        if (!msg) return;
        switch (msg->type) {
            case SKSE::MessagingInterface::kDataLoaded:
                spdlog::info("kDataLoaded — registering Papyrus natives");
                if (auto* vm = RE::BSScript::Internal::VirtualMachine::GetSingleton()) {
                    Papyrus::Register(vm);
                }
                break;

            case SKSE::MessagingInterface::kPostLoad:
                // TODO: handshake with SKEE/NiOverride here once we add real
                // NiOverride writes inside Roster::Tick.
                spdlog::info("kPostLoad");
                break;

            default:
                break;
        }
    }

    // Per-frame tick. SKSE doesn't ship a generic OnFrame hook; the standard
    // approach is to install a Hooks::Install() that detours the game's
    // BSInputDeviceManager::PollInputDevices (called once per frame) or to
    // use UI::OnFrameUpdate. For tonight: stub the tick at the messaging
    // boundary so the plugin loads cleanly. Wiring a real frame hook is the
    // next focused task — TODO before testing pulse output.
    //
    // Placeholder: call Roster::Tick() from a SKSE main-thread task once
    // per frame via TaskInterface AddTask in a loop self-rescheduling at
    // ~16ms cadence. Crude but compatible with all builds.

    void ScheduleNextFrameTick()
    {
        auto* taskInterface = SKSE::GetTaskInterface();
        if (!taskInterface) {
            return;
        }
        taskInterface->AddTask([] {
            Roster::Instance().Tick();
            ScheduleNextFrameTick();
        });
    }

}  // namespace

SKSEPluginLoad(const SKSE::LoadInterface* skse)
{
    SKSE::Init(skse);
    log::Setup();

    spdlog::info("MTFPulse v{}.{}.{} loaded",
                 0, 0, 1);
    spdlog::info("Runtime: AE/SE {}.{}.{}",
                 skse->RuntimeVersion().major(),
                 skse->RuntimeVersion().minor(),
                 skse->RuntimeVersion().patch());

    auto* messaging = SKSE::GetMessagingInterface();
    if (messaging) {
        messaging->RegisterListener(OnSKSEMessage);
    }

    ScheduleNextFrameTick();
    return true;
}
