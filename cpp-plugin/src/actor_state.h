#pragma once

// Tier 2 #2: per-(actor, preset) state cache.
//
// Mirrors the StorageUtil-backed `mtf.preset.<name>.<field>` keys per actor
// in MTF_MainQuest. Writes are write-through (both C++ + StorageUtil); reads
// check C++ first and fall back to StorageUtil on miss (the fallback then
// populates C++ via the next write so subsequent reads hit C++).
//
// Lifetime: process-scoped — same as PresetRegistry. State is recovered on
// a fresh DLL session by the first Get-miss falling through to StorageUtil.
// No SKSE Serialization is registered; StorageUtil is the durable source of
// truth.

#include <array>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

namespace MTFPulse {

    // Per-field "uninitialized" sentinels. When an entry is first created
    // via SetTier, the OTHER fields default to these — Get returns the
    // sentinel, signalling Papyrus to fall through to StorageUtil for that
    // specific field. This avoids the operator[] default-constructed-fields
    // bug where a SetTier would mask a real StorageUtil base/layers value.
    constexpr std::int32_t kFieldUninitInt   = INT32_MIN;
    constexpr float        kFieldUninitFloat = -987654321.0f;

    struct ActorPresetState
    {
        static constexpr std::size_t kSlots = 16;  // MAX_CONDITIONS upper bound
        static constexpr std::size_t kAreas = 4;   // body/face/hands/feet

        // Default constructor fills arrays with field-uninitialized sentinels.
        // Don't default to "real" values like -1/0 — those collide with the
        // legitimate defaults Papyrus would return on a fresh StorageUtil key
        // (e.g. tier defaults to -1, layers defaults to 0).
        ActorPresetState()
            : tier{kFieldUninitInt},
              pulse_start_rt{kFieldUninitFloat},
              base{kFieldUninitInt, kFieldUninitInt, kFieldUninitInt, kFieldUninitInt},
              layers{kFieldUninitInt, kFieldUninitInt, kFieldUninitInt, kFieldUninitInt}
        {
            persist_until.fill(kFieldUninitFloat);
            cool_until.fill(kFieldUninitFloat);
        }

        std::int32_t tier;
        float        pulse_start_rt;
        std::array<float, kSlots>        persist_until;
        std::array<float, kSlots>        cool_until;
        std::array<std::int32_t, kAreas> base;
        std::array<std::int32_t, kAreas> layers;
    };

    class ActorStateRegistry
    {
    public:
        static ActorStateRegistry& Instance();

        // Key: (actor formID, preset name). FormID is enough — we don't need
        // to pin actor pointers and survive Form recycling, because the
        // StorageUtil keys are also formID-scoped, so if the formID is reused
        // the StorageUtil values would also be wrong. Same blast radius.

        std::optional<std::int32_t> GetTier(std::uint32_t actor_form_id, std::string_view preset) const;
        void SetTier(std::uint32_t actor_form_id, std::string preset, std::int32_t tier);

        std::optional<float> GetPulseStartRT(std::uint32_t actor_form_id, std::string_view preset) const;
        void SetPulseStartRT(std::uint32_t actor_form_id, std::string preset, float t);

        std::optional<float> GetPersistUntil(std::uint32_t actor_form_id, std::string_view preset, std::int32_t slot) const;
        void SetPersistUntil(std::uint32_t actor_form_id, std::string preset, std::int32_t slot, float t);

        std::optional<float> GetCoolUntil(std::uint32_t actor_form_id, std::string_view preset, std::int32_t slot) const;
        void SetCoolUntil(std::uint32_t actor_form_id, std::string preset, std::int32_t slot, float t);

        std::optional<std::int32_t> GetBase(std::uint32_t actor_form_id, std::string_view preset, std::int32_t area) const;
        void SetBase(std::uint32_t actor_form_id, std::string preset, std::int32_t area, std::int32_t value);

        std::optional<std::int32_t> GetLayers(std::uint32_t actor_form_id, std::string_view preset, std::int32_t area) const;
        void SetLayers(std::uint32_t actor_form_id, std::string preset, std::int32_t area, std::int32_t value);

        // Removes the (actor, preset) entry entirely.
        void Clear(std::uint32_t actor_form_id, std::string_view preset);

        // Diagnostics.
        std::size_t Size() const;

    private:
        ActorStateRegistry() = default;

        struct Key
        {
            std::uint32_t form_id;
            std::string   preset;
            bool operator==(const Key& o) const noexcept
            { return form_id == o.form_id && preset == o.preset; }
        };
        struct KeyHash
        {
            std::size_t operator()(const Key& k) const noexcept
            {
                // Mix formID with the preset name's std::hash. xor-shift is
                // good enough — collisions just walk a bucket.
                std::size_t h1 = std::hash<std::uint32_t>{}(k.form_id);
                std::size_t h2 = std::hash<std::string>{}(k.preset);
                return h1 ^ (h2 + 0x9e3779b9u + (h1 << 6) + (h1 >> 2));
            }
        };

        mutable std::mutex mtx_;
        std::unordered_map<Key, ActorPresetState, KeyHash> states_;
    };

}  // namespace MTFPulse
