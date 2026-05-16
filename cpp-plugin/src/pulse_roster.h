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
    };

    class Roster
    {
    public:
        static Roster& Instance();

        // Capacity is fixed; eviction policy is farthest-from-player.
        static constexpr std::size_t kCapacity = 32;  // generous vs Papyrus' 8

        void SetEnabled(bool on);
        bool IsEnabled() const { return enabled_.load(std::memory_order_relaxed); }

        // Add or refresh. Returns true if the actor is now in the roster.
        bool Set(RE::Actor* actor, const PulseEntry& entry);
        bool Clear(RE::Actor* actor);
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

        // Find by FormID. -1 if not present. Must be called with mtx_ held.
        std::int32_t FindLocked(std::uint32_t formID) const;
        void         EvictFarthestLocked(RE::TESObjectREFR* anchor);
    };

}  // namespace MTFPulse
