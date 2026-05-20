#pragma once

#include <cstdint>
#include <string_view>

// Runtime config for MTFPulse + Papyrus side.
//
// Source: Data/SKSE/Plugins/MagicTattoosFramework.ini, parsed once at
// kPostLoad via Win32 GetPrivateProfileIntW. Cached for the rest of the
// session — INI edits take effect on Skyrim restart.
//
// Bethesda INI naming convention: type-prefixed keys (iFoo for int,
// fFoo for float, bFoo for bool, sFoo for string). We follow that.
//
// Default section is [General]. If a value is missing or out of range,
// GetInt returns the supplied default.
namespace MTFPulse::Config {

    // Parse the INI from disk and populate the cache. Safe to call more
    // than once; subsequent calls re-read. Called from main.cpp on
    // kPostLoad.
    void Load();

    // Read an int from the cached INI. If the key is absent or fails to
    // parse, returns defaultValue. Reads from [General] unless an
    // explicit "section.key" form is provided in `key`.
    std::int32_t GetInt(std::string_view key, std::int32_t defaultValue);

}  // namespace MTFPulse::Config
