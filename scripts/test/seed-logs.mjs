// TEST ONLY: writes the fixture logs into the LOCAL Firestore emulator so
// fetch-bug-logs.ps1 -Emulator can be checked end to end. Refuses anything that
// is not localhost.   node scripts/test/seed-logs.mjs [port]   (default 8080)
import { FIXTURE } from './fixture-logs.mjs';

const port = Number(process.argv[2] ?? 8080);
const project = 'why-not-cafe-menu-dev';
const host = `localhost:${port}`;
if (!/^localhost:\d+$/.test(host)) throw new Error('refusing a non-local host');
const docs = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const headers = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };

const str = (v) => ({ stringValue: String(v) });
const field = (v) => (v === null || v === undefined ? { nullValue: null } : str(v));

for (const l of FIXTURE) {
  const { id, createdAt, ...rest } = l;
  const fields = { createdAt: { timestampValue: createdAt } };
  for (const [k, v] of Object.entries(rest)) fields[k] = field(v);
  const res = await fetch(`${docs}/clientLogs?documentId=${encodeURIComponent(id)}`, {
    method: 'POST', headers, body: JSON.stringify({ fields }),
  });
  if (!res.ok) throw new Error(`seed ${id}: ${res.status} ${await res.text()}`);
}
console.log(`seeded ${FIXTURE.length} logs into ${host} (${project})`);
