// Turns minified Bug Log stack lines (main.dart.js:LINE:COL) into Dart file:line:col.
// Usage: node scripts/decode-stack.mjs <logId> [path-to-.map]
//   Reads client-logs/prod-latest.json; picks the map matching the log's `build`
//   from deploy_backups/sourcemaps/ unless a map path is given. Read-only, no deps.
import fs from 'node:fs';
import path from 'node:path';

const [logId, mapArg] = process.argv.slice(2);
if (!logId) { console.error('usage: node scripts/decode-stack.mjs <logId> [map]'); process.exit(1); }
const root = path.resolve(import.meta.dirname, '..');
const data = JSON.parse(fs.readFileSync(path.join(root, 'client-logs/prod-latest.json'), 'utf8'));
const logs = Array.isArray(data) ? data : data.logs || data.items;
const log = logs.find((l) => l.id === logId);
if (!log) { console.error('log not found: ' + logId); process.exit(1); }

const safe = String(log.build || '').replace(/[:@]/g, '_');
const mapPath = mapArg || path.join(root, 'deploy_backups/sourcemaps', `${safe}.main.dart.js.map`);
if (!fs.existsSync(mapPath)) {
  console.error(`No source map for build "${log.build}" (${mapPath}). Only builds made with scripts/build-prod.ps1 after this change have one.`);
  process.exit(2);
}
const map = JSON.parse(fs.readFileSync(mapPath, 'utf8'));

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function decodeMappings(str) {
  const lines = [];
  let src = 0, sl = 0, sc = 0, name = 0;
  for (const line of str.split(';')) {
    let gc = 0;
    const segs = [];
    for (const seg of line.split(',')) {
      if (!seg) continue;
      const v = [];
      let shift = 0, val = 0;
      for (const ch of seg) {
        const d = B64.indexOf(ch);
        val += (d & 31) << shift;
        if (d & 32) { shift += 5; continue; }
        v.push(val & 1 ? -(val >> 1) : val >> 1);
        shift = 0; val = 0;
      }
      gc += v[0];
      if (v.length > 1) {
        src += v[1]; sl += v[2]; sc += v[3];
        if (v.length > 4) name += v[4];
        segs.push([gc, src, sl, sc, v.length > 4 ? name : -1]);
      }
    }
    lines.push(segs);
  }
  return lines;
}
const lines = decodeMappings(map.mappings);

function lookup(line, col) {
  const segs = lines[line - 1];
  if (!segs) return null;
  let best = null;
  for (const s of segs) { if (s[0] <= col - 1) best = s; else break; }
  if (!best) return null;
  return `${map.sources[best[1]]}:${best[2] + 1}:${best[3] + 1}` + (best[4] >= 0 ? ` (${map.names[best[4]]})` : '');
}

console.log(`${log.id}  build ${log.build}\n${log.message}\n`);
for (const raw of String(log.stackTrace || '').split('\n')) {
  const m = /main\.dart\.js:(\d+):(\d+)/.exec(raw);
  const dart = m ? lookup(+m[1], +m[2]) : null;
  console.log(dart ? `${dart}\n    <- ${raw.trim().slice(0, 90)}` : raw.trim());
}
