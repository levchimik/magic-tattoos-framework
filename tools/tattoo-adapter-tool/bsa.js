/* Minimal Bethesda Archive (.bsa) name-table reader — pure JS, browser-safe.
 *
 * Many Skyrim overlay mods don't ship loose `textures/…/*.dds`; instead they
 * seal every texture inside a single `.bsa` (Bethesda Archive). libarchive.js
 * lists that `.bsa` as one opaque entry, so the adapter tool's
 * `detectTexturesRoot()` finds zero `.dds` and gives up.
 *
 * This module reconstructs the internal file paths from a BSA WITHOUT touching
 * the texture data. A BSA's folder/file/name tables live at the very FRONT of
 * the file (a few KB even for a 300 MB archive), so we read only the header,
 * compute exactly how many bytes the tables occupy, and slice just that prefix.
 * Compression (archiveFlags & 0x4) affects only the file DATA, never the name
 * tables, so we ignore it entirely.
 *
 * Supports BSA versions 104 (Skyrim LE / FO3 / FNV) and 105 (Skyrim SE/AE).
 * Fallout 4's `.ba2` (magic "BTDX") is a different format and is reported as
 * unsupported rather than mis-parsed.
 *
 * Reference: https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format
 */

const LATIN1 = new TextDecoder('latin1');

// BSA archiveFlags bits we care about.
const FLAG_DIR_NAMES  = 0x1; // folder-name bzstrings present before each block
const FLAG_FILE_NAMES = 0x2; // trailing file-name block present

/**
 * Read a BSA's internal file paths from a Blob/File.
 *
 * @param {Blob} blob - a File/Blob whose bytes are a `.bsa`.
 * @returns {Promise<{paths: string[], version: number, warning?: string}>}
 *   `paths` are backslash-delimited internal paths exactly as the BSA stores
 *   them, e.g. `textures\actors\character\overlays\foo\001.dds`. On an
 *   unparseable input, `paths` is empty and `warning` explains why
 *   ('not-bsa' | 'no-filenames').
 */
export async function readBsaPaths(blob) {
    // ── Header (36 bytes) ───────────────────────────────────────────────
    const headBuf = await blob.slice(0, 36).arrayBuffer();
    if (headBuf.byteLength < 36) return { paths: [], version: 0, warning: 'not-bsa' };
    const h = new DataView(headBuf);

    // Magic "BSA\0" == 0x42 0x53 0x41 0x00
    if (h.getUint8(0) !== 0x42 || h.getUint8(1) !== 0x53 ||
        h.getUint8(2) !== 0x41 || h.getUint8(3) !== 0x00) {
        return { paths: [], version: 0, warning: 'not-bsa' };
    }

    const version              = h.getUint32(4, true);
    const archiveFlags         = h.getUint32(12, true);
    const folderCount          = h.getUint32(16, true);
    const fileCount            = h.getUint32(20, true);
    const totalFolderNameLength = h.getUint32(24, true);
    const totalFileNameLength   = h.getUint32(28, true);

    const hasDirNames  = (archiveFlags & FLAG_DIR_NAMES)  !== 0;
    const hasFileNames = (archiveFlags & FLAG_FILE_NAMES) !== 0;

    // Without the file-name block we can't recover any paths — bail cleanly.
    if (!hasFileNames || fileCount === 0) {
        return { paths: [], version, warning: 'no-filenames' };
    }

    // Folder-record size differs by version: v105 (SSE) is 24 bytes, earlier
    // versions are 16. We only ever read the `count` field at +8, so the exact
    // tail layout doesn't matter — just the stride.
    const folderRecSize = version >= 105 ? 24 : 16;

    // ── Compute the exact prefix length the tables occupy ───────────────
    //   header(36)
    // + folderRecords (folderCount × folderRecSize)
    // + folder-name+file-record blocks:
    //     folderCount length-prefix bytes + totalFolderNameLength name bytes
    //     + fileCount × 16 file-record bytes
    // + file-name block (totalFileNameLength)
    const tablesLen =
        36 +
        folderCount * folderRecSize +
        (hasDirNames ? folderCount + totalFolderNameLength : 0) +
        fileCount * 16 +
        totalFileNameLength;

    const buf = await blob.slice(0, tablesLen).arrayBuffer();
    const dv  = new DataView(buf);
    const u8  = new Uint8Array(buf);

    // ── Folder records: capture each folder's file count ────────────────
    let p = 36;
    const folderFileCounts = new Array(folderCount);
    for (let i = 0; i < folderCount; i++) {
        folderFileCounts[i] = dv.getUint32(p + 8, true); // count field at +8
        p += folderRecSize;
    }

    // ── Folder-name bzstrings + (skipped) file records ──────────────────
    const folderNames = new Array(folderCount);
    for (let i = 0; i < folderCount; i++) {
        if (hasDirNames) {
            const len = u8[p]; // bzstring length byte (includes trailing null)
            p += 1;
            const raw = LATIN1.decode(u8.subarray(p, p + len));
            folderNames[i] = raw.replace(/\0+$/, ''); // strip null terminator(s)
            p += len;
        } else {
            folderNames[i] = '';
        }
        // File records are 16 bytes each; we don't need them (names come from
        // the trailing block) so just step over them.
        p += folderFileCounts[i] * 16;
    }

    // ── File-name block: null-separated, global file order ──────────────
    const nameBytes = u8.subarray(p, p + totalFileNameLength);
    const fileNames = LATIN1.decode(nameBytes).split('\0').filter(s => s.length > 0);

    // ── Stitch folder + file names back into full internal paths ────────
    const paths = [];
    let ni = 0;
    for (let i = 0; i < folderCount; i++) {
        for (let j = 0; j < folderFileCounts[i]; j++) {
            const fname = fileNames[ni++];
            if (fname === undefined) break; // malformed: fewer names than records
            paths.push(folderNames[i] ? `${folderNames[i]}\\${fname}` : fname);
        }
    }

    return { paths, version };
}
