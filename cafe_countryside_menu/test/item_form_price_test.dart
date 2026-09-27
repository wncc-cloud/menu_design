// billing_cafe phase12.md §12.4-C (forbid ₹0 items) and §12.4-C2 (a fractional
// price must round-trip through the edit form instead of being rounded).
import 'package:cafe_countryside_menu/features/admin/items/widgets/item_form.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _section = DraftSectionModel(
  id: 's1',
  name: 'Mains',
  icon: '🍕',
  sortOrder: 1,
  active: true,
  businessId: 'default',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

DraftItemModel _item(double price) => DraftItemModel(
      id: 'i1',
      sectionId: 's1',
      name: 'Pizza',
      price: price,
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

Future<DraftItemModel?> _openAndSave(
  WidgetTester tester, {
  DraftItemModel? existing,
  String? typePrice,
}) async {
  DraftItemModel? result;
  var closed = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await showDialog<DraftItemModel>(
            context: context,
            builder: (_) => ItemFormDialog(sections: [_section], existing: existing),
          );
          closed = true;
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (typePrice != null) {
    await tester.enterText(find.widgetWithText(TextFormField, 'Price (₹) *'), typePrice);
  }
  if (existing == null) {
    await tester.enterText(find.widgetWithText(TextFormField, 'Name *'), 'Tea');
  }
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  return closed ? result : null;
}

void main() {
  test('formatPriceForEditing keeps fractions and drops a needless ".0"', () {
    expect(formatPriceForEditing(49.5), '49.5');
    expect(formatPriceForEditing(50), '50');
    expect(formatPriceForEditing(49.99), '49.99');
    expect(formatPriceForEditing(0.5), '0.5');
  });

  testWidgets('₹49.50 opens as 49.5 and saving without touching it keeps ₹49.50', (tester) async {
    final saved = await _openAndSave(tester, existing: _item(49.5));
    expect(saved, isNotNull);
    expect(saved!.price, 49.5, reason: 'must not be silently rounded to 50');
  });

  testWidgets('a whole-rupee price still opens/saves as before', (tester) async {
    final saved = await _openAndSave(tester, existing: _item(120));
    expect(saved!.price, 120);
  });

  testWidgets('a price of 0 is rejected, the dialog stays open, with an explanation', (tester) async {
    final saved = await _openAndSave(tester, typePrice: '0');
    expect(saved, isNull, reason: 'the form did not submit');
    expect(find.textContaining('more than ₹0'), findsOneWidget);
    expect(find.textContaining('100% discount'), findsOneWidget);
  });

  testWidgets('0.00 is also rejected', (tester) async {
    final saved = await _openAndSave(tester, typePrice: '0.00');
    expect(saved, isNull);
    expect(find.textContaining('more than ₹0'), findsOneWidget);
  });

  testWidgets('editing an existing item to 0 is rejected too', (tester) async {
    final saved = await _openAndSave(tester, existing: _item(30), typePrice: '0');
    expect(saved, isNull);
  });

  testWidgets('a normal price is accepted', (tester) async {
    final saved = await _openAndSave(tester, typePrice: '25');
    expect(saved, isNotNull);
    expect(saved!.price, 25);
  });
}
