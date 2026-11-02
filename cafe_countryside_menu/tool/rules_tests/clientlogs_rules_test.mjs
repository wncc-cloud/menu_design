// Rules tests for clientLogs (Bug Logs), plan phase1a step 1a-L0 / section E.3c.
//
// Run from cafe_countryside_menu/:
//   firebase emulators:exec --only firestore --project demo-menu-rules "node tool/rules_tests/clientlogs_rules_test.mjs"
//
// No npm packages: plain fetch against the Firestore emulator's REST API.
//  * `Authorization: Bearer owner` bypasses rules (used only to seed/inspect).
//  * An unsigned JWT acts as a signed-in user (the emulator accepts alg:none).
//  * No Authorization header = anonymous customer.
// Writes use :commit with a REQUEST_TIME transform so `createdAt == request.time`
// holds, exactly like the app's FieldValue.serverTimestamp().

const HOST = process.env.FIRESTORE_EMULATOR_HOST;
if (!HOST) {
  console.error('FIRESTORE_EMULATOR_HOST is not set: run via `firebase emulators:exec`.');
  process.exit(2);
}
const PROJECT = process.env.GCLOUD_PROJECT || 'demo-menu-rules';
const DB = `projects/${PROJECT}/databases/(default)/documents`;
const BASE = `http://${HOST}/v1/${DB}`;

const SOURCES = [
  'FlutterError', 'PlatformDispatcher', 'runZonedGuarded', 'Checkout.submit', 'Checkout.appCheck',
  'Checkout.freshBusiness', 'Checkout.revalidateCart', 'OrderRequest.create', 'OrderRequest.fetchCafeOpen',
  'OrderRequest.getRequest', 'OrderStatus.poll', 'PosAppCheck.activate', 'PosAppCheck.getToken',
  'Menu.revalidate', 'MenuCache.read', 'LoginPage.signIn', 'Popup.missingExtra',
];

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt = (uid, email = `${uid}@example.com`) =>
  `${b64({ alg: 'none', typ: 'JWT' })}.${b64({
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, sub: uid, user_id: uid, email,
    firebase: { identities: {}, sign_in_provider: 'google.com' },
  })}.`;

const OWNER = { Authorization: 'Bearer owner' };
const as = (uid) => ({ Authorization: `Bearer ${jwt(uid)}` });
const ANON = {};

// ---- value helpers ----------------------------------------------------------
const S = (v) => (v === null ? { nullValue: null } : { stringValue: String(v) });
const I = (v) => ({ integerValue: String(v) });
const T = (d) => ({ timestampValue: d.toISOString() });

function logFields(over = {}) {
  const base = {
    type: S('ERROR'), source: S('Checkout.submit'), message: S('HTTP 500'), stackTrace: S(null),
    userId: S(null), userEmail: S(null), userAgent: S('test-agent'), appUrl: S('/checkout'),
    expireAt: T(new Date(Date.now() + 7 * 864e5)), schemaVersion: I(1),
  };
  const f = { ...base, ...over };
  for (const k of Object.keys(f)) if (f[k] === undefined) delete f[k];
  return f;
}

async function commit(headers, writes) {
  const res = await fetch(`http://${HOST}/v1/${DB}:commit`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify({ writes }),
  });
  return res.status;
}

/** create-only (precondition exists:false), createdAt = request time. */
const createLog = (headers, id, fields = logFields(), { precondition = true, serverTime = true } = {}) =>
  commit(headers, [{
    update: { name: `${DB}/clientLogs/${id}`, fields },
    ...(serverTime ? { updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }] } : {}),
    ...(precondition ? { currentDocument: { exists: false } } : {}),
  }]);

const seed = (path, fields) => commit(OWNER, [{ update: { name: `${DB}/${path}`, fields } }]);
const getDoc = async (headers, path) => (await fetch(`${BASE}/${path}`, { headers })).status;
const listLogs = async (headers) => (await fetch(`${BASE}/clientLogs?pageSize=1000`, { headers }));
const countLogs = async () => ((await (await listLogs(OWNER)).json()).documents ?? []).length;
const deleteDoc = async (headers, path) => (await fetch(`${BASE}/${path}`, { method: 'DELETE', headers })).status;

// ---- tiny harness -----------------------------------------------------------
let pass = 0;
const failures = [];
function expectOk(name, status) {
  if (status === 200) { pass++; console.log(`  PASS [ALLOW] ${name}`); }
  else { failures.push(`${name}: expected 200, got ${status}`); console.log(`  FAIL [ALLOW] ${name} (got ${status})`); }
}
function expectDenied(name, status) {
  if (status === 403 || status === 409) { pass++; console.log(`  PASS [DENY ] ${name} (${status})`); }
  else { failures.push(`${name}: expected 403/409, got ${status}`); console.log(`  FAIL [DENY ] ${name} (got ${status})`); }
}
const bucketNow = () => Math.floor(Date.now() / 1800000);
const bid = (source, slot, bucket) => `${source}~${slot}~${bucket}`;

// ---- tests ------------------------------------------------------------------
async function main() {
  // Reset emulator data.
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });

  await seed('admins/owner1', { active: { booleanValue: true }, role: S('owner') });
  await seed('admins/mgr1', { active: { booleanValue: true }, role: S('manager') });
  await seed('admins/staff1', { active: { booleanValue: true }, role: S('staff') });
  await seed('admins/off1', { active: { booleanValue: false }, role: S('owner') });
  // 'plain1' is signed in but NOT an admin (no admins doc).

  const b = bucketNow();

  console.log('\n=== 1. Bounded path (anonymous customer) ===');
  expectOk('slot 0, current bucket', await createLog(ANON, bid('Checkout.submit', 0, b)));
  expectOk('slot 1, current bucket', await createLog(ANON, bid('Checkout.submit', 1, b)));
  expectOk('slot 2, current bucket', await createLog(ANON, bid('Checkout.submit', 2, b)));
  expectOk('bucket -1 (clock skew)', await createLog(ANON, bid('Checkout.submit', 0, b - 1)));
  expectOk('bucket +1 (clock skew)', await createLog(ANON, bid('Checkout.submit', 0, b + 1)));
  expectOk('WARN type on another allow-listed source', await createLog(ANON, bid('MenuCache.read', 0, b), logFields({ type: S('WARN'), source: S('MenuCache.read') })));
  expectOk('with optional errorCode/breadcrumbs/build', await createLog(ANON, bid('OrderStatus.poll', 0, b), logFields({
    source: S('OrderStatus.poll'), errorCode: S('unavailable'), breadcrumbs: S('-1.0s [x] y'), build: S('abc1234+wip@2026-10-21T10:00'),
  })));

  console.log('\n=== 2. Bounded path refusals ===');
  expectDenied('duplicate id (create precondition)', await createLog(ANON, bid('Checkout.submit', 0, b)));
  expectDenied('duplicate id via plain set (= update)', await createLog(ANON, bid('Checkout.submit', 0, b), logFields(), { precondition: false }));
  expectDenied('bucket +2', await createLog(ANON, bid('Checkout.submit', 1, b + 2)));
  expectDenied('bucket -2', await createLog(ANON, bid('Checkout.submit', 1, b - 2)));
  expectDenied('bucket 5 buckets off', await createLog(ANON, bid('Checkout.submit', 1, b + 5)));
  expectDenied('bucket not a number', await createLog(ANON, 'Checkout.submit~0~abc'));
  expectDenied('bucket empty', await createLog(ANON, 'Checkout.submit~0~'));
  expectDenied('unknown source', await createLog(ANON, bid('Evil.source', 0, b), logFields({ source: S('Evil.source') })));
  expectDenied('admin-only source on anonymous path', await createLog(ANON, bid('Settings.save', 0, b), logFields({ source: S('Settings.save') })));
  expectDenied('random id on anonymous path', await createLog(ANON, 'RandomId12345'));
  expectDenied('slot 3', await createLog(ANON, bid('Checkout.submit', 3, b)));
  expectDenied('slot -1', await createLog(ANON, bid('Checkout.submit', -1, b)));
  expectDenied('source in id differs from source field', await createLog(ANON, bid('Checkout.appCheck', 0, b)));
  expectDenied('extra part in id', await createLog(ANON, `${bid('Checkout.submit', 2, b)}~x`));
  expectDenied('foreign userId from anonymous', await createLog(ANON, bid('Checkout.appCheck', 0, b), logFields({ source: S('Checkout.appCheck'), userId: S('someoneElse') })));
  expectDenied('userEmail without userId', await createLog(ANON, bid('Checkout.appCheck', 1, b), logFields({ source: S('Checkout.appCheck'), userEmail: S('victim@example.com') })));

  console.log('\n=== 3. Shape rules (apply to both paths) ===');
  const sh = (name, over, id = bid('Checkout.freshBusiness', 0, b)) =>
    createLog(ANON, id, logFields({ source: S('Checkout.freshBusiness'), ...over })).then((s) => expectDenied(name, s));
  await sh('type INFO', { type: S('INFO') });
  await sh('message over 2000', { message: S('x'.repeat(2001)) });
  await sh('build over 80', { build: S('x'.repeat(81)) });
  await sh('build not a string', { build: I(5) });
  await sh('unknown extra key', { admin: { booleanValue: true } });
  await sh('missing userAgent', { userAgent: undefined });
  await sh('schemaVersion 2', { schemaVersion: I(2) });
  await sh('appUrl over 500', { appUrl: S('/' + 'a'.repeat(500)) });
  await sh('expireAt 9 days out', { expireAt: T(new Date(Date.now() + 9 * 864e5)) });
  await sh('expireAt in the past', { expireAt: T(new Date(Date.now() - 1000)) });
  expectDenied('client-chosen createdAt (not request time)', await createLog(ANON, bid('Checkout.freshBusiness', 1, b),
    logFields({ source: S('Checkout.freshBusiness'), createdAt: T(new Date(Date.now() - 864e5)) }), { serverTime: false }));
  expectOk('same doc is fine when the shape is valid', await createLog(ANON, bid('Checkout.freshBusiness', 2, b), logFields({ source: S('Checkout.freshBusiness'), build: S('x'.repeat(80)) })));

  console.log('\n=== 4. Admin path ===');
  expectOk('owner: random id, own userId, any source', await createLog(as('owner1'), 'adminRandom1', logFields({ source: S('Settings.save'), userId: S('owner1'), userEmail: S('owner1@example.com') })));
  expectOk('manager: random id', await createLog(as('mgr1'), 'adminRandom2', logFields({ source: S('ItemForm.imageUpload'), userId: S('mgr1') })));
  expectOk('staff (isAdmin) random id', await createLog(as('staff1'), 'adminRandom3', logFields({ source: S('BulkImport.parse'), userId: S('staff1') })));
  expectDenied('admin random id but userId of someone else', await createLog(as('owner1'), 'adminRandom4', logFields({ userId: S('mgr1') })));
  expectDenied('admin random id with userId null', await createLog(as('owner1'), 'adminRandom5', logFields({ userId: S(null) })));
  expectDenied('inactive admin random id', await createLog(as('off1'), 'adminRandom6', logFields({ userId: S('off1') })));
  expectOk('admin may also use the bounded path', await createLog(as('owner1'), bid('LoginPage.signIn', 0, b), logFields({ source: S('LoginPage.signIn'), userId: S('owner1') })));

  console.log('\n=== 5. Signed-in NON-admin ===');
  expectDenied('random id (unbounded) refused', await createLog(as('plain1'), 'plainRandom1', logFields({ userId: S('plain1') })));
  expectOk('bounded id accepted, own userId + email', await createLog(as('plain1'), bid('Menu.revalidate', 0, b), logFields({ source: S('Menu.revalidate'), userId: S('plain1'), userEmail: S('plain1@example.com') })));
  expectDenied('bounded id but foreign userId', await createLog(as('plain1'), bid('Menu.revalidate', 1, b), logFields({ source: S('Menu.revalidate'), userId: S('owner1') })));
  expectOk('bounded id, no user fields', await createLog(as('plain1'), bid('Menu.revalidate', 2, b), logFields({ source: S('Menu.revalidate') })));
  expectDenied('admin-only source via bounded id refused', await createLog(as('plain1'), bid('Settings.save', 0, b), logFields({ source: S('Settings.save'), userId: S('plain1') })));

  console.log('\n=== 6. Read / update / delete ===');
  const any = bid('Checkout.submit', 0, b);
  expectDenied('anonymous get', await getDoc(ANON, `clientLogs/${any}`));
  expectDenied('anonymous list', (await listLogs(ANON)).status);
  expectDenied('non-admin get', await getDoc(as('plain1'), `clientLogs/${any}`));
  expectOk('admin get', await getDoc(as('staff1'), `clientLogs/${any}`));
  expectOk('admin list', (await listLogs(as('owner1'))).status);
  expectDenied('update refused even for owner', await commit(as('owner1'), [{
    update: { name: `${DB}/clientLogs/${any}`, fields: logFields() },
    updateMask: { fieldPaths: ['message'] }, currentDocument: { exists: true },
  }]));
  expectDenied('anonymous delete', await deleteDoc(ANON, `clientLogs/${any}`));
  expectDenied('staff delete', await deleteDoc(as('staff1'), `clientLogs/${any}`));
  expectOk('manager delete', await deleteDoc(as('mgr1'), `clientLogs/${any}`));
  expectOk('owner delete', await deleteDoc(as('owner1'), `clientLogs/${bid('Checkout.submit', 1, b)}`));

  console.log('\n=== 7. Spam burst (200 anonymous attempts) ===');
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  await seed('admins/owner1', { active: { booleanValue: true }, role: S('owner') });
  const attempts = [];
  const validKeys = new Set();
  for (let i = 0; i < 200; i++) {
    const kind = i % 4;
    if (kind === 0) { // valid shape, varied message, but the id space is fixed
      const src = SOURCES[i % 16], slot = i % 3, bk = b + ((i % 3) - 1);
      validKeys.add(bid(src, slot, bk));
      attempts.push(createLog(ANON, bid(src, slot, bk), logFields({ source: S(src), message: S(`unique message ${i}`) })));
    } else if (kind === 1) { // random ids
      attempts.push(createLog(ANON, `spam-${i}-${Math.random().toString(36).slice(2)}`, logFields({ message: S(`spam ${i}`) })));
    } else if (kind === 2) { // far-future bucket
      attempts.push(createLog(ANON, bid('Checkout.submit', i % 3, b + 100 + i), logFields({ message: S(`future ${i}`) })));
    } else { // unknown sources
      attempts.push(createLog(ANON, bid(`Spam${i}`, 0, b), logFields({ source: S(`Spam${i}`), message: S(`s ${i}`) })));
    }
  }
  await Promise.all(attempts);
  const stored = await countLogs();
  const cap = 16 * 3 * 48;
  if (stored === validKeys.size && stored <= cap) {
    pass++; console.log(`  PASS 200 attempts stored exactly ${stored} docs (= unique valid ids; hard cap ${cap}/day)`);
  } else {
    failures.push(`spam burst stored ${stored}, expected ${validKeys.size} (cap ${cap})`);
    console.log(`  FAIL spam burst stored ${stored}, expected ${validKeys.size}`);
  }

  console.log(`\n${pass} passed, ${failures.length} failed`);
  if (failures.length) { console.log(failures.map((f) => ' - ' + f).join('\n')); process.exit(1); }
}

main().catch((e) => { console.error(e); process.exit(2); });
