#include "frame_hook.h"
#include "log.h"
#include "pulse_roster.h"

#include <RE/Skyrim.h>
#include <SKSE/SKSE.h>
#include <REL/Relocation.h>

namespace MTFPulse::frame_hook {

    namespace {

        bool g_installed = false;

        // Hook Actor::Update via vtable swap on the PlayerCharacter vtable.
        // Update fires once per frame while the player is loaded — exactly
        // the cadence we want for pulse animation. Vtable swapping is just
        // a memory write, no instruction-byte editing, no trampolines, no
        // risk of splitting the function prologue.
        //
        // Vtable index 0xAD: see Actor.h
        //   `SKYRIM_REL_VR_VIRTUAL void Update(float a_delta);  // 0AD`
        // PlayerCharacter inherits the slot unchanged.
        //
        // Caveat: this only ticks while the player exists in the world
        // (after Update has been called at least once on the PC). In the
        // main menu the roster isn't ticked — fine, nothing to animate.
        struct PCUpdateHook
        {
            static void thunk(RE::Actor* a_self, float a_dt)
            {
                // Run the original Update first — game state must be
                // advanced before we read it.
                func(a_self, a_dt);
                try {
                    Roster::Instance().Tick();
                } catch (const std::exception& e) {
                    spdlog::error("frame_hook: Tick threw: {}", e.what());
                } catch (...) {
                    spdlog::error("frame_hook: Tick threw (unknown)");
                }
            }
            static inline REL::Relocation<decltype(thunk)> func;
        };

    }  // namespace

    void Install()
    {
        if (g_installed) {
            spdlog::warn("frame_hook: Install() called twice — ignoring");
            return;
        }

        // VTABLE_PlayerCharacter[0] is the primary vtable (PC inherits
        // multiple — [0] is the one containing Actor::Update at 0xAD).
        REL::Relocation<std::uintptr_t> vtbl{ RE::VTABLE_PlayerCharacter[0] };
        PCUpdateHook::func = vtbl.write_vfunc(0xAD, PCUpdateHook::thunk);

        g_installed = true;
        spdlog::info("frame_hook: installed PlayerCharacter::Update vtable swap (slot 0xAD @ vtbl {:x})",
                     vtbl.address());
    }

}  // namespace MTFPulse::frame_hook
