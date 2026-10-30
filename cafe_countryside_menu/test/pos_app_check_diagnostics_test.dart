// Bug Logs: when App Check has no token, the log must say why (it used to be silent).
import 'package:flutter_test/flutter_test.dart';

import 'package:cafe_countryside_menu/core/services/pos_app_check_service.dart';

void main() {
  setUp(PosAppCheckService.debugReset);

  test('before activation: no token, never throws, diagnostics name the state', () async {
    expect(PosAppCheckService.diagnostics, contains('activation=not-started'));
    expect(await PosAppCheckService.getToken(), isNull);
  });
}
