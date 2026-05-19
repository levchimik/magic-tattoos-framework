#include "skee_bridge.h"
#include "log.h"
#include "skee_interface.h"

#include <SKSE/SKSE.h>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>  // EXCEPTION_EXECUTE_HANDLER for __try / __except

namespace MTFPulse::skee_bridge {

    namespace {
        // Cached on Init(), used by every WriteEmissiveMult call. Null
        // means the bridge isn't ready (init not called, SKEE absent, or
        // the version is too old).
        skee::IOverrideInterface* g_override = nullptr;
    }

    bool IsReady() { return g_override != nullptr; }

    namespace {
        // Helper isolated from C++ destructors so we can use __try/__except.
        // MSVC forbids mixing structured exception handling with functions
        // that have unwindable C++ objects in the same scope.
        //
        // Returns true if the vtable call completed without raising a
        // Windows structured exception (access violation, illegal instr,
        // etc.). On exception, returns false — caller is expected to
        // disable the bridge to prevent repeated crashes.
        //
        // `key` is one of skee::OverrideParam::kParam_* — the same enum the
        // Papyrus-side NiOverride.AddNodeOverride* family uses.
        static bool CallSetNodeProperty_SEH(
            skee::IOverrideInterface*             over,
            skee::TESObjectREFR*                  refr,
            const char*                           nodeName,
            skee::skee_u16                        key,
            skee::IOverrideInterface::SetVariant& variant) noexcept
        {
            __try {
                over->SetNodeProperty(
                    refr,
                    /*firstPerson=*/false,
                    nodeName,
                    key,
                    skee::OverrideParam::kIndexMax,
                    variant,
                    /*immediate=*/true);
                return true;
            }
            __except (EXCEPTION_EXECUTE_HANDLER) {
                return false;
            }
        }
    }

    bool Init()
    {
        if (g_override) {
            return true;  // already initialised
        }

        auto* messaging = SKSE::GetMessagingInterface();
        if (!messaging) {
            spdlog::warn("skee_bridge: no SKSE messaging interface");
            return false;
        }

        skee::InterfaceExchangeMessage msg{};
        // Dispatch is synchronous: SKEE's handler runs inline and fills
        // msg.interfaceMap before this call returns. If SKEE isn't loaded,
        // Dispatch returns false (no receiver) and msg.interfaceMap stays
        // null — which is the absent-dependency case we handle next.
        // Plugin name is case-sensitive — SKEE registers itself as
        // lowercase "skee" (verified in skse64.log: `loading plugin "skee"`).
        const bool dispatched = messaging->Dispatch(
            skee::InterfaceExchangeMessage::kMessage_ExchangeInterface,
            &msg,
            sizeof(msg),
            "skee");

        if (!dispatched || !msg.interfaceMap) {
            spdlog::warn("skee_bridge: SKEE not present (dispatch={}, map={})",
                         dispatched, static_cast<void*>(msg.interfaceMap));
            return false;
        }

        auto* iface = msg.interfaceMap->QueryInterface("Override");
        if (!iface) {
            spdlog::warn("skee_bridge: 'Override' interface not found in SKEE map");
            return false;
        }

        // Down-cast through IPluginInterface — both classes live in the
        // skee:: namespace and IOverrideInterface really IS the runtime
        // type SKEE registered under that name.
        auto* over = static_cast<skee::IOverrideInterface*>(iface);
        const auto version = over->GetVersion();
        if (version < skee::IOverrideInterface::kPluginVersion2) {
            spdlog::warn("skee_bridge: Override interface v{} is too old (need >= {})",
                         version,
                         static_cast<int>(skee::IOverrideInterface::kPluginVersion2));
            return false;
        }

        g_override = over;
        spdlog::info("skee_bridge: acquired Override interface v{}", version);
        return true;
    }

    namespace {
        // Shared cast + SEH call path used by every Write* function below.
        // Doing the cast in one place keeps the reinterpret_cast quirk
        // (RE::TESObjectREFR* ↔ skee::TESObjectREFR* — same underlying
        // pointer, different opaque typedefs) isolated to one location.
        bool WriteVariant(
            RE::Actor*                            actor,
            const char*                           nodeName,
            skee::skee_u16                        key,
            skee::IOverrideInterface::SetVariant& variant)
        {
            if (!g_override || !actor || !nodeName) {
                return false;
            }
            auto* refr = reinterpret_cast<skee::TESObjectREFR*>(static_cast<RE::TESObjectREFR*>(actor));
            if (!CallSetNodeProperty_SEH(g_override, refr, nodeName, key, variant)) {
                spdlog::error("skee_bridge: SetNodeProperty raised SEH on node='{}' key={} — disabling bridge",
                              nodeName, static_cast<int>(key));
                g_override = nullptr;
                return false;
            }
            return true;
        }
    }

    bool WriteEmissiveMult(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, float mult)
    {
        // SetNodeProperty doesn't take isFemale (it operates on the already-
        // attached node graph regardless of sex). The parameter is kept in
        // our public signature because the *persist* path AddNodeOverride
        // does need it, and we may add that variant later.
        skee::FloatVariant variant{ mult };
        return WriteVariant(actor, nodeName, skee::OverrideParam::kParam_ShaderEmissiveMultiple, variant);
    }

    bool WriteAlpha(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, float alpha)
    {
        skee::FloatVariant variant{ alpha };
        return WriteVariant(actor, nodeName, skee::OverrideParam::kParam_ShaderAlpha, variant);
    }

    bool WriteTint(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, std::int32_t rgb)
    {
        skee::IntVariant variant{ rgb };
        return WriteVariant(actor, nodeName, skee::OverrideParam::kParam_ShaderTintColor, variant);
    }

    bool WriteEmissiveColor(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, std::int32_t rgb)
    {
        skee::IntVariant variant{ rgb };
        return WriteVariant(actor, nodeName, skee::OverrideParam::kParam_ShaderEmissiveColor, variant);
    }

}  // namespace MTFPulse::skee_bridge
