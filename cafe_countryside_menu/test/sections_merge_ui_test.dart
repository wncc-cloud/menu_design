// 1a-2: Merge on the REAL Sections page (the prod case: "Chef Specials" ->
// Chef Special only), the delete flow's Merge offer, permissions, and the
// banner count. In-memory repository, no Firebase.
import 'package:cafe_countryside_menu/features/admin/auth/auth_provider.dart';
import 'package:cafe_countryside_menu/features/admin/ops/admin_ops.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_page.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_provider.dart';
import 'package:cafe_countryside_menu/features/admin/shared_admin_business_provider.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

class _FakeBusiness extends AdminBusinessNotifier {
  @override
  Future<BusinessModel> build() async => BusinessModel.empty();
}

class H {
  final FakeDraftRepository repo;
  late final ProviderContainer container;
  BusinessModel business = BusinessModel.empty();
  H(this.repo);
}

Future<H> pumpSections(
  WidgetTester tester, {
  AdminRole role = AdminRole.owner,
  BusinessModel? business,
  Future<BusinessModel?> Function()? loader,
}) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = FakeDraftRepository(
    draft: tDraft(
      [tSec('cs', 'Chef Specials'), tSec('tea', 'Tea', sort: 1), tSec('para', 'Paratha', sort: 2)],
      [
        for (var i = 0; i < 10; i++) tItem('c$i', 'cs', sort: i, chef: i >= 5),
        tItem('t1', 'tea'),
      ],
    ),
  );
  repo.snapshot = repo.draft;
  final h = H(repo);
  if (business != null) h.business = business;
  h.container = ProviderContainer(overrides: [
    draftRepositoryProvider.overrideWithValue(repo),
    currentAdminProvider.overrideWith((ref) async => tAdmin(role)),
    freshBusinessLoaderProvider.overrideWithValue(loader ?? () async => h.business),
    adminBusinessProvider.overrideWith(_FakeBusiness.new),
  ]);
  addTearDown(h.container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: h.container,
    child: const MaterialApp(home: SectionsPage()),
  ));
  await tester.pumpAndSettle();
  return h;
}

int itemsIn(FakeDraftRepository r, String section) => r.draft!.items.where((i) => i.sectionId == section).length;
bool hasSection(FakeDraftRepository r, String id) => r.draft!.sections.any((s) => s.id == id);

Future<void> openMerge(WidgetTester tester, String sectionId) async {
  await tester.tap(find.byKey(Key('merge-$sectionId')));
  await tester.pumpAndSettle();
}

Future<void> chooseTarget(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  group('permissions', () {
    testWidgets('owner sees Merge on each section', (tester) async {
      await pumpSections(tester);
      expect(find.byKey(const Key('merge-cs')), findsOneWidget);
      expect(find.byKey(const Key('merge-tea')), findsOneWidget);
    });

    testWidgets('staff see no Merge (and no edit controls)', (tester) async {
      await pumpSections(tester, role: AdminRole.staff);
      expect(find.byKey(const Key('merge-cs')), findsNothing);
    });
  });

  group('Merge dialog', () {
    testWidgets('target starts empty, Merge disabled, "Delete the emptied section" ticked by default', (tester) async {
      await pumpSections(tester);
      await openMerge(tester, 'cs');
      expect(find.text('Merge “Chef Specials” into…'), findsOneWidget);
      expect(find.text('Choose a section…'), findsWidgets);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge')).onPressed, isNull);
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
    });

    testWidgets('the source section is not offered as a target', (tester) async {
      await pumpSections(tester);
      await openMerge(tester, 'cs');
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Chef Specials'), findsOneWidget, reason: 'only the page tile behind the dialog, NOT in the menu');
      expect(find.text('Tea'), findsNWidgets(2), reason: 'the tile and the menu entry');
      expect(find.text('🍳 Chef Special only'), findsWidgets);
    });

    testWidgets('PROD CASE: Chef Specials -> Chef Special only: preview, apply, section deleted, Undo', (tester) async {
      final h = await pumpSections(tester);
      await openMerge(tester, 'cs');
      await chooseTarget(tester, '🍳 Chef Special only');
      expect(find.textContaining('10 items move to 🍳 Chef Special only'), findsOneWidget);
      expect(find.textContaining('5 will also get the Chef Special flag'), findsOneWidget);
      expect(find.textContaining('Section Chef Specials will be deleted (it is empty)'), findsOneWidget);
      expect(find.textContaining('The first-load pop-up does not use it'), findsOneWidget);
      expect(find.textContaining('Tip: Dashboard → Export Menu JSON first'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(itemsIn(h.repo, chefOnlySectionId), 10);
      expect(hasSection(h.repo, 'cs'), isFalse);
      expect(find.textContaining('Merged. 10 items moved, section deleted.'), findsWidgets);
      expect(find.text('11 unpublished changes — Publish to go live'), findsOneWidget, reason: '10 items + 1 removed section');

      await tester.tap(find.textContaining('Undo ('));
      await tester.pumpAndSettle();
      expect(hasSection(h.repo, 'cs'), isTrue);
      expect(itemsIn(h.repo, 'cs'), 10);
      expect(itemsIn(h.repo, chefOnlySectionId), 0);
      expect(find.textContaining('unpublished change'), findsNothing, reason: 'back to the published state');
    });

    testWidgets('unticking "delete" keeps the (now empty) section', (tester) async {
      final h = await pumpSections(tester);
      await openMerge(tester, 'cs');
      await chooseTarget(tester, 'Tea');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(find.textContaining('will be deleted'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(hasSection(h.repo, 'cs'), isTrue);
      expect(itemsIn(h.repo, 'tea'), 11);
    });

    testWidgets('first-load pop-up pointing at the source: move done, delete skipped, reason shown', (tester) async {
      final h = await pumpSections(
        tester,
        business: BusinessModel.empty().copyWith(firstLoadPopup: const FirstLoadPopup(choice: 'sec:cs')),
      );
      await openMerge(tester, 'cs');
      await chooseTarget(tester, 'Tea');
      expect(find.textContaining('The first-load pop-up opens this section, so it will not be deleted'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(itemsIn(h.repo, 'tea'), 11);
      expect(hasSection(h.repo, 'cs'), isTrue);
    });

    testWidgets('Chef Special hidden: the dialog warns before applying', (tester) async {
      await pumpSections(
        tester,
        business: BusinessModel.empty().copyWith(systemSections: [
          const SystemSection(key: chefSpecialKey, name: '', icon: '🍳', visible: false),
          const SystemSection(key: bestSellerKey, name: '', icon: '⭐'),
        ]),
      );
      await openMerge(tester, 'cs');
      await chooseTarget(tester, '🍳 Chef Special only');
      expect(find.textContaining('Chef Special is hidden on the menu'), findsOneWidget);
    });

    testWidgets('empty section: only the delete is offered ("nothing to move")', (tester) async {
      final h = await pumpSections(tester);
      await openMerge(tester, 'para');
      await chooseTarget(tester, 'Tea');
      expect(find.textContaining('The section is already empty — nothing to move'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(hasSection(h.repo, 'para'), isFalse);
    });

    testWidgets('empty section with "delete" unticked: nothing to do, Merge stays disabled', (tester) async {
      await pumpSections(tester);
      await openMerge(tester, 'para');
      await chooseTarget(tester, 'Tea');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge')).onPressed, isNull);
    });

    testWidgets('the target vanished before Apply: "changed meanwhile", nothing written, dialog stays', (tester) async {
      final h = await pumpSections(tester);
      await openMerge(tester, 'cs');
      await chooseTarget(tester, 'Tea');
      h.repo.beforeApply = (r) => r.setDraft(r.draft!.copyWith(sections: [for (final s in r.draft!.sections) if (s.id != 'tea') s]));
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The target section no longer exists (changed meanwhile). Nothing was changed.'), findsWidgets);
      expect(itemsIn(h.repo, 'cs'), 10);
      expect(find.text('Merge “Chef Specials” into…'), findsOneWidget);
    });

    testWidgets('offline: dialog stays open with the message; nothing changed', (tester) async {
      final h = await pumpSections(tester);
      await openMerge(tester, 'cs');
      await chooseTarget(tester, 'Tea');
      h.repo.throwOnUpdate = Exception('offline');
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't save — check your connection. Nothing was changed."), findsOneWidget);
      expect(itemsIn(h.repo, 'cs'), 10);
    });

    testWidgets('business doc unreadable: the preview and the apply keep the section (fail closed)', (tester) async {
      final h = await pumpSections(tester, loader: () async => throw Exception('offline'));
      await openMerge(tester, 'cs');
      await chooseTarget(tester, 'Tea');
      expect(find.textContaining("Couldn't check the first-load pop-up"), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(itemsIn(h.repo, 'tea'), 11);
      expect(hasSection(h.repo, 'cs'), isTrue);
    });
  });

  group('delete flow offers Merge (plan A.2)', () {
    testWidgets('Delete on a section with items: explanation + "Merge into another section…" opens the Merge dialog', (tester) async {
      await pumpSections(tester);
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('“Chef Specials” has 10 items'), findsOneWidget);
      await tester.tap(find.text('Merge into another section…'));
      await tester.pumpAndSettle();
      expect(find.text('Merge “Chef Specials” into…'), findsOneWidget);
    });

    testWidgets('Delete on an EMPTY section: the confirm comes first, then it is deleted (R1)', (tester) async {
      final h = await pumpSections(tester);
      await tester.tap(find.byTooltip('Delete').last); // Paratha (empty)
      await tester.pumpAndSettle();
      expect(find.text('Delete section?'), findsOneWidget);
      expect(hasSection(h.repo, 'para'), isTrue, reason: 'nothing is deleted before the click');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(hasSection(h.repo, 'para'), isFalse);
    });
  });
}
