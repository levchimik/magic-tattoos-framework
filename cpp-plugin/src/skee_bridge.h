#pragma once

#include <RE/Skyrim.h>

namespace MTFPulse::skee_bridge {

    // Handshake with SKEE/NiOverride. Call from the SKSE kPostLoad
    // messaging callback — SKEE registers its InterfaceExchange listener
    // on its own kPostLoad, and SKSE delivers kPostLoad to plugins in
    // registration order, so by the time our handler runs SKEE is ready
    // to respond.
    //
    // Returns true if the IOverrideInterface was acquired. Logs to spdlog
    // either way.
    bool Init();

    bool IsReady();

    // Write a single emissive-multiple value to one body overlay node.
    // No-op (returns false) if the bridge isn't initialized or actor is
    // null. `nodeName` example: "ovl0", "ovl1", ... mirroring NiOverride's
    // body overlay slot naming used by the Papyrus path.
    //
    // Internally maps to:
    //   IOverrideInterface::SetNodeProperty(refr, firstPerson=false,
    //       nodeName, key=kParam_ShaderEmissiveMultiple, index=0xFF,
    //       SetVariant{float}, immediate=true)
    bool WriteEmissiveMult(RE::Actor* actor, bool isFemale, const char* nodeName, float mult);

    // Write the per-shader alpha value [0..1]. Same SetNodeProperty path as
    // WriteEmissiveMult but with key = kParam_ShaderAlpha. Used by the
    // pulse roster's transition lerp to cross-fade overlay visibility.
    bool WriteAlpha(RE::Actor* actor, bool isFemale, const char* nodeName, float alpha);

    // Write the per-shader tint color (packed 0x00RRGGBB). Used by the
    // transition lerp to cross-fade between tier tints (e.g. black → white
    // over the transition duration).
    bool WriteTint(RE::Actor* actor, bool isFemale, const char* nodeName, std::int32_t rgb);

    // Write the per-shader emissive color (packed 0x00RRGGBB). Same path
    // as WriteTint with key = kParam_ShaderEmissiveColor. Cross-fading
    // this avoids the "snap to white" artifact when transitioning from a
    // colored emissive (red/green/blue) to a tier with a neutral emissive
    // color (which gets multiplied by the still-fading em_mult on the
    // first frames of the lerp).
    bool WriteEmissiveColor(RE::Actor* actor, bool isFemale, const char* nodeName, std::int32_t rgb);

}  // namespace MTFPulse::skee_bridge
