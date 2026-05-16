// Adds 5 MGEFs (one per spell school) and 1 Spell to MagicTattoosFramework.esp.
// The spell is a hidden Ability with 5 Peak Value Modifier effects that
// each target a school's *Mod actor value, so adding it to the player makes
// spells from every school cost more (magnitude is mutated at runtime by
// MTF_Plugin_Base).
//
// FormIDs: MGEFs at 0x810-0x814, Spell at 0x815 (next free after 0x80F).
// Usage:
//   cd "F:/stuff/Skyrim modding"
//   node "F:/stuff/MagicTattoosFramework/tools/add_cost_penalty_records.js"

const xelib = require('F:/stuff/Skyrim modding/node_modules/xeditlib');

const SCHOOLS = [
    // editorId suffix, full-name suffix, Magic Skill index, Actor Value enum string
    ['Alteration',   'Alteration',   18, 'Alteration Modifier'],
    ['Conjuration',  'Conjuration',  19, 'Conjuration Modifier'],
    ['Destruction',  'Destruction',  20, 'Destruction Modifier'],
    ['Illusion',     'Illusion',     21, 'Illusion Modifier'],
    ['Restoration',  'Restoration',  22, 'Restoration Modifier'],
];

const PEAK_VALUE_MODIFIER = 34;
const CAST_CONSTANT = 0;
const DELIVERY_SELF = 0;

const BASE_FID = 0x810;            // first new MGEF
const SPELL_FID = 0x815;           // ability spell

function log(s) { console.log(s); }

// Note: do NOT call setFormID manually. local=true keeps load-order byte 0
// which injects the record into Skyrim.esm's FormID space. xelib auto-assigns
// FormIDs from the file's NextObjectID header, which is what we want.

function setEnumValue(h, path, name) {
    // Some enum paths accept either the string name or the integer index.
    // Try string first; fall back to int.
    try { xelib.setValue(h, path, name); }
    catch (e) { xelib.setIntValue(h, path, parseInt(name, 10)); }
}

function trySetFlag(h, path, name, on) {
    try { xelib.setFlag(h, path, name, on); }
    catch (e) { log(`  (warn) flag "${name}" at ${path}: ${e.message}`); }
}

function addMGEF(file, schoolIdx) {
    const [edSuffix, nameSuffix, magicSkill, av] = SCHOOLS[schoolIdx];
    const edid = `MTF_MGEF_Cost_${edSuffix}`;
    log(`Adding MGEF ${edid}`);

    const mgefGroup = xelib.addElement(file, 'MGEF');
    log(`  mgefGroup handle=${mgefGroup} sig=${xelib.signature(mgefGroup)} type=${xelib.elementType(mgefGroup)}`);
    const rec = xelib.addElement(mgefGroup, 'MGEF');
    log(`  rec handle=${rec} sig=${xelib.signature(rec)} fid=${xelib.getFormID(rec).toString(16)}`);

    xelib.addElementValue(rec, 'EDID', edid);
    xelib.addElementValue(rec, 'FULL', `Spell Cost Penalty (${nameSuffix})`);

    // Create DATA — xEdit names it "DATA - Data" with typo "Archtype".
    xelib.addElement(rec, 'DATA');
    const D = 'Magic Effect Data\\DATA - Data';
    trySetFlag(rec, `${D}\\Flags`, 'Hide in UI',      true);
    trySetFlag(rec, `${D}\\Flags`, 'No Hit Event',    true);
    trySetFlag(rec, `${D}\\Flags`, 'No Death Dispel', true);
    xelib.setFloatValue(rec, `${D}\\Base Cost`, 0.0);
    xelib.setIntValue(rec,   `${D}\\Magic Skill`, magicSkill);
    xelib.setIntValue(rec,   `${D}\\Resist Value`, -1);
    xelib.setFloatValue(rec, `${D}\\Taper Weight`, 0.0);
    xelib.setUIntValue(rec,  `${D}\\Minimum Skill Level`, 0);
    xelib.setUIntValue(rec,  `${D}\\Spellmaking\\Area`, 0);
    xelib.setFloatValue(rec, `${D}\\Spellmaking\\Casting Time`, 0.0);
    xelib.setFloatValue(rec, `${D}\\Taper Curve`, 0.0);
    xelib.setFloatValue(rec, `${D}\\Taper Duration`, 0.0);
    xelib.setFloatValue(rec, `${D}\\Second AV Weight`, 0.0);
    xelib.setIntValue(rec,   `${D}\\Archtype`, PEAK_VALUE_MODIFIER); // xEdit typo
    xelib.setValue(rec,      `${D}\\Actor Value`, av);
    xelib.setIntValue(rec,   `${D}\\Casting Type`, CAST_CONSTANT);
    xelib.setIntValue(rec,   `${D}\\Delivery`, DELIVERY_SELF);
    xelib.setIntValue(rec,   `${D}\\Second Actor Value`, -1);
    xelib.setFloatValue(rec, `${D}\\Skill Usage Multiplier`, 0.0);
    xelib.setFloatValue(rec, `${D}\\Dual Casting\\Scale`, 0.0);

    return rec;
}

function addCostPenaltySpell(file, mgefRecs) {
    const edid = 'MTF_Spell_CostPenalty';
    log(`Adding SPEL ${edid}`);
    const grp = xelib.addElement(file, 'SPEL');
    const rec = xelib.addElement(grp, 'SPEL');
    log(`  SPEL rec fid=${xelib.getFormID(rec).toString(16)}`);

    xelib.addElementValue(rec, 'EDID', edid);
    xelib.addElementValue(rec, 'FULL', 'Spell Cost Penalty');

    // SPIT - Data subrecord
    xelib.addElement(rec, 'SPIT');
    const S = 'SPIT - Data';
    xelib.setUIntValue(rec,  `${S}\\Base Cost`, 0);
    xelib.setIntValue(rec,   `${S}\\Type`, 0x07);          // 7 = Ability
    xelib.setFloatValue(rec, `${S}\\Charge Time`, 0.0);
    xelib.setIntValue(rec,   `${S}\\Cast Type`, CAST_CONSTANT);
    xelib.setIntValue(rec,   `${S}\\Target Type`, DELIVERY_SELF);
    xelib.setFloatValue(rec, `${S}\\Cast Duration`, 0.0);
    xelib.setFloatValue(rec, `${S}\\Range`, 0.0);

    // Effects array. The record is created with a single empty effect already;
    // populate it with the first MGEF, then addElement for the remaining 4.
    for (let i = 0; i < mgefRecs.length; i++) {
        const fid = xelib.getFormID(mgefRecs[i]);
        const efPath = i === 0 ? 'Effects\\[0]' : 'Effects\\.';
        const ef = i === 0 ? xelib.getElement(rec, efPath) : xelib.addElement(rec, efPath);
        xelib.setUIntValue(ef,  'EFID - Base Effect', fid);
        xelib.setFloatValue(ef, 'EFIT - \\Magnitude', 1.0);
        xelib.setUIntValue(ef,  'EFIT - \\Area', 0);
        xelib.setUIntValue(ef,  'EFIT - \\Duration', 0);
    }
    return rec;
}

(async () => {
    try {
        log('init...');         xelib.init();
        log('setGamePath...');  xelib.setGamePath('S:/SteamLibrary/steamapps/common/Skyrim Special Edition/');
        log('setGameMode...');  xelib.setGameMode(4); // gmSSE

        const espName = 'MagicTattoosFramework.esp';
        const dataDir = 'F:/Modlists/Modding Essentials/Stock Game/Data';
        const espPath = `${dataDir}/${espName}`;

        // Loading via load order — MagicTattoosFramework.esp must be present in plugins.txt.
        log('Loading plugins...');
        xelib.loadPlugins(`Skyrim.esm\n${espName}\n`, true, false);
        await xelib.waitForLoader();

        const file = xelib.fileByName(espName);
        if (!file) throw new Error(`${espName} not loaded`);
        log(`File handle: ${file}`);

        const mgefRecs = [];
        for (let i = 0; i < SCHOOLS.length; i++) {
            mgefRecs.push(addMGEF(file, i));
        }
        addCostPenaltySpell(file, mgefRecs);

        log('Saving...');
        xelib.saveFile(file, '');
        log('Done.');
    } catch (e) {
        console.error('FAILED:', e.message);
        console.error(xelib.getExceptionMessage());
        console.error(xelib.getExceptionStack());
        process.exitCode = 1;
    } finally {
        xelib.close();
    }
})();
