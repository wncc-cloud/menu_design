// One place to pump an admin page/widget with an in-memory draft repository,
// fake business data and an overridable clock (no Firebase).
import 'package:cafe_countryside_menu/features/admin/auth/auth_provider.dart';
import 'package:cafe_countryside_menu/features/admin/ops/admin_ops.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_provider.dart';
import 'package:cafe_countryside_menu/features/admin/shared_admin_business_provider.dart';
import 'package:cafe_countryside_menu/features/menu/models/menu_snapshot_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/menu_provider.dart' as mp;
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'draft_fixtures.dart';
import 'fake_draft_repository.dart';

class FakeAdminBusiness extends AdminBusinessNotifier {
  final BusinessModel biz;
  FakeAdminBusiness(this.biz);
  @override
  Future<BusinessModel> build() async => biz;
}

class FakeMenu extends mp.MenuController {
  @override
  Future<MenuSnapshotModel?> build() async => const MenuSnapshotModel(sections: [], items: []);
}

class AdminHarness {
  final FakeDraftRepository repo;
  DateTime now = DateTime(2026, 10, 22, 12);
  BusinessModel business;
  late final ProviderContainer container;
  AdminHarness(this.repo, this.business);
}

/// Pumps [home] (an admin page or a widget) inside a MaterialApp, or inside
/// [router] when navigation matters.
Future<AdminHarness> pumpAdmin(
  WidgetTester tester, {
  Widget? home,
  Widget Function(AdminHarness h)? app,
  AdminRole role = AdminRole.owner,
  FakeDraftRepository? repo,
  BusinessModel? business,
  Size size = const Size(1400, 1400),
  bool snapshotEqualsDraft = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final r = repo ??
      FakeDraftRepository(
        draft: tDraft(
          [tSec('a', 'Alpha'), tSec('b', 'Bravo', sort: 1), tSec('h', 'Hidden Bar', sort: 2, active: false)],
          [
            tItem('a1', 'a', name: 'Apple Pie', price: 120, sort: 0),
            tItem('a2', 'a', name: 'Apricot Tart', price: 49.5, sort: 1),
            tItem('b1', 'b', name: 'Banana Split', sort: 0),
            tItem('r1', 'a', name: 'Secret Dish', chef: true, only: true, sort: 2),
          ],
        ),
      );
  if (snapshotEqualsDraft) r.snapshot ??= r.draft;
  final h = AdminHarness(r, business ?? BusinessModel.empty());
  h.container = ProviderContainer(overrides: [
    draftRepositoryProvider.overrideWithValue(r),
    currentAdminProvider.overrideWith((ref) async => tAdmin(role)),
    freshBusinessLoaderProvider.overrideWithValue(() async => h.business),
    adminClockProvider.overrideWithValue(() => h.now),
    adminBusinessProvider.overrideWith(() => FakeAdminBusiness(h.business)),
    mp.menuControllerProvider.overrideWith(FakeMenu.new),
  ]);
  addTearDown(h.container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: h.container,
    child: app != null ? app(h) : MaterialApp(home: home!),
  ));
  await tester.pumpAndSettle();
  return h;
}

/// Lets a 150 ms search debounce fire.
Future<void> settleSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}
