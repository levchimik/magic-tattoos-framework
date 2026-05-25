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
    packArea:      document.getElementById('packArea'),
    dropZone:      document.getElementById('dropZone'),
    fileInput:     document.getElementById('fileInput'),
    dropMeta:      document.getElementById('dropMeta'),
    statusCard:    document.getElementById('statusCard'),
    statusContent: document.getElementById('statusContent'),
    downloadBtn:   document.getElementById('downloadBtn'),
};

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
        catalog:        null,
    };

    els.dropMeta.innerHTML =
        `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)}) &mdash; ` +
        `${ddsEntries.length} texture${ddsEntries.length === 1 ? '' : 's'} catalogued under ` +
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
        `Texture root detected: <code>${escapeHtml(state.root)}</code>.`
    );
    addStatus('ok',
        `JSON output path: <code>SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/${escapeHtml(packId)}.json</code>`
    );
    addStatus('info',
        `Output is JSON-only &mdash; the catalog points at textures from the source mod, ` +
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
        // The output is a thin MO2-installable ZIP wrapping ONLY the
        // catalog JSON. No textures pass through. End users install the
        // source texture mod separately; this catalog is just the
        // pointer that tells MTF which textures to use.
        const out = new JSZip();
        const newJsonPath =
            `SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/${state.catalog.packId}.json`;
        const jsonText = JSON.stringify(state.catalog, null, 2) + '\n';
        out.file(newJsonPath, jsonText);

        const blob = await out.generateAsync({
            type: 'blob',
            compression: 'DEFLATE',
            compressionOptions: { level: 6 },
        });

        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${state.catalog.packId}.zip`;
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
