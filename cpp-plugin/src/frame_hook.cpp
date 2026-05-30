#include "frame_hook.h"
#include "log.h"
#include "pulse_roster.h"

#include <RE/Skyrim.h>
#include <SKSE/SKSE.h>
#include <REL/Relocation.h>

namespace MTFPulse::frame_hook {

    namespace {

        bool g_installed = false;

        // Hook the main game-loop update via a call-site trampoline.
        //
        // WHY NOT PlayerCharacter::Update (the previous approach):
        // Actor::Update (vtable 0xAD) fires only while the player ACTOR is
        // processed, which `tfc` (toggle free camera) suspends -- freezing the
        // pulse and (post-V4) live em/alpha/tint/emissive writes until a menu
        // forces a 3D rebuild. PlayerCamera::Update (TESCamera vtable 0x02)
        // was also tried and produced NO overlay at all, so it is not usable.
        //
        // WHY THE MAIN LOOP:
        // This is the canonical per-frame hook (used by e.g. True Directional
        // Movement). It replaces a `call` to a do-nothing sub (Nullsub) inside
        // the main update routine, executed EVERY frame in all camera modes
        // INCLUDING free camera under tfc. So pulse keeps running and tier
        // color changes apply live in tfc. A full game-pausing menu still
        // halts the main loop; the menu's own 3D rebuild repaints then.
        //
        // Address (verified verbatim against True Directional Movement's
        // Hooks.h, AE-compatible -- internal address cross-check below):
        //   REL::RelocationID(35565, 36564)   SE id 0x5B2FF0 / AE id 0x5D9F50
        //   + REL::Relocate(0x748, 0xC26)     SE 0x5B3738    / AE 0x5DAB76
        //   write_call<5>                     5-byte call instruction
        //   (0x5B2FF0 + 0x748 == 0x5B3738 ✓ ; 0x5D9F50 + 0xC26 == 0x5DAB76 ✓)
        // CommonLibSSE-NG resolves SE-vs-AE at runtime from Address Library,
        // so one build works on 1.6.1170 (our pinned runtime) and others.
        //
        // The replaced call targets a Nullsub (does nothing); we still invoke
        // the original via the trampoline to preserve exact call semantics,
        // then run our per-frame Tick. Signature is void().
        struct MainUpdateHook
        {
            static void thunk()
            {
                func();  // original Nullsub -- preserve original call behavior
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
            spdlog::warn("frame_hook: Install() called twice -- ignoring");
            return;
        }

        // One write_call<5> needs a 14-byte trampoline slot. AllocTrampoline
        // must run before GetTrampoline().write_call.
        SKSE::AllocTrampoline(14);
        auto& trampoline = SKSE::GetTrampoline();

        REL::Relocation<std::uintptr_t> target{ REL::RelocationID(35565, 36564) };
        const auto callSite = target.address() + REL::Relocate(0x748, 0xC26);
        MainUpdateHook::func =
            trampoline.write_call<5>(callSite, MainUpdateHook::thunk);

        g_installed = true;
        spdlog::info("frame_hook: installed main-loop update hook (call @ {:x})", callSite);
    }

}  // namespace MTFPulse::frame_hook
