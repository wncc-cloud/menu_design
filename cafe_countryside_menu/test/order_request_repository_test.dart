// phase_plan/phase11_5.md — dedicated tests for the Firestore REST API
// typed-value envelope encode/decode, independent of a real HTTP
// round-trip. lines[] (an array of maps) is the trickiest shape to get
// wrong — covered explicitly, not just assumed from the simpler cases.
import 'package:flutter_test/flutter_test.dart';
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';

void main() {
  group('encodeFirestoreValue', () {
    test('String', () {
      expect(encodeFirestoreValue('hello'), {'stringValue': 'hello'});
    });

    test('bool', () {
      expect(encodeFirestoreValue(true), {'booleanValue': true});
      expect(encodeFirestoreValue(false), {'booleanValue': false});
    });

    test('int', () {
      expect(encodeFirestoreValue(30000), {'integerValue': '30000'});
    });

    test('double', () {
      expect(encodeFirestoreValue(4550.5), {'doubleValue': 4550.5});
    });

    test('null', () {
      expect(encodeFirestoreValue(null), {'nullValue': null});
    });

    test('DateTime becomes an ISO-8601 UTC timestampValue', () {
      final dt = DateTime.utc(2026, 8, 28, 12, 0, 0);
      final encoded = encodeFirestoreValue(dt);
      expect(encoded.keys.single, 'timestampValue');
      expect(encoded['timestampValue'], '2026-08-28T12:00:00.000Z');
    });

    test('a flat list of strings', () {
      final encoded = encodeFirestoreValue(['a', 'b']);
      expect(encoded, {
        'arrayValue': {
          'values': [
            {'stringValue': 'a'},
            {'stringValue': 'b'},
          ],
        },
      });
    });

    test('a map', () {
      final encoded = encodeFirestoreValue({'a': 1, 'b': 'x'});
      expect(encoded, {
        'mapValue': {
          'fields': {
            'a': {'integerValue': '1'},
            'b': {'stringValue': 'x'},
          },
        },
      });
    });

    test('an array of maps (the lines[] shape) — the trickiest case', () {
      final line = {
        'menuItemId': 'm1',
        'name': 'Pizza',
        'unitPricePaise': 30000,
        'quantity': 1,
        'notes': null,
        'requiresKitchen': true,
        'readyNow': true,
      };
      final encoded = encodeFirestoreValue([line]);

      final values = (encoded['arrayValue'] as Map)['values'] as List;
      expect(values, hasLength(1));
      final mapValue = values.single as Map;
      expect(mapValue.keys.single, 'mapValue');
      final fields = (mapValue['mapValue'] as Map)['fields'] as Map;
      expect(fields['menuItemId'], {'stringValue': 'm1'});
      expect(fields['unitPricePaise'], {'integerValue': '30000'});
      expect(fields['notes'], {'nullValue': null});
      expect(fields['requiresKitchen'], {'booleanValue': true});
    });
  });

  group('decodeFirestoreValue', () {
    test('String', () {
      expect(decodeFirestoreValue({'stringValue': 'hello'}), 'hello');
    });

    test('bool', () {
      expect(decodeFirestoreValue({'booleanValue': true}), isTrue);
    });

    test('integerValue parses back to a Dart int', () {
      expect(decodeFirestoreValue({'integerValue': '30000'}), 30000);
      expect(decodeFirestoreValue({'integerValue': '30000'}), isA<int>());
    });

    test('doubleValue', () {
      expect(decodeFirestoreValue({'doubleValue': 4550.5}), 4550.5);
    });

    test('nullValue', () {
      expect(decodeFirestoreValue({'nullValue': null}), isNull);
    });

    test('timestampValue parses back to a DateTime', () {
      final decoded = decodeFirestoreValue({'timestampValue': '2026-08-28T12:00:00.000Z'});
      expect(decoded, isA<DateTime>());
      expect((decoded as DateTime).toUtc(), DateTime.utc(2026, 8, 28, 12, 0, 0));
    });

    test('a full round trip through encode then decode for a request-shaped payload', () {
      final original = {
        'shortCode': '1234',
        'customerName': 'Rahul',
        'tableNumber': '',
        'lines': [
          {
            'menuItemId': 'm1',
            'name': 'Pizza',
            'unitPricePaise': 30000,
            'quantity': 2,
            'notes': null,
            'requiresKitchen': true,
            'readyNow': true,
          },
        ],
        'status': 'PENDING',
        'claimedAt': null,
        'linkedOrderNumber': null,
      };

      final encoded = original.map((key, value) => MapEntry(key, encodeFirestoreValue(value)));
      final decoded = encoded.map((key, value) => MapEntry(key, decodeFirestoreValue(value)));

      expect(decoded, original);
    });
  });
}
