#include "actor_state.h"

namespace MTFPulse {

    ActorStateRegistry& ActorStateRegistry::Instance()
    {
        static ActorStateRegistry inst;
        return inst;
    }

    // Helpers to clamp slot/area indices into the fixed-size arrays. Out-of-
    // range returns std::nullopt on reads and is a silent no-op on writes —
    // matches the existing Papyrus accessors' lenient bounds (e.g.
    // `_getActorPresetBase` returns -1 on bad area, doesn't crash).

    static bool ValidSlot(std::int32_t slot)
    {
        return slot >= 0 && slot < static_cast<std::int32_t>(ActorPresetState::kSlots);
    }
    static bool ValidArea(std::int32_t area)
    {
        return area >= 0 && area < static_cast<std::int32_t>(ActorPresetState::kAreas);
    }

    std::optional<std::int32_t> ActorStateRegistry::GetTier(std::uint32_t form_id, std::string_view preset) const
    {
        std::lock_guard<std::mutex> g(mtx_);
        auto it = states_.find(Key{form_id, std::string(preset)});
        if (it == states_.end()) return std::nullopt;
        return it->second.tier;
    }

    void ActorStateRegistry::SetTier(std::uint32_t form_id, std::string preset, std::int32_t tier)
    {
        std::lock_guard<std::mutex> g(mtx_);
        states_[Key{form_id, std::move(preset)}].tier = tier;
    }

    std::optional<float> ActorStateRegistry::GetPulseStartRT(std::uint32_t form_id, std::string_view preset) const
    {
        std::lock_guard<std::mutex> g(mtx_);
        auto it = states_.find(Key{form_id, std::string(preset)});
        if (it == states_.end()) return std::nullopt;
        return it->second.pulse_start_rt;
    }

    void ActorStateRegistry::SetPulseStartRT(std::uint32_t form_id, std::string preset, float t)
    {
        std::lock_guard<std::mutex> g(mtx_);
        states_[Key{form_id, std::move(preset)}].pulse_start_rt = t;
    }

    std::optional<float> ActorStateRegistry::GetPersistUntil(std::uint32_t form_id, std::string_view preset, std::int32_t slot) const
    {
        if (!ValidSlot(slot)) return std::nullopt;
        std::lock_guard<std::mutex> g(mtx_);
        auto it = states_.find(Key{form_id, std::string(preset)});
        if (it == states_.end()) return std::nullopt;
        return it->second.persist_until[static_cast<std::size_t>(slot)];
    }

    void ActorStateRegistry::SetPersistUntil(std::uint32_t form_id, std::string preset, std::int32_t slot, float t)
    {
        if (!ValidSlot(slot)) return;
        std::lock_guard<std::mutex> g(mtx_);
        states_[Key{form_id, std::move(preset)}].persist_until[static_cast<std::size_t>(slot)] = t;
    }

    std::optional<float> ActorStateRegistry::GetCoolUntil(std::uint32_t form_id, std::string_view preset, std::int32_t slot) const
    {
        if (!ValidSlot(slot)) return std::nullopt;
        std::lock_guard<std::mutex> g(mtx_);
        auto it = states_.find(Key{form_id, std::string(preset)});
        if (it == states_.end()) return std::nullopt;
        return it->second.cool_until[static_cast<std::size_t>(slot)];
    }

    void ActorStateRegistry::SetCoolUntil(std::uint32_t form_id, std::string preset, std::int32_t slot, float t)
    {
        if (!ValidSlot(slot)) return;
        std::lock_guard<std::mutex> g(mtx_);
        states_[Key{form_id, std::move(preset)}].cool_until[static_cast<std::size_t>(slot)] = t;
    }

    std::optional<std::int32_t> ActorStateRegistry::GetBase(std::uint32_t form_id, std::string_view preset, std::int32_t area) const
    {
        if (!ValidArea(area)) return std::nullopt;
        std::lock_guard<std::mutex> g(mtx_);
        auto it = states_.find(Key{form_id, std::string(preset)});
        if (it == states_.end()) return std::nullopt;
        return it->second.base[static_cast<std::size_t>(area)];
    }

    void ActorStateRegistry::SetBase(std::uint32_t form_id, std::string preset, std::int32_t area, std::int32_t value)
    {
        if (!ValidArea(area)) return;
        std::lock_guard<std::mutex> g(mtx_);
        states_[Key{form_id, std::move(preset)}].base[static_cast<std::size_t>(area)] = value;
    }

    std::optional<std::int32_t> ActorStateRegistry::GetLayers(std::uint32_t form_id, std::string_view preset, std::int32_t area) const
    {
        if (!ValidArea(area)) return std::nullopt;
        std::lock_guard<std::mutex> g(mtx_);
        auto it = states_.find(Key{form_id, std::string(preset)});
        if (it == states_.end()) return std::nullopt;
        return it->second.layers[static_cast<std::size_t>(area)];
    }

    void ActorStateRegistry::SetLayers(std::uint32_t form_id, std::string preset, std::int32_t area, std::int32_t value)
    {
        if (!ValidArea(area)) return;
        std::lock_guard<std::mutex> g(mtx_);
        states_[Key{form_id, std::move(preset)}].layers[static_cast<std::size_t>(area)] = value;
    }

    void ActorStateRegistry::Clear(std::uint32_t form_id, std::string_view preset)
    {
        std::lock_guard<std::mutex> g(mtx_);
        states_.erase(Key{form_id, std::string(preset)});
    }

    std::size_t ActorStateRegistry::Size() const
    {
        std::lock_guard<std::mutex> g(mtx_);
        return states_.size();
    }

}  // namespace MTFPulse
