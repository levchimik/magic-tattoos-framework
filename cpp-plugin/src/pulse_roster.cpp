#include "pulse_roster.h"
#include "log.h"
#include "skee_bridge.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <numbers>
#include <cstdio>

namespace MTFPulse {

    namespace {
        // Steady-clock epoch shared by Set() (for transition_start) and
        // Tick() (for the per-frame `now`). Plugin-init relative; the
        // pulse-phase math doesn't care about absolute epoch because the
        // wave is periodic, but the *transition* lerp does need consistent
        // arithmetic between when we record the start and when we measure
        // elapsed.
        const auto& TOrigin()
        {
            static const auto t = std::chrono::steady_clock::now();
            return t;
        }

        float NowSec()
        {
            return std::chrono::duration<float>(std::chrono::steady_clock::now() - TOrigin()).count();
        }

        // Cosine ease-in-out: 0 at p=0, 1 at p=1, derivative=0 at both
        // ends — looks more natural than a linear ramp for tint/alpha.
        float EaseInOut(float p)
        {
            p = std::clamp(p, 0.0f, 1.0f);
            return 0.5f - 0.5f * std::cos(p * std::numbers::pi_v<float>);
        }

        // Per-channel RGB lerp. Tints are packed 0x00RRGGBB.
        std::int32_t LerpRgb(std::int32_t a, std::int32_t b, float t)
        {
            t = std::clamp(t, 0.0f, 1.0f);
            const int ar = (a >> 16) & 0xFF;
            const int ag = (a >> 8)  & 0xFF;
            const int ab =  a        & 0xFF;
            const int br = (b >> 16) & 0xFF;
            const int bg = (b >> 8)  & 0xFF;
            const int bb =  b        & 0xFF;
            const int r  = std::clamp(static_cast<int>(ar + (br - ar) * t + 0.5f), 0, 255);
            const int g  = std::clamp(static_cast<int>(ag + (bg - ag) * t + 0.5f), 0, 255);
            const int bl = std::clamp(static_cast<int>(ab + (bb - ab) * t + 0.5f), 0, 255);
            return (r << 16) | (g << 8) | bl;
        }
    }  // namespace

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

    std::int32_t Roster::FindLocked(std::uint32_t formID, std::int32_t base_slot) const
    {
        for (std::size_t i = 0; i < count_; ++i) {
            if (entries_[i].actor_formID == formID && entries_[i].base_slot == base_slot) {
                return static_cast<std::int32_t>(i);
            }
        }
        return -1;
    }

    void Roster::RemoveAtLocked(std::size_t slot)
    {
        if (slot >= count_) {
            return;
        }
        const auto last = count_ - 1;
        if (slot != last) {
            entries_[slot] = entries_[last];
        }
        entries_[last] = PulseEntry{};
        --count_;
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
        RemoveAtLocked(static_cast<std::size_t>(worst));
    }

    bool Roster::Set(RE::Actor* actor, const PulseEntry& src)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();

        std::int32_t slot = FindLocked(formID, src.base_slot);

        // Capture transition from-state from the existing entry's last
        // interpolated values (if any) BEFORE overwriting the slot. This
        // lets chained transitions (a new tier change while a previous
        // cross-fade is still in flight) start from the current visual
        // state rather than snapping back to the previous tier's target.
        //
        // For fresh entries (no previous), from_ defaults to target_ —
        // the transition runs for `duration` seconds but is visually a
        // no-op. Authors who want a "fade in from invisible" on first
        // apply should author the preset's tier-0 with alpha=0; the next
        // tier transition will then naturally fade alpha up.
        PulseEntry seeded = src;

        // Preserve flash state across Set() — both hot state (last_hit /
        // intensity / last_tick) AND the configured parameters (mask, peak,
        // ramp, decay, retrigger). v0.1.3 effect-binding design means
        // SetActorFlash is called once on flash.onhit's onActivate, then
        // refreshed on the slow (~2s) onTick. But SetActorPulse runs at
        // 10 Hz to keep the per-layer emissive ceilings in sync — if Set()
        // overwrites flash params with src's defaults, the 100ms after each
        // _applyPulse wipes the flash configuration, dropping hits.
        //
        // SetFlashParams writes directly to entries_[slot] (no Set() trip),
        // so callers that legitimately update flash params still take
        // effect. Tier changes deactivate cleanly: ClearActorFlash on the
        // OLD effect empties the tag set before _applyPulse runs for the
        // new tier, so preserving "tags={}" is the right behavior there.
        if (slot >= 0) {
            const auto& prev = entries_[slot];
            seeded.flash_tags          = prev.flash_tags;
            seeded.flash_peak_emissive = prev.flash_peak_emissive;
            seeded.flash_ramp_ms       = prev.flash_ramp_ms;
            seeded.flash_decay_ms      = prev.flash_decay_ms;
            seeded.flash_retrigger_ms  = prev.flash_retrigger_ms;
            seeded.flash_last_hit      = prev.flash_last_hit;
            seeded.flash_last_tag      = prev.flash_last_tag;
            seeded.flash_intensity     = prev.flash_intensity;
            seeded.flash_last_tick     = prev.flash_last_tick;
        }

        if (slot >= 0 && src.transition_duration > 0.0f) {
            const auto& prev = entries_[slot];
            const std::int32_t copyN = std::clamp<std::int32_t>(src.layer_count, 0, 4);
            for (std::int32_t i = 0; i < copyN; ++i) {
                const auto L = static_cast<std::size_t>(i);
                if (prev.has_last_interp) {
                    seeded.from_em_mult[L]  = prev.last_interp_em_mult[L];
                    seeded.from_alpha[L]    = prev.last_interp_alpha[L];
                    seeded.from_tint[L]     = prev.last_interp_tint[L];
                    seeded.from_emissive[L] = prev.last_interp_emissive[L];
                } else {
                    // No prior frame ran — fall back to prev's target.
                    seeded.from_em_mult[L]  = prev.layer_base_em_mult[L];
                    seeded.from_alpha[L]    = prev.target_alpha[L];
                    seeded.from_tint[L]     = prev.target_tint[L];
                    seeded.from_emissive[L] = prev.target_emissive[L];
                }
            }
            seeded.transition_start = NowSec();
            seeded.has_last_interp  = false;  // Tick will repopulate this frame
        } else if (slot < 0 && src.transition_duration > 0.0f) {
            // Fresh entry: from_ = target_ ⇒ visually instant.
            const std::int32_t copyN = std::clamp<std::int32_t>(src.layer_count, 0, 4);
            for (std::int32_t i = 0; i < copyN; ++i) {
                const auto L = static_cast<std::size_t>(i);
                seeded.from_em_mult[L]  = src.layer_base_em_mult[L];
                seeded.from_alpha[L]    = src.target_alpha[L];
                seeded.from_tint[L]     = src.target_tint[L];
                seeded.from_emissive[L] = src.target_emissive[L];
            }
            seeded.transition_start = NowSec();
            seeded.has_last_interp  = false;
        }

        if (slot < 0) {
            if (count_ >= kCapacity) {
                auto* player = RE::PlayerCharacter::GetSingleton();
                EvictFarthestLocked(player);
            }
            if (count_ >= kCapacity) {
                spdlog::warn("Roster::Set FULL formID=0x{:08x} base_slot={} kCapacity={}",
                             formID, src.base_slot, kCapacity);
                return false;
            }
            slot = static_cast<std::int32_t>(count_++);
        }
        entries_[slot]              = seeded;
        entries_[slot].actor        = actor->GetHandle();
        entries_[slot].actor_formID = formID;
        return true;
    }

    bool Roster::ClearAt(RE::Actor* actor, std::int32_t base_slot)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const std::int32_t slot = FindLocked(formID, base_slot);
        if (slot < 0) {
            return false;
        }
        RemoveAtLocked(static_cast<std::size_t>(slot));
        return true;
    }

    std::size_t Roster::ClearAllForActor(RE::Actor* actor)
    {
        if (!actor) {
            return 0;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        std::size_t removed = 0;
        // Walk backwards so RemoveAtLocked's last-into-slot compaction
        // doesn't make us skip entries.
        for (std::size_t i = count_; i-- > 0;) {
            if (entries_[i].actor_formID == formID) {
                RemoveAtLocked(i);
                ++removed;
            }
        }
        return removed;
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
    //
    // When an entry is mid-transition (transition_duration > 0 and we're
    // still within the window), three properties cross-fade from the
    // captured from_* values to the entry's target values:
    //   - emissive_mult ceiling (per layer) — the value pulse modulates
    //   - alpha (per layer) — written via skee_bridge during transition
    //   - tint (per layer) — written via skee_bridge during transition
    // Depth/rate/pause snap to the new values immediately. After the
    // transition window closes we zero transition_duration so subsequent
    // frames take the fast steady-pulse path; alpha/tint writes stop and
    // the Papyrus-side ApplyNodeOverrides values remain on the live node.
    void Roster::Tick()
    {
        if (!enabled_.load(std::memory_order_relaxed)) {
            return;
        }
        std::lock_guard lock(mtx_);
        if (count_ == 0) {
            return;
        }

        const float now = NowSec();

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

            // Sample the waveform at the current phase. With pause > 0 the
            // wave runs for one cycle then holds at 0 for `pause` seconds
            // before starting again — matches the Papyrus implementation
            // and the wave_lut covers exactly one cycle, not the dwell.
            auto sample = [&](float phase) -> float {
                if (e.has_wave_lut) {
                    // Wrap phase into [0,1) then bilinear-blend the two
                    // adjacent LUT samples.
                    phase -= std::floor(phase);
                    const float fi   = phase * static_cast<float>(PulseEntry::kWaveLUTSize);
                    const auto  i0   = static_cast<std::size_t>(fi) % PulseEntry::kWaveLUTSize;
                    const auto  i1   = (i0 + 1) % PulseEntry::kWaveLUTSize;
                    const float frac = fi - std::floor(fi);
                    return e.wave_lut[i0] + (e.wave_lut[i1] - e.wave_lut[i0]) * frac;
                }
                return 0.5f - 0.5f * std::cos(phase * 2.0f * std::numbers::pi_v<float>);
            };

            float wave;
            if (e.pause > 0.0f && e.rate > 0.0f) {
                const float cycle  = 1.0f / e.rate;
                const float period = cycle + e.pause;
                const float tMod   = t - std::floor(t / period) * period;
                if (tMod < cycle) {
                    wave = sample(tMod * e.rate);
                } else {
                    wave = 0.0f;
                }
            } else if (e.rate > 0.0f) {
                wave = sample(t * e.rate);
            } else {
                wave = 0.0f;
            }
            const float pulsed = floorM + depth * wave;

            // Transition state: if we're inside the cross-fade window, set
            // `transitioning=true` and compute `eased` ∈ [0,1]. Otherwise
            // the layer loop uses target values directly.
            bool  transitioning = false;
            float eased         = 1.0f;
            if (e.transition_duration > 0.0f) {
                const float tt = now - e.transition_start;
                if (tt >= e.transition_duration) {
                    // Window closed. Snap to target and disable future
                    // transition processing on this entry.
                    e.transition_duration = 0.0f;
                    eased = 1.0f;
                } else if (tt <= 0.0f) {
                    // Clock skew or just-set entry — treat as start.
                    eased = 0.0f;
                    transitioning = true;
                } else {
                    eased = EaseInOut(tt / e.transition_duration);
                    transitioning = true;
                }
            }

            // Flash envelope (v0.1.3 additive). When a qualifying hit has
            // stamped flash_last_hit, target=1 while within retrigger window
            // — past that, target=0 and intensity eases out.
            //
            // v0.1.3 changed the lane from multiplicative to additive:
            //   old: final = pulsed * ceiling * (1 + (peak-1)*intensity)
            //   new: final = pulsed * ceiling + peak_add * intensity
            // The additive form means a tattoo with emissivemult=0 (visually
            // off in the steady state) can still glow on hit — the additive
            // lane bypasses the ceiling entirely. flash_peak_emissive now
            // holds the additive amount at intensity=1 (NOT a multiplier).
            // 0 disables the lane.
            float flash_add = 0.0f;
            if (!e.flash_tags.empty() && e.flash_peak_emissive > 0.0f) {
                const float dt_sec = (e.flash_last_tick > 0.0f)
                    ? std::max(0.0f, now - e.flash_last_tick)
                    : 0.0f;
                const float retrig_sec = e.flash_retrigger_ms * 0.001f;
                const float target = ((now - e.flash_last_hit) < retrig_sec) ? 1.0f : 0.0f;
                if (e.flash_intensity < target) {
                    const float step = (e.flash_ramp_ms > 0.0f)
                        ? (dt_sec * 1000.0f / e.flash_ramp_ms)
                        : 1.0f;
                    e.flash_intensity = std::min(target, e.flash_intensity + step);
                } else if (e.flash_intensity > target) {
                    const float step = (e.flash_decay_ms > 0.0f)
                        ? (dt_sec * 1000.0f / e.flash_decay_ms)
                        : 1.0f;
                    e.flash_intensity = std::max(target, e.flash_intensity - step);
                }
                flash_add = e.flash_peak_emissive * e.flash_intensity;
            }
            e.flash_last_tick = now;

            // One write per active layer: nodes are named "Body [ovlN]"
            // where N = base_slot + layer_index (matches MTF_MainQuest's
            // applyOverlay format). The per-layer base emissive multiplier
            // is the ceiling — pulse modulates between (1-depth)*ceiling
            // and 1.0*ceiling.
            char node[32];
            for (std::int32_t li = 0; li < e.layer_count; ++li) {
                const auto L = static_cast<std::size_t>(li);
                std::snprintf(node, sizeof(node), "Body [ovl%d]",
                              static_cast<int>(e.base_slot + li));

                // Effective ceiling = lerp(from, target, eased) while
                // transitioning, just `target` otherwise.
                float ceiling = e.layer_base_em_mult[L];
                if (transitioning) {
                    ceiling = e.from_em_mult[L] + (e.layer_base_em_mult[L] - e.from_em_mult[L]) * eased;
                }

                const float final_mult = pulsed * ceiling + flash_add;
                skee_bridge::WriteEmissiveMult(actor, e.is_female, node, final_mult);
                e.last_interp_em_mult[L] = ceiling;

                if (transitioning) {
                    const float        alpha    = e.from_alpha[L] + (e.target_alpha[L] - e.from_alpha[L]) * eased;
                    const std::int32_t tint     = LerpRgb(e.from_tint[L],     e.target_tint[L],     eased);
                    const std::int32_t emissive = LerpRgb(e.from_emissive[L], e.target_emissive[L], eased);
                    skee_bridge::WriteAlpha(actor, e.is_female, node, alpha);
                    skee_bridge::WriteTint(actor, e.is_female, node, tint);
                    skee_bridge::WriteEmissiveColor(actor, e.is_female, node, emissive);
                    e.last_interp_alpha[L]    = alpha;
                    e.last_interp_tint[L]     = tint;
                    e.last_interp_emissive[L] = emissive;
                } else {
                    // Steady state — last_interp tracks target so a future
                    // transition snapshots the right "from" without
                    // needing a frame of catch-up.
                    e.last_interp_alpha[L]    = e.target_alpha[L];
                    e.last_interp_tint[L]     = e.target_tint[L];
                    e.last_interp_emissive[L] = e.target_emissive[L];
                }
            }
            e.has_last_interp = true;
        }
    }

    bool Roster::SetFlashParams(RE::Actor* actor, std::int32_t base_slot,
                                float peak_emissive, float ramp_ms,
                                float decay_ms, float retrigger_ms,
                                std::unordered_set<std::string> tags)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const std::int32_t slot = FindLocked(formID, base_slot);
        if (slot < 0) {
            spdlog::warn("MTFFlash SetFlashParams MISS formID=0x{:08x} base_slot={} count={}",
                         formID, base_slot, count_);
            return false;
        }
        auto& e = entries_[slot];
        e.flash_peak_emissive = std::max(0.0f, peak_emissive);
        e.flash_ramp_ms       = std::max(1.0f, ramp_ms);
        e.flash_decay_ms      = std::max(1.0f, decay_ms);
        e.flash_retrigger_ms  = std::max(0.0f, retrigger_ms);
        e.flash_tags          = std::move(tags);
        return true;
    }

    bool Roster::ClearFlash(RE::Actor* actor, std::int32_t base_slot)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const std::int32_t slot = FindLocked(actor->GetFormID(), base_slot);
        if (slot < 0) {
            return false;
        }
        entries_[slot].flash_tags.clear();
        return true;
    }

    bool Roster::TriggerFlash(RE::Actor* actor, std::int32_t base_slot,
                              std::string_view tag)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const std::int32_t slot = FindLocked(formID, base_slot);
        if (slot < 0) {
            spdlog::warn("MTFFlash TriggerFlash MISS_ENTRY formID=0x{:08x} base_slot={} tag={}",
                         formID, base_slot, std::string(tag));
            return false;
        }
        auto& e = entries_[slot];
        if (e.flash_tags.empty()) {
            spdlog::warn("MTFFlash TriggerFlash TAGS_EMPTY formID=0x{:08x} base_slot={} tag={} peak={:.2f}",
                         formID, base_slot, std::string(tag), e.flash_peak_emissive);
            return false;
        }
        // "*" is the wildcard tag — matches any incoming tag, including
        // tags fired by external mods through their own
        // MTFPulse.TriggerActorFlash calls. Otherwise exact membership.
        const bool wildcard = e.flash_tags.count("*") > 0;
        if (!wildcard) {
            // unordered_set<string>::find with string_view via heterogeneous
            // lookup isn't trivially set up without a custom hash; just
            // promote to string for the lookup. Tag strings are tiny.
            if (e.flash_tags.find(std::string(tag)) == e.flash_tags.end()) {
                return false;
            }
        }
        e.flash_last_hit = NowSec();
        e.flash_last_tag.assign(tag.data(), tag.size());
        return true;
    }

    std::size_t Roster::TriggerFlashAllSlotsForActor(RE::Actor* actor,
                                                     std::string_view tag)
    {
        if (!actor) {
            return 0;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const auto now    = NowSec();
        std::size_t hits  = 0;
        // No wildcard semantics here beyond what each entry's own
        // flash_tags decides — we just walk matching entries and apply
        // the same gate TriggerFlash uses.
        for (std::size_t i = 0; i < count_; ++i) {
            auto& e = entries_[i];
            if (e.actor_formID != formID) {
                continue;
            }
            if (e.flash_tags.empty()) {
                continue;
            }
            bool fire = e.flash_tags.count("*") > 0;
            if (!fire) {
                if (e.flash_tags.find(std::string(tag)) == e.flash_tags.end()) {
                    continue;
                }
            }
            e.flash_last_hit = now;
            e.flash_last_tag.assign(tag.data(), tag.size());
            ++hits;
        }
        return hits;
    }

}  // namespace MTFPulse
