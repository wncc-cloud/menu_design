// Safe retry + diagnostics for OrderRequestRepository.createRequest.
// Uses a fake http client and the repository's local-emulator mode (no App
// Check, no Firebase), and captures what reaches Bug Logs.
import 'dart:convert';

import 'package:cafe_countryside_menu/core/logging/client_log.dart';
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int code, Map<String, dynamic> body, {String? date}) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json', 'date': ?date},
    );

String _httpDate(DateTime utc) {
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${wd[utc.weekday - 1]}, ${two(utc.day)} ${mo[utc.month - 1]} ${utc.year} '
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
}

Map<String, dynamic> _payload({DateTime? now}) {
  final n = now ?? DateTime.now();
  return {
    'shortCode': '1234',
    'customerName': 'Rahul',
    'customerPhone': '9876543210',
    'tableNumber': '',
    'orderNotes': '',
    'lines': [
      {'menuItemId': 'm1', 'name': 'Pizza', 'unitPricePaise': 30000, 'quantity': 1}
    ],
    'status': 'PENDING',
    'createdAt': n,
    'expiresAt': n.add(const Duration(minutes: 3)),
    'claimedAt': null,
    'claimedBy': null,
    'linkedOrderId': null,
    'linkedOrderNumber': null,
  };
}

OrderRequestRepository _repo(MockClientHandler handler) => OrderRequestRepository(
      posProjectId: 'p',
      posWebApiKey: 'k',
      businessId: 'b',
      useLocalEmulator: true,
      client: MockClient(handler),
      retryDelay: Duration.zero,
    );

void main() {
  late List<Map<String, dynamic>> logged;

  setUp(() {
    logged = [];
    OrderRequestRepository.lastServerOffset = null;
    debugClientLogs = ClientLogRepository(
      gate: LogGate(sessionCap: 1000, dedupeWindow: Duration.zero),
      currentUser: () => null,
      randomId: () => 'id${logged.length}',
      setDoc: (id, data) async => logged.add(data),
    );
  });
  tearDown(() => debugClientLogs = null);

  group('normal order', () {
    test('one request, with a client-chosen document id, no extra logs', () async {
      final calls = <http.Request>[];
      final repo = _repo((req) async {
        calls.add(req);
        return _json(200, {'name': 'projects/p/databases/(default)/documents/businesses/b/customerOrderRequests/x'});
      });
      final id = await repo.createRequest(_payload());
      expect(calls, hasLength(1));
      expect(calls.single.url.queryParameters['documentId'], id);
      expect(id, hasLength(20));
      expect(logged, isEmpty);
    });
  });

  group('network drop', () {
    test('retries once with the SAME id and succeeds; logs one WARN', () async {
      final ids = <String?>[];
      var n = 0;
      final repo = _repo((req) async {
        ids.add(req.url.queryParameters['documentId']);
        if (++n == 1) throw http.ClientException('Load failed', req.url);
        return _json(200, {'name': 'x/y'});
      });
      final id = await repo.createRequest(_payload());
      expect(n, 2);
      expect(ids[0], ids[1]);
      expect(id, ids[0]);
      expect(logged.single['type'], 'WARN');
      expect(logged.single['message'], contains('attempt1: ClientException: Load failed'));
      expect(logged.single['message'], isNot(contains('uri=')));
    });

    test('retry says already exists (409) and our order can be read: counts as placed', () async {
      var posts = 0;
      final repo = _repo((req) async {
        if (req.method == 'POST') {
          if (++posts == 1) throw http.ClientException('Failed to fetch', req.url);
          return _json(409, {'error': {'status': 'ALREADY_EXISTS', 'message': 'exists'}});
        }
        return _json(200, {'fields': {}});
      });
      final id = await repo.createRequest(_payload());
      expect(posts, 2);
      expect(id, hasLength(20));
      expect(logged.single['type'], 'WARN');
    });

    test('both tries drop and nothing can be read back: throws and logs ONE error', () async {
      final repo = _repo((req) async => throw http.ClientException('Load failed', req.url));
      await expectLater(repo.createRequest(_payload()), throwsA(isA<OrderRequestException>()));
      expect(logged, hasLength(1));
      expect(logged.single['type'], 'ERROR');
      expect(logged.single['message'], contains('attempt1'));
      expect(logged.single['message'], contains('attempt2'));
      expect(logged.single['message'], contains('shape: lines=1 name=5 phone=10'));
    });
  });

  group('403', () {
    test('wrong phone clock: retries once with server-aligned times', () async {
      final device = DateTime.now().toUtc();
      final serverNow = device.add(const Duration(minutes: 7)); // phone is 7 min slow
      final bodies = <Map<String, dynamic>>[];
      var n = 0;
      final repo = _repo((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        if (++n == 1) {
          return _json(403, {'error': {'status': 'PERMISSION_DENIED', 'message': 'Missing or insufficient permissions.'}},
              date: _httpDate(serverNow));
        }
        return _json(200, {'name': 'x/y'});
      });
      await repo.createRequest(_payload(now: device));
      expect(n, 2);
      String ts(Map<String, dynamic> b) => (b['fields']['expiresAt'] as Map)['timestampValue'] as String;
      final first = DateTime.parse(ts(bodies[0]));
      final second = DateTime.parse(ts(bodies[1]));
      expect(second.difference(first).inMinutes, inInclusiveRange(6, 7));
      // The customer saw nothing, but a WARN records that the clock was wrong.
      expect(logged.single['type'], 'WARN');
      expect(logged.single['message'], contains('clockOffsetSec=4'));
      expect(logged.single['message'], contains('PERMISSION_DENIED'));
    });

    test('rule refusal with a correct clock: NO retry, one ERROR naming the reason', () async {
      final device = DateTime.now().toUtc();
      var n = 0;
      final repo = _repo((req) async {
        n++;
        return _json(403, {'error': {'status': 'PERMISSION_DENIED', 'message': 'Missing or insufficient permissions.'}},
            date: _httpDate(device));
      });
      await expectLater(repo.createRequest(_payload()), throwsA(isA<OrderRequestException>()));
      expect(n, 1);
      expect(logged, hasLength(1));
      final msg = logged.single['message'] as String;
      expect(msg, contains('HTTP 403 PERMISSION_DENIED "Missing or insufficient permissions."'));
      expect(msg, contains('clockOffsetSec='));
      expect(msg, contains('lifeSec=180'));
    });

    test('an unreadable error body never crashes the order flow', () async {
      final repo = _repo((req) async => http.Response('<html>nope</html>', 502));
      await expectLater(repo.createRequest(_payload()), throwsA(isA<OrderRequestException>()));
      expect(logged.single['message'], contains('HTTP 502'));
    });
  });

  group('helpers', () {
    test('parseHttpDate', () {
      expect(parseHttpDate('Mon, 09 Nov 2026 11:10:37 GMT'), DateTime.utc(2026, 11, 9, 11, 10, 37));
      expect(parseHttpDate('garbage'), isNull);
    });

    test('newRequestId is 20 URL-safe characters and differs each time', () {
      final a = OrderRequestRepository.newRequestId();
      final b = OrderRequestRepository.newRequestId();
      expect(a, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
      expect(a, isNot(b));
    });

    test('shiftRequestTimes moves only createdAt and expiresAt', () {
      final p = _payload();
      final s = shiftRequestTimes(p, const Duration(minutes: 5));
      expect((s['expiresAt'] as DateTime).difference(p['expiresAt'] as DateTime), const Duration(minutes: 5));
      expect(s['customerName'], p['customerName']);
    });
  });
}
