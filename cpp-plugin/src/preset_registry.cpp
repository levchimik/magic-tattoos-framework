#include "preset_registry.h"

namespace MTFPulse {

    PresetRegistry& PresetRegistry::Instance()
    {
        static PresetRegistry inst;
        return inst;
    }

    std::size_t PresetRegistry::Set(std::string name, PresetData data)
    {
        std::lock_guard<std::mutex> g(mtx_);
        presets_.insert_or_assign(std::move(name), std::move(data));
        return presets_.size();
    }

    std::optional<PresetData> PresetRegistry::Get(std::string_view name) const
    {
        std::lock_guard<std::mutex> g(mtx_);
        auto it = presets_.find(std::string(name));
        if (it == presets_.end()) {
            return std::nullopt;
        }
        return it->second;
    }

    bool PresetRegistry::Has(std::string_view name) const
    {
        std::lock_guard<std::mutex> g(mtx_);
        return presets_.find(std::string(name)) != presets_.end();
    }

    bool PresetRegistry::Remove(std::string_view name)
    {
        std::lock_guard<std::mutex> g(mtx_);
        return presets_.erase(std::string(name)) > 0;
    }

    std::size_t PresetRegistry::Size() const
    {
        std::lock_guard<std::mutex> g(mtx_);
        return presets_.size();
    }

    void PresetRegistry::Clear()
    {
        std::lock_guard<std::mutex> g(mtx_);
        presets_.clear();
    }

}  // namespace MTFPulse
