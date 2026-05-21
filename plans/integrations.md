# Integrations Roadmap

Snapshot of what MTF's plugin ESPs cover today vs. what's available in the
mods they target. Not a commitment — a catalog to draw from when picking
the next plugin to expand.

Last updated: 2026-05-21 (post-v0.1.14).

---

## Current plugins

### `MTF_Plugin_Base` (built-in)

Covers the engine surface — vanilla ActorValues, shaders, sounds. Not a
third-party integration.

### `MTF_Plugin_BFNG` — Beeing Female NG

Binds to `FWController` (FormID `0x182A` in `BeeingFemale.esm`). Soft-master:
skips registration if BFNG isn't loaded. Mirrors FMR's pregnancy/ovulation
surface so presets are roughly portable across the two pregnancy mods with
a key rename.

**Conditions exposed (5):**

| Condition | Source method | Description |
|---|---|---|
| `pregnancy` | `IsPregnant` + `GetStatePercentage` | belly stage 1..100 (only while pregnant) |
| `ovulation` | `GetFemaleState == 1` | currently ovulating |
| `cycle.phase` | `GetFemaleState` | 4-tier enum dropdown (follicular / ovulating / luteal / menstruating) |
| `baby.health` | `GetBabyHealth` | min baby health 0..100 (only while pregnant) |
| `num.births` | `GetNumBirth` | slow-evolving birth counter |

**Effects exposed (1):**

| Effect | Method | Description |
|---|---|---|
| `trigger.ovulation` | `ChangeState(target, 1)` | one-shot: forces cycle phase to ovulating (no-op if pregnant or already ovulating) |

ESP ships with `BeeingFemale.esm` as a hard master — file sits ready in the
mod folder but only activates once the user installs BFNG and enables both
the ESM and `MTF_Plugin_BFNG.esp`.

### `MTF_Plugin_FMR` — Fertility Mode Reloaded

Binds to `_JSW_BB_Storage` (FormID `0x000D62` in `Fertility Mode.esm`).
Soft-master: skips registration if FMR isn't loaded.

**Conditions exposed (2 of ~8 useful storage fields):**

| Condition | Source field | Description |
|---|---|---|
| `pregnancy` | computed from `LastConception` / `PregnancyDuration` | belly stage 1..100 |
| `ovulation` | `LastOvulation` in `(0, EggLife]` | within egg-life window |

**Effects exposed (1):**

| Effect | Description |
|---|---|
| `trigger.ovulation` | one-shot: sets `LastOvulation[index] = 0.001` (no-op if pregnant) |

**Unexposed FMR storage worth surfacing:**

| Field / event | Use |
|---|---|
| Cycle phase (faction rank 116..119 on `ImmersiveEffectsFaction`) | categorical 4-tier condition: menstrual / follicular / ovulatory / luteal |
| `LastInsemination` | time-since-insemination tier (fresh / lingering / clearing) |
| `SpermCount` | scalar "wet" tier |
| Recovery (faction rank 101..115) | post-birth 15-tier ramp |
| `LastBirth` | long-tail postpartum tier (days since birth) |
| `FertilityModeLabor` ModEvent | brief labor-in-progress signal — ephemeral burst |
| `CurrentFather` / `LastFather` | niche paternity reads (could drive "marked by X" patterns) |

### `MTF_Plugin_SLA` — SexLab Aroused

Binds to `slaFrameworkScr` (FormID `0x04290F` in `SexLabAroused.esm`).
The canonical class is shared across all SLA forks, so this plugin works on:

- **Classic SexLab Aroused** (LE port)
- **SexLab Aroused Redux**
- **OSL Aroused** (Modding Essentials uses this)
- **SLO Aroused NG** (DoD uses this)

**Conditions exposed (1 of ~9 portable methods):**

| Condition | Source method | Description |
|---|---|---|
| `arousal` | `GetActorArousal` | exposure ≥ threshold |

**Effects exposed (3):**

| Effect | Method | Description |
|---|---|---|
| `arousal.rate` | `SetActorExposure(cur+param)` per game-hour | climb own exposure |
| `arousal.rate.npc` | same, fanned across nearby NPCs | pheromone aura |
| `modify.arousal` | `SetActorExposure(cur+param)` once | burst-add on switch |

---

## Cross-fork compatibility map (SLA family)

Methods on `slaFrameworkScr` — those present on **both** OSL Aroused and SLO
Aroused NG can be called by the existing `MTF_Plugin_SLA` without
fork-specific code.

### Portable (both forks)

**Reads:**
`GetActorArousal`, `GetActorExposure`, `GetActorExposureRate`,
`GetActorTimeRate`, `GetActorDaysSinceLastOrgasm`, `IsActorExhibitionist`,
`IsActorArousalLocked`, `IsActorArousalBlocked`, `GetGenderPreference`,
`GetMostArousedActorInLocation`, `GetVersion`.

**Writes:**
`SetActorExposure`, `UpdateActorExposure`, `SetActorExposureRate`,
`UpdateActorExposureRate`, `SetActorTimeRate`, `UpdateActorTimeRate`,
`SetActorExhibitionist`, `SetActorArousalLocked`, `SetGenderPreference`,
`UpdateActorOrgasmDate`.

### OSL Aroused only

`GetActorHoursSinceLastSex` (slaFrameworkScr),
plus the `OSLAroused_ModInterface` global API (`GetLibido`, `ModifyLibido`,
`RegisterOrgasm`, `ModifyArousalMultiple`, etc.).

### SLO Aroused NG only

`SetActorArousalBlocked`, `GetActorDaysSinceLastRape`,
`GetDynamicEffectValue` / `SetDynamicArousalEffect` /
`ModDynamicArousalEffect` (named long-running modifier system),
`UpdateSOSPosition`, `HandleErection` (SOS schlong control).

Plus its modular `sla_*plugin` system (DD plugin, OStim plugin, etc.) and
the `slax` utility module.

### Fork-detection strategy (if we want OSL/SLO-only methods)

Two options:

1. **Per-fork sub-plugin.** A second plugin (e.g. `MTF_Plugin_SLA_OSL.esp`
   or `MTF_Plugin_SLA_SLO.esp`) that registers only when its specific
   `OSLArousedNative.pex` / `slax.pex` resolves. Cleanest separation.
2. **Runtime check + branch.** `_resolveDeps` probes for the fork-specific
   script and sets a `bool _isOSL` flag; conditional accessors branch.
   Less code, but ties our plugin to specific upstream filenames.

For the slow expansion list, sticking with portable methods avoids both.

---

## Highest-ROI portable expansions (today)

### SLA additions

**New conditions:**

| ID | Backed by | Notes |
|---|---|---|
| `days.since.orgasm` | `GetActorDaysSinceLastOrgasm` | flagship slow-evolving tier source |
| `exposure.rate` | `GetActorExposureRate` | rate-of-climb, independent of current level |
| `arousal.lock` | `IsActorArousalLocked` | boolean flag (chastity / bondage narrative) |
| `arousal.blocked` | `IsActorArousalBlocked` | boolean flag (temporarily off-line) |
| `exhibitionist` | `IsActorExhibitionist` | boolean flag — gates exhibitionist-only sets |
| `gender.preference` | `GetGenderPreference` | orientation enum (straight/bi/gay) |
| `time.rate` | `GetActorTimeRate` | per-actor SLA time scalar |

**New effects:**

| ID | Backed by | Notes |
|---|---|---|
| `set.exposure.rate` | `SetActorExposureRate` / `UpdateActorExposureRate` | per-tier libido modifier |
| `trigger.orgasm` | `UpdateActorOrgasmDate` | one-shot climax event (resets days-since timer) |
| `set.time.rate` | `SetActorTimeRate` / `UpdateActorTimeRate` | per-actor time scalar |
| `set.exhibitionist` | `SetActorExhibitionist` | toggle exhibitionist flag |
| `set.arousal.lock` | `SetActorArousalLocked` | lock/unlock arousal changes |
| `set.gender.preference` | `SetGenderPreference` | set orientation enum |

### FMR additions

**New conditions:**

| ID | Backed by | Notes |
|---|---|---|
| `cycle.phase` | `ImmersiveEffectsFaction` rank 116..119 | menstrual/follicular/ovulatory/luteal |
| `insemination.fresh` | game-time - `LastInsemination` | hours-since-insemination |
| `sperm.level` | `SpermCount[index]` | scalar 0..N |
| `postpartum` | `ImmersiveEffectsFaction` rank 101..115 | recovery 15-tier ramp |
| `time.since.birth` | game-time - `LastBirth` | long-tail days-since-birth |

**New effects:**

| ID | Backed by | Notes |
|---|---|---|
| `trigger.labor.burst` | listen for `FertilityModeLabor` ModEvent | ephemeral on-labor effect (driven by event, not user action) |

---

## Candidate new plugins (deps installed but unintegrated)

Mods that ship public Papyrus APIs and are loaded in at least one of the
target modlists, but MTF doesn't yet expose. Each would be its own ESP +
script pair following the existing soft-master pattern (`_resolveDeps`
returns `None` when the mod is absent; `_tryRegister` silently bails).

### `MTF_Plugin_SexLab` — SexLab Framework P+

**Status:** SexLab Framework PPLUS is installed and active in Modding
Essentials (`SexLab.esm` loaded). DoD's modlist also runs SexLab core +
P+, so a single plugin works on both.

**Soft-dep strategy:**
- Drop `SexLabFramework.psc`, `SexLabStatistics.psc`, `sslActorStats.psc`
  into `_deps/` for compile.
- Probe a canonical SL form (e.g. `SexLabQuestFramework` from
  `SexLab.esm`) in `_resolveDeps()`; bail if absent.
- All listed methods are `Global Native`; once dep resolves they're
  callable as `SexLabFramework.Func(...)`.

**Conditions (8–10):**

| ID | Backed by | Use |
|---|---|---|
| `sexlab.in.scene` | `SexLabFramework.IsActorActive(Actor)` | currently fucking |
| `sexlab.cum.total` | `SexLabFramework.CountCumFx(Actor, -1)` | total cum layers |
| `sexlab.cum.vaginal` | `CountCumVaginal(Actor)` | per-orifice count |
| `sexlab.cum.oral` | `CountCumOral(Actor)` | per-orifice count |
| `sexlab.cum.anal` | `CountCumAnal(Actor)` | per-orifice count |
| `sexlab.skill.vaginal` | `sslActorStats.GetSkill(Actor, "Vaginal")` | lifetime XP — slow-evolving ⭐ |
| `sexlab.skill.anal` | `GetSkill(Actor, "Anal")` | same |
| `sexlab.skill.oral` | `GetSkill(Actor, "Oral")` | same |
| `sexlab.lewd` | `sslActorStats.GetLewd(Actor)` | lewdness stat |
| `sexlab.pure` | `sslActorStats.GetPure(Actor)` | purity stat (inverse of lewd) |
| `sexlab.has.strapon` | `SexLabFramework.HasStrapon(Actor)` | flag |

**Effects (3–4):**

| ID | Backed by | Use |
|---|---|---|
| `cum.apply` | `AddCumFx(Actor, type)` / `AddCumFxLayers(...)` | apply cum on activate (param = type, param2 = layers) |
| `cum.remove` | `RemoveCumFx(Actor, -1)` | clean cum |
| `skill.add.xp` | `sslActorStats.AddSkillXP(Actor, ...)` | bump per-skill XP on burst |
| `encounter.log` | `SexLabStatistics.AddEncounter(...)` | log a synthetic encounter (niche) |

**Event hooks (no polling):**

SexLab P+ supports `SexLabThreadHook` registration via
`SexLabFramework.RegisterHook(hook)`. The hook receives:
- scene start
- per-actor stage-advance
- per-actor orgasm
- scene end

Wiring this up lets MTF fire ephemeral burst effects (shader pulse + sound
sting + cum apply) on scene events without polling. Comparable in shape to
the `FertilityModeLabor` ModEvent listener proposed for FMR.

### `MTF_Plugin_OStim` — OStim Standalone

**Status:** OStim Standalone is installed and active in Modding Essentials
(`OStim.esp` loaded). Independent of SexLab — MTF can support both
ecosystems in parallel.

**Soft-dep strategy:**
- Drop `OActor.psc`, `OEvent.psc`, `OLibrary.psc` into `_deps/` for
  compile.
- Probe an OStim quest form (e.g. via `Game.GetFormFromFile(?, "OStim.esp")`)
  in `_resolveDeps`; bail if absent.
- All listed methods on `OActor` are `Global Native`; callable as
  `OActor.Func(...)` once dep resolves.

**Conditions (5–7):**

| ID | Backed by | Use |
|---|---|---|
| `ostim.in.scene` | `OActor.IsInOStim(Actor)` | currently in scene |
| `ostim.excitement` | `OActor.GetExcitement(Actor)` | per-scene arousal scalar |
| `ostim.excitement.mult` | `OActor.GetExcitementMultiplier(Actor)` | actor multiplier |
| `ostim.times.climaxed` | `OActor.GetTimesClimaxed(Actor)` | per-scene climax counter |
| `ostim.climax.stalled` | `OActor.IsClimaxStalled(Actor, true)` | stall flag |
| `ostim.has.tag` | `OActor.HasMetadata(Actor, tag)` | actor-attached tag flag (param = tag string) |
| `ostim.has.schlong` | `OActor.HasSchlong(Actor)` | SOS flag |

**Effects (3–4):**

| ID | Backed by | Use |
|---|---|---|
| `trigger.climax.ostim` | `OActor.Climax(Actor, IgnoreStall)` | force climax — pair w/ shader/sound burst |
| `excitement.modify` | `OActor.ModifyExcitement(Actor, val, RespectMult)` | bump excitement |
| `excitement.set` | `OActor.SetExcitement(Actor, val)` | absolute set |
| `climax.stall` / `climax.permit` | `StallClimax` / `PermitClimax` | block or unblock climax |
| `metadata.add` | `OActor.AddMetadata(Actor, tag)` | attach actor tag (could chain to other OStim addons) |

**Event hooks (ModEvent broadcasts):**

OStim sends these ModEvents that any script can register for:

| Event | Fires |
|---|---|
| `ostim_start` | scene begins |
| `ostim_end` | scene ends |
| `ostim_orgasm` | global orgasm event |
| `ostim_actor_orgasm` | per-actor orgasm (params include actor) |
| `ostim_thirdactor_join` | third actor joins |
| `ostim_thirdactor_leave` | third actor leaves |
| `ostim_thread_end` | thread ends |
| `ostim_subthread_start` / `end` / `orgasm` | subthread lifecycle |

Same pattern as FMR's `FertilityModeLabor`: MTF subscribes once at plugin
register, fans events into the dispatch context, fires ephemeral effects.

### Overlap notes

SexLab and OStim both expose "in scene" and "climax" semantics. Users
running both will get parallel events. Rather than try to merge them,
each plugin emits its own framework-namespaced conditions (`sexlab.in.scene`
vs `ostim.in.scene`). Presets can either OR them together (gate on either
framework being active) or pick one.

---

## Other mod candidates (not yet installed)

Mods that would map well to MTF tiers but are **not** in either modlist
today.

### Tier A — slam-dunk MTF fits

**Wear & Tear (OStim addon)** — Orifice looseness state evolves with use.
*The* MTF philosophy: tattoos that deepen with body history. Sits on top of
the proposed OStim plugin.

### Tier B — broad appeal, non-adult-themed

**SunHelm Survival** — Hunger / thirst / cold / wet / sleep tiers. Maps
straight to MTF tier conditions. Universal appeal — would broaden MTF's
audience beyond adult mods.

**Wintersun** — Divine devotion 0..100 + favored god enum. Slow-evolving,
natural MTF use case for religious-mark tattoos.

### Tier C — niche but iconic

**Sacrosanct / Better Vampires / Sacrilege** — Vampire stage 1..4 from
feeding hunger. Visual progression of vampirism.

**Skooma Whore / Drug Wars** — Addiction stages.

**Bathing in Skyrim / Submerged** — Cleanliness tiers. Could drive
"tattoo gleams when clean / dulls when grimy" effects.

---

## Sequencing notes

Roughly in priority order:

1. **SLA portable expansion** (parked, 4 user-picked surfaces:
   `days.since.orgasm`, `arousal.lock`, `exposure.rate`,
   `set.exposure.rate`, `trigger.orgasm`). Smallest delta — extends an
   existing plugin, no new ESP.

2. **FMR expansion** — cycle phase, insemination/sperm reads, postpartum,
   labor event listener. Same shape as the SLA expansion.

3. **`MTF_Plugin_SexLab`** new ESP. Biggest dependency footprint but also
   biggest user-facing surface (cum overlays, lifetime skill levels,
   per-partner stats).

4. **`MTF_Plugin_OStim`** new ESP. Smaller surface than SexLab P+ but
   covers an independent ecosystem; many users run one but not the other.

5. **New-mod integrations** (Wear & Tear / SunHelm / Wintersun). Only
   makes sense after the user installs them.

The two new ESPs (SexLab, OStim) are each ~8–15h of work (script + ESP +
alias kick + test presets). The SLA / FMR expansions are each ~2–4h.
