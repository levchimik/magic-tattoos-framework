#include "papyrus.h"
#include "config.h"
#include "log.h"
#include "pulse_roster.h"

#include <string>
#include <string_view>
#include <unordered_set>

namespace MTFPulse::Papyrus {

    namespace {
        // Parse a comma-separated tag string into a set. Trims whitespace,
        // lowercases ASCII (so "Blunt" and "blunt" hash to the same key),
        // drops empty fragments. "*" is preserved verbatim.
        std::unordered_set<std::string> ParseTags(std::string_view csv)
        {
            std::unordered_set<std::string> out;
            std::string buf;
            buf.reserve(16);
            auto flush = [&] {
                while (!buf.empty() && (buf.back() == ' ' || buf.back() == '\t')) {
                    buf.pop_back();
                }
                std::size_t s = 0;
                while (s < buf.size() && (buf[s] == ' ' || buf[s] == '\t')) {
                    ++s;
                }
                if (s < buf.size()) {
                    std::string norm(buf.begin() + s, buf.end());
                    for (auto& c : norm) {
                        if (c >= 'A' && c <= 'Z') {
                            c = static_cast<char>(c - 'A' + 'a');
                        }
                    }
                    out.insert(std::move(norm));
                }
                buf.clear();
            };
            for (char c : csv) {
                if (c == ',' || c == ';') {
                    flush();
                } else {
                    buf.push_back(c);
                }
            }
            flush();
            return out;
        }
        constexpr std::string_view kClassName = "MTFPulse";

        // Set the pulse parameters for one actor. Caller passes per-layer
        // emissive multipliers as a float array (length == layerN, max 4).
        //
        // Signature mirrors what the Papyrus side already computes — see
        // MTF_MainQuest._rosterAddOrUpdate.
        void SetActorPulse(
            RE::StaticFunctionTag*    /*tag*/,
            RE::Actor*                actor,
            float                     rate,
            std::int32_t              depth_pct,
            float                     pause,
            std::int32_t              layer_count,
            float                     start_time,
            std::vector<float>        em_mults,
            std::int32_t              base_overlay_slot,
            bool                      is_female,
            std::vector<float>        wave_lut)
        {
            if (!actor) {
                spdlog::warn("SetActorPulse called with null actor");
                return;
            }
            // v0.1.3: only layer_count<=0 clears the entry now. Previously
            // we also cleared on rate<=0 or depth_pct<=0 since those make
            // the pulse mathematically inert — but flash-only tiers
            // (no pulse, only the additive lane) need a live roster entry
            // so SetActorFlash has somewhere to write. Tick handles rate=0
            // correctly: wave=0 ⇒ pulsed=1.0 ⇒ ceiling passes through.
            if (layer_count <= 0) {
                Roster::Instance().ClearAt(actor, base_overlay_slot);
                return;
            }
            PulseEntry e{};
            e.rate         = std::max(0.0f, rate);
            e.depth        = std::clamp(depth_pct, 0, 100) * 0.01f;
            e.pause        = std::max(0.0f, pause);
            e.start_time   = start_time;
            e.base_slot    = base_overlay_slot;
            e.layer_count  = std::clamp(layer_count, 0, 4);
            e.is_female    = is_female;
            // Legacy entry point doesn't carry alpha/tint, so default the
            // targets to "fully visible, untinted white". If a later
            // SetActorPulseWithTransition arrives on this entry, Tick will
            // have populated last_interp_alpha/tint from these defaults,
            // giving a sensible from-state for the cross-fade.
            for (std::int32_t i = 0; i < e.layer_count; ++i) {
                const auto L = static_cast<std::size_t>(i);
                e.layer_base_em_mult[L] = (i < static_cast<std::int32_t>(em_mults.size()))
                    ? em_mults[L]
                    : 0.0f;
                e.target_alpha[L]    = 1.0f;
                e.target_tint[L]     = static_cast<std::int32_t>(0xFFFFFF);
                e.target_emissive[L] = static_cast<std::int32_t>(0xFFFFFF);
            }
            if (wave_lut.size() == PulseEntry::kWaveLUTSize) {
                std::copy(wave_lut.begin(), wave_lut.end(), e.wave_lut.begin());
                e.has_wave_lut = true;
            } else {
                e.has_wave_lut = false;
            }
            Roster::Instance().Set(actor, e);
        }

        // Set pulse + cross-fade transition in one call. Identical to
        // SetActorPulse except the caller additionally passes:
        //   tintRGBs    — per-layer target tint colors (packed 0x00RRGGBB)
        //                 written via skee_bridge during transition lerp;
        //                 length should match layer_count (extras ignored,
        //                 missing padded with white = 0xFFFFFF)
        //   alphasPct   — per-layer target alpha as 0..100 percent (matches
        //                 Papyrus JSON convention); C++ stores 0..1
        //   transitionDuration — seconds to fade from prior state to the
        //                 new target. 0 or negative behaves as SetActorPulse.
        //
        // C++ snapshots the prior entry's last interpolated em_mult/alpha/
        // tint as the from-state — chained transitions don't snap back.
        // For fresh actors with no prior entry, from = target ⇒ no visible
        // fade on first-ever apply (intentional: per-tier transitions are
        // the interesting case).
        void SetActorPulseWithTransition(
            RE::StaticFunctionTag*    /*tag*/,
            RE::Actor*                actor,
            float                     rate,
            std::int32_t              depth_pct,
            float                     pause,
            std::int32_t              layer_count,
            float                     start_time,
            std::vector<float>        em_mults,
            std::int32_t              base_overlay_slot,
            bool                      is_female,
            std::vector<float>        wave_lut,
            std::vector<std::int32_t> tint_rgbs,
            std::vector<std::int32_t> alphas_pct,
            std::vector<std::int32_t> emissive_rgbs,
            float                     transition_duration)
        {
            if (!actor) {
                spdlog::warn("SetActorPulseWithTransition called with null actor");
                return;
            }
            // v0.1.1 cross-fade: we accept rate=0 / depth_pct=0 entries.
            // The Papyrus side forwards "tier change" events regardless of
            // whether the target tier has a pulse, so the C++ roster has
            // a continuously-live entry to lerp alpha/tint/em_mult across
            // tier boundaries (including tier 1 → tier 0 fade-out). An
            // entry with rate=0 doesn't drive a pulse — Tick computes
            // wave=0, pulsed=1.0, so final_mult collapses to just the
            // (possibly-interpolated) layer ceiling.
            //
            // The only hard-bail case is no layers — nothing to write.
            if (layer_count <= 0) {
                Roster::Instance().ClearAt(actor, base_overlay_slot);
                return;
            }
            PulseEntry e{};
            e.rate                = std::max(0.0f, rate);
            e.depth               = std::clamp(depth_pct, 0, 100) * 0.01f;
            e.pause               = std::max(0.0f, pause);
            e.start_time          = start_time;
            e.base_slot           = base_overlay_slot;
            e.layer_count         = std::clamp(layer_count, 0, 4);
            e.is_female           = is_female;
            e.transition_duration = std::max(0.0f, transition_duration);
            for (std::int32_t i = 0; i < e.layer_count; ++i) {
                const auto L = static_cast<std::size_t>(i);
                e.layer_base_em_mult[L] = (i < static_cast<std::int32_t>(em_mults.size()))
                    ? em_mults[L]
                    : 0.0f;
                const std::int32_t a_pct = (i < static_cast<std::int32_t>(alphas_pct.size()))
                    ? alphas_pct[L]
                    : 100;
                e.target_alpha[L] = std::clamp(a_pct, 0, 100) * 0.01f;
                e.target_tint[L]  = (i < static_cast<std::int32_t>(tint_rgbs.size()))
                    ? tint_rgbs[L]
                    : static_cast<std::int32_t>(0xFFFFFF);
                e.target_emissive[L] = (i < static_cast<std::int32_t>(emissive_rgbs.size()))
                    ? emissive_rgbs[L]
                    : static_cast<std::int32_t>(0xFFFFFF);
            }
            if (wave_lut.size() == PulseEntry::kWaveLUTSize) {
                std::copy(wave_lut.begin(), wave_lut.end(), e.wave_lut.begin());
                e.has_wave_lut = true;
            } else {
                e.has_wave_lut = false;
            }
            Roster::Instance().Set(actor, e);
        }

        // Same as SetActorPulseWithTransition, plus the caller pins the
        // cross-fade anchor by passing `transitionStartRT` (seconds from
        // the same clock NowSec() uses — i.e. Utility.GetCurrentRealTime()
        // on the Papyrus side). When > 0, Roster::Set stores this value
        // directly as transition_start instead of capturing its own
        // NowSec(); when <= 0 we fall through to the legacy NowSec()
        // path. Callers that batch multiple Set calls in one Papyrus
        // tick should snapshot one anchor (typically a few tens of ms in
        // the FUTURE so every Set in the burst lands before the anchor)
        // and pass it to every Set so all entries lerp in lockstep.
        // Forward anchors are safe; back-dated anchors that land past
        // (anchor + transition_duration) will hit Tick's snap path which
        // skips alpha/tint writes.
        void SetActorPulseWithTransitionAt(
            RE::StaticFunctionTag*    /*tag*/,
            RE::Actor*                actor,
            float                     rate,
            std::int32_t              depth_pct,
            float                     pause,
            std::int32_t              layer_count,
            float                     start_time,
            std::vector<float>        em_mults,
            std::int32_t              base_overlay_slot,
            bool                      is_female,
            std::vector<float>        wave_lut,
            std::vector<std::int32_t> tint_rgbs,
            std::vector<std::int32_t> alphas_pct,
            std::vector<std::int32_t> emissive_rgbs,
            float                     transition_duration,
            float                     transition_start_rt)
        {
            if (!actor) {
                spdlog::warn("SetActorPulseWithTransitionAt called with null actor");
                return;
            }
            if (layer_count <= 0) {
                Roster::Instance().ClearAt(actor, base_overlay_slot);
                return;
            }
            PulseEntry e{};
            e.rate                = std::max(0.0f, rate);
            e.depth               = std::clamp(depth_pct, 0, 100) * 0.01f;
            e.pause               = std::max(0.0f, pause);
            e.start_time          = start_time;
            e.base_slot           = base_overlay_slot;
            e.layer_count         = std::clamp(layer_count, 0, 4);
            e.is_female           = is_female;
            e.transition_duration = std::max(0.0f, transition_duration);
            e.transition_start    = std::max(0.0f, transition_start_rt);  // 0 = legacy NowSec path
            for (std::int32_t i = 0; i < e.layer_count; ++i) {
                const auto L = static_cast<std::size_t>(i);
                e.layer_base_em_mult[L] = (i < static_cast<std::int32_t>(em_mults.size()))
                    ? em_mults[L]
                    : 0.0f;
                const std::int32_t a_pct = (i < static_cast<std::int32_t>(alphas_pct.size()))
                    ? alphas_pct[L]
                    : 100;
                e.target_alpha[L] = std::clamp(a_pct, 0, 100) * 0.01f;
                e.target_tint[L]  = (i < static_cast<std::int32_t>(tint_rgbs.size()))
                    ? tint_rgbs[L]
                    : static_cast<std::int32_t>(0xFFFFFF);
                e.target_emissive[L] = (i < static_cast<std::int32_t>(emissive_rgbs.size()))
                    ? emissive_rgbs[L]
                    : static_cast<std::int32_t>(0xFFFFFF);
            }
            if (wave_lut.size() == PulseEntry::kWaveLUTSize) {
                std::copy(wave_lut.begin(), wave_lut.end(), e.wave_lut.begin());
                e.has_wave_lut = true;
            } else {
                e.has_wave_lut = false;
            }
            Roster::Instance().Set(actor, e);
        }

        // ── Transition batching (v0.1.7) ──────────────────────────────
        // Wrap a Papyrus burst that touches several roster slots in
        // BeginTransitionBatch / EndTransitionBatch. SetActorPulse* calls
        // between the two queue into C++'s pending list instead of
        // installing into the live roster immediately; EndTransitionBatch
        // takes ONE NowSec snapshot and installs every queued entry with
        // the same transition_start, so they all enter the live roster
        // atomically and Tick lerps them in lockstep. This is the
        // architectural fix to the stacked-preset "tattoos fade in one
        // after another" symptom — without batching, each Set() landed at
        // its own NowSec and later entries either started mid-lerp or hit
        // Tick's snap path when the Papyrus burst exceeded
        // transition_duration. Calling Begin twice (without an intervening
        // End) logs a warning and is otherwise a no-op; calling End
        // without a matching Begin is also a no-op.
        void BeginTransitionBatch(RE::StaticFunctionTag* /*tag*/)
        {
            Roster::Instance().BeginBatch();
        }
        void EndTransitionBatch(RE::StaticFunctionTag* /*tag*/)
        {
            Roster::Instance().EndBatch();
        }

        // Expose the C++ clock used by Tick / Roster::Set so Papyrus can
        // sample it for a shared transition anchor. C++ NowSec is
        // steady_clock since DLL init (see pulse_roster.cpp TOrigin) —
        // Papyrus's Utility.GetCurrentRealTime() counts from Skyrim launch
        // and the two are off by a constant (DLL init lands a few seconds
        // into game launch under SKSE plugin load). Without this, callers
        // that wanted to pin transition_start would pass a Papyrus-time
        // value that C++ then misinterpreted as C++ time → tt computed
        // in Tick was wildly negative and the cross-fade stuck at eased=0
        // forever, leaving tattoos painted at their from-state.
        float GetNowSec(RE::StaticFunctionTag* /*tag*/)
        {
            return NowSec();
        }

        // Removes EVERY entry the actor owns (across all base_slots).
        // Use on death / unload / total teardown.
        void ClearActor(RE::StaticFunctionTag* /*tag*/, RE::Actor* actor)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().ClearAllForActor(actor);
        }

        // Removes one entry by (actor, base_slot). Use when a single preset
        // becomes inactive on an actor that still owns other presets.
        void ClearActorAt(RE::StaticFunctionTag* /*tag*/, RE::Actor* actor, std::int32_t base_slot)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().ClearAt(actor, base_slot);
        }

        void ClearAll(RE::StaticFunctionTag* /*tag*/)
        {
            Roster::Instance().ClearAll();
        }

        void SetEnabled(RE::StaticFunctionTag* /*tag*/, bool on)
        {
            Roster::Instance().SetEnabled(on);
        }

        std::int32_t Size(RE::StaticFunctionTag* /*tag*/)
        {
            return static_cast<std::int32_t>(Roster::Instance().Size());
        }

        // Flash on event (v0.1.3 additive, string-tag dispatch). Pushed by
        // the flash.onhit effect when its slot becomes the winning tier.
        // Requires a steady roster entry to already exist for
        // (actor, base_slot).
        //
        // peakEmissivePct is the ADDITIVE peak amount expressed as percent
        // of 1.0 emissive — 0 disables the lane, 100 = "+1.0 added at
        // peak intensity", 500 = +5.0 (very bright spike). Range 0..1000.
        // ramp/decay/retrigger are milliseconds.
        //
        // tagsCsv is a comma-separated list of event tags the entry will
        // react to. The reserved tag "*" is a wildcard matching any
        // incoming tag (including tags fired by external mods). Tags are
        // case-insensitive — internally lowercased for matching. Empty
        // string disables the lane (same effect as ClearActorFlash).
        //
        // Examples:
        //   "blunt,bladed"         — melee only
        //   "fire,frost,shock"     — elemental hits only
        //   "*"                    — any event ever fired
        //   ""                     — disabled
        void SetActorFlash(
            RE::StaticFunctionTag* /*tag*/,
            RE::Actor*               actor,
            std::int32_t             base_slot,
            std::int32_t             peak_emissive_pct,
            std::int32_t             ramp_ms,
            std::int32_t             decay_ms,
            std::int32_t             retrigger_ms,
            RE::BSFixedString        tags_csv)
        {
            if (!actor) {
                return;
            }
            const float peak = std::clamp(peak_emissive_pct, 0, 1000) * 0.01f;
            std::string_view view = tags_csv.empty()
                ? std::string_view{}
                : std::string_view(tags_csv.c_str());
            Roster::Instance().SetFlashParams(
                actor, base_slot, peak,
                static_cast<float>(std::max(1, ramp_ms)),
                static_cast<float>(std::max(1, decay_ms)),
                static_cast<float>(std::max(0, retrigger_ms)),
                ParseTags(view));
        }

        void ClearActorFlash(RE::StaticFunctionTag* /*tag*/,
                             RE::Actor* actor, std::int32_t base_slot)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().ClearFlash(actor, base_slot);
        }

        // Stamp an event. `tag` is a short identifier ("blunt", "fire",
        // "sla.aroused.over80", ...). Case-insensitive. Cheap — no SKEE
        // writes; the next Tick frame picks up the new last_hit timestamp
        // and runs the envelope if the tag matches.
        void TriggerActorFlash(RE::StaticFunctionTag* /*tag*/,
                               RE::Actor*        actor,
                               std::int32_t      base_slot,
                               RE::BSFixedString tag_str)
        {
            if (!actor) {
                return;
            }
            // Lowercase the incoming tag to match how ParseTags normalises
            // the stored set.
            std::string norm;
            if (!tag_str.empty()) {
                norm.assign(tag_str.c_str());
                for (auto& c : norm) {
                    if (c >= 'A' && c <= 'Z') {
                        c = static_cast<char>(c - 'A' + 'a');
                    }
                }
            }
            Roster::Instance().TriggerFlash(actor, base_slot, norm);
        }

        // ── Fade on death (v0.1.4) ───────────────────────────────────────
        // Arm fade on (actor, base_slot). Requires a pre-existing roster
        // entry — caller must run SetActorPulse(WithTransition) first.
        //
        // mode: 0 = overlay (em→0, alpha→0; corpse invisible tattoo)
        //       1 = emissive (em→1.0 baseline; texture visible, no glow)
        //       2 = inverted (em down then back; flicker effect)
        // durationMs: full animation duration. For mode=2 the dip + recover
        //             each take durationMs/2.
        void SetActorFade(
            RE::StaticFunctionTag* /*tag*/,
            RE::Actor*   actor,
            std::int32_t base_slot,
            std::int32_t mode,
            std::int32_t duration_ms)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().SetFadeParams(
                actor, base_slot,
                std::clamp(mode, 0, 2),
                static_cast<float>(std::max(1, duration_ms)));
        }

        void ClearActorFade(RE::StaticFunctionTag* /*tag*/,
                            RE::Actor* actor, std::int32_t base_slot)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().ClearFade(actor, base_slot);
        }

        // Manual fire (for testing or custom triggers — death sink is the
        // primary path). Returns nothing; Roster::TriggerFade is no-op if
        // entry missing / not armed / already active.
        void TriggerActorFade(RE::StaticFunctionTag* /*tag*/,
                              RE::Actor* actor, std::int32_t base_slot)
        {
            if (!actor) {
                return;
            }
            Roster::Instance().TriggerFade(actor, base_slot);
        }

        // Read an int from Data/SKSE/Plugins/MagicTattoosFramework.ini.
        // `key` may be a bare name (resolved against [General]) or the
        // "section.name" form for non-default sections. Returns the
        // supplied default if the file or key is missing.
        std::int32_t GetConfigInt(RE::StaticFunctionTag* /*tag*/,
                                  RE::BSFixedString key,
                                  std::int32_t      default_value)
        {
            std::string_view v = key.empty()
                ? std::string_view{}
                : std::string_view(key.c_str());
            return Config::GetInt(v, default_value);
        }

    }  // namespace

    bool Register(RE::BSScript::IVirtualMachine* vm)
    {
        if (!vm) {
            return false;
        }
        vm->RegisterFunction("SetActorPulse",               kClassName, SetActorPulse);
        vm->RegisterFunction("SetActorPulseWithTransition",   kClassName, SetActorPulseWithTransition);
        vm->RegisterFunction("SetActorPulseWithTransitionAt", kClassName, SetActorPulseWithTransitionAt);
        vm->RegisterFunction("GetNowSec",                     kClassName, GetNowSec);
        vm->RegisterFunction("BeginTransitionBatch",          kClassName, BeginTransitionBatch);
        vm->RegisterFunction("EndTransitionBatch",            kClassName, EndTransitionBatch);
        vm->RegisterFunction("ClearActor",                  kClassName, ClearActor);
        vm->RegisterFunction("ClearActorAt",  kClassName, ClearActorAt);
        vm->RegisterFunction("ClearAll",      kClassName, ClearAll);
        vm->RegisterFunction("SetEnabled",    kClassName, SetEnabled);
        vm->RegisterFunction("Size",          kClassName, Size);
        vm->RegisterFunction("SetActorFlash",     kClassName, SetActorFlash);
        vm->RegisterFunction("ClearActorFlash",   kClassName, ClearActorFlash);
        vm->RegisterFunction("TriggerActorFlash", kClassName, TriggerActorFlash);
        vm->RegisterFunction("SetActorFade",      kClassName, SetActorFade);
        vm->RegisterFunction("ClearActorFade",    kClassName, ClearActorFade);
        vm->RegisterFunction("TriggerActorFade",  kClassName, TriggerActorFade);
        vm->RegisterFunction("GetConfigInt",      kClassName, GetConfigInt);
        spdlog::info("Papyrus natives registered under '{}'", kClassName);
        return true;
    }

}  // namespace MTFPulse::Papyrus
