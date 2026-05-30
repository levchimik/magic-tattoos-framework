// MTF Preset Validator — schema check + installable-ZIP packaging.
//
// Schema is ported from MTF_MainQuest.psc's SavePreset / LoadPreset
// (search those names in the script for the source of truth). The current
// schema is version 8; LoadPreset still accepts >=4 but warns on legacy
// keys. The MCM accepts a preset as live when root `.valid == 1`.
//
// JSZip is loaded as a classic <script> in index.html and exposes the
// global `JSZip`.

const CURRENT_SCHEMA = 9;         // MTF_MainQuest.SavePreset writes 9 (v0.2.9+)
const MIN_SCHEMA = 4;             // LoadPreset refuses anything < 4
const SLOT_COUNT = 8;             // MTF_MainQuest: while s < 8
const MAX_LAYERS_PER_SLOT = 4;    // MTF_MainQuest.MAX_LAYERS_PER_SLOT()
const MAX_EFFECTS_PER_SLOT = 32;  // MTF_MainQuest.MAX_EFFECTS_PER_SLOT()
const MAX_NAME_LEN = 32;          // MTF_MainQuest._sanitizePresetName

// ── Known keys (typo catcher) ───────────────────────────────────────────────
const KNOWN_TOP = new Set([
    'displayname', 'schemaversion', 'valid', 'transition', 'fadeondeath',
    'slot', 'int',  // JsonUtil leaves an `int` namespace block on disk
]);
const KNOWN_SLOT = new Set([
    'cond', 'persist', 'cool', 'cooldown', 'pulse', 'layer', 'effect',
    'name',  // v0.2.9: per-slot display name override (empty = use canonical label)
]);
// v0.3.1 (schema 9): conditions are an array under cond.items[] + an operator.
const KNOWN_COND = new Set(['packid', 'entryid', 'op', 'items']);
const KNOWN_COND_ITEM = new Set(['pluginid', 'param', 'param2']);
// Legacy condition keys (schema 8 single-cond / v0.3.0 hybrid) — now errors.
const LEGACY_COND = new Set(['pluginid', 'param', 'param2', 'count']);
const KNOWN_PERSIST = new Set(['min', 'allowOverride']);
const KNOWN_COOL = new Set(['min']);
const KNOWN_PULSE = new Set(['rate', 'depth', 'pause', 'waveform']);
const KNOWN_LAYER = new Set(['tint', 'emissive', 'emissivemult', 'alpha']);
const KNOWN_EFFECT = new Set([
    'key', 'param1', 'param2', 'param3', 'param4', 'param5',
    // Legacy (v0.1.3 → folded into paramN in v0.2.1). Handled explicitly
    // below with a "legacy" warning so it's not confused with a typo.
    'extras',
]);
const KNOWN_FADE = new Set(['enabled', 'mode', 'durationms']);

// ── Type helpers ────────────────────────────────────────────────────────────
const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isNumber = (v) => typeof v === 'number' && Number.isFinite(v);
const isInt = (v) => isNumber(v) && Number.isInteger(v);
const isString = (v) => typeof v === 'string';
const isBoolInt = (v) => v === 0 || v === 1;

// "#RRGGBB" / "RRGGBB" or int 0..16777215.
function isColorValue(v) {
    if (isInt(v)) return v >= 0 && v <= 16777215;
    if (isString(v)) {
        const m = v.match(/^#?([0-9A-Fa-f]{6})$/);
        return m !== null;
    }
    return false;
}

// Mirror MTF_MainQuest._sanitizePresetName: keep [A-Za-z0-9_-], cap 32, else `_`.
function sanitizePresetName(raw) {
    if (!raw) return '';
    let out = '';
    const max = Math.min(raw.length, MAX_NAME_LEN);
    for (let i = 0; i < max; i++) {
        const ch = raw[i];
        out += /[A-Za-z0-9_\-]/.test(ch) ? ch : '_';
    }
    return out;
}

// ── Report ──────────────────────────────────────────────────────────────────
// Each finding: { level: 'err' | 'warn' | 'info', msg: string, path?: string }
class Report {
    constructor() {
        this.findings = [];
    }
    err(msg, path)  { this.findings.push({ level: 'err',  msg, path }); }
    warn(msg, path) { this.findings.push({ level: 'warn', msg, path }); }
    info(msg, path) { this.findings.push({ level: 'info', msg, path }); }

    get errors()   { return this.findings.filter(f => f.level === 'err').length; }
    get warnings() { return this.findings.filter(f => f.level === 'warn').length; }
    get ok()       { return this.errors === 0; }
}

// ── Param validators ────────────────────────────────────────────────────────
function validateCond(cond, slotIdx, report) {
    const base = `slot[${slotIdx}].cond`;
    if (!isPlainObject(cond)) {
        report.err(`must be an object`, base);
        return;
    }
    // Visual keys (unchanged across schemas).
    if ('packid' in cond && !isString(cond.packid)) {
        report.err(`must be a string`, `${base}.packid`);
    }
    if ('entryid' in cond && !isString(cond.entryid)) {
        report.err(`must be a string`, `${base}.entryid`);
    }
    // v0.3.1: operator combining the conditions. 0 = AND (all), 1 = OR (any).
    if ('op' in cond) {
        if (!isInt(cond.op) || (cond.op !== 0 && cond.op !== 1)) {
            report.err(`must be 0 (AND - all must pass) or 1 (OR - any passes)`, `${base}.op`);
        }
    }
    // v0.3.1: conditions live in cond.items[]. Absent/empty array = an
    // unconfigured slot (visual-only or Default). Each item: pluginid (string,
    // required) + optional param / param2 (int slider, or string menu id).
    if ('items' in cond) {
        if (!Array.isArray(cond.items)) {
            report.err(`must be an array of condition objects`, `${base}.items`);
        } else {
            cond.items.forEach((item, idx) => {
                const ib = `${base}.items[${idx}]`;
                if (!isPlainObject(item)) {
                    report.err(`must be an object`, ib);
                    return;
                }
                if (!('pluginid' in item) || !isString(item.pluginid)) {
                    report.err(`required string field missing - format "pluginid:conditionid"`, `${ib}.pluginid`);
                } else if (item.pluginid !== '' && !item.pluginid.includes(':')) {
                    report.warn(`expected "pluginid:conditionid" form (e.g. "mtf.base:magicka.below")`, `${ib}.pluginid`);
                }
                if ('param' in item && !isInt(item.param) && !isString(item.param)) {
                    report.err(`must be an integer (slider param) or string (menu param id)`, `${ib}.param`);
                }
                if ('param2' in item && !isInt(item.param2) && !isString(item.param2)) {
                    report.err(`must be an integer (slider param) or string (menu param id)`, `${ib}.param2`);
                }
                for (const k of Object.keys(item)) {
                    if (!KNOWN_COND_ITEM.has(k)) {
                        report.warn(`unknown field (typo? known: ${[...KNOWN_COND_ITEM].join(', ')})`, `${ib}.${k}`);
                    }
                }
            });
        }
    }
    // Legacy schema-8 / v0.3.0 condition fields (flat pluginid/param, condx<j>)
    // are no longer read by LoadPreset (schema 9 hard cutover) - flag as errors
    // so a stale preset fails loudly instead of silently losing its condition.
    for (const k of Object.keys(cond)) {
        if (LEGACY_COND.has(k) || k.startsWith('condx')) {
            report.err(`legacy condition field - schema 9 moved conditions into ${base}.items[]; re-save in MTF v0.3.1+ or run tools/migrate_presets_to_items.py`, `${base}.${k}`);
        } else if (!KNOWN_COND.has(k)) {
            report.warn(`unknown field (typo? known: ${[...KNOWN_COND].join(', ')})`, `${base}.${k}`);
        }
    }
}

function validatePersist(persist, slotIdx, report) {
    const base = `slot[${slotIdx}].persist`;
    if (!isPlainObject(persist)) {
        report.err(`must be an object`, base);
        return;
    }
    if ('min' in persist) {
        if (!isInt(persist.min)) report.err(`must be an integer (minutes)`, `${base}.min`);
        else if (persist.min < 0) report.err(`must be >= 0`, `${base}.min`);
    }
    if ('allowOverride' in persist) {
        if (!isInt(persist.allowOverride)) {
            report.err(`must be 0 or 1`, `${base}.allowOverride`);
        } else if (!isBoolInt(persist.allowOverride)) {
            report.err(`must be 0 (locked) or 1 (allow override)`, `${base}.allowOverride`);
        }
    }
    for (const k of Object.keys(persist)) {
        if (!KNOWN_PERSIST.has(k)) {
            report.warn(`unknown field (typo? known: ${[...KNOWN_PERSIST].join(', ')})`, `${base}.${k}`);
        }
    }
}

function validateCool(cool, slotIdx, report) {
    const base = `slot[${slotIdx}].cool`;
    if (!isPlainObject(cool)) {
        report.err(`must be an object`, base);
        return;
    }
    if ('min' in cool) {
        if (!isInt(cool.min)) report.err(`must be an integer (minutes)`, `${base}.min`);
        else if (cool.min < 0) report.err(`must be >= 0`, `${base}.min`);
    }
    for (const k of Object.keys(cool)) {
        if (!KNOWN_COOL.has(k)) {
            report.warn(`unknown field (typo? known: ${[...KNOWN_COOL].join(', ')})`, `${base}.${k}`);
        }
    }
}

function validatePulse(pulse, slotIdx, report) {
    const base = `slot[${slotIdx}].pulse`;
    if (!isPlainObject(pulse)) {
        report.err(`must be an object`, base);
        return;
    }
    if ('rate' in pulse) {
        if (!isNumber(pulse.rate)) report.err(`must be a number (Hz)`, `${base}.rate`);
        else if (pulse.rate < 0) report.err(`must be >= 0`, `${base}.rate`);
    }
    if ('depth' in pulse) {
        if (!isInt(pulse.depth)) report.err(`must be an integer (0..100)`, `${base}.depth`);
        else if (pulse.depth < 0 || pulse.depth > 100) report.err(`must be 0..100`, `${base}.depth`);
    }
    if ('pause' in pulse) {
        if (!isNumber(pulse.pause)) report.err(`must be a number (seconds)`, `${base}.pause`);
        else if (pulse.pause < 0) report.err(`must be >= 0`, `${base}.pause`);
    }
    if ('waveform' in pulse && !isString(pulse.waveform)) {
        report.err(`must be a string (waveform name, "" = built-in cosine)`, `${base}.waveform`);
    }
    for (const k of Object.keys(pulse)) {
        if (!KNOWN_PULSE.has(k)) {
            report.warn(`unknown field (typo? known: ${[...KNOWN_PULSE].join(', ')})`, `${base}.${k}`);
        }
    }
}

function validateLayer(layer, slotIdx, layerIdx, report) {
    const base = `slot[${slotIdx}].layer[${layerIdx}]`;
    if (!isPlainObject(layer)) {
        report.err(`must be an object`, base);
        return;
    }
    if ('tint' in layer && !isColorValue(layer.tint)) {
        report.err(`must be "#RRGGBB" or int 0..16777215`, `${base}.tint`);
    }
    if ('emissive' in layer && !isColorValue(layer.emissive)) {
        report.err(`must be "#RRGGBB" or int 0..16777215`, `${base}.emissive`);
    }
    if ('emissivemult' in layer) {
        if (!isNumber(layer.emissivemult)) report.err(`must be a number`, `${base}.emissivemult`);
        else if (layer.emissivemult < 0) report.warn(`negative values invert the emissive — usually unintended`, `${base}.emissivemult`);
    }
    if ('alpha' in layer) {
        if (!isInt(layer.alpha)) report.err(`must be an integer (0..100)`, `${base}.alpha`);
        else if (layer.alpha < 0 || layer.alpha > 100) report.err(`must be 0..100`, `${base}.alpha`);
    }
    for (const k of Object.keys(layer)) {
        if (!KNOWN_LAYER.has(k)) {
            report.warn(`unknown field (typo? known: ${[...KNOWN_LAYER].join(', ')})`, `${base}.${k}`);
        }
    }
}

function validateEffect(effect, slotIdx, fxIdx, report) {
    const base = `slot[${slotIdx}].effect[${fxIdx}]`;
    if (!isPlainObject(effect)) {
        report.err(`must be an object`, base);
        return;
    }
    // Legacy: `extras` was a v0.1.3 nested object for ramp/decay/volume etc.
    // v0.2.1 collapsed these into param1..5; the load path no longer reads
    // `extras`. Old presets still carry the block harmlessly.
    if ('extras' in effect) {
        report.warn(
            `legacy field — v0.2.1 collapsed extras into param1..param5; this block is ignored on load`,
            `${base}.extras`,
        );
    }
    if (!('key' in effect)) {
        report.err(`required field missing — must be "pluginid:effectid" (e.g. "mtf.base:damage.magicka")`, `${base}.key`);
    } else if (!isString(effect.key)) {
        report.err(`must be a string`, `${base}.key`);
    } else if (effect.key !== '') {
        // Format: pluginid:effectid. pluginid often has dots ("mtf.base"),
        // effectid often has dots too ("damage.magicka"). Strictly require
        // a single ":" separator with non-empty halves.
        const colon = effect.key.indexOf(':');
        if (colon < 0) {
            report.err(`must contain ":" separator — format is "pluginid:effectid"`, `${base}.key`);
        } else {
            const left = effect.key.slice(0, colon);
            const right = effect.key.slice(colon + 1);
            if (!left)  report.err(`pluginid (before ":") is empty`, `${base}.key`);
            if (!right) report.err(`effectid (after ":") is empty`, `${base}.key`);
            if (effect.key.indexOf(':', colon + 1) >= 0) {
                report.err(`contains more than one ":" — only one separator allowed`, `${base}.key`);
            }
        }
    }
    // v0.2.9: effect paramN dispatches on the catalog's per-param declaration:
    // slider params write/read int, menu params write/read a string id. The
    // loader picks based on pLoad.GetEffectParamMenuOptionCount(effectIdx, n)
    // — opaque to a preset-only validator, so accept either.
    for (let n = 1; n <= 5; n++) {
        const k = `param${n}`;
        if (k in effect && !isInt(effect[k]) && !isString(effect[k])) {
            report.err(`must be an integer (slider param) or string (menu param id)`, `${base}.${k}`);
        }
    }
    for (const k of Object.keys(effect)) {
        if (!KNOWN_EFFECT.has(k)) {
            report.warn(`unknown field (typo? known: ${[...KNOWN_EFFECT].join(', ')})`, `${base}.${k}`);
        }
    }
}

function validateSlot(slot, slotIdx, schemaVersion, report) {
    const base = `slot[${slotIdx}]`;
    if (!isPlainObject(slot)) {
        report.err(`must be an object`, base);
        return;
    }

    if ('cond' in slot) validateCond(slot.cond, slotIdx, report);
    if ('persist' in slot) validatePersist(slot.persist, slotIdx, report);
    if ('cool' in slot) validateCool(slot.cool, slotIdx, report);
    if ('pulse' in slot) validatePulse(slot.pulse, slotIdx, report);

    // v0.2.9: per-slot display name override. Empty string = use canonical
    // label (plugin's condition.label). LoadPreset reads it as a plain string.
    if ('name' in slot && !isString(slot.name)) {
        report.err(`must be a string (empty = use the plugin's canonical condition label)`, `${base}.name`);
    }

    // Legacy cooldown.min / cooldown.mode (schemas 4..7). LoadPreset ignores
    // these at schema 8, so flag as a warning the author may want to migrate.
    if ('cooldown' in slot) {
        if (schemaVersion >= 8) {
            report.warn(
                `legacy field — schema 8 reads persist.min / persist.allowOverride / cool.min instead; this block is ignored on load`,
                `${base}.cooldown`,
            );
        }
        if (!isPlainObject(slot.cooldown)) {
            report.err(`must be an object`, `${base}.cooldown`);
        } else {
            if ('min' in slot.cooldown && !isInt(slot.cooldown.min)) {
                report.err(`must be an integer`, `${base}.cooldown.min`);
            }
            if ('mode' in slot.cooldown && !isInt(slot.cooldown.mode)) {
                report.err(`must be an integer`, `${base}.cooldown.mode`);
            }
        }
    }

    if ('layer' in slot) {
        if (!Array.isArray(slot.layer)) {
            report.err(`must be an array (up to ${MAX_LAYERS_PER_SLOT} entries)`, `${base}.layer`);
        } else {
            if (slot.layer.length > MAX_LAYERS_PER_SLOT) {
                report.err(
                    `${slot.layer.length} entries — runtime caps at ${MAX_LAYERS_PER_SLOT}, extras are dropped on load`,
                    `${base}.layer`,
                );
            }
            slot.layer.forEach((l, i) => validateLayer(l, slotIdx, i, report));
        }
    }

    if ('effect' in slot) {
        if (!Array.isArray(slot.effect)) {
            report.err(`must be an array (up to ${MAX_EFFECTS_PER_SLOT} entries)`, `${base}.effect`);
        } else {
            if (slot.effect.length > MAX_EFFECTS_PER_SLOT) {
                report.err(
                    `${slot.effect.length} entries — runtime caps at ${MAX_EFFECTS_PER_SLOT}, extras are dropped on load`,
                    `${base}.effect`,
                );
            }
            slot.effect.forEach((e, i) => validateEffect(e, slotIdx, i, report));
        }
    }

    for (const k of Object.keys(slot)) {
        if (!KNOWN_SLOT.has(k)) {
            report.warn(`unknown field (typo? known: ${[...KNOWN_SLOT].join(', ')})`, `${base}.${k}`);
        }
    }
}

function validateFade(fade, report) {
    const base = `fadeondeath`;
    if (!isPlainObject(fade)) {
        report.err(`must be an object`, base);
        return;
    }
    if ('enabled' in fade) {
        if (!isInt(fade.enabled)) report.err(`must be 0 or 1`, `${base}.enabled`);
        else if (!isBoolInt(fade.enabled)) report.err(`must be 0 (off) or 1 (on)`, `${base}.enabled`);
    }
    if ('mode' in fade) {
        if (!isInt(fade.mode)) report.err(`must be an integer (0..2)`, `${base}.mode`);
        else if (fade.mode < 0 || fade.mode > 2) report.err(`must be 0..2`, `${base}.mode`);
    }
    if ('durationms' in fade) {
        if (!isInt(fade.durationms)) report.err(`must be an integer (milliseconds)`, `${base}.durationms`);
        else if (fade.durationms < 1) report.err(`must be >= 1 (0 falls back to default 2000)`, `${base}.durationms`);
    }
    for (const k of Object.keys(fade)) {
        if (!KNOWN_FADE.has(k)) {
            report.warn(`unknown field (typo? known: ${[...KNOWN_FADE].join(', ')})`, `${base}.${k}`);
        }
    }
}

// ── Top-level validator ─────────────────────────────────────────────────────
export function validatePreset(json) {
    const report = new Report();

    if (!isPlainObject(json)) {
        report.err(`root must be a JSON object — got ${Array.isArray(json) ? 'array' : typeof json}`);
        return report;
    }

    // displayname
    if (!('displayname' in json)) {
        report.err(`required field missing`, `displayname`);
    } else if (!isString(json.displayname)) {
        report.err(`must be a string`, `displayname`);
    } else if (json.displayname === '') {
        report.err(`must be non-empty`, `displayname`);
    }

    // schemaversion
    let schemaVersion = CURRENT_SCHEMA;
    if (!('schemaversion' in json)) {
        report.err(`required field missing — current is ${CURRENT_SCHEMA}`, `schemaversion`);
    } else if (!isInt(json.schemaversion)) {
        report.err(`must be an integer`, `schemaversion`);
    } else {
        schemaVersion = json.schemaversion;
        if (schemaVersion < MIN_SCHEMA) {
            report.err(`${schemaVersion} is below MIN_SCHEMA ${MIN_SCHEMA} — LoadPreset refuses to load this`, `schemaversion`);
        } else if (schemaVersion < CURRENT_SCHEMA) {
            report.warn(`${schemaVersion} is below current ${CURRENT_SCHEMA} — loads, but new fields fall back to defaults`, `schemaversion`);
        } else if (schemaVersion > CURRENT_SCHEMA) {
            report.warn(`${schemaVersion} is above current ${CURRENT_SCHEMA} — likely from a newer MTF version; this validator only knows up to ${CURRENT_SCHEMA}`, `schemaversion`);
        }
    }

    // valid
    if (!('valid' in json)) {
        report.warn(`missing — in-game ListPresets() filters on valid==1, so absent reads as 0 (deleted)`, `valid`);
    } else if (!isInt(json.valid)) {
        report.err(`must be 0 or 1`, `valid`);
    } else if (json.valid === 0) {
        report.warn(`set to 0 — in-game MCM treats this as a deleted preset and hides it`, `valid`);
    } else if (json.valid !== 1) {
        report.err(`must be 0 or 1`, `valid`);
    }

    // transition
    if ('transition' in json) {
        if (!isPlainObject(json.transition)) {
            report.err(`must be an object`, `transition`);
        } else if ('duration' in json.transition) {
            if (!isNumber(json.transition.duration)) {
                report.err(`must be a number (seconds, 0 disables fading)`, `transition.duration`);
            } else if (json.transition.duration < 0) {
                report.err(`must be >= 0`, `transition.duration`);
            }
            for (const k of Object.keys(json.transition)) {
                if (k !== 'duration') {
                    report.warn(`unknown field (only "duration" is read)`, `transition.${k}`);
                }
            }
        }
    }

    // fadeondeath
    if ('fadeondeath' in json) validateFade(json.fadeondeath, report);

    // slot
    if (!('slot' in json)) {
        report.err(`required field missing — must be an array of exactly ${SLOT_COUNT} slot objects`, `slot`);
    } else if (!Array.isArray(json.slot)) {
        report.err(`must be an array`, `slot`);
    } else {
        // The in-game LoadPreset hard-loops `while s < 8`: < 8 leaves the
        // tail slots uninitialized (silently default to empty + 0, which is
        // usually but not always benign), > 8 silently ignores the extras
        // and the next SavePreset overwrites the file back to exactly 8.
        if (json.slot.length < SLOT_COUNT) {
            report.err(
                `${json.slot.length} entries — must have exactly ${SLOT_COUNT} (slot 0 is Default, 1..7 are conditional); missing slots default to empty on load`,
                `slot`,
            );
        } else if (json.slot.length > SLOT_COUNT) {
            report.warn(
                `${json.slot.length} entries — in-game loader only reads slots 0..${SLOT_COUNT - 1}; extras are silently ignored and the next SavePreset overwrites the file to exactly ${SLOT_COUNT}`,
                `slot`,
            );
        }
        // Validate every slot that's present so authors see all issues.
        json.slot.forEach((s, i) => validateSlot(s, i, schemaVersion, report));
    }

    // Unknown top-level keys
    for (const k of Object.keys(json)) {
        if (!KNOWN_TOP.has(k)) {
            report.warn(`unknown top-level field (typo?)`, k);
        }
    }

    return report;
}

// ── UI wiring ───────────────────────────────────────────────────────────────
const dropZone     = document.getElementById('dropZone');
const fileInput    = document.getElementById('fileInput');
const jsonInput    = document.getElementById('jsonInput');
const validateBtn  = document.getElementById('validateBtn');
const clearBtn     = document.getElementById('clearBtn');
const formatBtn    = document.getElementById('formatBtn');
const reportCard   = document.getElementById('reportCard');
const reportContent= document.getElementById('reportContent');
const actionCard   = document.getElementById('actionCard');
const actionName   = document.getElementById('actionName');
const downloadBtn  = document.getElementById('downloadBtn');

let lastValidJson = null;
let lastDisplayName = '';

function setReport(html) {
    reportContent.innerHTML = html;
    reportCard.hidden = false;
}

function clearReport() {
    reportContent.innerHTML = '';
    reportCard.hidden = true;
    actionCard.hidden = true;
    lastValidJson = null;
    lastDisplayName = '';
    downloadBtn.disabled = true;
}

function escapeHtml(s) {
    return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function renderReport(report, json) {
    const e = report.errors;
    const w = report.warnings;
    let summaryClass, summaryHtml;
    if (e === 0 && w === 0) {
        summaryClass = 'ok';
        summaryHtml = `<strong>All checks passed.</strong> Schema is clean; the in-game loader will accept this preset as-is.`;
    } else if (e === 0) {
        summaryClass = 'warn';
        summaryHtml = `<strong>Valid with ${w} warning${w === 1 ? '' : 's'}.</strong> The in-game loader will accept it, but you should review the notes below.`;
    } else {
        summaryClass = 'err';
        summaryHtml = `<strong>${e} error${e === 1 ? '' : 's'}${w ? `, ${w} warning${w === 1 ? '' : 's'}` : ''}.</strong> Fix the errors below before installing — the in-game loader will reject this or silently load wrong values.`;
    }

    let rowsHtml = '';
    if (report.findings.length === 0) {
        rowsHtml = `<div class="row"><span class="icon ok">&check;</span><span>No issues found.</span></div>`;
    } else {
        // Sort: errors first, then warnings, then info; preserve in-group order.
        const order = { err: 0, warn: 1, info: 2 };
        const sorted = [...report.findings].sort((a, b) => order[a.level] - order[b.level]);
        for (const f of sorted) {
            const icon = f.level === 'err' ? '&times;' : f.level === 'warn' ? '!' : 'i';
            const path = f.path ? `<span class="breadcrumb">${escapeHtml(f.path)}</span>` : '';
            rowsHtml += `<div class="row"><span class="icon ${f.level}">${icon}</span><span>${escapeHtml(f.msg)}${path}</span></div>`;
        }
    }

    setReport(`<div class="summary ${summaryClass}">${summaryHtml}</div>${rowsHtml}`);

    if (report.ok && isPlainObject(json)) {
        lastValidJson = json;
        lastDisplayName = isString(json.displayname) ? json.displayname : '';
        const sanitized = sanitizePresetName(lastDisplayName);
        if (sanitized === '') {
            // Defensive: shouldn't happen because displayname is required + non-empty.
            actionCard.hidden = true;
            return;
        }
        actionCard.hidden = false;
        actionName.innerHTML = `Will install as <code>${escapeHtml(sanitized)}.json</code>` +
            (sanitized !== lastDisplayName ? ` <span style="color:var(--fg-muted)">(sanitized from <code>${escapeHtml(lastDisplayName)}</code>)</span>` : '');
        downloadBtn.disabled = false;
    } else {
        actionCard.hidden = true;
        downloadBtn.disabled = true;
    }
}

function runValidation() {
    const text = jsonInput.value.trim();
    if (!text) {
        setReport(`<div class="summary err"><strong>Empty input.</strong> Drop a <code>.json</code> file or paste one above.</div>`);
        downloadBtn.disabled = true;
        actionCard.hidden = true;
        return;
    }

    let json;
    try {
        json = JSON.parse(text);
    } catch (err) {
        const m = err.message || String(err);
        setReport(`<div class="summary err"><strong>JSON parse error.</strong></div>` +
            `<div class="row"><span class="icon err">&times;</span><span>${escapeHtml(m)}</span></div>`);
        downloadBtn.disabled = true;
        actionCard.hidden = true;
        return;
    }

    const report = validatePreset(json);
    renderReport(report, json);
}

async function downloadZip() {
    if (!lastValidJson) return;
    const name = sanitizePresetName(lastDisplayName);
    if (!name) return;

    // Re-serialize from the parsed object so the file inside the ZIP is
    // normalized JSON (no BOM, consistent indentation). The in-game JsonUtil
    // doesn't care, but it makes diffs and re-uploads predictable.
    const body = JSON.stringify(lastValidJson, null, '\t') + '\n';

    const zip = new JSZip();
    zip.file(`SKSE/Plugins/StorageUtilData/MagicTattoosFramework/presets/${name}.json`, body);
    const blob = await zip.generateAsync({ type: 'blob', compression: 'DEFLATE' });

    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `MTF-Preset-${name}.zip`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// ── Event wiring ────────────────────────────────────────────────────────────
validateBtn.addEventListener('click', runValidation);
downloadBtn.addEventListener('click', downloadZip);

clearBtn.addEventListener('click', () => {
    jsonInput.value = '';
    clearReport();
    jsonInput.focus();
});

formatBtn.addEventListener('click', () => {
    const text = jsonInput.value.trim();
    if (!text) return;
    try {
        const j = JSON.parse(text);
        jsonInput.value = JSON.stringify(j, null, '\t') + '\n';
    } catch (err) {
        // Don't reformat invalid JSON — let validate report the parse error.
        runValidation();
    }
});

// Ctrl/Cmd+Enter inside the textarea triggers validation.
jsonInput.addEventListener('keydown', (ev) => {
    if ((ev.ctrlKey || ev.metaKey) && ev.key === 'Enter') {
        ev.preventDefault();
        runValidation();
    }
});

// File drop / browse
dropZone.addEventListener('click', () => fileInput.click());
dropZone.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter' || ev.key === ' ') {
        ev.preventDefault();
        fileInput.click();
    }
});

['dragenter', 'dragover'].forEach((evt) => {
    dropZone.addEventListener(evt, (ev) => {
        ev.preventDefault();
        ev.stopPropagation();
        dropZone.classList.add('drag-over');
    });
});
['dragleave', 'drop'].forEach((evt) => {
    dropZone.addEventListener(evt, (ev) => {
        ev.preventDefault();
        ev.stopPropagation();
        dropZone.classList.remove('drag-over');
    });
});

dropZone.addEventListener('drop', (ev) => {
    const f = ev.dataTransfer && ev.dataTransfer.files && ev.dataTransfer.files[0];
    if (f) loadFile(f);
});

fileInput.addEventListener('change', () => {
    const f = fileInput.files && fileInput.files[0];
    if (f) loadFile(f);
});

async function loadFile(file) {
    try {
        const text = await file.text();
        jsonInput.value = text;
        runValidation();
    } catch (err) {
        setReport(`<div class="summary err"><strong>Could not read file.</strong></div>` +
            `<div class="row"><span class="icon err">&times;</span><span>${escapeHtml(err.message || String(err))}</span></div>`);
    }
}
