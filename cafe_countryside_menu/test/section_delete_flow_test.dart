// 1a-0(e): the "Delete section?" confirm must come BEFORE any write (bug-050:
// an empty section used to be deleted first, then the dialog appeared), the
// first-load pop-up guard uses a FRESH business read, and it fails closed.
import 'package:cafe_countryside_menu/features/admin/sections/section_delete_flow.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DraftSectionModel _sec(String id, String name) => DraftSectionModel(
      id: id,
      name: name,
      icon: '',
      sortOrder: 1,
      active: true,
      businessId: 'default',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

DraftItemModel _item(String id, String sectionId) => DraftItemModel(
      id: id,
      sectionId: sectionId,
      name: id,
      price: 10,
      description: '',
      ingredients: '',
      imageUrl: '',
      cloudinaryPublicId: '',
      isVeg: true,
      isBestseller: false,
      available: true,
      availableFrom: '',
      availableTill: '',
      sortOrder: 1,
      businessId: 'default',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

DraftData _draft({List<DraftItemModel> items = const []}) => DraftData(
      sections: [_sec('empty', 'Paratha'), _sec('full', 'Pasta')],
      items: items,
      draftUpdatedAt: DateTime(2026),
      updatedBy: 'u',
    );

BusinessModel _biz(String choice) => BusinessModel.empty().copyWith(firstLoadPopup: FirstLoadPopup(choice: choice));

void main() {
  late List<String> events;

  Future<void> run(
    WidgetTester tester, {
    required DraftSectionModel section,
    required DraftData draft,
    required Future<BusinessModel?> Function() business,
    String? deleteError,
    Future<void> Function()? whileDialogOpen,
    bool tapDelete = false,
    bool tapCancel = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => confirmAndDeleteSection(
              context: context,
              section: section,
              currentDraft: () => draft,
              fetchFreshBusiness: () {
                events.add('fetchBusiness');
                return business();
              },
              deleteSection: (id) async {
                events.add('delete:$id');
                return deleteError;
              },
              isMounted: () => true,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    if (tester.any(find.text('Delete section?'))) events.add('dialogShown');
    if (tapCancel) {
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    if (tapDelete) {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
    }
  }

  setUp(() => events = []);

  testWidgets('EMPTY section: dialog first, nothing is deleted before the click', (tester) async {
    await run(tester, section: _sec('empty', 'Paratha'), draft: _draft(), business: () async => _biz('none'));
    expect(events, ['fetchBusiness', 'dialogShown'], reason: 'no delete before the user confirms');
  });

  testWidgets('Cancel never deletes', (tester) async {
    await run(tester, section: _sec('empty', 'Paratha'), draft: _draft(), business: () async => _biz('none'), tapCancel: true);
    expect(events.where((e) => e.startsWith('delete')), isEmpty);
  });

  testWidgets('Confirm deletes exactly once, after the dialog', (tester) async {
    await run(tester, section: _sec('empty', 'Paratha'), draft: _draft(), business: () async => _biz('none'), tapDelete: true);
    expect(events, ['fetchBusiness', 'dialogShown', 'delete:empty']);
  });

  testWidgets('section with items: explained, no dialog, no delete', (tester) async {
    await run(tester,
        section: _sec('full', 'Pasta'),
        draft: _draft(items: [_item('a', 'full'), _item('b', 'full')]),
        business: () async => _biz('none'));
    expect(events, ['fetchBusiness']);
    expect(find.textContaining('has 2 items'), findsOneWidget);
  });

  testWidgets('first-load pop-up points here: blocked with the reason', (tester) async {
    await run(tester, section: _sec('empty', 'Paratha'), draft: _draft(), business: () async => _biz('sec:empty'));
    expect(events, ['fetchBusiness']);
    expect(find.textContaining('first-load pop-up'), findsOneWidget);
  });

  testWidgets('pop-up pointing at ANOTHER section does not block', (tester) async {
    await run(tester, section: _sec('empty', 'Paratha'), draft: _draft(), business: () async => _biz('sec:full'));
    expect(events, ['fetchBusiness', 'dialogShown']);
  });

  testWidgets('FAILS CLOSED when the business doc cannot be read', (tester) async {
    await run(tester,
        section: _sec('empty', 'Paratha'),
        draft: _draft(),
        business: () async => throw Exception('offline'));
    expect(events, ['fetchBusiness'], reason: 'no dialog, no delete');
    expect(find.textContaining("Couldn't check the pop-up"), findsOneWidget);
  });

  testWidgets('missing business document is treated as "no pop-up"', (tester) async {
    await run(tester, section: _sec('empty', 'Paratha'), draft: _draft(), business: () async => null);
    expect(events, ['fetchBusiness', 'dialogShown']);
  });

  testWidgets('an error from the delete itself is shown', (tester) async {
    await run(tester,
        section: _sec('empty', 'Paratha'),
        draft: _draft(),
        business: () async => _biz('none'),
        deleteError: 'Something went wrong',
        tapDelete: true);
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  group('canDeleteSection', () {
    test('ok / hasItems / popupPointsHere', () {
      final d = _draft(items: [_item('a', 'full')]);
      expect(canDeleteSection(d, 'empty', firstLoadChoice: 'none'), isA<SectionDeleteOk>());
      expect(canDeleteSection(d, 'full', firstLoadChoice: 'none'), isA<SectionHasItems>());
      expect((canDeleteSection(d, 'full', firstLoadChoice: 'none') as SectionHasItems).count, 1);
      expect(canDeleteSection(d, 'empty', firstLoadChoice: 'sec:empty'), isA<SectionPopupPointsHere>());
      expect(canDeleteSection(d, 'empty', firstLoadChoice: 'sec:full'), isA<SectionDeleteOk>());
      expect(canDeleteSection(d, 'empty', firstLoadChoice: 'chef'), isA<SectionDeleteOk>());
    });

    test('items take precedence over the pop-up reason (merge is the way out)', () {
      final d = _draft(items: [_item('a', 'full')]);
      expect(canDeleteSection(d, 'full', firstLoadChoice: 'sec:full'), isA<SectionHasItems>());
    });

    test('hidden items still count', () {
      final hidden = _item('h', 'empty').copyWith(active: false);
      expect(canDeleteSection(_draft(items: [hidden]), 'empty', firstLoadChoice: 'none'), isA<SectionHasItems>());
    });
  });
}
