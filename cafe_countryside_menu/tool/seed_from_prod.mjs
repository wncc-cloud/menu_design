// Seeds the LOCAL Firestore emulator with a prod-shaped menu so the Phase 1a
// admin tools can be rehearsed (and tested) against real data shapes.
//
// Source of the menu (pick one):
//   default      unauthenticated GET of the PUBLIC document menu/current of the
//                prod project (the same read every customer's phone does; no
//                credentials). Read-only: this script never writes to prod.
//   --from-file  a local JSON file: either the Firestore REST document
//                (has "fields") or plain {"sections": [...], "items": [...]}.
//
// What it writes (emulator only, refuses any non-local host):
//   menu/current                the menu as customers see it
//   menuDraft/data              the draft, built the way DraftRepository.initFromMenu does
//   menu/lastPublishedDraft     the same draft as the "last published" snapshot (so
//                               Discard works and the change count starts at 0)
//   admins/<uid>                only with --admin-uid (role owner)
// The public document has NO hidden items/sections, so a few synthetic ones are
// added (names start with "[seed]") for the Menu-check tests.
//
// Usage (from cafe_countryside_menu/, emulator already running):
//   node tool/seed_from_prod.mjs --project why-not-cafe-menu-dev --host localhost:8080 --admin-uid <uid>
//   node tool/seed_from_prod.mjs --from-file my_menu.json --fixture-out test/fixtures/prod_menu.json
// Options: --project --host --prod-project --from-file --admin-uid --fixture-out --no-synthetic

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true]);
  return acc;
}, []));
const PROJECT = args.project || 'why-not-cafe-menu-dev';
const HOST = args.host || process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080';
const PROD_PROJECT = args['prod-project'] || 'cafe-countryside-menu';

if (!/^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(HOST)) {
  console.error(`Refusing to write to non-local host "${HOST}". This script only seeds the emulator.`);
  process.exit(2);
}

// ---- Firestore REST value <-> plain JSON ------------------------------------
function decode(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('nullValue' in v) return null;
  if ('timestampValue' in v) return { __ts: v.timestampValue };
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, decode(x)]));
  return null;
}
function encode(x) {
  if (x === null || x === undefined) return { nullValue: null };
  if (typeof x === 'string') return { stringValue: x };
  if (typeof x === 'boolean') return { booleanValue: x };
  if (typeof x === 'number') return Number.isInteger(x) ? { integerValue: String(x) } : { doubleValue: x };
  if (Array.isArray(x)) return { arrayValue: { values: x.map(encode) } };
  if (x.__ts) return { timestampValue: x.__ts };
  return { mapValue: { fields: Object.fromEntries(Object.entries(x).map(([k, v]) => [k, encode(v)])) } };
}

// ---- load the source menu ------------------------------------------------------
async function loadMenu() {
  if (args['from-file']) {
    const raw = JSON.parse(readFileSync(args['from-file'], 'utf8'));
    return raw.fields ? Object.fromEntries(Object.entries(raw.fields).map(([k, v]) => [k, decode(v)])) : raw;
  }
  const url = `https://firestore.googleapis.com/v1/projects/${PROD_PROJECT}/databases/(default)/documents/menu/current`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`public menu/current GET failed: HTTP ${res.status}`);
  const doc = await res.json();
  return Object.fromEntries(Object.entries(doc.fields).map(([k, v]) => [k, decode(v)]));
}

// ---- build the draft exactly like DraftRepository.initFromMenu ---------------
const now = { __ts: new Date().toISOString() };
const sectionToDraft = (s) => ({
  id: s.id, name: s.name, icon: '', sortOrder: s.sortOrder ?? 0, active: true,
  businessId: 'default', createdAt: now, updatedAt: now,
});
const itemToDraft = (i) => ({
  id: i.id, sectionId: i.sectionId, name: i.name, price: i.price ?? 0,
  description: i.description ?? '', ingredients: i.ingredients ?? '',
  imageUrl: i.cloudinaryImageUrl ?? '', cloudinaryPublicId: i.cloudinaryPublicId ?? '',
  active: true, isVeg: i.isVeg ?? true, isBestseller: i.isBestseller ?? false,
  available: i.available ?? true, availableFrom: i.availableFrom ?? '', availableTill: i.availableTill ?? '',
  requiresKitchen: i.requiresKitchen ?? true, noteAllowed: i.noteAllowed ?? true,
  isChefSpecial: i.isChefSpecial ?? false, chefOnly: i.chefOnly ?? false,
  sortOrder: i.sortOrder ?? 0, businessId: 'default', createdAt: now, updatedAt: now,
});

function addSynthetic(sections, items) {
  const maxSort = Math.max(-1, ...sections.map((s) => s.sortOrder));
  const hiddenSec = { ...sectionToDraft({ id: 'seed-hidden', name: '[seed] Seasonal (hidden)', sortOrder: maxSort + 1 }), active: false };
  sections.push(hiddenSec);
  const base = (id, name, sectionId, sortOrder) => itemToDraft({ id, name, sectionId, price: 150, sortOrder });
  items.push(base('seed-h1', '[seed] Pumpkin Latte', 'seed-hidden', 0));
  items.push(base('seed-h2', '[seed] Eggnog', 'seed-hidden', 1));
  const firstReal = sections.find((s) => s.active);
  if (firstReal) items.push({ ...base('seed-h3', '[seed] Hidden item', firstReal.id, 9999), active: false });
}

// ---- write to the emulator -------------------------------------------------------
const DB = `projects/${PROJECT}/databases/(default)/documents`;
async function write(path, plainFields) {
  const res = await fetch(`http://${HOST}/v1/${DB}:commit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({ writes: [{ update: { name: `${DB}/${path}`, fields: Object.fromEntries(Object.entries(plainFields).map(([k, v]) => [k, encode(v)])) } }] }),
  });
  if (!res.ok) throw new Error(`write ${path}: HTTP ${res.status} ${await res.text()}`);
}

const menu = await loadMenu();
const sections = (menu.sections || []).map(sectionToDraft);
const items = (menu.items || []).map(itemToDraft);
if (!args['no-synthetic']) addSynthetic(sections, items);

await write('menu/current', { ...menu, updatedAt: now });
await write('menuDraft/data', { sections, items, draftUpdatedAt: now, updatedBy: 'seed', lastPublishedAt: now });
await write('menu/lastPublishedDraft', { sections, items, draftUpdatedAt: now, updatedBy: 'seed', lastPublishedAt: now });
if (args['admin-uid'] && args['admin-uid'] !== true) {
  await write(`admins/${args['admin-uid']}`, { active: true, role: 'owner', email: 'seed@example.com', name: 'Seed Owner' });
}

if (args['fixture-out'] && args['fixture-out'] !== true) {
  mkdirSync(dirname(args['fixture-out']), { recursive: true });
  // Public data only; timestamps dropped so the fixture is stable.
  const strip = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => !(v && v.__ts)));
  writeFileSync(args['fixture-out'], JSON.stringify({ sections: sections.map(strip), items: items.map(strip) }, null, 1));
}

const hiddenItems = items.filter((i) => !i.active).length;
console.log(`Seeded ${HOST} (${PROJECT}): ${sections.length} sections (${sections.filter((s) => !s.active).length} hidden), ` +
  `${items.length} items (${hiddenItems} hidden), snapshot written${typeof args['admin-uid'] === 'string' ? `, admin ${args['admin-uid']}` : ''}.`);
