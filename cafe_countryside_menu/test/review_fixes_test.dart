// Regression tests for the code-review findings fixed after 1a-F / 1a-L:
// non-finite prices, Menu check long-name tip, and the owner's tools switch
// (loading counts as OFF, a Settings save refreshes it).
import 'dart:async';

import 'package:cafe_countryside_menu/features/admin/items/items_page.dart';
import 'package:cafe_countryside_menu/features/admin/ops/admin_tools_switch.dart';
import 'package:cafe_countryside_menu/features/admin/settings/settings_provider.dart';
import 'package:cafe_countryside_menu/features/admin/shared_admin_business_provider.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart';
import 'package:cafe_countryside_menu/features/shared/models/item_validators.dart';
import 'package:cafe_countryside_menu/features/shared/repositories/business_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_harness.dart';
import 'support/draft_fixtures.dart';

OpContext ctx() => OpContext(now: DateTime(2026, 10, 22, 9), chefSectionVisible: true);

class _SlowAdminBusiness extends AdminBusinessNotifier {
  _SlowAdminBusiness(this.gate, this.biz);
  final Completer<void> gate;
  final BusinessModel biz;
  @override
  Future<BusinessModel> build() async {
    await gate.future;
    return biz;
  }
}

class _FailingAdminBusiness extends AdminBusinessNotifier {
  @override
  Future<BusinessModel> build() async => throw Exception('offline');
}

class _CountingAdminBusiness extends AdminBusinessNotifier {
  _CountingAdminBusiness(this.onBuild);
  final void Function() onBuild;
  @override
  Future<BusinessModel> build() async {
    onBuild();
    return BusinessModel.empty();
  }
}

class _FakeBusinessRepo implements BusinessRepository {
  @override
  Future<void> saveSettings(BusinessModel business) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('non-finite prices (double.tryParse accepts NaN / Infinity)', () {
    test('the shared validator rejects them', () {
      for (final bad in ['NaN', 'nan', 'Infinity', '-Infinity', 'infinity']) {
        expect(validateItemPrice(bad), 'Enter a valid number', reason: bad);
      }
      expect(validateItemPrice('49.50'), isNull);
    });

    test('quick edit refuses a NaN / Infinity price instead of storing it', () {
      final d = tDraft([tSec('a', 'A')], [tItem('x', 'a', name: 'Latte', price: 120)]);
      for (final p in [double.nan, double.infinity]) {
        final e = QuickItemEdit.of(d.items.single);
        final r = quickEditItem(
          d,
          'x',
          QuickItemEdit(
            name: e.name,
            price: p,
            sectionId: e.sectionId,
            isChefSpecial: e.isChefSpecial,
            chefOnly: e.chefOnly,
            active: e.active,
            noteAllowed: e.noteAllowed,
          ),
          ctx(),
        );
        expect(r.isBlocked, isTrue, reason: '$p');
        expect(r.draftToWrite, isNull);
      }
    });

    test('bulk price skips a stored NaN instead of throwing inside the transaction', () {
      final d = tDraft([tSec('a', 'A')], [tItem('x', 'a', price: double.nan), tItem('y', 'a', price: 100)]);
      final r = bulkPrice(d, ['x', 'y'], const PriceChange(mode: PriceMode.percent, amount: 10), ctx());
      expect(r.newDraft!.items.firstWhere((i) => i.id == 'y').price, 110);
      expect(r.newDraft!.items.firstWhere((i) => i.id == 'x').price.isNaN, isTrue, reason: 'left as it was');
    });

    test('Menu check flags a non-finite price like a zero price', () {
      final d = tDraft([tSec('a', 'A')], [tItem('x', 'a', price: double.infinity)]);
      expect(menuProblems(d).any((p) => p.kind == ProblemKind.zeroPrice), isTrue);
    });
  });

  group('Menu check long-name tip', () {
    test('uses the trimmed length (same as the quick-edit tip): trailing spaces alone do not trigger it', () {
      final name = 'a' * 40 + ' ' * 5;
      final d = tDraft([tSec('a', 'A')], [tItem('x', 'a', name: name)]);
      expect(menuProblems(d).where((p) => p.kind == ProblemKind.longName), isEmpty);
    });

    test('cuts on whole characters: an emoji at the cut is never split', () {
      final name = '${'a' * 29}😀${'b' * 20}'; // the emoji straddles UTF-16 index 29/30
      final d = tDraft([tSec('a', 'A')], [tItem('x', 'a', name: name)]);
      final tip = menuProblems(d).singleWhere((p) => p.kind == ProblemKind.longName);
      expect(tip.title, contains('😀'));
      // A well-formed string round-trips through runes without replacement characters.
      expect(String.fromCharCodes(tip.title.runes), tip.title);
      expect(tip.title.contains('�'), isFalse);
    });
  });

  group('owner tools switch: robustness', () {
    testWidgets('while the setting is still loading the tools are NOT offered; they appear when it says ON', (tester) async {
      final gate = Completer<void>();
      await pumpAdmin(
        tester,
        home: const ItemsPage(),
        adminBusinessFactory: () => _SlowAdminBusiness(gate, BusinessModel.empty()),
      );
      expect(find.byKey(const Key('select-toggle')), findsNothing, reason: 'unknown yet: no editing tool');
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-toggle')), findsOneWidget);
    });

    testWidgets('loading then OFF: the tools never appear', (tester) async {
      final gate = Completer<void>();
      await pumpAdmin(
        tester,
        home: const ItemsPage(),
        adminBusinessFactory: () => _SlowAdminBusiness(gate, BusinessModel.empty().copyWith(adminToolsEnabled: false)),
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-toggle')), findsNothing);
    });

    test('an unreadable setting counts as ON, also while Riverpod retries it', () async {
      final container = ProviderContainer(
        retry: (_, _) => null, // no background retry timers in a test
        overrides: [adminBusinessProvider.overrideWith(_FailingAdminBusiness.new)],
      );
      addTearDown(container.dispose);
      container.listen(adminToolsStateProvider, (_, _) {});
      expect(container.read(adminToolsStateProvider), isNull, reason: 'loading: unknown');
      await container.read(adminBusinessProvider.future).then((_) {}, onError: (_) {});
      expect(container.read(adminToolsStateProvider), isTrue);
      expect(container.read(adminToolsOnProvider), isTrue);
    });

    test('a Settings save refreshes the cached admin business (the off switch applies at once)', () async {
      var builds = 0;
      final container = ProviderContainer(overrides: [
        settingsBusinessRepositoryProvider.overrideWithValue(_FakeBusinessRepo()),
        adminBusinessProvider.overrideWith(() => _CountingAdminBusiness(() => builds++)),
      ]);
      addTearDown(container.dispose);
      container.listen(adminBusinessProvider, (_, _) {});
      container.listen(settingsProvider, (_, _) {});
      await container.read(adminBusinessProvider.future);
      expect(builds, 1);

      expect(await container.read(settingsProvider.notifier).save(BusinessModel.empty()), isNull);
      await container.read(adminBusinessProvider.future);
      expect(builds, 2, reason: 'the admin copy was re-read after the save');
    });
  });
}
