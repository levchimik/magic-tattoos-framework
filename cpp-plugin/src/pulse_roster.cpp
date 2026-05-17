#include "pulse_roster.h"
#include "log.h"
#include "skee_bridge.h"

#include <cmath>
#include <numbers>
#include <cstdio>

namespace MTFPulse {

    Roster& Roster::Instance()
    {
        static Roster s;
        return s;
    }

    void Roster::SetEnabled(bool on)
    {
        enabled_.store(on, std::memory_order_relaxed);
    }

    std::size_t Roster::Size() const
    {
        std::lock_guard lock(mtx_);
        return count_;
    }

    std::int32_t Roster::FindLocked(std::uint32_t formID) const
    {
        for (std::size_t i = 0; i < count_; ++i) {
            if (entries_[i].actor_formID == formID) {
                return static_cast<std::int32_t>(i);
            }
        }
        return -1;
    }

    void Roster::EvictFarthestLocked(RE::TESObjectREFR* anchor)
    {
        if (count_ == 0 || !anchor) {
            return;
        }
        const auto anchor_pos = anchor->GetPosition();
        std::int32_t worst    = -1;
        float        worst_d2 = -1.0f;
        for (std::size_t i = 0; i < count_; ++i) {
            auto a = entries_[i].actor.get().get();
            if (!a) {
                worst = static_cast<std::int32_t>(i);
                break;
            }
            const auto pos = a->GetPosition();
            const float dx = pos.x - anchor_pos.x;
            const float dy = pos.y - anchor_pos.y;
            const float dz = pos.z - anchor_pos.z;
            const float d2 = dx * dx + dy * dy + dz * dz;
            if (d2 > worst_d2) {
                worst_d2 = d2;
                worst    = static_cast<std::int32_t>(i);
            }
        }
        if (worst < 0) {
            return;
        }
        // Compact: move last into slot `worst`.
        const auto last = count_ - 1;
        if (static_cast<std::size_t>(worst) != last) {
            entries_[worst] = entries_[last];
        }
        entries_[last] = PulseEntry{};
        --count_;
    }

    bool Roster::Set(RE::Actor* actor, const PulseEntry& src)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();

        std::int32_t slot = FindLocked(formID);
        if (slot < 0) {
            if (count_ >= kCapacity) {
                auto* player = RE::PlayerCharacter::GetSingleton();
                EvictFarthestLocked(player);
            }
            if (count_ >= kCapacity) {
                return false;
            }
            slot = static_cast<std::int32_t>(count_++);
        }
        entries_[slot]              = src;
        entries_[slot].actor        = actor->GetHandle();
        entries_[slot].actor_formID = formID;
        return true;
    }

    bool Roster::Clear(RE::Actor* actor)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto   formID = actor->GetFormID();
        std::int32_t slot   = FindLocked(formID);
        if (slot < 0) {
            return false;
        }
        const auto last = count_ - 1;
        if (static_cast<std::size_t>(slot) != last) {
            entries_[slot] = entries_[last];
        }
        entries_[last] = PulseEntry{};
        --count_;
        return true;
    }

    void Roster::ClearAll()
    {
        std::lock_guard lock(mtx_);
        for (std::size_t i = 0; i < count_; ++i) {
            entries_[i] = PulseEntry{};
        }
        count_ = 0;
    }

    // Per-frame tick. Wave model mirrors the Papyrus path exactly:
    //   wave = (in cycle) 0.5 - 0.5·cos(2π·rate·tMod)
    //          (in pause) 0
    //   mult = (1 - depth) + depth · wave
    void Roster::Tick()
    {
        if (!enabled_.load(std::memory_order_relaxed)) {
            return;
        }
        std::lock_guard lock(mtx_);
        if (count_ == 0) {
            return;
        }

        // Real time clock: GetGameTime() is in days; we want seconds. SKSE's
        // calendar singleton has nanos but not a frame-coherent realtime.
        // Use the Calendar's game-time-since-start in hours converted to s,
        // multiplied by the day-length ratio? Simpler: use the menu manager's
        // global anim time. TODO: pick the same clock Papyrus' Utility.GetCurrentRealTime
        // exposes — under the hood it's the game's "wall-clock since launch"
        // value. For now use a steady_clock against a static start.
        static const auto t_origin = std::chrono::steady_clock::now();
        const auto now_pt          = std::chrono::steady_clock::now();
        const float now            = std::chrono::duration<float>(now_pt - t_origin).count();

        // Bail early if SKEE didn't initialise — no point computing waves
        // we can't write. The bridge logs the failure once at startup.
        if (!skee_bridge::IsReady()) {
            return;
        }

        for (std::size_t i = 0; i < count_; ++i) {
            auto& e = entries_[i];
            auto* actor = e.actor.get().get();
            if (!actor) {
                continue;
            }
            const float t      = now - e.start_time;
            const float depth  = e.depth;
            const float floorM = 1.0f - depth;
            float wave;
            if (e.pause > 0.0f && e.rate > 0.0f) {
                const float cycle  = 1.0f / e.rate;
                const float period = cycle + e.pause;
                const float tMod   = t - std::floor(t / period) * period;
                if (tMod < cycle) {
                    wave = 0.5f - 0.5f * std::cos(tMod * e.rate * 2.0f * std::numbers::pi_v<float>);
                } else {
                    wave = 0.0f;
                }
            } else {
                wave = 0.5f - 0.5f * std::cos(t * e.rate * 2.0f * std::numbers::pi_v<float>);
            }
            const float pulsed = floorM + depth * wave;

            // One write per active layer: nodes are named "Body [ovlN]"
            // where N = base_slot + layer_index (matches MTF_MainQuest's
            // applyOverlay format). The per-layer base emissive multiplier
            // is the ceiling — pulse modulates between (1-depth)*ceiling
            // and 1.0*ceiling.
            char node[32];
            for (std::int32_t li = 0; li < e.layer_count; ++li) {
                std::snprintf(node, sizeof(node), "Body [ovl%d]",
                              static_cast<int>(e.base_slot + li));
                const float layerCeiling = e.layer_base_em_mult[static_cast<std::size_t>(li)];
                const float final_mult   = pulsed * layerCeiling;
                skee_bridge::WriteEmissiveMult(actor, e.is_female, node, final_mult);
            }
        }
    }

}  // namespace MTFPulse
