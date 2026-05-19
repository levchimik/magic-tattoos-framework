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

#include "frame_hook.h"
#include "hit_sink.h"
#include "log.h"
#include "papyrus.h"
#include "pulse_roster.h"
#include "skee_bridge.h"

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
                // Frame hook: vtable swap on PlayerCharacter::Update.
                // (Previous attempt used write_branch on a function entry
                // which crashed — write_branch is for call-site redirects,
                // not function prologues. See frame_hook.cpp for details.)
                frame_hook::Install();
                // Hit sink: global TESHitEvent → flash dispatch on every
                // actor (player + NPCs) that has a roster entry with a
                // matching tag set. Installed after kDataLoaded so the
                // TESDataHandler keyword lookups have the load order in
                // place. (v0.1.3 — was previously player-only via the
                // Papyrus MTF_HitListener alias.)
                HitSink::Install();
                break;

            case SKSE::MessagingInterface::kPostLoad:
                spdlog::info("kPostLoad");
                break;

            case SKSE::MessagingInterface::kPostPostLoad:
                // SKEE registers its InterfaceExchange listener on its OWN
                // kPostLoad, so dispatching at our kPostLoad races with it.
                // kPostPostLoad fires after every plugin's kPostLoad has run,
                // guaranteeing SKEE is ready to respond.
                spdlog::info("kPostPostLoad — initialising SKEE bridge");
                skee_bridge::Init();
                break;

            default:
                break;
        }
    }

    // Per-frame tick: NOT WIRED YET.
    //
    // A previous version used SKSE::TaskInterface::AddTask self-rescheduling
    // (each tick queues the next one). That froze the game — SKSE drains its
    // task queue in-place, so a task that re-arms itself becomes an infinite
    // loop on the main thread.
    //
    // The correct path is a BSInputDeviceManager::PollInputDevices detour
    // (the canonical per-frame hook in SKSE plugins). Coming next; for now
    // the plugin loads, registers natives, and the roster sits idle — usable
    // for smoke-testing Papyrus → MTFPulse calls without any frame work.

}  // namespace

// SKSE plugin metadata. Without this, SKSE refuses to load the DLL ("no
// version data" in skse64.log). Must live in a translation unit at global
// scope. Address-library-independent because we don't currently touch any
// runtime offsets — once we add a per-frame hook we'll switch to a pinned
// runtime version list.
SKSEPluginInfo(
    .Version = REL::Version{ 0, 0, 1, 0 },
    .Name = "MTFPulse",
    .Author = "MTF",
)

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

    return true;
}
