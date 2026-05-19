#include "hit_sink.h"
#include "log.h"
#include "pulse_roster.h"

#include <string_view>

namespace MTFPulse {

    namespace {
        // Vanilla TESObjectWEAP::Data::AnimationType values (from the
        // CK / Papyrus GetWeaponType). Mirrors MTF_HitListener._classify.
        //   0 HtH          1 OneHSword     2 OneHDagger
        //   3 OneHAxe      4 OneHMace      5 TwoHSword
        //   6 TwoHAxe (incl. warhammer)    7 Bow
        //   8 Staff        9 Crossbow
        // Returns one of: "blunt", "bladed", "ranged", "any".
        // Staff (8) is unclassified → "any" (the elemental spell path,
        // if any, comes via the spell source, not the staff itself).
        std::string_view ClassifyWeapon(RE::TESObjectWEAP* w, RE::BGSKeyword* kwWarhammer)
        {
            if (!w) {
                return "any";
            }
            const auto type = static_cast<std::uint32_t>(w->GetWeaponType());
            if (type == 0 || type == 4) {
                return "blunt";
            }
            if (type == 6) {
                // 2H axe family — warhammer (blunt) vs battleaxe (bladed).
                if (kwWarhammer && w->HasKeyword(kwWarhammer)) {
                    return "blunt";
                }
                return "bladed";
            }
            if (type == 1 || type == 2 || type == 3 || type == 5) {
                return "bladed";
            }
            if (type == 7 || type == 9) {
                return "ranged";
            }
            // Staff (8) and any unknown future type → "any".
            return "any";
        }

        // Returns one of: "fire", "frost", "shock", "any".
        std::string_view ClassifySpell(RE::SpellItem* s,
                                       RE::BGSKeyword* kwFire,
                                       RE::BGSKeyword* kwFrost,
                                       RE::BGSKeyword* kwShock)
        {
            if (!s) {
                return "any";
            }
            // SpellItem::HasKeyword walks the spell's effects' MGEFs.
            if (kwFire && s->HasKeyword(kwFire)) {
                return "fire";
            }
            if (kwFrost && s->HasKeyword(kwFrost)) {
                return "frost";
            }
            if (kwShock && s->HasKeyword(kwShock)) {
                return "shock";
            }
            return "any";
        }
    }  // namespace

    HitSink* HitSink::GetSingleton()
    {
        static HitSink s;
        return &s;
    }

    void HitSink::Install()
    {
        auto* sink = GetSingleton();
        if (sink->installed_) {
            return;
        }
        auto* handler = RE::TESDataHandler::GetSingleton();
        if (!handler) {
            spdlog::warn("HitSink::Install: TESDataHandler not ready, deferring keyword lookup");
        } else {
            sink->kw_warhammer_  = handler->LookupForm<RE::BGSKeyword>(0x06D930, "Skyrim.esm");
            sink->kw_magicfire_  = handler->LookupForm<RE::BGSKeyword>(0x01CEAD, "Skyrim.esm");
            sink->kw_magicfrost_ = handler->LookupForm<RE::BGSKeyword>(0x01CEAE, "Skyrim.esm");
            sink->kw_magicshock_ = handler->LookupForm<RE::BGSKeyword>(0x01CEAF, "Skyrim.esm");
            spdlog::info("HitSink keywords: warhammer={} fire={} frost={} shock={}",
                         sink->kw_warhammer_  ? "ok" : "miss",
                         sink->kw_magicfire_  ? "ok" : "miss",
                         sink->kw_magicfrost_ ? "ok" : "miss",
                         sink->kw_magicshock_ ? "ok" : "miss");
        }
        auto* src = RE::ScriptEventSourceHolder::GetSingleton();
        if (src) {
            src->AddEventSink<RE::TESHitEvent>(sink);
            sink->installed_ = true;
            spdlog::info("HitSink: TESHitEvent sink installed");
        } else {
            spdlog::error("HitSink::Install: ScriptEventSourceHolder not available");
        }
    }

    RE::BSEventNotifyControl HitSink::ProcessEvent(
        const RE::TESHitEvent*               a_event,
        RE::BSTEventSource<RE::TESHitEvent>* /*src*/)
    {
        if (!a_event || !a_event->target) {
            return RE::BSEventNotifyControl::kContinue;
        }
        auto* targetActor = a_event->target.get() ? a_event->target.get()->As<RE::Actor>() : nullptr;
        if (!targetActor) {
            return RE::BSEventNotifyControl::kContinue;
        }

        // Classify the hit source. source/projectile are FormIDs;
        // LookupByID returns the live TESForm. Weapon vs Spell decides
        // the tag.
        std::string_view tag = "any";
        if (a_event->source != 0) {
            auto* form = RE::TESForm::LookupByID(a_event->source);
            if (form) {
                if (auto* w = form->As<RE::TESObjectWEAP>()) {
                    tag = ClassifyWeapon(w, kw_warhammer_);
                } else if (auto* s = form->As<RE::SpellItem>()) {
                    tag = ClassifySpell(s, kw_magicfire_, kw_magicfrost_, kw_magicshock_);
                }
            }
        } else if (a_event->projectile != 0) {
            // Source==0 with a projectile typically means the projectile
            // outlived its launcher (e.g. arrow in flight after the bow
            // owner's weapon swap). Fall back to "ranged" for arrows /
            // bolts; magic projectiles already get classified via source
            // when present.
            tag = "ranged";
        }
        // Unarmed strikes (source==0, projectile==0) → BLUNT to match
        // Papyrus _classify's "None source = unarmed" branch.
        if (a_event->source == 0 && a_event->projectile == 0) {
            tag = "blunt";
        }

        Roster::Instance().TriggerFlashAllSlotsForActor(targetActor, tag);
        return RE::BSEventNotifyControl::kContinue;
    }

}  // namespace MTFPulse
