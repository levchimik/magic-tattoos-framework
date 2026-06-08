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
        // Exactly one of these is non-null after a successful Init().
        //   g_override     — SKEE >= v2 (wrapper SetVariant API)
        //   g_override_v1  — SKEE  v1   (legacy OverrideVariant API, RaceMenu 0.4.19.x)
        // Both null means the bridge isn't ready (init not called, SKEE
        // absent, or an unsupported version).
        skee::IOverrideInterface*   g_override    = nullptr;
        skee::IOverrideInterfaceV1* g_override_v1 = nullptr;
    }

    bool IsReady() { return g_override != nullptr || g_override_v1 != nullptr; }

    namespace {
        // Helpers isolated from C++ destructors so we can use __try/__except.
        // MSVC forbids mixing structured exception handling with functions
        // that have unwindable C++ objects in the same scope.
        //
        // Returns true if the vtable call completed without raising a
        // Windows structured exception (access violation, illegal instr,
        // etc.). On exception, returns false — caller is expected to
        // disable the bridge to prevent repeated crashes. This is the net
        // that keeps a vtable-layout mismatch (esp. the hand-transcribed v1
        // ABI) from becoming a hard CTD.
        //
        // `key` is one of skee::OverrideParam::kParam_* — the same enum the
        // Papyrus-side NiOverride.AddNodeOverride* family uses.
        static bool CallSetNodeProperty_SEH_v2(
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

        // v1 path: key+index already packed inside `ov`; nodeName is the raw
        // interned BSFixedString pointer passed by value as void*.
        static bool CallSetNodeProperty_SEH_v1(
            skee::IOverrideInterfaceV1* over,
            skee::TESObjectREFR*        refr,
            void*                       nodeName,
            skee::OverrideVariantV1*    ov) noexcept
        {
            __try {
                over->SetNodeProperty(refr, nodeName, ov, /*immediate=*/true);
                return true;
            }
            __except (EXCEPTION_EXECUTE_HANDLER) {
                return false;
            }
        }
    }

    bool Init()
    {
        if (g_override || g_override_v1) {
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

        // GetVersion() lives at the same vtable slot (1, after the virtual
        // dtor) in every SKEE generation, so reading it through the minimal
        // IPluginInterface base is safe regardless of which ABI the rest of
        // the object uses.
        const auto version = iface->GetVersion();

        if (version >= skee::IOverrideInterface::kPluginVersion2) {
            g_override = static_cast<skee::IOverrideInterface*>(iface);
            spdlog::info("skee_bridge: acquired Override interface v{} (wrapper ABI)", version);
            return true;
        }

        if (version == skee::IOverrideInterface::kPluginVersion1) {
            // Legacy RaceMenu 0.4.19.x. The object is SKEE's internal concrete
            // OverrideInterface; we drive it through the hand-transcribed v1
            // vtable shim. SEH-guarded, so a layout mismatch disables the
            // bridge rather than crashing.
            g_override_v1 = reinterpret_cast<skee::IOverrideInterfaceV1*>(iface);
            spdlog::info("skee_bridge: acquired Override interface v1 (legacy ABI) — pulse enabled on old RaceMenu");
            return true;
        }

        spdlog::warn("skee_bridge: Override interface v{} unsupported", version);
        return false;
    }

    namespace {
        // Shared write path used by every Write* function below. Routes to
        // whichever ABI Init() acquired. Doing the reinterpret_cast and the
        // v1/v2 branch in one place keeps the per-property functions trivial.
        //
        // `fv` is used when isFloat, `iv` (packed 0x00RRGGBB for colors) when
        // not. The RE::TESObjectREFR* ↔ skee::TESObjectREFR* cast is the same
        // underlying pointer, different opaque typedefs.
        bool WriteProp(
            RE::Actor*     actor,
            const char*    nodeName,
            skee::skee_u16 key,
            bool           isFloat,
            float          fv,
            skee::skee_i32 iv)
        {
            if (!actor || !nodeName) {
                return false;
            }
            auto* refr = reinterpret_cast<skee::TESObjectREFR*>(static_cast<RE::TESObjectREFR*>(actor));

            if (g_override) {  // v2 wrapper ABI
                if (isFloat) {
                    skee::FloatVariant variant{ fv };
                    if (!CallSetNodeProperty_SEH_v2(g_override, refr, nodeName, key, variant)) {
                        spdlog::error("skee_bridge: v2 SetNodeProperty raised SEH on node='{}' key={} — disabling bridge",
                                      nodeName, static_cast<int>(key));
                        g_override = nullptr;
                        return false;
                    }
                } else {
                    skee::IntVariant variant{ iv };
                    if (!CallSetNodeProperty_SEH_v2(g_override, refr, nodeName, key, variant)) {
                        spdlog::error("skee_bridge: v2 SetNodeProperty raised SEH on node='{}' key={} — disabling bridge",
                                      nodeName, static_cast<int>(key));
                        g_override = nullptr;
                        return false;
                    }
                }
                return true;
            }

            if (g_override_v1) {  // v1 legacy ABI
                skee::OverrideVariantV1 ov;
                if (isFloat) {
                    ov.SetFloat(key, /*index=*/-1, fv);
                } else {
                    ov.SetInt(key, /*index=*/-1, iv);
                }
                // BSFixedString is one interned pointer; construct it (which
                // interns into the game's shared string pool SKEE also reads)
                // and pass that pointer by value.
                RE::BSFixedString node(nodeName);
                void* nodeArg = *reinterpret_cast<void* const*>(&node);
                if (!CallSetNodeProperty_SEH_v1(g_override_v1, refr, nodeArg, &ov)) {
                    spdlog::error("skee_bridge: v1 SetNodeProperty raised SEH on node='{}' key={} — disabling bridge",
                                  nodeName, static_cast<int>(key));
                    g_override_v1 = nullptr;
                    return false;
                }
                return true;
            }

            return false;  // bridge not ready
        }
    }

    bool WriteEmissiveMult(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, float mult)
    {
        // v0.2.9 black-blob floor: SKEE overlay shaders couple diffuse
        // visibility to emissive intensity — em=0 renders the base ink's
        // dark "lit-by-emissive" diffuse as a near-black blob at alpha 100.
        // Clamp 0 → 0.001 so the dark diffuse isn't exposed raw. 0.001
        // contributes no visible glow on its own, and pulse_roster's
        // gloss_basis still reads the unfloored ceiling, so a genuinely
        // matte layer (ceiling 0) keeps gloss=0/spec=0. Lives here at the
        // SKEE write boundary so every call path (steady pulse, fade-on-
        // death, drain-one-shot) is covered uniformly.
        if (mult <= 0.0f) {
            mult = 0.001f;
        }
        return WriteProp(actor, nodeName, skee::OverrideParam::kParam_ShaderEmissiveMultiple, /*isFloat=*/true, mult, 0);
    }

    bool WriteAlpha(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, float alpha)
    {
        return WriteProp(actor, nodeName, skee::OverrideParam::kParam_ShaderAlpha, /*isFloat=*/true, alpha, 0);
    }

    bool WriteTint(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, std::int32_t rgb)
    {
        return WriteProp(actor, nodeName, skee::OverrideParam::kParam_ShaderTintColor, /*isFloat=*/false, 0.0f, rgb);
    }

    bool WriteEmissiveColor(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, std::int32_t rgb)
    {
        return WriteProp(actor, nodeName, skee::OverrideParam::kParam_ShaderEmissiveColor, /*isFloat=*/false, 0.0f, rgb);
    }

    bool WriteGlossiness(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, float gloss)
    {
        return WriteProp(actor, nodeName, skee::OverrideParam::kParam_ShaderGlossiness, /*isFloat=*/true, gloss, 0);
    }

    bool WriteSpecular(RE::Actor* actor, [[maybe_unused]] bool isFemale, const char* nodeName, float spec)
    {
        return WriteProp(actor, nodeName, skee::OverrideParam::kParam_ShaderSpecularStrength, /*isFloat=*/true, spec, 0);
    }

}  // namespace MTFPulse::skee_bridge
