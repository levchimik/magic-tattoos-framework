/* MTF Content Pack Builder — pure-browser ZIP→pack converter.
 *
 * Pipeline:
 *   1. User picks/drops a Skyrim mod ZIP
 *   2. Walk every entry, find .dds files under textures/ (or Data/textures/)
 *   3. Build the MTF catalog JSON
 *   4. Compose a new ZIP containing all original entries + the new JSON at
 *      SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/<packid>.json
 *   5. Trigger download — Blob + <a download>, no upload anywhere
 *
 * Pure vanilla JS, single global namespace, no build step. JSZip is the
 * only dependency.
 */

(() => {
    'use strict';

    // ─── DOM refs ───────────────────────────────────────────────────────
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

    // ─── State ──────────────────────────────────────────────────────────
    // Holds the parsed input + derived catalog between "drop" and "download".
    // null until a ZIP successfully parses.
    let state = null;

    // ─── Utilities ──────────────────────────────────────────────────────

    /**
     * Detect the "textures root" inside a parsed ZIP.
     * Returns the path PREFIX that should be stripped from each entry so
     * the remainder is what Skyrim will look up under Data/textures/.
     * Returns null if no recognizable layout was found.
     *
     * Recognized layouts (case-insensitive):
     *   - "textures/..."           → strip "textures/"
     *   - "Data/textures/..."      → strip "Data/textures/"
     *   - "data/textures/..."      → strip "data/textures/"
     */
    function detectTexturesRoot(entryPaths) {
        // Look for any .dds under one of the known prefixes. We accept the
        // first match — packs that mix layouts are pathological and we
        // tell the user via the status panel.
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
     * Sanitize an entry id derived from a filename. Keep it lowercase-ish
     * but allow original case for visual identity. Spaces → underscores
     * (otherwise StorageUtil keys go funny in some Papyrus paths).
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

    // ─── Status panel ───────────────────────────────────────────────────

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

    // ─── Drop-zone wiring ───────────────────────────────────────────────

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
        if (file) handleZip(file);
    });
    els.fileInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (file) handleZip(file);
    });

    // ─── Form change re-renders catalog (cheap, no re-parse) ────────────
    [els.packId, els.packLabel, els.packArea].forEach(el => {
        el.addEventListener('input', () => {
            if (state) rebuildCatalog();
        });
    });

    // ─── Main pipeline ──────────────────────────────────────────────────

    async function handleZip(file) {
        clearStatus();
        state = null;
        els.downloadBtn.disabled = true;
        els.dropMeta.hidden = false;
        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)}) &mdash; reading&hellip;`;

        let zip;
        try {
            zip = await JSZip.loadAsync(file);
        } catch (err) {
            els.dropMeta.innerHTML = `<strong>${escapeHtml(file.name)}</strong> &mdash; failed to read.`;
            showSummary(`<strong>Bad ZIP.</strong> ${escapeHtml(err.message || String(err))}`);
            return;
        }

        // Collect all entries (files + dirs); JSZip stores dirs as separate
        // entries with `.dir == true`. We only care about files.
        const entryPaths = [];
        zip.forEach((relPath, zipEntry) => {
            if (!zipEntry.dir) entryPaths.push(relPath);
        });

        const root = detectTexturesRoot(entryPaths);
        if (!root) {
            els.dropMeta.innerHTML =
                `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)})`;
            showSummary(
                `<strong>No <code>textures/</code> root found.</strong> ` +
                `The ZIP needs to look like a Skyrim mod download &mdash; with ` +
                `<code>textures/&hellip;/*.dds</code> at the root (or <code>Data/textures/&hellip;</code>). ` +
                `Re-package and try again.`
            );
            return;
        }

        // Walk every entry; split into DDS-under-textures vs. everything else.
        const ddsEntries = []; // { fullPath, relativeToTextures, stem }
        const extraneousDDS = []; // .dds files outside the textures/ root
        for (const path of entryPaths) {
            const lower = path.toLowerCase();
            if (!lower.endsWith('.dds')) continue;
            if (lower.startsWith(root.toLowerCase())) {
                const relative = path.substring(root.length);
                ddsEntries.push({
                    fullPath: path,
                    relative: relative,
                    stem: stemOf(path),
                });
            } else {
                extraneousDDS.push(path);
            }
        }

        if (ddsEntries.length === 0) {
            els.dropMeta.innerHTML =
                `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)})`;
            showSummary(
                `<strong>No <code>.dds</code> files found</strong> under <code>${escapeHtml(root)}</code>. ` +
                `Did you drop the right ZIP?`
            );
            return;
        }

        // Detect an existing visuals JSON the output would replace — informational.
        const existingCatalog = entryPaths.find(p => {
            const l = p.toLowerCase();
            return l.includes('skse/plugins/storageutildata/magictattoosframework/visuals/') &&
                   l.endsWith('.json');
        });

        // Stash state. Catalog is rebuilt every time the form changes —
        // see rebuildCatalog(). The ZIP itself is reused for output.
        state = {
            file:            file,
            zip:             zip,
            entryPaths:      entryPaths,
            root:            root,
            ddsEntries:      ddsEntries,
            extraneousDDS:   extraneousDDS,
            existingCatalog: existingCatalog,
            catalog:         null,
        };

        els.dropMeta.innerHTML =
            `<strong>${escapeHtml(file.name)}</strong> (${formatBytes(file.size)}) &mdash; ` +
            `${ddsEntries.length} texture${ddsEntries.length === 1 ? '' : 's'} found under ` +
            `<code>${escapeHtml(root)}</code>.`;

        rebuildCatalog();
    }

    /**
     * Build the catalog JSON from current form state + parsed ddsEntries.
     * Re-runs on every form-field change; cheap because we already have
     * the file list. Records the result in state.catalog and renders the
     * status panel.
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

        // ─── Render status panel ────────────────────────────────────────
        els.statusCard.hidden = false;
        els.statusContent.innerHTML = '';
        showSummary(
            `Ready to package <strong>${escapeHtml(packId)}</strong> ` +
            `(<strong>${entries.length}</strong> entries, area: <strong>${escapeHtml(packArea)}</strong>).`
        );

        addStatus('ok',
            `Texture root: <code>${escapeHtml(state.root)}</code> — left unchanged in the output ZIP.`
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
                `Input ZIP already contains a catalog: <code>${escapeHtml(state.existingCatalog)}</code>. ` +
                `Output will overwrite it.`
            );
        }

        // Collision report
        const idCounts = new Map();
        entries.forEach(e => idCounts.set(e.label, (idCounts.get(e.label) || 0) + 1));
        const collisions = [...idCounts.entries()].filter(([, n]) => n > 1);
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

    // ─── Output composition ─────────────────────────────────────────────

    els.downloadBtn.addEventListener('click', async () => {
        if (!state || !state.catalog) return;

        els.downloadBtn.disabled = true;
        els.downloadBtn.textContent = 'Packaging…';

        try {
            const out = new JSZip();

            // 1. Copy every original entry. Files keep their compressed
            //    representation if JSZip can; otherwise re-compress.
            //    We skip an existing visuals/<same-name>.json so the new one wins.
            const newJsonPath =
                `SKSE/Plugins/StorageUtilData/MagicTattoosFramework/visuals/${state.catalog.packId}.json`;
            const newJsonLower = newJsonPath.toLowerCase();
            const copyJobs = [];
            state.zip.forEach((relPath, zipEntry) => {
                if (zipEntry.dir) return;
                if (relPath.toLowerCase() === newJsonLower) return;
                copyJobs.push(
                    zipEntry.async('uint8array').then(data => {
                        out.file(relPath, data, {
                            date: zipEntry.date,
                            unixPermissions: zipEntry.unixPermissions,
                            dosPermissions: zipEntry.dosPermissions,
                        });
                    })
                );
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

    // ─── Tiny helpers ───────────────────────────────────────────────────

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
})();
