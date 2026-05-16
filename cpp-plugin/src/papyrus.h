#pragma once

#include <RE/Skyrim.h>
#include <SKSE/SKSE.h>

namespace MTFPulse::Papyrus {

    // Registers all natives under the "MTFPulse" script name.
    bool Register(RE::BSScript::IVirtualMachine* vm);

}  // namespace MTFPulse::Papyrus
