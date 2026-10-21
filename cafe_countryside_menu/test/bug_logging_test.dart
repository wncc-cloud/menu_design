// Bug Logs: the pure parts (flood guard, size cap, breadcrumbs, reading a doc).
// The Firestore writes themselves are covered by the rules test and a manual
// check against the emulator.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cafe_countryside_menu/core/logging/app_log.dart';
import 'package:cafe_countryside_menu/core/logging/client_log.dart';

void main() {
  group('LogGate', () {
    test('ignores the same error inside the window, allows it after', () {
      var t = DateTime(2026, 1, 1);
      final gate = LogGate(now: () => t);
      expect(gate.allow('ERROR', 'A', 'boom'), isTrue);
      expect(gate.allow('ERROR', 'A', 'boom'), isFalse);
      expect(gate.allow('ERROR', 'A', 'other'), isTrue);
      expect(gate.allow('WARN', 'A', 'boom'), isTrue);
      t = t.add(const Duration(seconds: 31));
      expect(gate.allow('ERROR', 'A', 'boom'), isTrue);
    });

    test('stops at the per-session cap', () {
      final gate = LogGate(sessionCap: 3);
      expect(gate.allow('ERROR', 'A', '1'), isTrue);
      expect(gate.allow('ERROR', 'A', '2'), isTrue);
      expect(gate.allow('ERROR', 'A', '3'), isTrue);
      expect(gate.allow('ERROR', 'A', '4'), isFalse);
    });
  });

  group('capUtf8', () {
    test('short text is untouched', () => expect(capUtf8('hello', 10), 'hello'));

    test('cuts to the byte budget', () {
      expect(capUtf8('a' * 50, 10), 'a' * 10);
    });

    test('never splits an emoji', () {
      final out = capUtf8('ab😀😀', 5); // each emoji is 4 bytes
      expect(out, 'ab');
      expect(out.codeUnits.every((u) => u < 0xD800 || u > 0xDFFF), isTrue);
    });
  });

  group('Breadcrumbs', () {
    setUp(Breadcrumbs.clear);

    test('empty gives null', () => expect(Breadcrumbs.render(), isNull));

    test('keeps only the newest 25 and stays under the rules cap', () {
      for (var i = 0; i < 60; i++) {
        Breadcrumbs.add('event $i ${'x' * 200}');
      }
      final out = Breadcrumbs.render()!;
      expect(out.length, lessThanOrEqualTo(Breadcrumbs.maxTotalLength));
      expect(out, contains('event 59'));
      expect(out, isNot(contains('event 10 ')));
    });

    test('logError leaves a breadcrumb', () {
      logError('Tag', 'bad thing');
      expect(Breadcrumbs.render(), contains('[Tag] ERROR: bad thing'));
    });
  });

  group('ClientLogEntry.fromMap', () {
    test('reads a full doc', () {
      final e = ClientLogEntry.fromMap('id1', {
        'type': 'WARN',
        'source': 'Menu.revalidate',
        'message': 'm',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      });
      expect(e.type, 'WARN');
      expect(e.createdAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 2)), isTrue);
    });

    test('a malformed doc does not throw', () {
      final e = ClientLogEntry.fromMap('id2', {'type': 5, 'message': null, 'createdAt': 'x'});
      expect(e.type, 'ERROR');
      expect(e.message, '');
      expect(e.createdAt, isNull);
    });
  });

  test('logClientError never throws even when Firebase is not initialised', () {
    expect(() => logClientError('Test', Exception('x')), returnsNormally);
    expect(() => logClientWarn('Test', Exception('y')), returnsNormally);
  });
}
