#pragma once

#include <RE/Skyrim.h>
#include <array>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace MTFPulse {

    // Steady-clock-since-DLL-init, in seconds. Same clock Tick() reads,
    // same clock Roster::Set() stores into PulseEntry.transition_start.
    // Exposed so the Papyrus glue can return it (MTFPulse.GetNowSec) and
    // callers that pin a shared transition anchor across a batch of Set()s
    // sample it in C++ time — Papyrus's Utility.GetCurrentRealTime() runs
    // on a different epoch (Skyrim launch, not DLL init) and mixing the
    // two breaks Tick's tt = now - transition_start math.
    float NowSec();

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

        // ── Cross-fade transition (v0.1.1) ────────────────────────────────
        // When transition_duration > 0 and (now - transition_start) <
        // transition_duration, Tick interpolates from from_* to the new
        // target values (layer_base_em_mult / target_alpha / target_tint)
        // and writes alpha+tint via skee_bridge each frame.
        //
        // After transition completes, transition_duration is set back to 0
        // (one-shot) and Tick stops writing alpha+tint — the Papyrus-side
        // ApplyNodeOverrides already pushed the target alpha/tint to the
        // store, so the live node retains those values once C++ stops
        // overriding them.
        //
        // Per-layer "from" snapshots are captured from the *previous*
        // entry's last interpolated state (last_interp_*) at Set() time,
        // so chained transitions don't snap back to the prior target.
        // Fresh entries (no previous) default from_ = target_, yielding a
        // no-op transition (instant).
        float                transition_start{ 0.0f };
        float                transition_duration{ 0.0f };  // 0 = no transition

        // Target alpha/tint/emissive per layer. Even outside transition,
        // these are the "what the Papyrus store wants" reference values.
        std::array<float,        4> target_alpha{};     // 0..1
        std::array<std::int32_t, 4> target_tint{};      // packed 0x00RRGGBB
        std::array<std::int32_t, 4> target_emissive{};  // packed 0x00RRGGBB

        // From-state captured at transition start.
        std::array<float,        4> from_em_mult{};
        std::array<float,        4> from_alpha{};
        std::array<std::int32_t, 4> from_tint{};
        std::array<std::int32_t, 4> from_emissive{};

        // Last value Tick wrote per layer. Used by Set() to seed from_*
        // when a new transition starts mid-flight. Updated every frame
        // Tick writes a property, including outside of transitions (so a
        // fresh transition into a steady entry uses the post-pulse live
        // value, not the entry's stored ceiling).
        std::array<float,        4> last_interp_em_mult{};
        std::array<float,        4> last_interp_alpha{};
        std::array<std::int32_t, 4> last_interp_tint{};
        std::array<std::int32_t, 4> last_interp_emissive{};
        bool                        has_last_interp{ false };

        // ── Flash on event (v0.1.3 additive, string-tag dispatch) ─────────
        // Transient additive emissive lane that bypasses the ceiling. When
        // `flash_tags` is non-empty AND a matching TriggerActorFlash has
        // stamped `flash_last_hit` + `flash_last_tag`, Tick eases
        // `flash_intensity` toward target and adds
        // (flash_peak_emissive * intensity) on top of the steady pulse —
        // so even a layer with emissivemult=0 (off in steady state) can
        // flash bright on a qualifying event.
        //
        // Matching rule (in Tick):
        //   fire = flash_tags.contains(flash_last_tag) ||
        //          flash_tags.contains("*");
        //
        // "*" is the wildcard tag — matches any incoming tag, including
        // tags fired by external mods through their own
        // MTFPulse.TriggerActorFlash calls. Empty set disables the lane.
        //
        // Tags are short ASCII identifiers, dotted for namespacing:
        // "blunt", "bladed", "ranged", "fire", "frost", "shock" for
        // built-in combat classes; external mods use prefixed names like
        // "sla.aroused.over80" to avoid collision.
        //
        // flash_peak_emissive is the ADDITIVE amount at intensity=1 (NOT
        // a multiplier). 0 disables, 1.0 = "+1.0 emissive at peak", 3.0 =
        // very bright spike. Caller passes int-percent (100 = 1.0) via
        // the SetActorFlash native; SetFlashParams stores the divided float.
        float                              flash_peak_emissive { 0.0f };    // 0 = disabled
        float                              flash_ramp_ms       { 150.0f };
        float                              flash_decay_ms      { 500.0f };
        float                              flash_retrigger_ms  { 800.0f };
        std::unordered_set<std::string>    flash_tags          {};          // empty = disabled

        // Hot state, mutated by TriggerFlash + Tick.
        float         flash_last_hit      { -1.0e6f }; // NowSec() at last qualifying event
        std::string   flash_last_tag      {};          // the tag the last trigger carried
        float         flash_intensity     { 0.0f };    // [0,1]
        float         flash_last_tick     { 0.0f };    // for dt computation

        // ── Fade on death (v0.1.4 one-shot) ───────────────────────────────
        // Independent lane from flash. When a preset binds the
        // mtf.base:ondeath.fade effect, its onActivate calls
        // SetActorFade(actor, base_slot, mode, durationMs) — this writes
        // fade_mode/fade_duration_ms and sets fade_armed=true. The entry
        // stays in the roster idle.
        //
        // When a TESDeathEvent fires for this actor (global C++ sink in
        // death_sink.cpp), Roster::TriggerFadeAllSlotsForActor walks the
        // roster, finds every entry with fade_armed=true, snapshots
        // last_interp_em_mult/alpha into fade_from_em/alpha, sets
        // fade_active=true, and stamps fade_start_sec=now. fade_armed
        // stays true so re-arming after manual revival just works, but
        // we gate by `!fade_active` so double-trigger from
        // dying-then-dead double-fire is a no-op.
        //
        // Tick interpolates per mode:
        //   kOverlay  : em → 0, alpha → 0 over duration.
        //   kEmissive : em → 1.0 (baseline), alpha unchanged.
        //   kInverted : em from→0 in first half, then 0→from in second
        //               half. Alpha unchanged. End state matches start.
        //
        // When elapsed >= duration, Tick writes the final frame, marks
        // the entry for deferred removal, and the Tick post-pass pops it
        // out of entries_. One-shot — animation runs once, entry dies.
        enum FadeMode : std::int32_t {
            kFadeOverlay  = 0,
            kFadeEmissive = 1,
            kFadeInverted = 2,
        };
        std::int32_t fade_mode         { kFadeOverlay };
        float        fade_duration_ms  { 0.0f };  // 0 disables
        bool         fade_armed        { false }; // preset bound, awaiting death
        bool         fade_active       { false }; // animation in flight
        float        fade_start_sec    { 0.0f };
        std::array<float, 4> fade_from_em    {};
        std::array<float, 4> fade_from_alpha {};
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

        // ── Flash (v0.1.3) ────────────────────────────────────────────────
        // Update the flash params on an existing entry. Returns false if no
        // entry exists at (actor, base_slot) — caller must ensure a steady
        // roster entry has been registered first (via SetActorPulse or
        // SetActorPulseWithTransition with rate=0 / depth=0).
        bool SetFlashParams(RE::Actor* actor, std::int32_t base_slot,
                            float peak_emissive, float ramp_ms,
                            float decay_ms, float retrigger_ms,
                            std::unordered_set<std::string> tags);

        // Empty the flash tag set on (actor, base_slot). Tick will let any
        // in-flight intensity decay naturally on the next frames.
        bool ClearFlash(RE::Actor* actor, std::int32_t base_slot);

        // Stamp the flash trigger time on (actor, base_slot) if the
        // incoming `tag` matches the entry's tag set (either exact match
        // or via the "*" wildcard). No-op if no entry or no flash
        // configured. Returns true if the trigger was accepted.
        bool TriggerFlash(RE::Actor* actor, std::int32_t base_slot,
                          std::string_view tag);

        // Convenience: trigger flash on EVERY entry whose actor_formID
        // matches `actor`. Used by the global TESHitEvent sink so a
        // single hit dispatches to every base-slot that actor has
        // (stacked presets, NPC tattoos, etc.) without the caller
        // needing to know the slot map. Returns count of entries that
        // accepted the trigger.
        std::size_t TriggerFlashAllSlotsForActor(RE::Actor* actor,
                                                 std::string_view tag);

        // ── Fade on death (v0.1.4) ────────────────────────────────────────
        // Arm fade on (actor, base_slot). Like SetFlashParams, requires
        // an existing steady roster entry — caller must have run a prior
        // SetActorPulse(WithTransition) so the slot exists.
        // mode: 0=overlay, 1=emissive, 2=inverted. durationMs >= 1.
        bool SetFadeParams(RE::Actor* actor, std::int32_t base_slot,
                           std::int32_t mode, float duration_ms);

        // Disarm fade on (actor, base_slot). If an animation is in
        // flight it's cancelled in place — last interp values stick.
        bool ClearFade(RE::Actor* actor, std::int32_t base_slot);

        // Manual one-shot fire of armed fade on a single (actor, base_slot).
        // Returns true if a fade was started. No-op if no entry, not
        // armed, or already active.
        bool TriggerFade(RE::Actor* actor, std::int32_t base_slot);

        // Death-sink entry point: fire armed fade on EVERY entry whose
        // actor_formID matches `actor`. Returns count of fades started.
        std::size_t TriggerFadeAllSlotsForActor(RE::Actor* actor);

        // ── Transition batching (v0.1.7) ──────────────────────────────────
        // Buffer incoming Set() calls into pending_batch_ until EndBatch
        // fires, then install all queued entries atomically with one
        // shared transition_start anchor. Solves the "stacked-preset
        // cross-fades staircase" problem at the architectural level —
        // Papyrus loops the slow per-preset work (JsonUtil reads, effect
        // de/activate, NiOverride writes) and each iteration would
        // otherwise call Set() at its own NowSec, leaving every preset's
        // first Tick frame at a different lerp position (later entries
        // jump past earlier ones, or hit the snap path past
        // transition_duration). With batching, all Sets queue during the
        // burst and EndBatch picks one NowSec + small forward offset so
        // every slot enters the live roster with the same transition_start
        // and the first frame after the anchor passes runs them in
        // lockstep. Nested BeginBatch is idempotent (warns and treats as
        // no-op); EndBatch without a matching Begin is a safe no-op.
        // Calls to Set OUTSIDE a batch are immediate (legacy behavior).
        void BeginBatch();
        void EndBatch();

        // Called from the per-frame hook.
        void Tick();

        std::size_t Size() const;

    private:
        Roster() = default;

        // entries_ is fixed-size. count_ tracks current population.
        std::array<PulseEntry, kCapacity> entries_{};
        std::size_t count_{ 0 };

        // Mutex guards entries_/count_/pending_batch_. The Set/Clear
        // callbacks come from Papyrus VM threads; Tick runs on the main
        // thread.
        mutable std::mutex mtx_;
        std::atomic<bool>  enabled_{ true };

        // Batched-set state (v0.1.7). When in_batch_ is true, Set() queues
        // incoming entries into pending_batch_ alongside their actor; the
        // matching EndBatch() then installs all queued entries in one
        // atomic mtx_-held pass with a single shared transition_start.
        // Both are mtx_-guarded — Papyrus's BeginBatch/EndBatch glue is
        // serialized through the same mutex Set/Tick already use.
        bool                                            in_batch_{ false };
        std::vector<std::pair<RE::Actor*, PulseEntry>>  pending_batch_;

        // Find by (FormID, base_slot). -1 if not present. mtx_ held.
        std::int32_t FindLocked(std::uint32_t formID, std::int32_t base_slot) const;
        void         RemoveAtLocked(std::size_t slot);
        void         EvictFarthestLocked(RE::TESObjectREFR* anchor);

        // Install ONE entry into the live roster — same logic as Set's
        // non-batch path, but factored out so EndBatch can reuse it for
        // queued entries. mtx_ must be held by the caller. `anchor_ts`
        // overrides any per-entry transition_start; pass NowSec() (or
        // NowSec() + small forward offset) for the entire batch.
        bool InstallLocked(RE::Actor* actor, const PulseEntry& src, float anchor_ts);
    };

}  // namespace MTFPulse
