# Magic Tattoos Framework — reference

How MTF decides what to render, where its data lives, and what every in-game
setting does. The runtime model, file layout, and the audio-visual effects come
first; the page-by-page [MCM page reference](#mcm-page-reference) (General,
Preset editor, Plugins) is at the bottom.

> **Two meanings of "slot" — keep them straight:**
> - **Condition slot** (a *tier*): one entry in a preset — Default plus numbered
>   1…MAX, priority-ordered. A condition slot decides *which tattoo shows under
>   which condition*. Everything in [How a slot is chosen](#how-a-slot-is-chosen-at-runtime)
>   and the [Preset editor](#page-2--preset-editor) means this.
> - **Overlay slot**: a numeric NiOverride/SKEE index that a rendered overlay
>   *layer* physically occupies. These are the General page's *Overlay slot
>   (Body/Face/Hand/Feet)* sliders — pure engine plumbing to avoid clashing with
>   other overlay mods. Unrelated to condition slots; you rarely touch them.
>
> In short: **condition slots = priority tiers in a preset; overlay slots =
> SKEE render channels.** Where it could be ambiguous below, the full term is used.

---

## How a slot is chosen at runtime

Here, "slot" always means **condition slot** (a preset tier) — not the General
page's overlay slots. Condition slots are evaluated **top priority first**: the
Default slot always renders when no numbered condition slot's predicate matches;
numbered condition slots are checked in order and the first one satisfied wins.

1. Every `Update interval` seconds, MTF walks the numbered Condition slots in
   priority order.
2. The **first** slot whose condition(s) pass (per its Match mode) becomes the
   winning tier — its visuals render and its effects fire.
3. Numbered slots with **no condition set** are skipped (a `continue`, not a
   stop) — evaluation keeps going to lower-priority slots, so gaps are fine.
4. If none pass, the **Default** slot renders (effects-only if its Visual pack
   is `(no texture)`).
5. Persistence/cooldown can keep a slot winning (or locked out) past the moment
   its condition stops matching.
6. On a tier change, visuals cross-fade over **Transition → Duration**.

### Example — "Magicka Tracker"

A preset that turns one tattoo into a magicka gauge. It uses the Default slot as
the calm baseline and three numbered slots, each a `mtf.base:magicka.below`
condition at a different threshold. (Ships in the FOMOD — *Extras → Example
preset: Magicka Tracker* — and needs the Bitchcraft content pack for its
texture.)

| Slot | Name | Condition | Pack / texture | Look (layer 0) |
|------|------|-----------|----------------|----------------|
| **Default** (fallback) | *Full Magicka* | — always — | `mtf.bitchcraft` → *Sanguine Back* | violet `#8C6CD0`, em ×1.75, soft double-hump pulse 0.5 Hz / depth 100% |
| **1** (highest priority) | *No Magicka* | magicka **below 10%** | `<none>` | tattoo hidden ("burned out") |
| **2** | *Low Magicka* | magicka **below 40%** | inherits Default | crimson `#CC0033`, em ×3.0, fast pulse 2.5 Hz / depth 80% |
| **3** | *Medium Magicka* | magicka **below 70%** | inherits Default | amber `#EAAB00`, em ×4.0, pulse 1.3 Hz / depth 85% |

Because the evaluator checks **slot 1 first** and stops at the first match, the
overlapping `below` thresholds resolve into clean bands:

| Current magicka | Slots tested | Winner |
|-----------------|--------------|--------|
| ≥ 70% | 1✗ 2✗ 3✗ | **Default** — calm violet tattoo |
| 40–70% | 1✗ 2✗ 3✓ | **Slot 3** — amber, brighter glow |
| 10–40% | 1✗ 2✓ | **Slot 2** — crimson, fast urgent pulse |
| < 10% | 1✓ | **Slot 1** — tattoo hidden |

Key things the example shows:
- **Strictest threshold at the lowest index.** Put `below 10` in slot 1, not
  slot 3 — otherwise `below 70` would win first and the tighter bands could
  never trigger (first match wins).
- **`""` inherits, `<none>` hides.** Slots 2 and 3 leave the pack blank to reuse
  the Default's *Sanguine Back* texture and just re-tint and re-pulse it; slot 1
  sets `<none>` to deliberately blank the overlay at empty magicka.
- **Custom slot names** (*Full / No / Low / Medium Magicka*) label each tier in
  the MCM — spaces and mixed case are fine.
- **Transition** is 1.5 s, so crossing a band cross-fades the color/glow rather
  than snapping.
- `allowOverride = 1` and no persist/cooldown on every slot, so the tier tracks
  magicka live with no stickiness.

## Where the data lives

- **Presets**: `Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/*.json`
- **Visual packs**: `Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/*.json`
- **Waveforms**: `Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/waveforms/*.json`

A preset references packs by `packid` + `entryid`; it does not embed textures,
so packs must be installed for a preset's overlays to appear.

## Visual & sound effects

These ship in the **Base** effect plugin (`mtf.base`) and are picked like any
other effect via the **Effect N** menu (Preset editor). They affect presentation
only — no gameplay stats — and run for as long as the slot is the winning tier
(or for a fixed duration). Each is per-effect, so a slot can stack several at
once.

### Flash (`flash.onhit`)

Briefly spikes the tattoo's **own glow** to a peak brightness on a chosen
trigger, then decays back — a reactive pulse layered on top of the slot's
steady emissive.

| Param | Control | What it does |
|-------|---------|--------------|
| **Trigger event** | Menu | When to flash: *Disabled*, *Blunt only*, *Bladed only*, *Ranged only*, *Fire/Frost/Shock only*, *Melee (Blunt+Bladed)*, *Physical (Blunt+Bladed+Ranged)*, *Magic (Fire+Frost+Shock)*, *All combat classes*, or *On spell cast*. |
| **Peak emissive** | Slider | Flash brightness, additive, as % of 1.0 (0–1000, default 300). |
| **Ramp up (ms)** | Slider | Rise time to peak (default 150). |
| **Decay (ms)** | Slider | Fall time back to baseline (default 500). |
| **Sustain window (ms)** | Slider | How long it holds at peak before decaying (default 800). |

> This is an **additive** lane on the glow — it brightens on top of the layer's
> existing emissive, so the layer's base Emission strength can be 0 and the
> flash still shows. It only needs the slot to actually render a tattoo (a
> Visual pack assigned, not `(no texture)`); there must be an overlay on screen
> to flash.

### Vanilla Shader (`shader.play`)

Plays a stock Skyrim **EffectShader** on the actor while the slot is active —
the same visual envelopes vanilla spells use (fire cloak, frost, ghost, ward…).

| Param | Control | What it does |
|-------|---------|--------------|
| **Shader** | Menu | Which vanilla shader. 22 options: *Fire Cloak, Fire Burst, Frost, Frost Chillrend, Shock, Shock Storm, Stoneflesh, Ebonyflesh, Dragonhide, Soul Trap, Ghost (Ethereal), Ghost Red, Invisibility, Muffle, Ward Shield, Reanimate, Turn Undead Flames, Heal, Absorb Health, Vampire Change, Werewolf Transform, Detect Life*. |
| **Duration (s)** | Slider | How long to play, 0–60s. **0 = until the slot deactivates.** |

> Vanilla shaders carry their own baked ambient audio (e.g. Fire Cloak brings
> the fire crackle). Use **Vanilla Sound** only when you want a sound the shader
> doesn't already provide.

### Vanilla Sound (`sound.play`)

Plays a looping stock Skyrim **sound** from the actor while the slot is active.

| Param | Control | What it does |
|-------|---------|--------------|
| **Sound** | Menu | Which looping sound. ~35 options grouped by theme — *Fire / Frost / Shock* ready-loops and hums, *Soul Trap*, *Ward shimmer*, *Restoration* heal/circle, *Detect Life pulse*, *Alteration / Illusion* hums, *UI* stings (level up, skill up, quest, shout, perk, journal), *Dragon* roars, *Hagraven shriek*, and *Conjuration* portal/bound-weapon/impact. |
| **Duration (s)** | Slider | How long to play, 0–60s. **0 = until the slot deactivates.** |
| **Volume (%)** | Slider | Playback volume, 0–100% (default 100). |

> The sound and shader lists are **fixed** — they resolve to records baked into
> `MagicTattoosFramework.esp`, so new sounds/shaders can't be added via config.
> A third-party MTF plugin can register its own effect that plays its own forms.

---

# MCM page reference

Descriptions here mirror the in-menu info text (highlight any option in-game to
see the short version on the right).

## Page 1 — General

Global on/off and engine-wide settings.

| Option | Type | What it does |
|--------|------|--------------|
| **Enable** | Toggle | Master switch. Turns the whole mod on or off. |
| **Update interval (sec)** | Slider | How often the script re-checks conditions. Lower = more responsive, higher = better performance. |
| **Overlay slot (Body)** | Slider | First NiOverride overlay slot used for body art. Each layer of the chosen entry occupies one consecutive slot starting here (up to 4, since an entry can stack up to 4 layers). Avoid overlapping the ranges used by other NiOverride overlay mods (SlaveTats, RaceMenu overlays). |
| **Overlay slot (Face)** | Slider | First overlay slot for face art. Only matters when a slot picks a pack with `area=Face`. Same consecutive-slot rule as Body. Pick a range that doesn't collide with other face-overlay users. |
| **Overlay slot (Hand)** | Slider | First overlay slot for hand art. Only matters for packs with `area=Hand`. Same consecutive-slot rule. |
| **Overlay slot (Feet)** | Slider | First overlay slot for feet art. Only matters for packs with `area=Feet`. Same consecutive-slot rule. |
| **Reload visual packs** | Button | Re-scans `Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/` for pack JSONs right now. The count in parentheses is how many are loaded. |
| **Rescan packs on load** | Toggle | Runs the same scan automatically every time a save loads, so packs installed/removed since last session are picked up without opening this menu. **Default ON.** |
| **Debug mode** | Toggle | Shows a corner toast whenever the active tier changes (listing what's draining), for verifying conditions/effects fire. Also enables lifecycle audit counters (`cqf MTF_MainQuest DumpLifecycleAudit`). |

> **Overlay-slot note:** These are *overlay slots* (SKEE render channels), not
> the condition slots/tiers of a preset. Each area reserves a consecutive band of
> NiOverride slots starting at its base — one slot per layer the active entry
> defines (up to 4). The usable count is also bounded by SKEE's `iNumOverlays`
> for that pool (`skee64.ini`); non-Body pools default to ~3, so a 4-layer entry
> on Face/Hand/Feet may be clamped. If a tattoo from another overlay mod
> disappears or doubles up, move these bases to an unused range.

---

## Page 2 — Preset editor

Builds and edits a **preset**: a set of **condition slots** (tiers), each
pairing a *condition* (when it shows) with *visuals* (what shows) and optional
*effects* (what it does). Edits live in a scratch buffer until you **Save**.
("Slot" on this page always means a condition slot, never a General-page overlay
slot.)

### Preset (top)

| Option | Type | What it does |
|--------|------|--------------|
| **Editing** | Label | Which preset is currently loaded into the editor (read-only). |
| **Save** | Button | Overwrites the loaded preset's JSON on disk with the current editor state. |
| **Save as…** | Input | Type a name to commit the current editor state as a NEW preset. Name = letters/digits/`_`/`-`, max 32 chars. Fails on an existing name (use Save to overwrite). |
| **Load preset** | Menu | Loads an existing preset into the editor. **Replaces current edits** — Save first to keep them. Spell-applied presets stack on top and are unaffected. |
| **Delete preset** | Menu | Hides a preset from the picker (soft-delete). It flags the preset `hidden=1`; the `.json` file is **not** removed from disk (PapyrusUtil can't delete files), so it lingers as a reclaimable tombstone. Built-in presets can't be deleted. Editor state and spell-applied presets are unaffected. |
| **New preset** | Menu | Clears all slots, layers, effects, and transition duration to defaults. Use Save as… to commit. |

### Transition

| Option | Type | What it does |
|--------|------|--------------|
| **Duration** | Slider | Seconds to cross-fade visuals (alpha, tint, emissive color, emission strength) when the active tier changes. 0 = snap instantly. Saved with the preset. |

### Configure slot

**Configure slot** (menu) picks which condition slot the sections below edit. The
Default slot is the always-on fallback; Conditions 1…MAX are priority-ordered.

| Option | Type | What it does |
|--------|------|--------------|
| **Slot name** | Input | Renames the slot for clarity (e.g. "Magicka draught" instead of "Condition 3"). Empty restores the default label. Save to persist. |
| **Swap with slot…** | Menu | Swaps this slot's condition, effects, cooldown, and name with another slot. Visuals stay tied to the slot index. Both slots' timers clear; NPCs revalidate next tick. Default slot can't be swapped. |

### Condition (numbered slots only)

| Option | Type | What it does |
|--------|------|--------------|
| **Condition type** | Menu | Which predicate must be satisfied for this slot to activate. List is built from registered condition plugins. |
| **(condition param)** | Slider/Menu/Input | Threshold/parameter for the chosen condition (e.g. "Magicka below %"). Control type, label, and format come from the plugin (numeric → slider, choice → menu, free text → input). |
| **(condition param 2)** | Slider/Menu/Input | Optional second parameter for conditions that need one. |
| **Condition 2 type** | Menu | Optional second predicate, combined with condition 1 via Match mode. |
| **Condition 2 params** | Slider/Menu/Input | Threshold(s) for condition 2. |
| **Match mode** | Menu | **AND** = every condition in the slot must pass. **OR** = any one passing activates the slot. |

### Visuals

| Option | Type | What it does |
|--------|------|--------------|
| **Visual pack** | Menu | Which content pack supplies the texture. `(no texture)` = effects-only, no overlay. On numbered slots, `(inherit Default)` falls back to the Default slot's pack. Packs are JSON in the `visuals/` folder (see [Where the data lives](#where-the-data-lives)). |
| **Texture** | Menu | Which entry (image set) inside the pack to use. `(inherit Default)` on numbered slots falls back to Default's pick. |

#### Layer 0…3 (per layer)

A pack entry can stack up to 4 layers (e.g. base mark + glow halo). Each gets:

| Option | Type | What it does |
|--------|------|--------------|
| **Tint** | Color | Tint color for the layer. Layer 0 is typically the base mark, layer 1 the glow. |
| **Emission color** | Color | Glow color for the layer. |
| **Emission strength** | Slider | Glow intensity. 0 = no glow. This is the *peak* the pulse dims from. |
| **Opacity** | Slider | Layer opacity, 0–100%. |

### Pulse

Animates the glow of the slot's visuals.

| Option | Type | What it does |
|--------|------|--------------|
| **Rate** | Slider | Pulse cycles per second (Hz). 0 disables the animation. |
| **Depth** | Slider | How far the glow dims from peak. 0% = no pulse, 100% = fully off at the trough. |
| **Pause** | Slider | Seconds held at the dim trough between cycles. 0 = continuous. |
| **Waveform** | Menu | Curve shape for one cycle. Built-in cosine is default; JSON files in the `waveforms/` folder also appear here. |

### Fade on death

One-shot animation when the actor dies, then the entry stops animating. Saved
with the preset.

| Option | Type | What it does |
|--------|------|--------------|
| **Mode** | Menu | **Off** = nothing. **Overlay** = alpha to 0 (tattoo disappears). **Emissive** = glow to 0 (art stays, stops glowing). **Inverted** = dip to 0 then recover (a final flicker). |
| **Duration** | Slider | Full length of the fade in seconds. Inverted splits this half-dip, half-recover. |

### Cooldown / persistence (numbered slots only)

| Option | Type | What it does |
|--------|------|--------------|
| **Persist hours / minutes** | Sliders | Once activated, the slot stays active for hours:minutes regardless of whether the condition keeps firing. 0h0m disables persistence. |
| **Allow override** | Button | During the persist window, can a higher-priority slot take over? **Yes**: persistence still wins, but a higher-priority condition steals the tier. **No (locked)**: this slot wins outright until persist + cool both expire. |
| **Cool hours / minutes** | Sliders | After persistence ends (or after a normal deactivation when persist=0), the slot can't re-arm for hours:minutes. 0h0m disables cooldown. |

### Effects

Up to 8 effects per slot. Each effect fires while this slot is the **winning
tier**. Per effect:

| Option | Type | What it does |
|--------|------|--------------|
| **Effect N** | Menu | Pick an effect from the registered effect plugins. |
| **(effect params 1–5)** | Slider/Menu/Input | Parameters for the chosen effect. Control type, labels, and formats come from the plugin. |

Most built-in effects are stat tweaks (modify skill/resist/regen, toggle muffle,
damage magicka, etc.). Three of them are **audio-visual** rather than mechanical —
they let a tattoo trigger a vanilla shader, sound, or glow flash while the slot
is active. See [Visual & sound effects](#visual--sound-effects) above.

---

## Page 3 — Plugins

Lists every registered integration plugin (conditions + effects). The header
shows totals: plugin count, condition-item count, effect-item count.

| Option | Type | What it does |
|--------|------|--------------|
| **Previous / Next page** | Buttons | Page through the plugin list when there are more than fit on one screen. |
| **(per-plugin toggle)** | Toggle | Show/hide a plugin's options. Disabling only **hides** its conditions and effects from the slot dropdowns on the Preset editor — it does **not** turn off effects already bound in a saved preset; those keep firing. Existing bindings stay visible so you can clear them manually. The label shows `(id, Nc, Ne)` = condition count, effect count. |
