// Checks that fnv1a32 (lib/core/logging/log_id.dart) gives the same result when
// compiled to JavaScript (what customers' phones run) as an exact BigInt
// reference. Run from cafe_countryside_menu/:  node tool/check_log_hash_js.mjs
import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dir = mkdtempSync(join(tmpdir(), 'loghash-'));
const out = join(dir, 'probe.js');
const sh = process.platform === 'win32';
execFileSync('dart', ['compile', 'js', 'tool/log_hash_probe.dart', '-o', out, '-O1'], { stdio: 'inherit', shell: sh });
const printed = execFileSync('node', [out], { encoding: 'utf8' }).trim().split('\n').pop();
const got = JSON.parse(printed);

const inputs = [
  '', 'a', 'foobar', 'boom', 'Exception: SocketException: Failed host lookup',
  'FirebaseException: [cloud_firestore/unavailable] The service is currently unavailable.',
  `ü😀 ${'z'.repeat(3000)}`,
  ...Array.from({ length: 300 }, (_, i) => `failure number ${i}: ${'x'.repeat(i)}`),
];
function ref(s) {
  let h = 0x811c9dc5n;
  for (const b of Buffer.from(s, 'utf8')) h = ((h ^ BigInt(b)) * 0x01000193n) & 0xffffffffn;
  return Number(h);
}
let bad = 0;
inputs.forEach((s, i) => { if (got[i] !== ref(s)) { bad++; console.log(`MISMATCH #${i}: js=${got[i]} ref=${ref(s)}`); } });
console.log(bad ? `${bad} mismatches` : `OK: ${inputs.length} inputs identical in dart2js and BigInt reference`);
process.exit(bad ? 1 : 0);
