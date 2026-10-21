// 1a-0(b)/(d) characterization test for the Chef Special flags the item form
// saves (item_form.dart `_submit`). Written against the CURRENT code first (an
// explicit table, NOT the formula) so refactoring the form onto
// `normalizeItemFlags` provably changes nothing.
//
// Rule: a "Chef Special only" item (section = reserved id) is always
// isChefSpecial=true AND chefOnly=true; in a real section chefOnly only counts
// while isChefSpecial is on.
import 'package:cafe_countryside_menu/features/admin/items/widgets/item_form.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _section = DraftSectionModel(
  id: 's1',
  name: 'Mains',
  icon: '',
  sortOrder: 1,
  active: true,
  businessId: 'default',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

DraftItemModel _item({required String sectionId, required bool chef, required bool only}) => DraftItemModel(
      id: 'i1',
      sectionId: sectionId,
      name: 'Pizza',
      price: 100,
      description: '',
      ingredients: '',
      imageUrl: '',
      cloudinaryPublicId: '',
      isVeg: true,
      isBestseller: false,
      available: true,
      availableFrom: '',
      availableTill: '',
      isChefSpecial: chef,
      chefOnly: only,
      sortOrder: 1,
      businessId: 'default',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<DraftItemModel?> _saveUnchanged(WidgetTester tester, DraftItemModel existing) async {
  DraftItemModel? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await showDialog<DraftItemModel>(
            context: context,
            builder: (_) => ItemFormDialog(sections: [_section], existing: existing),
          );
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  // (stored isChefSpecial, stored chefOnly) -> (saved isChefSpecial, saved chefOnly)
  const realSection = <(bool, bool), (bool, bool)>{
    (false, false): (false, false),
    (false, true): (false, false), // chefOnly is meaningless without Chef Special
    (true, false): (true, false),
    (true, true): (true, true),
  };
  const reservedSection = <(bool, bool), (bool, bool)>{
    (false, false): (true, true),
    (false, true): (true, true),
    (true, false): (true, true),
    (true, true): (true, true),
  };

  for (final e in realSection.entries) {
    testWidgets('real section, stored chef=${e.key.$1} only=${e.key.$2} saves ${e.value}', (tester) async {
      final saved = await _saveUnchanged(tester, _item(sectionId: 's1', chef: e.key.$1, only: e.key.$2));
      expect(saved, isNotNull);
      expect((saved!.isChefSpecial, saved.chefOnly), e.value);
      expect(saved.sectionId, 's1');
    });
  }

  for (final e in reservedSection.entries) {
    testWidgets('Chef Special only section, stored chef=${e.key.$1} only=${e.key.$2} saves ${e.value}', (tester) async {
      final saved = await _saveUnchanged(tester, _item(sectionId: chefOnlySectionId, chef: e.key.$1, only: e.key.$2));
      expect(saved, isNotNull);
      expect((saved!.isChefSpecial, saved.chefOnly), e.value);
      expect(saved.sectionId, chefOnlySectionId);
    });
  }
}
