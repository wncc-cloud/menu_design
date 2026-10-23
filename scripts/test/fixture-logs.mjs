// Shared by summarize.test.mjs and seed-logs.mjs: a realistic mix of Bug Logs
// (customer = userId null, admin = userId set). Times are ISO so they can be
// written to the Firestore emulator and read back as IST strings.
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
const WINDOWS = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36';

const log = (id, over) => ({
  id, type: 'ERROR', source: 'Checkout.submit', message: 'x', userAgent: ANDROID, userId: null,
  build: 'abc1234@2026-10-22T11:10', createdAt: '2026-10-22T10:00:00.000Z', ...over,
});

export const FIXTURE = [
  // The same checkout failure, three customers, ids and numbers differ.
  log('Checkout.submit~0~1', { message: 'OrderRequest 403 for request AbCdEfGhIjKlMnOpQrSt123 table 4', createdAt: '2026-10-22T10:00:00.000Z', userAgent: ANDROID }),
  log('Checkout.submit~1~2', { message: 'OrderRequest 403 for request ZyXwVuTsRqPoNmLkJiHg987 table 12', createdAt: '2026-10-22T10:20:00.000Z', userAgent: IPHONE }),
  log('Checkout.submit~2~3', { message: 'OrderRequest 403 for request QqWwEeRrTtYyUuIiOoPp555 table 7', createdAt: '2026-10-22T10:40:00.000Z', userAgent: IPHONE }),
  // A recovered warning, one customer.
  log('Menu.revalidate~0~1', { type: 'WARN', source: 'Menu.revalidate', message: 'SocketException: Failed host lookup', createdAt: '2026-10-22T09:00:00.000Z' }),
  // Admin errors.
  log('admin-1', { source: 'Draft.update', message: 'permission-denied', userId: 'uid-owner', userEmail: 'owner@test.local', userAgent: WINDOWS, createdAt: '2026-10-22T11:00:00.000Z' }),
  log('admin-2', { source: 'Draft.update', message: 'permission-denied', userId: 'uid-owner', userEmail: 'owner@test.local', userAgent: WINDOWS, createdAt: '2026-10-22T11:05:00.000Z' }),
  // Same source, different error code => a separate problem.
  log('admin-3', { source: 'Settings.save', message: 'unavailable', errorCode: 'unavailable', userId: 'uid-owner', userAgent: WINDOWS, createdAt: '2026-10-22T11:10:00.000Z', build: 'def5678+wip@2026-10-22T12:00' }),
];
