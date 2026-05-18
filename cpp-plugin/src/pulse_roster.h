#pragma once

#include <RE/Skyrim.h>
#include <array>
#include <mutex>
#include <vector>

namespace MTFPulse {

    // One pulse subject. Snapshotted at Set(); the per-frame hot loop reads
    // these without any Papyrus/JsonUtil contact.
    struct PulseEntry
    {
        RE::ActorHandle actor{};
        std::uint32_t   actor_formID{ 0 };  // for stable identity even if handle expires briefly
        float           rate{ 0.0f };       // cycles per second
        float           depth{ 0.0f };      // 0..1
        float           pause{ 0.0f };      // seconds at trough between cycles
        float           start_time{ 0.0f }; // real-time epoch
        std::int32_t    base_slot{ 2 };     // NiOverride body overlay base slot (matches Papyrus OverlaySlot)
        std::int32_t    layer_count{ 0 };
        bool            is_female{ false };
        std::array<float, 4> layer_base_em_mult{};  // emissive intensity ceiling per layer

        // Waveform LUT, sampled across one full cycle (phase 0..1). When
        // has_wave_lut is false, Tick falls back to a cosine wave (same
        // shape the plugin shipped with before custom waveforms landed).
        static constexpr std::size_t kWaveLUTSize = 64;
        std::array<float, kWaveLUTSize> wave_lut{};
        bool            has_wave_lut{ false };
    };

    class Roster
    {
    public:
        static Roster& Instance();

        // Capacity is fixed; eviction policy is farthest-from-player.
        // Entries are keyed by (actor_formID, base_slot) so a single actor
        // can hold multiple stacked-preset entries simultaneously, each
        // driving its own disjoint NiOverride slot range.
        static constexpr std::size_t kCapacity = 128;

        void SetEnabled(bool on);
        bool IsEnabled() const { return enabled_.load(std::memory_order_relaxed); }

        // Add or refresh. Identity = (actor formID, entry.base_slot).
        // Returns true if the entry is now in the roster.
        bool Set(RE::Actor* actor, const PulseEntry& entry);

        // Remove ONE entry by (actor, base_slot). Returns true if removed.
        bool ClearAt(RE::Actor* actor, std::int32_t base_slot);

        // Remove EVERY entry for an actor (e.g. on death / unload).
        // Returns the count of entries removed.
        std::size_t ClearAllForActor(RE::Actor* actor);

        void ClearAll();

        // Called from the per-frame hook.
        void Tick();

        std::size_t Size() const;

    private:
        Roster() = default;

        // entries_ is fixed-size. count_ tracks current population.
        std::array<PulseEntry, kCapacity> entries_{};
        std::size_t count_{ 0 };

        // Mutex guards entries_/count_. The Set/Clear callbacks come from
        // Papyrus VM threads; Tick runs on the main thread.
        mutable std::mutex mtx_;
        std::atomic<bool>  enabled_{ true };

        // Find by (FormID, base_slot). -1 if not present. mtx_ held.
        std::int32_t FindLocked(std::uint32_t formID, std::int32_t base_slot) const;
        void         RemoveAtLocked(std::size_t slot);
        void         EvictFarthestLocked(RE::TESObjectREFR* anchor);
    };

}  // namespace MTFPulse
