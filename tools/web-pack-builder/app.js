/* MTF Content Pack Builder — pure-browser archive→pack converter.
 *
 * Pipeline:
 *   1. User picks/drops a Skyrim mod archive (zip, 7z, rar, tar, ...)
 *   2. libarchive.js opens it and extracts every entry
 *   3. We walk the entries, find .dds files under textures/ (or Data/textures/),
 *      build the MTF catalog JSON
 *   4. JSZip composes a new ZIP containing all original entries + the catalog at
 *      SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/<packid>.json
 *   5. Trigger download — Blob + <a download>, no upload anywhere
 *
 * libarchive.js (WASM port of libarchive) reads any format the C library
 * supports; JSZip writes the output ZIP. Mod managers want ZIP (or 7z) —
 * we always emit ZIP because writing 7z in-browser would need an LZMA2
 * encoder, which is bigger and slower than the value adds.
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
    packArea:      document.getElementById('packArea'),
    dropZone:      document.getElementById('dropZone'),
    fileInput:     document.getElementById('fileInput'),
    dropMeta:      document.getElementById('dropMeta'),
    statusCard:    document.getElementById('statusCard'),
    statusContent: document.getElementById('statusContent'),
    downloadBtn:   document.getElementById('downloadBtn'),
};

// ─── State ──────────────────────────────────────────────────────────────
// Holds the parsed input + derived catalog between "drop" and "download".
// `extractedEntries` holds File objects already pulled out of the input
// archive (libarchive's worker dies after extractFiles, so we can't
// re-extract — we hold the bytes in memory until download).
let state = null;

// ─── Utilities ──────────────────────────────────────────────────────────

/**
 * Detect the "textures root" inside a list of paths.
 * Returns the path PREFIX that should be stripped from each entry so
 * the remainder is what Skyrim looks up under Data/textures/.
 * Returns null if no recognizable layout was found.
 *
 * Recognized layouts (case-insensitive):
 *   - "textures/..."           → strip "textures/"
 *   - "Data/textures/..."      → strip "Data/textures/"
 *   - "data/textures/..."      → strip "data/textures/"
 */
function detectTexturesRoot(entryPaths) {
    const candidates = [
        'data/textures/',
        'textures/',
    ];
    for (const ep of entryPaths) {
        const lower = ep.toLowerCase();
        if (!lower.endsWith('.dds')) continue;
        for (const prefix of candidates) {
            if (lower.startsWith(prefix)) {
                return ep.substring(0, prefix.length);
            }
        }
    }
    return null;
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
 * Flatten the nested {dirName: {dirName: {fileName: File}}} object that
 * libarchive's `extractFiles()` returns into a flat list of
 * { path: "full/forward/slashed/path.dds", file: File } entries.
 *
 * We don't use libarchive's own per-entry callback because it fires via
 * setTimeout and resolves AFTER the extractFiles promise — see the call
 * site for the full RACE TRAP comment.
 */
function flattenContent(obj, prefix = '') {
    const out = [];
    if (!obj || typeof obj !== 'object') return out;
    for (const [key, val] of Object.entries(obj)) {
        if (val instanceof File) {
            out.push({ path: prefix + key, file: val });
        } else if (val && typeof val === 'object') {
            out.push(...flattenContent(val, prefix + key + '/'));
        }
    }
    return out;
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
[els.packId, els.packLabel, els.packArea].forEach(el => {
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

    // Extract every entry into memory. libarchive's worker terminates
    // after extractFiles completes, so we have to hoist the File objects
    // out for the output ZIP composition later.
    //
    // RACE TRAP: libarchive's per-entry callback fires via `setTimeout`,
    // meaning callbacks land AFTER the awaited promise resolves. Don't
    // collect via the callback — the array would still be empty when
    // we observe it. Instead, consume the resolved nested-object
    // RETURN value (the same `_content` libarchive builds internally
    // before scheduling those callbacks) and flatten it ourselves.
    els.dropMeta.innerHTML =
        `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)}) &mdash; extracting&hellip;`;

    let contentObj;
    try {
        contentObj = await archive.extractFiles();
    } catch (err) {
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> &mdash; extraction failed.`;
        showSummary(
            `<strong>Extraction failed.</strong> ${escapeHtml(err.message || String(err))} ` +
            `&mdash; the archive may be password-protected or corrupted.`
        );
        return;
    }
    const extractedEntries = flattenContent(contentObj);

    if (extractedEntries.length === 0) {
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)})`;
        showSummary(`<strong>Archive is empty.</strong>`);
        return;
    }

    // Detect the textures/ root from the extracted entry list.
    const allPaths = extractedEntries.map(e => e.path);
    const root = detectTexturesRoot(allPaths);
    if (!root) {
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)})`;
        showSummary(
            `<strong>No <code>textures/</code> root found.</strong> ` +
            `The archive needs to look like a Skyrim mod download &mdash; with ` +
            `<code>textures/&hellip;/*.dds</code> at the root (or <code>Data/textures/&hellip;</code>). ` +
            `Re-package and try again.`
        );
        return;
    }

    // Categorize entries: DDS under textures/ vs DDS outside vs everything else.
    const ddsEntries = []; // { fullPath, relative, stem }
    const extraneousDDS = [];
    for (const entry of extractedEntries) {
        const lower = entry.path.toLowerCase();
        if (!lower.endsWith('.dds')) continue;
        if (lower.startsWith(root.toLowerCase())) {
            ddsEntries.push({
                fullPath: entry.path,
                relative: entry.path.substring(root.length),
                stem: stemOf(entry.path),
            });
        } else {
            extraneousDDS.push(entry.path);
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

    // Detect existing visuals JSON the output would replace — informational.
    const existingCatalog = allPaths.find(p => {
        const l = p.toLowerCase();
        return l.includes('skse/plugins/storageutildata/magictattoosframework/visuals/') &&
               l.endsWith('.json');
    });

    state = {
        file:              file,
        extractedEntries:  extractedEntries,
        root:              root,
        ddsEntries:        ddsEntries,
        extraneousDDS:     extraneousDDS,
        existingCatalog:   existingCatalog,
        catalog:           null,
    };

    els.dropMeta.innerHTML =
        `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)}) &mdash; ` +
        `${extractedEntries.length} entries extracted, ` +
        `${ddsEntries.length} texture${ddsEntries.length === 1 ? '' : 's'} catalogued under ` +
        `<code>${escapeHtml(root)}</code>.`;

    rebuildCatalog();
}

/**
 * Build the catalog JSON from current form state + parsed ddsEntries.
 * Re-runs on every form-field change; cheap because all extraction
 * happened at drop time. Records result in state.catalog and renders
 * the status panel.
 */
function rebuildCatalog() {
    if (!state) return;

    // Validate form
    const packId = els.packId.value.trim();
    const packLabel = els.packLabel.value.trim();
    const packArea = els.packArea.value;
    const idOk = /^mtf\.[a-z0-9][a-z0-9._-]*$/.test(packId);

    if (!idOk) {
        els.statusCard.hidden = false;
        els.statusContent.innerHTML = '';
        showSummary(
            `<strong>Pack ID looks off.</strong> Expected the form ` +
            `<code>mtf.&lt;name&gt;</code> &mdash; lowercase, dots / dashes / underscores OK.`
        );
        state.catalog = null;
        els.downloadBtn.disabled = true;
        return;
    }
    if (!packLabel) {
        els.statusCard.hidden = false;
        els.statusContent.innerHTML = '';
        showSummary(`<strong>Display label is required.</strong>`);
        state.catalog = null;
        els.downloadBtn.disabled = true;
        return;
    }

    // Build entries
    const takenIds = new Set();
    const entries = state.ddsEntries.map(d => ({
        id:    makeEntryId(d.stem, takenIds),
        label: d.stem,
        layers: [
            { texture: toSkyrimPath(d.relative) },
        ],
    }));

    state.catalog = {
        schemaVersion: 3,
        packId:        packId,
        label:         packLabel,
        area:          packArea,
        entries:       entries,
    };

    // ─── Render status panel ────────────────────────────────────────────
    els.statusCard.hidden = false;
    els.statusContent.innerHTML = '';
    showSummary(
        `Ready to package <strong>${escapeHtml(packId)}</strong> ` +
        `(<strong>${entries.length}</strong> entries, area: <strong>${escapeHtml(packArea)}</strong>).`
    );

    addStatus('ok',
        `Texture root: <code>${escapeHtml(state.root)}</code> &mdash; left unchanged in the output ZIP.`
    );
    addStatus('ok',
        `JSON output path: <code>SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/${escapeHtml(packId)}.json</code>`
    );

    if (state.extraneousDDS.length > 0) {
        const sample = state.extraneousDDS.slice(0, 3).map(p => `<code>${escapeHtml(p)}</code>`).join(', ');
        const more = state.extraneousDDS.length > 3 ? ` and ${state.extraneousDDS.length - 3} more` : '';
        addStatus('warn',
            `${state.extraneousDDS.length} <code>.dds</code> file${state.extraneousDDS.length === 1 ? '' : 's'} ` +
            `outside the <code>${escapeHtml(state.root)}</code> root: ${sample}${more}. ` +
            `These are passed through to the output ZIP unchanged but not catalogued.`
        );
    }

    if (state.existingCatalog) {
        addStatus('warn',
            `Input archive already contains a catalog: <code>${escapeHtml(state.existingCatalog)}</code>. ` +
            `Output will overwrite it.`
        );
    }

    // Collision report
    const labelCounts = new Map();
    entries.forEach(e => labelCounts.set(e.label, (labelCounts.get(e.label) || 0) + 1));
    const collisions = [...labelCounts.entries()].filter(([, n]) => n > 1);
    if (collisions.length > 0) {
        const sample = collisions.slice(0, 3).map(([k, n]) => `<code>${escapeHtml(k)}</code> &times;${n}`).join(', ');
        addStatus('warn',
            `${collisions.length} entry name collision${collisions.length === 1 ? '' : 's'} ` +
            `auto-resolved with <code>-2</code>/<code>-3</code>/&hellip; suffixes: ${sample}. ` +
            `Edit the JSON afterward if you want prettier IDs.`
        );
    }

    addStatus('info',
        `Filename stems become the entry <code>id</code> AND <code>label</code>. ` +
        `Edit labels in the output JSON if you want better MCM display names.`
    );

    els.downloadBtn.disabled = false;
}

// ─── Output composition ─────────────────────────────────────────────────

els.downloadBtn.addEventListener('click', async () => {
    if (!state || !state.catalog) return;

    els.downloadBtn.disabled = true;
    els.downloadBtn.textContent = 'Packaging…';

    try {
        const out = new JSZip();

        // 1. Copy every original entry. The libarchive `File` objects
        //    expose `.arrayBuffer()` and `.lastModified`. We skip an
        //    existing visuals/<same-name>.json so the new one wins.
        const newJsonPath =
            `SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/${state.catalog.packId}.json`;
        const newJsonLower = newJsonPath.toLowerCase();

        const copyJobs = state.extractedEntries.map(async (entry) => {
            if (entry.path.toLowerCase() === newJsonLower) return;
            const buf = await entry.file.arrayBuffer();
            out.file(entry.path, new Uint8Array(buf), {
                date: new Date(entry.file.lastModified || Date.now()),
            });
        });
        await Promise.all(copyJobs);

        // 2. Add (or replace) the catalog JSON.
        const jsonText = JSON.stringify(state.catalog, null, 2) + '\n';
        out.file(newJsonPath, jsonText);

        // 3. Generate the output blob.
        const blob = await out.generateAsync({
            type: 'blob',
            compression: 'DEFLATE',
            compressionOptions: { level: 6 },
        });

        // 4. Trigger download.
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${state.catalog.packId}-mtf-bundle.zip`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        // Free the blob URL after the browser starts the download.
        setTimeout(() => URL.revokeObjectURL(url), 4000);

        els.downloadBtn.textContent = 'Download converted ZIP';
    } catch (err) {
        console.error(err);
        addStatus('err', `Packaging failed: ${escapeHtml(err.message || String(err))}`);
        els.downloadBtn.textContent = 'Download converted ZIP';
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
