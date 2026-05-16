// Generates the two seed visual-catalog JSONs for LewdMarksEffects.
//
// Each catalog has 96 entries (001..096). Every entry has two layers:
//   layer 0: base mark texture (no emissive multiplier override)
//   layer 1: glow texture (emissiveMult = 2.0 — keeps glow brighter than the
//            base mark when the user picks a single shared emissive value)
//
// Output paths (project tree — copy to MO2 mod folder on deploy):
//   data/SKSE/Plugins/StorageUtilData/LewdMarksEffects/visuals/
//       lme.racemenu-lewdmarks.json
//       lme.slavetats-lewdmarks.json
//
// Usage:
//   node F:/stuff/LewdMarksEffects/tools/gen_visual_catalogs.js

const fs = require('fs');
const path = require('path');

const COUNT = 96;
const OUT_DIR = path.resolve(
    'F:/stuff/LewdMarksEffects/data/SKSE/Plugins/StorageUtilData/LewdMarksEffects/visuals'
);

function pad3(n) {
    return n < 10 ? '00' + n : n < 100 ? '0' + n : '' + n;
}

function buildCatalog(packId, label, normalRoot, glowRoot) {
    const entries = [];
    for (let i = 1; i <= COUNT; i++) {
        const id = pad3(i);
        entries.push({
            id,
            label: 'Mark ' + id,
            layers: [
                { texture: normalRoot + id + '.dds' },
                { texture: glowRoot   + id + '.dds', emissiveMult: 2.0 }
            ]
        });
    }
    return {
        schemaVersion: 2,
        packId,
        label,
        area: 'Body',
        entries
    };
}

function writeJson(file, obj) {
    fs.writeFileSync(file, JSON.stringify(obj, null, 2));
    console.log('wrote', file, '(' + obj.entries.length + ' entries)');
}

(function main() {
    fs.mkdirSync(OUT_DIR, { recursive: true });

    // ASCII-only labels — PapyrusUtil's JSON parser silently fails the
    // whole file on multi-byte UTF-8 chars (em-dash, etc.).
    const rm = buildCatalog(
        'lme.racemenu-lewdmarks',
        'RaceMenu Overlays - LewdMarks',
        'actors\\character\\overlays\\lewdmarks\\',
        'actors\\character\\overlays\\lewdmarks-glow\\'
    );
    const st = buildCatalog(
        'lme.slavetats-lewdmarks',
        'SlaveTats - LewdMarks',
        'actors\\character\\slavetats\\LewdMarks\\',
        'actors\\character\\slavetats\\LewdMarks-glow\\'
    );

    writeJson(path.join(OUT_DIR, 'lme.racemenu-lewdmarks.json'), rm);
    writeJson(path.join(OUT_DIR, 'lme.slavetats-lewdmarks.json'), st);
})();
