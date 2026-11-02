// Bug Logs 2 Nov 2026: getToken() ran while activation was still pending and gave up.
import 'package:flutter_test/flutter_test.dart';

import 'package:cafe_countryside_menu/core/services/pos_app_check_service.dart';

void main() {
  setUp(PosAppCheckService.debugReset);

  test('getToken while activation is pending waits for it, then returns null if it failed', () async {
    PosAppCheckService.debugMarkPending();
    var done = false;
    final f = PosAppCheckService.getToken().then((v) {
      done = true;
      return v;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(done, isFalse, reason: 'must wait, not return null at once');
    PosAppCheckService.debugFinish(ok: false);
    expect(await f, isNull);
  });

  test('wait is bounded', () async {
    PosAppCheckService.debugMarkPending();
    final sw = Stopwatch()..start();
    expect(await PosAppCheckService.getToken(), isNull);
    expect(sw.elapsed, lessThan(const Duration(seconds: 7)));
  }, timeout: const Timeout(Duration(seconds: 15)));
}
