// node --test "scripts/test/*.test.mjs"
import assert from 'node:assert/strict';
import test from 'node:test';
import { deviceClass, parseArgs, shape, summarize } from '../summarize-bug-logs.mjs';
import { FIXTURE } from './fixture-logs.mjs';

test('shape blanks ids and numbers so the same failure groups together', () => {
  assert.equal(
    shape('OrderRequest 403 for request AbCdEfGhIjKlMnOpQrSt123 table 4'),
    'OrderRequest <n> for request <id> table <n>',
  );
  assert.equal(shape('first line\nsecond line 99'), 'first line');
  assert.equal(shape(undefined), '');
  assert.ok(shape('x'.repeat(500)).length <= 140);
});

test('deviceClass reads the user agent', () => {
  assert.equal(deviceClass('Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit Version/17.4 Mobile Safari/604.1'), 'iPhone Safari');
  assert.equal(deviceClass('Mozilla/5.0 (Linux; Android 14; Pixel 7) Chrome/124.0.0.0 Mobile Safari/537.36'), 'Android Chrome');
  assert.equal(deviceClass('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/155.0.0.0 Safari/537.36'), 'Windows Chrome');
  assert.equal(deviceClass('Mozilla/5.0 (Windows NT 10.0) Chrome/155 Safari/537 Edg/155'), 'Windows Edge');
  assert.equal(deviceClass(''), '? ?');
});

test('summarize groups the fixture into 4 problems, errors before warnings, frequent first', () => {
  const s = summarize(FIXTURE);
  assert.equal(s.length, 4);
  assert.deepEqual(s.map((g) => [g.type, g.source, g.count]), [
    ['ERROR', 'Checkout.submit', 3],
    ['ERROR', 'Draft.update', 2],
    ['ERROR', 'Settings.save', 1],
    ['WARN', 'Menu.revalidate', 1],
  ]);
});

test('summarize spread: device classes, customer vs admin, builds, time range', () => {
  const [checkout, draft, settings] = summarize(FIXTURE);
  assert.deepEqual([...checkout.devices].sort(), ['Android Chrome', 'iPhone Safari']);
  assert.equal(checkout.customers, 3);
  assert.equal(checkout.admins, 0);
  assert.equal(draft.admins, 2);
  assert.equal(draft.customers, 0);
  assert.deepEqual([...draft.devices], ['Windows Chrome']);
  assert.deepEqual([...settings.builds], ['def5678+wip@2026-10-22T12:00']);
  assert.equal(settings.errorCode, 'unavailable');
});

test('summarize keeps the first/last time and log ids', () => {
  const logs = FIXTURE.map((l, i) => ({ ...l, createdAtIst: `2026-10-22 1${i}:00:00 IST` }));
  const [checkout] = summarize(logs);
  assert.equal(checkout.first, '2026-10-22 10:00:00 IST');
  assert.equal(checkout.last, '2026-10-22 12:00:00 IST');
  assert.deepEqual(checkout.ids, ['Checkout.submit~0~1', 'Checkout.submit~1~2', 'Checkout.submit~2~3']);
});

test('an empty export is fine', () => {
  assert.deepEqual(summarize([]), []);
});

test('parseArgs: the number after --samples is not taken as the export name', () => {
  assert.deepEqual(parseArgs(['--samples', '3']), { target: 'prod', samples: 3 });
  assert.deepEqual(parseArgs(['emu', '--samples', '5']), { target: 'emu', samples: 5 });
  assert.deepEqual(parseArgs(['--samples', '4', 'emu']), { target: 'emu', samples: 4 });
  assert.deepEqual(parseArgs([]), { target: 'prod', samples: 2 });
});
