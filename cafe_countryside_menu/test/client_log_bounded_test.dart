// 1a-L0: bounded anonymous logs. Pure helpers (hash, bucket, id, URL cleaning),
// the write/fallback flow with an injected writer, and a sync check that the
// customer-source allow-list in the app equals the one in firestore.rules.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cafe_countryside_menu/core/logging/client_log.dart';

void main() {
  group('fnv1a32 / slotFor', () {
    test('matches the published FNV-1a test vectors', () {
      expect(fnv1a32(''), 0x811c9dc5);
      expect(fnv1a32('a'), 0xe40c292c);
      expect(fnv1a32('foobar'), 0xbf9cf968);
    });

    test('slot is stable and always 0, 1 or 2', () {
      for (final m in ['boom', 'Exception: x', '', 'ü😀', 'a' * 5000]) {
        final s = slotFor(m);
        expect(s, inInclusiveRange(0, 2));
        expect(slotFor(m), s);
      }
    });

    test('different messages spread over more than one slot', () {
      final slots = {for (var i = 0; i < 40; i++) slotFor('failure number $i')};
      expect(slots.length, greaterThan(1));
    });
  });

  group('logBucket / boundedLogId', () {
    test('bucket changes every 30 minutes (UTC epoch based)', () {
      final t0 = DateTime.fromMillisecondsSinceEpoch(1800000 * 100, isUtc: true);
      expect(logBucket(t0), 100);
      expect(logBucket(t0.add(const Duration(minutes: 29, seconds: 59))), 100);
      expect(logBucket(t0.add(const Duration(minutes: 30))), 101);
      expect(logBucket(t0.subtract(const Duration(milliseconds: 1))), 99);
    });

    test('id is <source>~<slot>~<bucket> and stable for the same failure', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1800000 * 7, isUtc: true);
      final id = boundedLogId('Checkout.submit', 'HTTP 500', now);
      expect(id, 'Checkout.submit~${slotFor('HTTP 500')}~7');
      expect(boundedLogId('Checkout.submit', 'HTTP 500', now), id);
    });
  });

  group('sanitiseAppUrl', () {
    test('keeps only the path and drops query and hash', () {
      expect(sanitiseAppUrl(Uri.parse('https://x.web.app/admin/items?edit=abc&find=q#frag')), '/admin/items');
    });

    test('masks the order-status request id', () {
      expect(sanitiseAppUrl(Uri.parse('https://x.web.app/order-status/AbCdEf1234567890xyz')), '/order-status/:id');
      expect(sanitiseAppUrl(Uri.parse('https://x.web.app/order-status/short')), '/order-status/:id');
    });

    test('masks any long opaque segment, leaves normal routes alone', () {
      expect(sanitiseAppUrl(Uri.parse('https://x.web.app/')), '/');
      expect(sanitiseAppUrl(Uri.parse('https://x.web.app/checkout')), '/checkout');
      expect(sanitiseAppUrl(Uri.parse('https://x.web.app/a/0123456789abcdef0123')), '/a/:id');
    });

    test('never exceeds the rules cap', () {
      final out = sanitiseAppUrl(Uri.parse('https://x.web.app/${'a/' * 400}'));
      expect(out.length, lessThanOrEqualTo(500));
    });
  });

  group('ClientLogRepository.write', () {
    late List<(String, Map<String, dynamic>)> calls;
    late DateTime clock;

    ClientLogRepository repo({
      ({String uid, String? email})? user,
      Future<void> Function(String, Map<String, dynamic>)? writer,
    }) {
      return ClientLogRepository(
        firestore: null,
        gate: LogGate(now: () => clock),
        currentUser: () => user,
        clock: () => clock,
        randomId: () => 'RANDOM',
        setDoc: writer ??
            (id, data) async {
              calls.add((id, data));
            },
      );
    }

    setUp(() {
      calls = [];
      clock = DateTime.fromMillisecondsSinceEpoch(1800000 * 9, isUtc: true);
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('anonymous visitor writes ONE bounded-id doc with no user fields', () async {
      final id = repo().write(type: 'ERROR', source: 'Checkout.submit', message: 'HTTP 500');
      await settle();
      expect(id, 'Checkout.submit~${slotFor('HTTP 500')}~9');
      expect(calls, hasLength(1));
      expect(calls.single.$1, id);
      expect(calls.single.$2['userId'], isNull);
      expect(calls.single.$2['userEmail'], isNull);
    });

    test('signed-in admin tries a random id first', () async {
      final id = repo(user: (uid: 'u1', email: 'a@b.c')).write(type: 'ERROR', source: 'Settings.save', message: 'm');
      await settle();
      expect(id, 'RANDOM');
      expect(calls.single.$1, 'RANDOM');
      expect(calls.single.$2['userId'], 'u1');
    });

    test('permission-denied on the admin path retries ONCE on the bounded path', () async {
      final seen = <String>[];
      final r = repo(
        user: (uid: 'u1', email: 'a@b.c'),
        writer: (id, data) async {
          seen.add(id);
          if (id == 'RANDOM') throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
        },
      );
      r.write(type: 'ERROR', source: 'Checkout.submit', message: 'x');
      await settle();
      await settle();
      expect(seen, ['RANDOM', 'Checkout.submit~${slotFor('x')}~9']);
    });

    test('a denied or duplicate bounded write is swallowed and never retried', () async {
      var n = 0;
      final r = repo(
        writer: (id, data) async {
          n++;
          throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
        },
      );
      expect(() => r.write(type: 'ERROR', source: 'Checkout.submit', message: 'x'), returnsNormally);
      await settle();
      await settle();
      expect(n, 1);
    });

    test('a failing bounded retry after the admin path is also swallowed', () async {
      var n = 0;
      final r = repo(
        user: (uid: 'u1', email: null),
        writer: (id, data) async {
          n++;
          throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
        },
      );
      r.write(type: 'ERROR', source: 'Settings.save', message: 'x');
      await settle();
      await settle();
      expect(n, 2);
    });

    test('a synchronous writer error never escapes write()', () {
      final r = repo(writer: (id, data) => throw StateError('boom'));
      expect(() => r.write(type: 'ERROR', source: 'Checkout.submit', message: 'x'), returnsNormally);
    });

    test('doc carries the build id only when one was compiled in, capped at 80 bytes', () async {
      final r = repo();
      r.write(type: 'ERROR', source: 'Checkout.submit', message: 'a');
      await settle();
      // No --dart-define=BUILD_ID in tests.
      expect(calls.single.$2.containsKey('build'), isFalse);
      expect(capBuildId('abc1234+wip@2026-10-21T10:00'), 'abc1234+wip@2026-10-21T10:00');
      expect(capBuildId('x' * 200)!.length, 80);
      expect(capBuildId(''), isNull);
    });

    test('appUrl written is sanitised', () async {
      repo().write(type: 'ERROR', source: 'Checkout.submit', message: 'a');
      await settle();
      expect((calls.single.$2['appUrl'] as String).contains('?'), isFalse);
    });

    test('only allow-listed types are written', () {
      expect(repo().write(type: 'INFO', source: 'Checkout.submit', message: 'a'), isNull);
    });
  });

  group('allow-list sync with firestore.rules', () {
    test('kCustomerLogSources equals the list inside boundedLogOk()', () {
      final rules = File('firestore.rules').readAsStringSync();
      final fn = RegExp(r'function boundedLogOk\([^)]*\)\s*\{([\s\S]*?)\n    \}').firstMatch(rules);
      expect(fn, isNotNull, reason: 'boundedLogOk() not found in firestore.rules');
      final list = RegExp(r"d\.source in \[([\s\S]*?)\]").firstMatch(fn!.group(1)!);
      expect(list, isNotNull, reason: 'allow-list not found in boundedLogOk()');
      final inRules = RegExp(r"'([^']+)'").allMatches(list!.group(1)!).map((m) => m.group(1)!).toSet();
      expect(inRules, kCustomerLogSources);
      expect(kCustomerLogSources, hasLength(16));
    });

    test('every customer source is an actual source used by the app code', () {
      final code = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final s in kCustomerLogSources) {
        expect(code.contains("'$s'"), isTrue, reason: 'source $s is not used anywhere in lib/');
      }
    });
  });
}
