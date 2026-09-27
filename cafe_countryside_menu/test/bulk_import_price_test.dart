// billing_cafe phase12.md §12.4-C — a ₹0 row used to import silently and then
// every counter order containing it was rejected. Errors return before any
// Firestore id is generated, so this needs no Firebase setup.
import 'dart:typed_data';

import 'package:cafe_countryside_menu/features/admin/items/bulk_import/bulk_import_service.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _sheet(List<String> priceCells) {
  final excel = Excel.createExcel();
  final sheet = excel['Menu Items'];
  sheet.appendRow(List.generate(12, (i) => TextCellValue('H$i')));
  sheet.appendRow(List.generate(12, (i) => TextCellValue('hint$i')));
  for (final price in priceCells) {
    sheet.appendRow([
      TextCellValue('Mains'),
      TextCellValue('🍕'),
      TextCellValue('Item $price'),
      TextCellValue(price),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('YES'),
      TextCellValue('NO'),
      TextCellValue('YES'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('YES'),
    ]);
  }
  return Uint8List.fromList(excel.encode()!);
}

final _emptyDraft = DraftData(
  sections: const [],
  items: const [],
  draftUpdatedAt: DateTime(2026),
  updatedBy: 'test',
);

void main() {
  test('a price of 0 is rejected with a clear reason, not silently imported', () {
    final result = parseAndValidate(_sheet(['0']), _emptyDraft);
    expect(result.hasErrors, isTrue);
    expect(result.errors!.single.message, contains('more than 0'));
    expect(result.errors!.single.message, contains('100% discount'));
    expect(result.errors!.single.rowNumber, 3);
  });

  test('0.00 is rejected too', () {
    final result = parseAndValidate(_sheet(['0.00']), _emptyDraft);
    expect(result.hasErrors, isTrue);
    expect(result.errors!.single.message, contains('more than 0'));
  });

  test('a negative price keeps its own message', () {
    final result = parseAndValidate(_sheet(['-5']), _emptyDraft);
    expect(result.errors!.single.message, 'Price cannot be negative');
  });

  test('every bad row is reported, each with its sheet row number', () {
    final result = parseAndValidate(_sheet(['0', '-1', 'abc']), _emptyDraft);
    expect(result.errors!.map((e) => e.rowNumber), [3, 4, 5]);
  });
}
