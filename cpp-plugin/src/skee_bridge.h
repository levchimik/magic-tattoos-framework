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

}  // namespace MTFPulse::skee_bridge
