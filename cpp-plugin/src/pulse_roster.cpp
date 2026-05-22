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

    } // anonymous namespace

    // Header-visible (see pulse_roster.h). papyrus.cpp's GetNowSec native
    // returns this so Papyrus callers pinning a shared transition anchor
    // sample the SAME steady_clock + TOrigin pair Tick reads, avoiding
    // the clock-epoch mismatch with Utility.GetCurrentRealTime().
    float NowSec()
    {
        return std::chrono::duration<float>(std::chrono::steady_clock::now() - TOrigin()).count();
    }

    namespace {

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

    std::int32_t Roster::FindLocked(std::uint32_t formID, std::uint8_t area,
                                    std::int32_t base_slot) const
    {
        // v0.1.17 Phase 3 (multi-area): identity is (formID, area, base_slot).
        // Same actor can hold a Body[ovl0] entry and a Face[ovl0] entry
        // without collision.
        for (std::size_t i = 0; i < count_; ++i) {
            const auto& e = entries_[i];
            if (e.actor_formID == formID
                    && e.area == area
                    && e.base_slot == base_slot) {
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

        // Batched mode: queue and defer install to EndBatch so every
        // entry pushed during this Papyrus burst lands in the live
        // roster with the same transition_start. See pulse_roster.h.
        if (in_batch_) {
            pending_batch_.emplace_back(actor, src);
            return true;
        }

        // Honor caller-specified transition_start if non-zero. Forward-
        // scheduled values (rtNow + small epsilon) are SAFE — Tick's
        // first read sees `tt <= 0` and takes the start-of-lerp branch
        // (transitioning=true, eased=0), which writes the from-state to
        // the live shader correctly. Back-dated anchors past
        // (anchor + transition_duration) hit Tick's snap path which
        // doesn't write alpha/tint/emissive — callers must pass anchors
        // that are now-or-future.
        const float anchorTS = (src.transition_start > 0.0f) ? src.transition_start : NowSec();
        return InstallLocked(actor, src, anchorTS);
    }

    bool Roster::InstallLocked(RE::Actor* actor, const PulseEntry& src, float anchor_ts)
    {
        // Caller holds mtx_.
        const auto formID = actor->GetFormID();
        std::int32_t slot = FindLocked(formID, src.area, src.base_slot);

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
            seeded.transition_start = anchor_ts;
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
            seeded.transition_start = anchor_ts;
            seeded.has_last_interp  = false;
        }

        // Pin pulse phase so the wave hits peak (phase=0.5 for the cosine
        // fallback, mid-LUT for custom waves) exactly when the transition
        // ends. Without this, when the pulse modulation switches on at
        // eased=1 the wave phase is essentially random — for slow rates
        // the wave is often still low at that point, so `pulsed *
        // target_em` pulls em DOWN below the smooth-ramp end value, which
        // users see as a "blink" right when the color settles. Pinning to
        // peak makes pulsed=1.0 at the handoff, so the steady-state value
        // matches the lerp end exactly. Only applies to transitions with
        // rate>0 — rate=0 entries (no pulse) don't need phase alignment.
        if (seeded.transition_duration > 0.0f && seeded.rate > 0.0f) {
            const float cycle = 1.0f / seeded.rate;
            seeded.start_time = seeded.transition_start
                              + seeded.transition_duration
                              - 0.5f * cycle;
        }

        if (slot < 0) {
            if (count_ >= kCapacity) {
                auto* player = RE::PlayerCharacter::GetSingleton();
                EvictFarthestLocked(player);
            }
            if (count_ >= kCapacity) {
                spdlog::warn("Roster::InstallLocked FULL formID=0x{:08x} base_slot={} kCapacity={}",
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

    void Roster::BeginBatch()
    {
        std::lock_guard lock(mtx_);
        if (in_batch_) {
            spdlog::warn("Roster::BeginBatch called while already batching ({} pending) — ignoring",
                         pending_batch_.size());
            return;
        }
        in_batch_ = true;
        pending_batch_.clear();  // defensive — should already be empty
    }

    void Roster::EndBatch()
    {
        std::lock_guard lock(mtx_);
        if (!in_batch_) {
            // Tolerated — Papyrus side may call EndBatch unconditionally
            // even when BeginBatch was skipped (e.g. early-return path).
            return;
        }
        // Single forward-scheduled anchor for the whole batch. Small
        // forward offset (~50 ms) means Tick's first read for every
        // installed slot sees `tt <= 0`, holding from-state on live until
        // the anchor passes — then all slots simultaneously start their
        // lerp on the same frame. Forward offset must be small to keep
        // perceptible lag low; the bulk of the wait users see is the
        // Papyrus burst itself between BeginBatch and EndBatch (the
        // sequential JsonUtil reads + effect activate), not the anchor.
        const float anchor_ts = NowSec() + 0.05f;
        for (auto& [actor, src] : pending_batch_) {
            if (!actor) {
                continue;
            }
            InstallLocked(actor, src, anchor_ts);
        }
        pending_batch_.clear();
        in_batch_ = false;
    }

    bool Roster::ClearAt(RE::Actor* actor, std::uint8_t area, std::int32_t base_slot)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const std::int32_t slot = FindLocked(formID, area, base_slot);
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

        // Deferred-removal list for one-shot fade entries that complete
        // during this Tick. We can't RemoveAtLocked mid-iteration (it
        // swaps with the last entry, breaking the forward walk), so we
        // collect indices and drain in descending order at the end.
        std::vector<std::size_t> to_remove;

        for (std::size_t i = 0; i < count_; ++i) {
            auto& e = entries_[i];
            auto* actor = e.actor.get().get();
            if (!actor) {
                continue;
            }

            // ── Fade-on-death one-shot override (v0.1.4) ──────────────────
            // When fade_active, the fade lerp fully owns em_mult/alpha
            // for the duration; steady pulse, flash, and cross-fade
            // transition logic are all skipped. We still need to issue
            // SKEE writes per layer, then either continue (mid-animation)
            // or queue for removal (animation complete).
            if (e.fade_active) {
                const float dur_sec = e.fade_duration_ms * 0.001f;
                const float elapsed = now - e.fade_start_sec;
                const float raw_t   = (dur_sec > 0.0f)
                    ? std::clamp(elapsed / dur_sec, 0.0f, 1.0f)
                    : 1.0f;
                const bool finished = (raw_t >= 1.0f);

                char node[32];
                for (std::int32_t li = 0; li < e.layer_count; ++li) {
                    const auto L = static_cast<std::size_t>(li);
                    std::snprintf(node, sizeof(node), "%s [ovl%d]",
                                  AreaName(e.area),
                                  static_cast<int>(e.base_slot + li));

                    float em    = e.fade_from_em[L];
                    float alpha = e.fade_from_alpha[L];
                    switch (e.fade_mode) {
                        case PulseEntry::kFadeOverlay: {
                            const float k = EaseInOut(raw_t);
                            em    = e.fade_from_em[L]    * (1.0f - k);
                            alpha = e.fade_from_alpha[L] * (1.0f - k);
                            break;
                        }
                        case PulseEntry::kFadeEmissive: {
                            const float k = EaseInOut(raw_t);
                            // Lerp em → 1.0 baseline. Alpha unchanged.
                            em    = e.fade_from_em[L] + (1.0f - e.fade_from_em[L]) * k;
                            alpha = e.fade_from_alpha[L];
                            break;
                        }
                        case PulseEntry::kFadeInverted: {
                            // First half: em → 0. Second half: 0 → from.
                            // Alpha unchanged across both halves.
                            float k;
                            if (raw_t < 0.5f) {
                                k  = EaseInOut(raw_t * 2.0f);
                                em = e.fade_from_em[L] * (1.0f - k);
                            } else {
                                k  = EaseInOut((raw_t - 0.5f) * 2.0f);
                                em = e.fade_from_em[L] * k;
                            }
                            alpha = e.fade_from_alpha[L];
                            break;
                        }
                        default:
                            break;
                    }

                    skee_bridge::WriteEmissiveMult(actor, e.is_female, node, em);
                    skee_bridge::WriteAlpha(actor, e.is_female, node, alpha);
                    e.last_interp_em_mult[L] = em;
                    e.last_interp_alpha[L]   = alpha;
                }
                e.has_last_interp = true;

                if (finished) {
                    // Recovery path: if the actor isn't actually dead at
                    // animation end, restore the target visual state.
                    // Skyrim's essential / protected actors fire
                    // TESDeathEvent during bleedout but recover; without
                    // this restore, alpha=0 from the final fade frame
                    // sticks in NiOverride and the tattoo stays invisible
                    // until something triggers a full redraw. For truly
                    // dead actors IsDead() is true and we leave the faded
                    // state as the final corpse visual (the entry is
                    // queued for removal so the C++ Tick stops writing).
                    if (!actor->IsDead()) {
                        for (std::int32_t li = 0; li < e.layer_count; ++li) {
                            const auto L = static_cast<std::size_t>(li);
                            std::snprintf(node, sizeof(node), "%s [ovl%d]",
                                          AreaName(e.area),
                                          static_cast<int>(e.base_slot + li));
                            skee_bridge::WriteEmissiveMult(actor, e.is_female, node, e.layer_base_em_mult[L]);
                            skee_bridge::WriteAlpha(actor, e.is_female, node, e.target_alpha[L]);
                        }
                    }
                    to_remove.push_back(i);
                }
                continue;
            }

            const float t      = now - e.start_time;

            // Transition state: if we're inside the cross-fade window, set
            // `transitioning=true` and compute `eased` ∈ [0,1]. Otherwise
            // the layer loop uses target values directly. Computed BEFORE
            // pulse depth so we can ramp pulse modulation in alongside the
            // tint/em ceiling lerp.
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

            // No depth ramp during transition — we lerp the ceiling
            // directly with no pulse modulation, and InstallLocked pinned
            // start_time so the wave hits peak at transition end. That
            // makes the handoff to steady-pulse seamless (pulsed=1 at
            // eased=1, so steady_em = target_em, matching the lerp end).
            const float floorM = 1.0f - e.depth;

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
            const float pulsed = floorM + e.depth * wave;

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

            // One write per active layer: nodes are named "<Area> [ovlN]"
            // where N = base_slot + layer_index (matches MTF_MainQuest's
            // applyOverlay format). The per-layer base emissive multiplier
            // is the ceiling — pulse modulates between (1-depth)*ceiling
            // and 1.0*ceiling.
            //
            // v0.1.17 Phase 3 (multi-area): AreaName(e.area) selects the
            // NiOverride node-name prefix per entry. Body entries (the
            // legacy default) keep painting into "Body [ovlN]"; face/
            // hand/feet pack entries paint into their own pools.
            char node[32];
            for (std::int32_t li = 0; li < e.layer_count; ++li) {
                const auto L = static_cast<std::size_t>(li);
                std::snprintf(node, sizeof(node), "%s [ovl%d]",
                              AreaName(e.area),
                              static_cast<int>(e.base_slot + li));

                // Steady-pulse target (used outside transitions and for
                // diagnostic logging).
                const float steady_em = pulsed * e.layer_base_em_mult[L];

                // During transition: pure ceiling lerp from the last
                // rendered em to the target ceiling, no wave/pulse
                // modulation. Wave phase was pinned at Install so it
                // hits peak at transition end, meaning pulsed≈1 at
                // eased=1 → steady_em≈target_em → seamless handoff.
                // Steady state: pulse modulates the ceiling normally.
                float em_no_flash;
                if (transitioning) {
                    em_no_flash = e.from_em_mult[L]
                                + (e.layer_base_em_mult[L] - e.from_em_mult[L]) * eased;
                } else {
                    em_no_flash = steady_em;
                }
                const float final_mult = em_no_flash + flash_add;
                skee_bridge::WriteEmissiveMult(actor, e.is_female, node, final_mult);
                // Track post-pulse rendered em (sans transient flash) so
                // the next transition's from_em snapshots the actual visible
                // value, not a static ceiling.
                e.last_interp_em_mult[L] = em_no_flash;

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

        // Drain completed one-shot fade entries. Sort descending so each
        // RemoveAtLocked's swap-with-last doesn't pull a still-active
        // entry into a slot we're about to remove. (We pushed in
        // ascending order during the forward walk; reversing gives us
        // descending.)
        if (!to_remove.empty()) {
            for (auto it = to_remove.rbegin(); it != to_remove.rend(); ++it) {
                RemoveAtLocked(*it);
            }
        }
    }

    bool Roster::SetFlashParams(RE::Actor* actor, std::uint8_t area,
                                std::int32_t base_slot,
                                float peak_emissive, float ramp_ms,
                                float decay_ms, float retrigger_ms,
                                std::unordered_set<std::string> tags)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const std::int32_t slot = FindLocked(formID, area, base_slot);
        if (slot < 0) {
            spdlog::warn("MTFFlash SetFlashParams MISS formID=0x{:08x} area={} base_slot={} count={}",
                         formID, static_cast<int>(area), base_slot, count_);
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

    bool Roster::ClearFlash(RE::Actor* actor, std::uint8_t area, std::int32_t base_slot)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const std::int32_t slot = FindLocked(actor->GetFormID(), area, base_slot);
        if (slot < 0) {
            return false;
        }
        entries_[slot].flash_tags.clear();
        return true;
    }

    bool Roster::TriggerFlash(RE::Actor* actor, std::uint8_t area,
                              std::int32_t base_slot, std::string_view tag)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const std::int32_t slot = FindLocked(formID, area, base_slot);
        if (slot < 0) {
            spdlog::warn("MTFFlash TriggerFlash MISS_ENTRY formID=0x{:08x} area={} base_slot={} tag={}",
                         formID, static_cast<int>(area), base_slot, std::string(tag));
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

    // ── Fade on death (v0.1.4) ───────────────────────────────────────────
    bool Roster::SetFadeParams(RE::Actor* actor, std::uint8_t area,
                               std::int32_t base_slot,
                               std::int32_t mode, float duration_ms)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const std::int32_t slot = FindLocked(formID, area, base_slot);
        if (slot < 0) {
            spdlog::warn("MTFFade SetFadeParams MISS formID=0x{:08x} area={} base_slot={} count={}",
                         formID, static_cast<int>(area), base_slot, count_);
            return false;
        }
        auto& e = entries_[slot];
        // Clamp mode to the known enum range so a hand-edited preset
        // value of 99 doesn't index out-of-bounds in Tick. Unknown ->
        // kFadeOverlay (the most visually-obvious mode, safest default
        // for "user typed something unexpected").
        if (mode < PulseEntry::kFadeOverlay || mode > PulseEntry::kFadeInverted) {
            mode = PulseEntry::kFadeOverlay;
        }
        e.fade_mode        = mode;
        e.fade_duration_ms = std::max(1.0f, duration_ms);
        e.fade_armed       = true;
        // Don't clobber fade_active: re-arming mid-fire is a no-op
        // (Tick is still driving the animation through to completion
        // and removal).
        return true;
    }

    bool Roster::ClearFade(RE::Actor* actor, std::uint8_t area, std::int32_t base_slot)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const std::int32_t slot = FindLocked(actor->GetFormID(), area, base_slot);
        if (slot < 0) {
            return false;
        }
        auto& e = entries_[slot];
        e.fade_armed  = false;
        e.fade_active = false;
        return true;
    }

    namespace {
        // Capture last-rendered em/alpha as the fade "from" state. Called
        // from both TriggerFade and TriggerFadeAllSlotsForActor with mtx_
        // already held by the caller.
        void StartFade(PulseEntry& e, float now)
        {
            for (std::int32_t li = 0; li < e.layer_count; ++li) {
                const auto L = static_cast<std::size_t>(li);
                if (e.has_last_interp) {
                    e.fade_from_em[L]    = e.last_interp_em_mult[L];
                    e.fade_from_alpha[L] = e.last_interp_alpha[L];
                } else {
                    // Tick hasn't run yet on this entry — fall back to the
                    // configured ceiling and target alpha so the lerp has
                    // a sensible starting point.
                    e.fade_from_em[L]    = e.layer_base_em_mult[L];
                    e.fade_from_alpha[L] = e.target_alpha[L];
                }
            }
            e.fade_active    = true;
            e.fade_start_sec = now;
            // Quench any in-flight flash on the same entry — during a
            // one-shot fade we want the fade visual to dominate. The
            // flash lane stays configured (tags / peak / etc. survive)
            // so a future re-arm of fade after revival could let flashes
            // resume; but for the one-shot duration we zero intensity.
            e.flash_intensity = 0.0f;
        }
    }  // namespace

    bool Roster::TriggerFade(RE::Actor* actor, std::uint8_t area, std::int32_t base_slot)
    {
        if (!actor) {
            return false;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const std::int32_t slot = FindLocked(formID, area, base_slot);
        if (slot < 0) {
            spdlog::warn("MTFFade TriggerFade MISS_ENTRY formID=0x{:08x} area={} base_slot={}",
                         formID, static_cast<int>(area), base_slot);
            return false;
        }
        auto& e = entries_[slot];
        if (!e.fade_armed || e.fade_active) {
            return false;
        }
        StartFade(e, NowSec());
        return true;
    }

    std::size_t Roster::TriggerFadeAllSlotsForActor(RE::Actor* actor)
    {
        if (!actor) {
            return 0;
        }
        std::lock_guard lock(mtx_);
        const auto formID = actor->GetFormID();
        const auto now    = NowSec();
        std::size_t fired = 0;
        for (std::size_t i = 0; i < count_; ++i) {
            auto& e = entries_[i];
            if (e.actor_formID != formID) {
                continue;
            }
            if (!e.fade_armed || e.fade_active) {
                continue;
            }
            StartFade(e, now);
            ++fired;
        }
        return fired;
    }

}  // namespace MTFPulse
