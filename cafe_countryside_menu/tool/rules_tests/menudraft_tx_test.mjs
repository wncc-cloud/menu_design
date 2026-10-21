// Plan phase1a 1a-0(f): a TRANSACTION write to menuDraft/data, as
// DraftRepository.updateDraft does it (begin -> read in tx -> commit with a
// field-masked update + exists precondition), passes the existing admin rule;
// non-admins are refused; other fields are untouched; a concurrent change makes
// the older transaction fail (which the SDK turns into a retry of `apply`).
//
// Run from cafe_countryside_menu/:
//   firebase emulators:exec --only firestore --project demo-menu-rules "node tool/rules_tests/menudraft_tx_test.mjs"

const HOST = process.env.FIRESTORE_EMULATOR_HOST;
if (!HOST) { console.error('Run via `firebase emulators:exec`.'); process.exit(2); }
const PROJECT = process.env.GCLOUD_PROJECT || 'demo-menu-rules';
const DB = `projects/${PROJECT}/databases/(default)/documents`;
const API = `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const as = (uid) => ({ Authorization: `Bearer ${b64({ alg: 'none' })}.${b64({
  iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, sub: uid, user_id: uid, email: `${uid}@example.com`,
  firebase: { identities: {}, sign_in_provider: 'google.com' } })}.` });
const OWNER = { Authorization: 'Bearer owner' };

const S = (v) => ({ stringValue: v });
const B = (v) => ({ booleanValue: v });
const items = (...names) => ({ arrayValue: { values: names.map((n) => ({ mapValue: { fields: { id: S(n), name: S(n), sectionId: S('s1') } } })) } });
const post = async (url, headers, body, ms = 8000) => {
  const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body), signal: AbortSignal.timeout(ms) });
  return { status: res.status, json: await res.json().catch(() => ({})) };
};
const begin = (h) => post(`${API}:beginTransaction`, h, { options: { readWrite: {} } }).then((r) => r.json.transaction);
// The SDK reads inside a transaction with batchGet + the transaction id.
const readInTx = async (h, tx) => {
  try {
    const r = await post(`${API}:batchGet`, h, { documents: [`${DB}/menuDraft/data`], transaction: tx }, 6000);
    return r.status;
  } catch (e) { return 'timeout'; }
};
const commitTx = (h, tx, itemsValue) => post(`${API}:commit`, h, {
  transaction: tx,
  writes: [{
    update: { name: `${DB}/menuDraft/data`, fields: { items: itemsValue, updatedBy: S('tester') } },
    updateMask: { fieldPaths: ['items', 'updatedBy'] },
    currentDocument: { exists: true },
  }],
});
const seed = (path, fields) => post(`${API}:commit`, OWNER, { writes: [{ update: { name: `${DB}/${path}`, fields } }] });
const getDraft = async () => (await (await fetch(`${API}/menuDraft/data`, { headers: OWNER })).json()).fields;

let pass = 0; const bad = [];
const ok = (name, cond, extra = '') => { if (cond) { pass++; console.log(`  PASS ${name}`); } else { bad.push(name + ' ' + extra); console.log(`  FAIL ${name} ${extra}`); } };

await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
await seed('admins/owner1', { active: B(true), role: S('owner') });
await seed('admins/staff1', { active: B(true), role: S('staff') });
const resetDraft = () => seed('menuDraft/data', { items: items('a', 'b'), updatedBy: S('seed'), lastPublishedAt: { timestampValue: '2026-01-01T00:00:00Z' } });

console.log('\n=== transaction write passes the admin rule ===');
for (const uid of ['owner1', 'staff1']) {
  await resetDraft();
  const h = as(uid); const tx = await begin(h);
  ok(`${uid}: begin transaction`, !!tx);
  ok(`${uid}: read inside the transaction`, (await readInTx(h, tx)) === 200);
  const c = await commitTx(h, tx, items('a', 'b', 'c'));
  ok(`${uid}: commit field-masked update`, c.status === 200, `got ${c.status}`);
}

console.log('\n=== non-admin and anonymous are refused ===');
await resetDraft();
for (const [name, h] of [['signed-in non-admin', as('plain1')], ['anonymous', {}]]) {
  const tx = await begin(h);
  const c = tx ? await commitTx(h, tx, items('hacked')) : { status: 'no-tx' };
  ok(`${name}: refused`, c.status === 403 || c.status === 'no-tx' || c.status === 400, `got ${c.status}`);
}
ok('draft untouched after refusals', (await getDraft()).items.arrayValue.values.length === 2);

console.log('\n=== field-level: other fields are never clobbered ===');
await resetDraft();
{
  const h = as('owner1'); const tx = await begin(h); await readInTx(h, tx);
  await commitTx(h, tx, items('a', 'b', 'c'));
  const f = await getDraft();
  ok('lastPublishedAt survives', f.lastPublishedAt?.timestampValue === '2026-01-01T00:00:00Z');
  ok('items replaced', f.items.arrayValue.values.length === 3);
  ok('updatedBy set', f.updatedBy.stringValue === 'tester');
}

console.log('\n=== exists:true precondition: no draft -> refused, nothing created ===');
await fetch(`${API}/menuDraft/data`, { method: 'DELETE', headers: OWNER });
{
  const h = as('owner1'); const tx = await begin(h);
  const c = await commitTx(h, tx, items('x'));
  ok('update of a missing draft fails (SDK reports not-found; updateDraft reads first and returns noDraft)', c.status === 404 || c.status === 403 || c.status === 400, `got ${c.status}`);
  const res = await fetch(`${API}/menuDraft/data`, { headers: OWNER });
  ok('no document was created', res.status === 404);
}

console.log('\n=== contention: a concurrent change makes the older transaction fail ===');
await resetDraft();
{
  const h = as('owner1');
  const txA = await begin(h); await readInTx(h, txA); // admin A read the draft
  // another writer (the live sold-out switch) changes the draft meanwhile
  const sold = await post(`${API}:commit`, as('staff1'), { writes: [{
    update: { name: `${DB}/menuDraft/data`, fields: { updatedBy: S('sold-out-switch') } },
    updateMask: { fieldPaths: ['updatedBy'] }, currentDocument: { exists: true } }] }).catch((e) => ({ status: 'timeout:' + e.name }));
  const cA = await commitTx(h, txA, items('from-A')).catch((e) => ({ status: 'timeout:' + e.name }));
  const f = await getDraft();
  // Exactly one of the two writers wins and the stored state is the winner's:
  // never a silent overwrite of the loser's change by a stale read.
  const aWins = cA.status === 200 && sold.status !== 200 && f.updatedBy.stringValue === 'tester';
  const soldWins = sold.status === 200 && cA.status !== 200 && f.updatedBy.stringValue === 'sold-out-switch';
  ok('exactly one writer wins and the stored state matches it (no lost update)', aWins || soldWins,
    `A=${cA.status} sold=${sold.status} updatedBy=${f.updatedBy.stringValue}`);
  console.log(`    (observed: concurrent writer ${sold.status}, older transaction ${cA.status})`);
}

console.log(`\n${pass} passed, ${bad.length} failed`);
if (bad.length) { console.log(bad.map((b) => ' - ' + b).join('\n')); process.exit(1); }
