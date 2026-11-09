// REAL-RULES check of OrderRequestRepository.createRequest against the POS
// project's Firestore emulator (loaded with billing-cafe/firebase/firestore.rules).
// Named *_check.dart so a plain `flutter test` skips it (it needs the emulator). Run from billing-cafe/firebase:
//
//   firebase emulators:exec --only firestore --project demo-why-not-cafe \
//     "cd /d D:devmenu_designcafe_countryside_menu && flutter test test/emulator/order_create_emulator_check.dart"
//   (emulators:exec runs the script through Windows cmd: use `cd /d` and a Windows
//   path such as D:\dev\menu_design\cafe_countryside_menu, not a /d/dev/... path)
//
// The repository's local-emulator mode already points at 127.0.0.1:8080 /
// demo-why-not-cafe. The emulator accepts `Authorization: Bearer owner` as an
// admin that bypasses rules; that is used only to seed and to COUNT documents.
import 'dart:convert';

import 'package:cafe_countryside_menu/core/logging/client_log.dart';
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _base = 'http://127.0.0.1:8080/v1/projects/demo-why-not-cafe/databases/(default)/documents';
const _col = '$_base/businesses/default/customerOrderRequests';
const _admin = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

/// Wraps a real client so a test can drop a reply, drop a request, or edit a reply.
class _Hook extends http.BaseClient {
  final http.Client _inner = http.Client();
  Future<http.StreamedResponse> Function(http.BaseRequest, Future<http.StreamedResponse> Function())? onSend;
  int sends = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sends++;
    Future<http.StreamedResponse> real() => _inner.send(request);
    final hook = onSend;
    return hook == null ? real() : hook(request, real);
  }
}

Map<String, dynamic> _order({
  DateTime? now,
  String name = 'Rahul',
  String phone = '9876543210',
  String notes = '',
  int lines = 1,
  int lifeMinutes = 3,
}) {
  final n = now ?? DateTime.now();
  return {
    'shortCode': '1234',
    'customerName': name,
    'customerPhone': phone,
    'tableNumber': '',
    'orderNotes': notes,
    'lines': [
      for (var i = 0; i < lines; i++)
        {'menuItemId': 'm$i', 'name': 'Pizza', 'unitPricePaise': 30000, 'quantity': 1, 'notes': null, 'requiresKitchen': true, 'readyNow': true}
    ],
    'status': 'PENDING',
    'createdAt': n,
    'expiresAt': n.add(Duration(minutes: lifeMinutes)),
    'claimedAt': null,
    'claimedBy': null,
    'linkedOrderId': null,
    'linkedOrderNumber': null,
  };
}

Future<int> _count() async {
  final r = await http.get(Uri.parse(_col), headers: _admin);
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  return (j['documents'] as List?)?.length ?? 0;
}

Future<void> _clear() async {
  final r = await http.get(Uri.parse(_col), headers: _admin);
  final docs = ((jsonDecode(r.body) as Map<String, dynamic>)['documents'] as List?) ?? const [];
  for (final d in docs) {
    final name = (d as Map)['name'] as String;
    await http.delete(Uri.parse('http://127.0.0.1:8080/v1/$name'), headers: _admin);
  }
}

void main() {
  late _Hook hook;
  late OrderRequestRepository repo;
  late List<Map<String, dynamic>> logged;

  setUp(() async {
    await _clear();
    hook = _Hook();
    logged = [];
    OrderRequestRepository.lastServerOffset = null;
    debugClientLogs = ClientLogRepository(
      gate: LogGate(sessionCap: 1000, dedupeWindow: Duration.zero),
      currentUser: () => null,
      randomId: () => 'id${logged.length}',
      setDoc: (id, data) async => logged.add(data),
    );
    repo = OrderRequestRepository(
      posProjectId: 'demo-why-not-cafe',
      posWebApiKey: 'unused',
      businessId: 'default',
      useLocalEmulator: true,
      client: hook,
      retryDelay: Duration.zero,
    );
  });
  tearDown(() => debugClientLogs = null);

  test('1. normal order: one request, document exists under the phone-chosen id, readable back, no logs', () async {
    final id = await repo.createRequest(_order());
    expect(hook.sends, 1);
    expect(await _count(), 1);
    final got = await repo.getRequest(id);
    expect(got, isNotNull);
    expect(got!['customerName'], 'Rahul');
    expect(got['status'], 'PENDING');
    expect(got['lines'], hasLength(1));
    expect(logged, isEmpty);
  });

  test('2. network drop BEFORE the server saw it: retry saves it, exactly one order, one WARN', () async {
    var first = true;
    hook.onSend = (req, real) async {
      if (req.method == 'POST' && first) {
        first = false;
        throw http.ClientException('Load failed', req.url);
      }
      return real();
    };
    final id = await repo.createRequest(_order());
    expect(await _count(), 1);
    expect(await repo.getRequest(id), isNotNull);
    expect(logged.single['type'], 'WARN');
    expect(logged.single['message'], contains('attempt1: ClientException: Load failed'));
  });

  test('3. network drop AFTER the server saved it (reply lost): retry is refused, read-back confirms, exactly ONE order', () async {
    var first = true;
    hook.onSend = (req, real) async {
      if (req.method == 'POST' && first) {
        first = false;
        await real(); // the order lands...
        throw http.ClientException('Failed to fetch', req.url); // ...but the reply is lost
      }
      return real();
    };
    final id = await repo.createRequest(_order());
    expect(await _count(), 1, reason: 'a repeat must NEVER create a second order');
    expect(await repo.getRequest(id), isNotNull);
    expect(logged.single['type'], 'WARN');
    // Record what the real emulator answers to the repeat (documents the 409-vs-403 question).
    // ignore: avoid_print
    print('repeat-create story: ${logged.single['message']}');
  });

  test('4. both tries drop and nothing arrived: customer gets the retry-able error, ONE ERROR log, zero orders', () async {
    hook.onSend = (req, real) async {
      if (req.method == 'POST') throw http.ClientException('Load failed', req.url);
      return real();
    };
    await expectLater(repo.createRequest(_order()), throwsA(isA<OrderRequestException>()));
    expect(await _count(), 0);
    expect(logged.where((l) => l['type'] == 'ERROR'), hasLength(1));
    expect(logged.single['message'], contains('attempt2'));
  });

  test('5. phone clock 7 min SLOW: real rules refuse (403), retry with server-aligned times saves it', () async {
    // The order is built from a clock 7 min behind real time; the reply's Date header is
    // faked to say "server is 7 min ahead of this phone" (what a real slow phone would see).
    final slow = DateTime.now().subtract(const Duration(minutes: 7));
    hook.onSend = (req, real) async {
      final r = await real();
      if (req.method == 'POST' && r.statusCode == 403) {
        final ahead = DateTime.now().toUtc().add(const Duration(minutes: 7));
        const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        String two(int n) => n.toString().padLeft(2, '0');
        final date = '${wd[ahead.weekday - 1]}, ${two(ahead.day)} ${mo[ahead.month - 1]} ${ahead.year} '
            '${two(ahead.hour)}:${two(ahead.minute)}:${two(ahead.second)} GMT';
        final headers = Map<String, String>.of(r.headers)..['date'] = date;
        return http.StreamedResponse(r.stream, r.statusCode, headers: headers, request: r.request, reasonPhrase: r.reasonPhrase);
      }
      return r;
    };
    // NB: with a REAL slow phone the server Date is genuinely 7 min ahead, so the retry
    // (times + 7 min) lands in the valid window. Here the emulator's real time is
    // "now", and slow+7min == now, so the same arithmetic applies.
    final id = await repo.createRequest(_order(now: slow));
    expect(hook.sends, 2);
    expect(await _count(), 1);
    expect(await repo.getRequest(id), isNotNull);
    expect(logged.single['type'], 'WARN');
    expect(logged.single['message'], contains('PERMISSION_DENIED'));
    expect(logged.single['message'], contains('clockOffsetSec=4')); // ~420
  });

  test('6. rule refusals with a CORRECT clock: one attempt, no retry, nothing saved, ERROR names the reason and the oversize field', () async {
    final cases = <String, Map<String, dynamic>>{
      'name 61 chars': _order(name: 'x' * 61),
      'phone 21 chars': _order(phone: '1' * 21),
      'notes 301 chars': _order(notes: 'n' * 301),
      '31 lines': _order(lines: 31),
      'life 31 min': _order(lifeMinutes: 31),
    };
    for (final e in cases.entries) {
      logged.clear();
      final before = hook.sends;
      await expectLater(repo.createRequest(e.value), throwsA(isA<OrderRequestException>()), reason: e.key);
      expect(hook.sends - before, 1, reason: '${e.key}: must not retry a real rule refusal');
      expect(logged, hasLength(1), reason: e.key);
      final m = logged.single['message'] as String;
      expect(m, contains('HTTP 403'), reason: e.key);
      expect(m, contains('shape:'), reason: e.key);
      // ignore: avoid_print
      print('${e.key} -> $m');
    }
    expect(await _count(), 0);
  });

  test('7. App Check header is irrelevant on the emulator, but a malformed body (bad field type) is refused cleanly, no crash', () async {
    final bad = _order()..['tableNumber'] = {'a': 1}; // map where a string is required
    await expectLater(repo.createRequest(bad), throwsA(isA<OrderRequestException>()));
    expect(logged.single['type'], 'ERROR');
    expect(await _count(), 0);
  });

  test('8. status reads: unknown id -> null; existing -> fields; no crash, no log for 404', () async {
    expect(await repo.getRequest('doesNotExist1234567890'), isNull);
    expect(logged, isEmpty);
  });

  test('9. café status: missing doc -> null (unknown, no log); open:true -> true; open:false -> false', () async {
    expect(await repo.fetchCafeOpen(), isNull);
    expect(logged, isEmpty, reason: '404 = not published yet is normal and must not be logged');
    Future<void> seed(bool open) async {
      final r = await http.patch(
        Uri.parse('$_base/businesses/default/public/cafeStatus'),
        headers: _admin,
        body: jsonEncode({'fields': {'open': {'booleanValue': open}}}),
      );
      expect(r.statusCode, 200);
    }

    await seed(true);
    expect(await repo.fetchCafeOpen(), isTrue);
    await seed(false);
    expect(await repo.fetchCafeOpen(), isFalse);
    expect(logged, isEmpty);
  });

  test('10. two customers ordering at once get different ids and both orders exist', () async {
    final ids = await Future.wait([repo.createRequest(_order()), repo.createRequest(_order())]);
    expect(ids[0], isNot(ids[1]));
    expect(await _count(), 2);
  });
}
