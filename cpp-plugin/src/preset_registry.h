#pragma once

// Tier 2 #1: lazy write-through preset cache.
//
// Mirrors the Papyrus warm scratch cache (`mtf.scratch.cached.<name>.*` keys
// in StorageUtil). Populated by the Papyrus side after a cold JSON load via
// `MTFPulse.PresetCacheSet(...)`; read back on subsequent reloads via
// `MTFPulse.PresetCacheGetSnapshot(...)` — one cross-script call replaces 13
// `StorageUtil.*ListToArray` calls and 4 scalar reads.
//
// Lifetime: process-lifetime (NOT save-lifetime). On fresh DLL load, the cache
// is empty until Papyrus walks each preset on first use. The StorageUtil warm
// cache remains as the persistent backing store; this is purely an in-memory
// shortcut.

#include <array>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>

namespace MTFPulse {

    // Slots × layers — must match MainQuest's MAX_CONDITIONS / MAX_LAYERS_PER_SLOT
    // for the MCM-slot range. Backend slots (s > 8) are stored in StorageUtil
    // namespaced keys per the existing Papyrus design and are NOT cached here;
    // the warm cache only ever held the 8-MCM-slot data (see
    // `_loadScratchFromCache`). Same here.
    struct PresetData
    {
        static constexpr std::size_t kSlots  = 8;
        static constexpr std::size_t kLayers = 32;  // 8 slots × 4 layers/slot

        // Slot-level arrays
        std::array<std::string, kSlots>  cond_pluginid{};
        std::array<std::int32_t, kSlots> cond_param{};
        std::array<std::string, kSlots>  cond_packid{};
        std::array<std::string, kSlots>  cond_entryid{};
        std::array<std::int32_t, kSlots> cooldown_min{};   // semantic: persistMin
        std::array<std::int32_t, kSlots> cooldown_mode{};  // semantic: allowOverride
        std::array<float, kSlots>        pulse_rate{};
        std::array<std::int32_t, kSlots> pulse_depth{};
        std::array<std::string, kSlots>  pulse_waveform{};

        // Layer-level arrays (slot * 4 + L indexed)
        std::array<std::int32_t, kLayers> layer_tint{};
        std::array<std::int32_t, kLayers> layer_emissive{};
        std::array<float, kLayers>        layer_emissive_mult{};
        std::array<std::int32_t, kLayers> layer_alpha{};

        // Top-level scalars
        float        transition_duration{1.0f};
        bool         fade_on_death_enabled{false};
        std::int32_t fade_on_death_mode{0};
        std::int32_t fade_on_death_duration_ms{2000};
    };

    class PresetRegistry
    {
    public:
        static PresetRegistry& Instance();

        // Replaces any existing entry. Returns the new size.
        std::size_t Set(std::string name, PresetData data);

        // Returns std::nullopt if `name` isn't cached.
        // Copies the entry to insulate the caller from the lock.
        std::optional<PresetData> Get(std::string_view name) const;

        bool Has(std::string_view name) const;

        // Returns true when an entry existed and was removed.
        bool Remove(std::string_view name);

        std::size_t Size() const;

        void Clear();

    private:
        PresetRegistry() = default;
        mutable std::mutex mtx_;
        std::unordered_map<std::string, PresetData> presets_;
    };

}  // namespace MTFPulse
