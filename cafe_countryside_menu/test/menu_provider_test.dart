// phase_plan/phase11_9.md (billing_cafe repo) Task 3 — the menu page's
// background refresh timer was widened from 5 to 20 minutes so an
// already-open customer tab doesn't force a fresh Firestore read every
// 5 minutes indefinitely. This just pins the constant so a future
// accidental narrowing gets caught; the timer itself needs a live
// FirebaseFirestore.instance to construct MenuController.build(), which
// isn't set up in this project's unit test environment.
import 'package:cafe_countryside_menu/features/menu/presentation/menu_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu background refresh interval is widened well past 5 minutes', () {
    expect(menuRefreshInterval, greaterThanOrEqualTo(const Duration(minutes: 15)));
    expect(menuRefreshInterval, const Duration(minutes: 20));
  });
}
