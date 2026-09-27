// billing_cafe phase12.md §12.3-B — the customer site reads public/cafeStatus
// over REST and must FAIL OPEN: anything other than a clear boolean is
// "unknown" (null), which callers treat as open.
import 'dart:convert';

import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _repo = OrderRequestRepository(
  posProjectId: 'p',
  posWebApiKey: 'k',
  businessId: 'biz',
  useLocalEmulator: true, // skips App Check token so no Firebase is needed
);

Future<bool?> _fetchWith(http.Response Function(http.Request) handler) {
  return http.runWithClient(
    () => _repo.fetchCafeOpen(timeout: const Duration(milliseconds: 200)),
    () => MockClient((r) async => handler(r)),
  );
}

http.Response _ok(Map<String, dynamic> fields) =>
    http.Response(jsonEncode({'fields': fields}), 200);

void main() {
  test('open: true -> true; open: false -> false', () async {
    expect(await _fetchWith((_) => _ok({'open': {'booleanValue': true}})), isTrue);
    expect(await _fetchWith((_) => _ok({'open': {'booleanValue': false}})), isFalse);
  });

  test('requests the right document', () async {
    Uri? seen;
    await _fetchWith((r) {
      seen = r.url;
      return _ok({'open': {'booleanValue': true}});
    });
    expect(seen!.path, endsWith('/businesses/biz/public/cafeStatus'));
  });

  test('not published yet (404) -> unknown, not closed', () async {
    expect(await _fetchWith((_) => http.Response('{}', 404)), isNull);
  });

  test('permission denied / server error -> unknown', () async {
    expect(await _fetchWith((_) => http.Response('{}', 403)), isNull);
    expect(await _fetchWith((_) => http.Response('{}', 500)), isNull);
  });

  test('malformed or wrong-typed body -> unknown', () async {
    expect(await _fetchWith((_) => http.Response('not json', 200)), isNull);
    expect(await _fetchWith((_) => _ok({'open': {'stringValue': 'false'}})), isNull);
    expect(await _fetchWith((_) => _ok({})), isNull);
  });

  test('a network failure never throws — unknown', () async {
    final result = await http.runWithClient(
      () => _repo.fetchCafeOpen(timeout: const Duration(milliseconds: 200)),
      () => MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(result, isNull);
  });

  test('a hung request times out into unknown instead of blocking the page', () async {
    final result = await http.runWithClient(
      () => _repo.fetchCafeOpen(timeout: const Duration(milliseconds: 50)),
      () => MockClient((_) => Future<http.Response>.delayed(const Duration(seconds: 5), () => http.Response('{}', 200))),
    );
    expect(result, isNull);
  });
}
