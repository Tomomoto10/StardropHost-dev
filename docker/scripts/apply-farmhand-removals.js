#!/usr/bin/env node
/**
 * StardropHost | apply-farmhand-removals.js
 * Runs at server startup (via entrypoint.sh) BEFORE SMAPI loads.
 * Reads pending-farmhand-removals.json and wipes matching farmhand
 * identity fields from the active save, making the cabin unclaimed.
 */

const fs   = require('fs');
const path = require('path');

const PENDING    = '/home/steam/.local/share/stardrop/pending-farmhand-removals.json';
const PREFS      = '/home/steam/.config/StardewValley/startup_preferences';
const SAVES_DIR  = '/home/steam/.config/StardewValley/Saves';
const BACKUP_DIR = '/home/steam/.local/share/stardrop/backups';

function log(msg) { process.stdout.write(`[FarmhandRemoval] ${msg}\n`); }

if (!fs.existsSync(PENDING)) process.exit(0);

let pending;
try { pending = JSON.parse(fs.readFileSync(PENDING, 'utf-8')); } catch {
  log('Could not parse pending file — skipping'); process.exit(0);
}
if (!Array.isArray(pending) || !pending.length) {
  try { fs.unlinkSync(PENDING); } catch {}
  process.exit(0);
}

// Find the active save folder name
function getSelectedSave() {
  try {
    const prefs = fs.readFileSync(PREFS, 'utf-8');
    const m = prefs.match(/<saveFolderName>([^<]+)<\/saveFolderName>/);
    if (m?.[1]?.trim()) return m[1].trim();
  } catch {}
  try {
    const dirs = fs.readdirSync(SAVES_DIR, { withFileTypes: true })
      .filter(d => d.isDirectory()).map(d => d.name);
    return dirs[0] || null;
  } catch { return null; }
}

const saveName = getSelectedSave();
if (!saveName) { log('No active save found — skipping'); process.exit(0); }

const saveFile = path.join(SAVES_DIR, saveName, saveName);
if (!fs.existsSync(saveFile)) {
  log(`Save file not found: ${saveFile} — skipping`); process.exit(0);
}

// Backup before modifying
try {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const now = new Date();
  const dd = String(now.getUTCDate()).padStart(2,'0');
  const mm = String(now.getUTCMonth()+1).padStart(2,'0');
  const ts = `D${dd}-${mm}-${now.getUTCFullYear()}-T${String(now.getUTCHours()).padStart(2,'0')}-${String(now.getUTCMinutes()).padStart(2,'0')}-${String(now.getUTCSeconds()).padStart(2,'0')}`;
  const backupPath = path.join(BACKUP_DIR, `${saveName}-pre-farmhand-removal-${ts}.bak`);
  fs.copyFileSync(saveFile, backupPath);
  log(`Backup: ${backupPath}`);
} catch (e) { log(`Warning: backup failed — ${e.message}`); }

let xml = fs.readFileSync(saveFile, 'utf-8');
let anyModified = false;

for (const { ownerName, tileX, tileY } of pending) {
  log(`Removing farmhand "${ownerName}" at tile (${tileX}, ${tileY})…`);
  let found = false;

  // Match each Cabin building block, identify by tile position, wipe farmhand identity
  xml = xml.replace(
    /(<Building[^>]*xsi:type="Cabin"[^>]*>)([\s\S]*?)(<\/Building>)/g,
    (full, open, inner, close) => {
      if (found) return full;
      if (!inner.includes(`<tileX>${tileX}</tileX>`) ||
          !inner.includes(`<tileY>${tileY}</tileY>`)) return full;

      found = true;
      // Wipe name and UniqueMultiplayerID within the <farmhand> block only
      const wiped = inner.replace(
        /(<farmhand>[\s\S]*?)(<name>)[^<]*(<\/name>)/,
        '$1$2$3'
      ).replace(
        /(<farmhand>[\s\S]*?)(<UniqueMultiplayerID>)[^<]*(<\/UniqueMultiplayerID>)/,
        '$10$3'
      );
      return open + wiped + close;
    }
  );

  if (found) {
    log(`✅ "${ownerName}" removed`);
    anyModified = true;
  } else {
    log(`⚠️  Cabin at (${tileX}, ${tileY}) not found in save — skipping`);
  }
}

if (anyModified) {
  fs.writeFileSync(saveFile, xml, 'utf-8');
  log('✅ Save file written');
}

try { fs.unlinkSync(PENDING); } catch {}
log('Done');
