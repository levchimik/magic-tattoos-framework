/* MTF Content Pack Builder — pure-browser archive→catalog converter.
 *
 * Pipeline:
 *   1. User picks/drops a Skyrim mod archive (zip, 7z, rar, tar, ...)
 *   2. libarchive.js opens it and LISTS entries (no actual extraction —
 *      we only need filenames, not file contents)
 *   3. We auto-derive `packId` and display label from the archive's
 *      filename, populating the form (user can edit)
 *   4. We walk the entry list, find .dds files under textures/
 *      (auto-detecting wrapper directories like ZAO's), build the MTF
 *      catalog JSON
 *   5. JSZip composes an output ZIP containing ONLY the catalog at
 *      SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/<packid>.json
 *      Textures themselves are NOT bundled — the user already has the
 *      source mod installed; content packs are pointer-only catalogs by
 *      convention (see content-packs/ in the framework repo)
 *   6. Trigger download — Blob + <a download>, no upload anywhere
 *
 * libarchive.js (WASM port of libarchive) reads any format the C library
 * supports. JSZip writes the output ZIP. Mod managers want ZIP, so we
 * always emit one (even though the payload is a single JSON file —
 * the ZIP wrapper makes MO2's "Install from archive" work without
 * manual extraction).
 *
 * This file is loaded as an ES module (<script type="module">) so it can
 * `import` libarchive.js. JSZip is a classic-script global pulled in via
 * a regular <script src=...> tag before this one.
 */

import { Archive } from './vendor/libarchive/libarchive.js';

// ─── DOM refs ───────────────────────────────────────────────────────────
const els = {
    packId:        document.getElementById('packId'),
    packLabel:     document.getElementById('packLabel'),
    dropZone:      document.getElementById('dropZone'),
    fileInput:     document.getElementById('fileInput'),
    dropMeta:      document.getElementById('dropMeta'),
    statusCard:    document.getElementById('statusCard'),
    statusContent: document.getElementById('statusContent'),
    downloadBtn:   document.getElementById('downloadBtn'),
};

// ─── Area inference helpers ─────────────────────────────────────────────

// RaceMenu API function-name → area mapping. Both `*Paint` and `*Overlay`
// variants are recognized. `Warpaint` is treated as face (RaceMenu's
// warpaint overlays sit on the face mesh).
const FN_AREA = {
    addbodypaint:    'Body',  addbodyoverlay:    'Body',
    addfacepaint:    'Face',  addfaceoverlay:    'Face',
    addheadpaint:    'Face',  addheadoverlay:    'Face',
    addwarpaint:     'Face',  addwarpaintoverlay:'Face',
    addhandpaint:    'Hands', addhandoverlay:    'Hands',
    addhandspaint:   'Hands', addhandsoverlay:   'Hands',
    addnailpaint:    'Hands', addnailoverlay:    'Hands',
    addnailspaint:   'Hands', addnailsoverlay:   'Hands',
    addfeetpaint:    'Feet',  addfeetoverlay:    'Feet',
    addfootpaint:    'Feet',  addfootoverlay:    'Feet',
};

// Per-DDS-path keyword classification — fallback when the .psc didn't
// register the texture or no .psc is present. Returns one of
// "Body"/"Face"/"Hands"/"Feet"/null.
function classifyByPath(p) {
    const lower = p.toLowerCase();
    if (lower.includes('head') || lower.includes('face')) return 'Face';
    if (lower.includes('nail') || lower.includes('polish') || lower.includes('hand')) return 'Hands';
    if (lower.includes('feet') || lower.includes('foot')) return 'Feet';
    return null;
}

// ─── State ──────────────────────────────────────────────────────────────
// Holds the parsed entry list + derived catalog between drop and download.
// We never hold extracted file CONTENT — only path metadata, since the
// output ZIP doesn't carry the textures themselves.
let state = null;

// ─── Utilities ──────────────────────────────────────────────────────────

/**
 * Detect the "textures root" inside a list of paths.
 * Returns the path PREFIX that should be stripped from each entry so
 * the remainder is what Skyrim looks up under Data/textures/.
 * Returns null if no recognizable layout was found.
 *
 * Tolerates wrapper directories — Nexus mods are very often packed as
 * `<ModName>/Data/Textures/...` or `<ModName>/textures/...` so that
 * extraction creates a named folder. We scan for the first dds path
 * that contains a `/textures/` segment and return everything up to and
 * including that segment, preferring a `/Data/textures/` match
 * (longer / more specific) over a bare `/textures/` match.
 *
 * All matching is case-insensitive (Bethesda paths mix `Textures` and
 * `textures` freely).
 *
 * Recognized layouts (examples):
 *   "textures/foo.dds"                               → "textures/"
 *   "Data/textures/foo.dds"                          → "Data/textures/"
 *   "ZAO Pack/Data/Textures/zao/foo.dds"             → "ZAO Pack/Data/Textures/"
 *   "MyMod 1.0/textures/foo.dds"                     → "MyMod 1.0/textures/"
 */
function detectTexturesRoot(entryPaths) {
    const ddsPaths = entryPaths.filter(p => p.toLowerCase().endsWith('.dds'));
    if (ddsPaths.length === 0) return null;

    // Pass 1: prefer 'data/textures/' anywhere in the path (most specific).
    for (const p of ddsPaths) {
        const lower = p.toLowerCase();
        if (lower.startsWith('data/textures/')) {
            return p.substring(0, 'data/textures/'.length);
        }
        const idx = lower.indexOf('/data/textures/');
        if (idx >= 0) {
            return p.substring(0, idx + '/data/textures/'.length);
        }
    }
    // Pass 2: fall back to bare 'textures/' anywhere in the path.
    for (const p of ddsPaths) {
        const lower = p.toLowerCase();
        if (lower.startsWith('textures/')) {
            return p.substring(0, 'textures/'.length);
        }
        const idx = lower.indexOf('/textures/');
        if (idx >= 0) {
            return p.substring(0, idx + '/textures/'.length);
        }
    }
    return null;
}

/**
 * Derive a sensible default display label + packId from the dropped
 * archive's filename. Nexus filenames look like
 *   "<HumanName> <version> <variant>-<NexusID>-<verSegments>-<unixTime>.<ext>"
 * e.g. "ZAO Active Overlays 0.3 SE-39407-0-31-1612931382.7z"
 * The reliable signal is "everything before the first digit" — once
 * digits appear it's all version / Nexus metadata. We trim trailing
 * junk (spaces, dashes, version markers like a lone 'v') and call that
 * the display label. The packId is `mtf.` + a lowercase dash-slug.
 *
 * Examples:
 *   "ZAO Active Overlays 0.3 SE-39407-..."  → "ZAO Active Overlays"  / mtf.zao-active-overlays
 *   "Beeing Female NG 3.4.2-168434-..."     → "Beeing Female NG"     / mtf.beeing-female-ng
 *   "Fertility Mode Reloaded v 1.0.3-..."   → "Fertility Mode Reloaded" / mtf.fertility-mode-reloaded
 *   "RaceMenu Animated Overlays SE-37275-…" → "RaceMenu Animated Overlays SE" / mtf.racemenu-animated-overlays-se
 *   "LewdMarksAroused-83794-..."            → "LewdMarksAroused"      / mtf.lewdmarksaroused
 *   "MyMod.7z"                              → "MyMod"                 / mtf.mymod
 */
function deriveDefaults(filename) {
    // Strip recognized archive extensions (handle compound .tar.gz first).
    let stem = filename.replace(/\.(tar\.gz|tar\.xz|tar\.bz2)$/i, '');
    stem = stem.replace(/\.(zip|7z|rar|tar|tgz|iso)$/i, '');

    // Take everything before the first digit. If the filename starts with
    // a digit, fall back to the whole stem.
    const digitIdx = stem.search(/\d/);
    let label = digitIdx > 0 ? stem.substring(0, digitIdx) : stem;

    // Trim trailing whitespace, hyphens, underscores.
    label = label.replace(/[\s_-]+$/, '');
    // Drop a trailing lone-letter version marker ("v", "V") with its space.
    label = label.replace(/\s+[vV]$/, '');
    label = label.trim();

    // Fallback if everything got stripped (e.g. all-digits filename).
    if (!label) label = stem;

    // Build slug: lowercase, runs of non-alphanumeric → single hyphen.
    const slug = label.toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');
    const packId = `mtf.${slug || 'pack'}`;

    return { label, packId };
}

/**
 * Sanitize an entry id derived from a filename. Keep visible case but
 * collapse whitespace to underscores (some Papyrus paths get cranky
 * about spaces in StorageUtil keys).
 */
function makeEntryId(stem, taken) {
    let id = stem.replace(/\s+/g, '_');
    if (!taken.has(id)) {
        taken.add(id);
        return id;
    }
    // Collision: append -2, -3, etc.
    let n = 2;
    while (taken.has(`${id}-${n}`)) n++;
    const out = `${id}-${n}`;
    taken.add(out);
    return out;
}

/**
 * Filename stem helper — strips path AND extension.
 * "actors/character/overlays/foo/001 mark.dds" → "001 mark"
 */
function stemOf(path) {
    const file = path.split('/').pop();
    const dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
}

/**
 * Slash-direction conversion. Skyrim's StorageUtil JSON tradition is
 * backslashes (because Bethesda's BSAs index that way). All shipping
 * MTF packs use backslashes, so we match that convention.
 */
function toSkyrimPath(forward) {
    return forward.replace(/\//g, '\\');
}

/**
 * Normalize a texture path for cross-source comparison: lowercase,
 * backslashes → forward, strip leading slashes / whitespace. Used as
 * the key for the .psc label lookup map.
 */
function normalizeKey(path) {
    return path.toLowerCase().replace(/\\/g, '/').replace(/^[\/\s]+/, '');
}

/**
 * Parse a Papyrus .psc source string for function calls that register
 * (name → texture-path) pairs AND identify which body area each
 * registration covers from the function name. RaceMenu has separate
 * APIs per area:
 *
 *   AddBodyPaint("name", "path.dds")   → Body
 *   AddFacePaint(...)  / AddWarpaint(...)               → Face
 *   AddHandPaint(...)  / AddNailPaint(...)              → Hands
 *   AddFeetPaint(...)  / AddFootPaint(...)              → Feet
 *
 * The regex catches any 2-arg function call whose second string ends
 * in `.dds`; the FN_AREA map decides the area (null → unknown, gets
 * path-keyword fallback at lookup time).
 *
 * Returns Map<normalizedKey, { name, area }>.
 *
 * Papyrus string literals double their backslashes (`\\` in source =
 * `\` in memory); normalizeKey collapses both to forward slashes.
 */
function parseScriptLabels(pscText) {
    const labels = new Map();
    const re = /\b(\w+)\s*\(\s*"([^"]+)"\s*,\s*"([^"]+\.dds)"\s*\)/gi;
    let m;
    while ((m = re.exec(pscText)) !== null) {
        const fnLower = m[1].toLowerCase();
        const area = FN_AREA[fnLower] || null;
        const name = m[2];
        const rawPath = m[3].replace(/\\\\/g, '\\');
        labels.set(normalizeKey(rawPath), { name, area });
    }
    return labels;
}

/**
 * Given the labels map (keys are normalized paths, values are
 * {name, area} objects) and a texture's relative-to-textures-root
 * path, find the best matching entry.
 *
 * Prefers exact match; falls back to suffix match (handles packs
 * whose .psc uses a slightly different leading directory than the
 * archive layout).
 */
function lookupLabel(labels, relativePath) {
    if (labels.size === 0) return null;
    const key = normalizeKey(relativePath);
    if (labels.has(key)) return labels.get(key);
    for (const [k, v] of labels) {
        if (key.endsWith(k) || k.endsWith(key)) return v;
    }
    return null;
}

/**
 * Per-area packId / label decoration. Body uses the bare base form;
 * other areas get an area-suffix on the packId and an "(Area)" tag
 * appended to the display label so multi-area packs stay
 * distinguishable in the MCM.
 */
function decorateForArea(basePackId, baseLabel, area) {
    if (area === 'Body') {
        return { packId: basePackId, label: baseLabel };
    }
    const suffix = area.toLowerCase(); // face / hands / feet
    return {
        packId: `${basePackId}-${suffix}`,
        label:  `${baseLabel} (${area})`,
    };
}

// ─── Status panel ───────────────────────────────────────────────────────

function clearStatus() {
    els.statusCard.hidden = true;
    els.statusContent.innerHTML = '';
}

function showSummary(html) {
    els.statusCard.hidden = false;
    const div = document.createElement('div');
    div.className = 'summary';
    div.innerHTML = html;
    els.statusContent.appendChild(div);
}

function addStatus(kind, text) {
    const row = document.createElement('div');
    row.className = 'status-row';
    const icon = document.createElement('span');
    icon.className = `status-icon ${kind}`;
    icon.textContent =
        kind === 'ok'   ? '✓' :
        kind === 'warn' ? '⚠' :
        kind === 'err'  ? '✗' :
                          'ⓘ';
    const msg = document.createElement('span');
    msg.innerHTML = text;
    row.appendChild(icon);
    row.appendChild(msg);
    els.statusContent.appendChild(row);
}

// ─── Drop-zone wiring ───────────────────────────────────────────────────

els.dropZone.addEventListener('click', () => els.fileInput.click());
els.dropZone.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        els.fileInput.click();
    }
});
els.dropZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    els.dropZone.classList.add('drag-over');
});
els.dropZone.addEventListener('dragleave', () => {
    els.dropZone.classList.remove('drag-over');
});
els.dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    els.dropZone.classList.remove('drag-over');
    const file = e.dataTransfer.files[0];
    if (file) handleArchive(file);
});
els.fileInput.addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (file) handleArchive(file);
});

// ─── Form change re-renders catalog (cheap, no re-parse) ────────────────
[els.packId, els.packLabel].forEach(el => {
    el.addEventListener('input', () => {
        if (state) rebuildCatalog();
    });
});

// ─── Main pipeline ──────────────────────────────────────────────────────

async function handleArchive(file) {
    clearStatus();
    state = null;
    els.downloadBtn.disabled = true;
    els.dropMeta.hidden = false;
    els.dropMeta.innerHTML =
        `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)}) &mdash; opening&hellip;`;

    // Auto-fill the form with defaults derived from the filename. Users
    // can still edit any of these before downloading.
    const { label, packId } = deriveDefaults(file.name);
    els.packId.value = packId;
    els.packLabel.value = label;

    // Open the archive. First call also triggers the wasm download
    // (libarchive lazy-loads it on first Archive.open) — that's why the
    // very first drop in a session is a touch slower than subsequent
    // drops, even for tiny ZIPs.
    let archive;
    try {
        archive = await Archive.open(file);
    } catch (err) {
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> &mdash; failed to open.`;
        showSummary(
            `<strong>Couldn't read archive.</strong> ` +
            `${escapeHtml(err.message || String(err))} &mdash; ` +
            `supported formats: zip, 7z, rar, tar, tar.gz / xz / bz2, iso.`
        );
        return;
    }

    // List entries WITHOUT extracting contents — getFilesArray returns
    // metadata only (compressed-file refs). We never call extract on
    // them because the output ZIP doesn't carry texture bytes; only the
    // filenames + sizes are needed to build the catalog.
    let entries;
    try {
        entries = await archive.getFilesArray();
    } catch (err) {
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> &mdash; listing failed.`;
        showSummary(
            `<strong>Couldn't list archive contents.</strong> ${escapeHtml(err.message || String(err))} ` +
            `&mdash; the archive may be password-protected or corrupted.`
        );
        return;
    }

    if (entries.length === 0) {
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)})`;
        showSummary(`<strong>Archive is empty.</strong>`);
        return;
    }

    // libarchive returns [{file: CompressedFile, path: "dir/"}] where
    // `path` is the directory (with trailing slash, empty string for
    // root) and `file.name` is the basename.
    const allPaths = entries.map(e => e.path + e.file.name);

    // Optional: parse any .psc files for human-readable entry labels.
    // SlaveTats / RaceMenu overlay packs ship a Papyrus script that
    // registers each texture with a curator-chosen name; using those
    // gives much better MCM dropdowns than the bare filename stem.
    // We extract each .psc via extractSingleFile (worker stays alive
    // until we explicitly close it) and merge all parsed labels.
    // We also keep the concatenated .psc text around for detectArea() —
    // RaceMenu's function-name choice (AddBodyPaint vs AddFacePaint
    // vs AddHandPaint vs AddFeetPaint) is the strongest area signal.
    const pscEntries = entries.filter(e => (e.path + e.file.name).toLowerCase().endsWith('.psc'));
    let labels = new Map();
    let pscParsed = null; // { paths: [...], count: N }
    let pscTextAll = '';
    if (pscEntries.length > 0) {
        const pscPaths = pscEntries.map(e => e.path + e.file.name);
        for (const pscPath of pscPaths) {
            try {
                const pscFile = await archive.extractSingleFile(pscPath);
                const text = await pscFile.text();
                pscTextAll += '\n' + text;
                const oneLabels = parseScriptLabels(text);
                for (const [k, v] of oneLabels) labels.set(k, v);
            } catch (err) {
                // Non-fatal: just skip this .psc, fall back to stems for its textures.
                console.warn(`Failed to parse ${pscPath}:`, err);
            }
        }
        pscParsed = { paths: pscPaths, count: labels.size };
    }

    // Close the archive worker — we have all the metadata + .psc text we need.
    try { await archive.close(); } catch (e) { /* best-effort */ }

    const root = detectTexturesRoot(allPaths);
    if (!root) {
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)})`;
        showSummary(
            `<strong>No <code>textures/</code> root found.</strong> ` +
            `The archive needs to look like a Skyrim mod download &mdash; with ` +
            `<code>textures/&hellip;/*.dds</code> at the root (or <code>Data/textures/&hellip;</code> ` +
            `or under a single wrapper directory like <code>MyMod/Data/Textures/&hellip;</code>).`
        );
        return;
    }

    // Categorize: DDS under textures/ vs DDS outside (excluded) vs non-DDS.
    const ddsEntries = []; // { fullPath, relative, stem }
    const extraneousDDS = [];
    for (const p of allPaths) {
        const lower = p.toLowerCase();
        if (!lower.endsWith('.dds')) continue;
        if (lower.startsWith(root.toLowerCase())) {
            ddsEntries.push({
                fullPath: p,
                relative: p.substring(root.length),
                stem:     stemOf(p),
            });
        } else {
            extraneousDDS.push(p);
        }
    }

    if (ddsEntries.length === 0) {
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)})`;
        showSummary(
            `<strong>No <code>.dds</code> files found</strong> under <code>${escapeHtml(root)}</code>. ` +
            `Did you drop the right archive?`
        );
        return;
    }

    state = {
        file:           file,
        root:           root,
        ddsEntries:     ddsEntries,
        extraneousDDS:  extraneousDDS,
        labels:         labels,
        pscParsed:      pscParsed,
        // Filled by rebuildCatalog: one entry per non-empty area group.
        catalogs:       null,
    };

    els.dropMeta.innerHTML =
        `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)}) &mdash; ` +
        `${ddsEntries.length} <code>.dds</code> file${ddsEntries.length === 1 ? '' : 's'} found under ` +
        `<code>${escapeHtml(root)}</code>.`;

    rebuildCatalog();
}

/**
 * Build the catalog JSON from current form state + parsed ddsEntries.
 * Re-runs on every form-field change; cheap because we cached the
 * filename list at drop time.
 */
function rebuildCatalog() {
    if (!state) return;

    const basePackId = els.packId.value.trim();
    const baseLabel  = els.packLabel.value.trim();
    const idOk = /^mtf\.[a-z0-9][a-z0-9._-]*$/.test(basePackId);

    if (!idOk) {
        els.statusCard.hidden = false;
        els.statusContent.innerHTML = '';
        showSummary(
            `<strong>Pack ID looks off.</strong> Expected the form ` +
            `<code>mtf.&lt;name&gt;</code> &mdash; lowercase, dots / dashes / underscores OK.`
        );
        state.catalogs = null;
        els.downloadBtn.disabled = true;
        return;
    }
    if (!baseLabel) {
        els.statusCard.hidden = false;
        els.statusContent.innerHTML = '';
        showSummary(`<strong>Display label is required.</strong>`);
        state.catalogs = null;
        els.downloadBtn.disabled = true;
        return;
    }

    // ─── Per-DDS resolution: label + area ───────────────────────────────
    // For each .dds we resolve:
    //   pscMatch  — the {name, area} object the .psc registered (or null)
    //   area      — pscMatch.area || classifyByPath || 'Body'
    //   label     — pscMatch.name || filename stem
    const ddsWithMeta = state.ddsEntries.map(d => {
        const pscMatch = lookupLabel(state.labels, d.relative);
        const area = (pscMatch && pscMatch.area)
            || classifyByPath(d.relative)
            || 'Body';
        const label = (pscMatch && pscMatch.name) || d.stem;
        return { ...d, pscMatch, area, label };
    });

    // ─── .psc curation filter ───────────────────────────────────────────
    // When a .psc is present, treat it as the author's curation: only
    // catalog .dds files the .psc explicitly registered. Safety valve:
    // if ZERO matches (paths misaligned), fall back to catalogging
    // everything.
    let sourceEntries = ddsWithMeta;
    let skippedUnregistered = 0;
    if (state.labels.size > 0) {
        const matched = ddsWithMeta.filter(d => d.pscMatch !== null);
        if (matched.length > 0) {
            skippedUnregistered = ddsWithMeta.length - matched.length;
            sourceEntries = matched;
        }
    }

    // ─── Group by area ──────────────────────────────────────────────────
    const groups = { Body: [], Face: [], Hands: [], Feet: [] };
    for (const d of sourceEntries) {
        groups[d.area].push(d);
    }

    // ─── Build one catalog per non-empty group ──────────────────────────
    const catalogs = [];
    for (const area of ['Body', 'Face', 'Hands', 'Feet']) {
        const groupEntries = groups[area];
        if (groupEntries.length === 0) continue;
        const { packId, label } = decorateForArea(basePackId, baseLabel, area);
        const takenIds = new Set();
        catalogs.push({
            schemaVersion: 3,
            packId:        packId,
            label:         label,
            area:          area,
            entries:       groupEntries.map(d => ({
                id:    makeEntryId(d.label, takenIds),
                label: d.label,
                layers: [{ texture: toSkyrimPath(d.relative) }],
            })),
        });
    }
    state.catalogs            = catalogs;
    state.skippedUnregistered = skippedUnregistered;
    state.labeledFromPsc      = sourceEntries.filter(d => d.pscMatch).length;

    // ─── Render status panel ────────────────────────────────────────────
    els.statusCard.hidden = false;
    els.statusContent.innerHTML = '';

    const totalEntries = catalogs.reduce((n, c) => n + c.entries.length, 0);
    const areaBreakdown = catalogs
        .map(c => `<strong>${c.entries.length}</strong> ${c.area}`)
        .join(', ');
    showSummary(
        `Ready to package <strong>${escapeHtml(basePackId)}</strong> &mdash; ` +
        `${totalEntries} entries across ${catalogs.length} catalog${catalogs.length === 1 ? '' : 's'} ` +
        `(${areaBreakdown}).`
    );

    addStatus('ok',
        `Texture root detected: <code>${escapeHtml(state.root)}</code>.`
    );

    // Per-catalog summary rows — one per output JSON.
    for (const cat of catalogs) {
        const fileName = `${cat.packId}.json`;
        addStatus('ok',
            `<strong>${escapeHtml(cat.label)}</strong> ` +
            `(${cat.entries.length} entries, area: ${cat.area}) &rarr; ` +
            `<code>${escapeHtml(fileName)}</code>`
        );
    }

    addStatus('info',
        `Output is JSON-only &mdash; catalog${catalogs.length === 1 ? '' : 's'} point at textures from the source mod, ` +
        `which the end user installs separately. (Matches the framework's ` +
        `<code>content-packs/</code> convention.)`
    );

    if (state.extraneousDDS.length > 0) {
        const sample = state.extraneousDDS.slice(0, 3).map(p => `<code>${escapeHtml(p)}</code>`).join(', ');
        const more = state.extraneousDDS.length > 3 ? ` and ${state.extraneousDDS.length - 3} more` : '';
        addStatus('warn',
            `${state.extraneousDDS.length} <code>.dds</code> file${state.extraneousDDS.length === 1 ? '' : 's'} ` +
            `outside the <code>${escapeHtml(state.root)}</code> root were ignored: ${sample}${more}.`
        );
    }

    // Collision report (across all catalogs combined)
    const allLabels = catalogs.flatMap(c => c.entries.map(e => e.label));
    const labelCounts = new Map();
    allLabels.forEach(l => labelCounts.set(l, (labelCounts.get(l) || 0) + 1));
    const collisions = [...labelCounts.entries()].filter(([, n]) => n > 1);
    if (collisions.length > 0) {
        const sample = collisions.slice(0, 3).map(([k, n]) => `<code>${escapeHtml(k)}</code> &times;${n}`).join(', ');
        addStatus('warn',
            `${collisions.length} entry name collision${collisions.length === 1 ? '' : 's'} ` +
            `auto-resolved with <code>-2</code>/<code>-3</code>/&hellip; suffixes: ${sample}. ` +
            `Edit the JSON afterward if you want prettier IDs.`
        );
    }

    // .psc label sourcing report
    if (state.pscParsed && state.pscParsed.count > 0) {
        const pscList = state.pscParsed.paths.map(p => `<code>${escapeHtml(p)}</code>`).join(', ');
        const allLabeled = state.labeledFromPsc === totalEntries;
        if (allLabeled) {
            addStatus('ok',
                `All ${totalEntries} entries labelled from ${pscList} ` +
                `(${state.pscParsed.count} mappings found).`
            );
        } else {
            addStatus('info',
                `${state.labeledFromPsc} of ${totalEntries} entries labelled from ${pscList}. ` +
                `The rest fall back to filename stems &mdash; the .psc likely doesn't register them.`
            );
        }
        if (state.skippedUnregistered > 0) {
            addStatus('info',
                `${state.skippedUnregistered} <code>.dds</code> file${state.skippedUnregistered === 1 ? '' : 's'} ` +
                `not registered in the .psc &mdash; skipped from the catalog (treating the .psc ` +
                `as the author's curation). Pre-extract the archive and remove the .psc if you want them all in.`
            );
        }
    } else if (state.pscParsed) {
        addStatus('warn',
            `Found .psc but no <code>AddBodyPaint</code> / similar calls. ` +
            `Entry labels fall back to filename stems.`
        );
    } else {
        addStatus('info',
            `No <code>.psc</code> source script found &mdash; entry labels default to filename stems, ` +
            `areas inferred from path keywords. Edit the JSON${catalogs.length === 1 ? '' : 's'} afterward if needed.`
        );
    }

    els.downloadBtn.disabled = false;
}

// ─── Output composition ─────────────────────────────────────────────────

els.downloadBtn.addEventListener('click', async () => {
    if (!state || !state.catalogs || state.catalogs.length === 0) return;

    els.downloadBtn.disabled = true;
    els.downloadBtn.textContent = 'Packaging…';

    try {
        // Thin MO2-installable ZIP wrapping ONE catalog JSON per area
        // group (1-4 files total). No textures pass through. End users
        // install the source texture mod separately.
        const out = new JSZip();
        for (const cat of state.catalogs) {
            const jsonPath =
                `SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/${cat.packId}.json`;
            out.file(jsonPath, JSON.stringify(cat, null, 2) + '\n');
        }

        const blob = await out.generateAsync({
            type: 'blob',
            compression: 'DEFLATE',
            compressionOptions: { level: 6 },
        });

        // Output filename uses the BASE packId (the Body / first one),
        // so a multi-area pack still gets a sensible mod name.
        const baseId = state.catalogs[0].packId;
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${baseId}.zip`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        // Free the blob URL after the browser starts the download.
        setTimeout(() => URL.revokeObjectURL(url), 4000);

        els.downloadBtn.textContent = 'Download pack ZIP';
    } catch (err) {
        console.error(err);
        addStatus('err', `Packaging failed: ${escapeHtml(err.message || String(err))}`);
        els.downloadBtn.textContent = 'Download pack ZIP';
    } finally {
        els.downloadBtn.disabled = false;
    }
});

// ─── Tiny helpers ───────────────────────────────────────────────────────

function formatBytes(n) {
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
    if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
    return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

function escapeHtml(s) {
    return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
