import 'package:excel/excel.dart';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/models/draft_data.dart';
import '../../../shared/models/draft_section_model.dart';
import '../../../shared/models/draft_item_model.dart';
import 'bulk_import_result.dart';

String _newId() => FirebaseFirestore.instance.collection('x').doc().id;

// ── Column indices ────────────────────────────────────────────────────────────
const int _colSection = 0;
const int _colIcon = 1;
const int _colName = 2;
const int _colPrice = 3;
const int _colDesc = 4;
const int _colIngr = 5;
const int _colVeg = 6;
const int _colBest = 7;
const int _colAvail = 8;
const int _colFrom = 9;
const int _colTill = 10;
const int _colActive = 11;

// ── Cell string helper ────────────────────────────────────────────────────────

// CRITICAL: TextCellValue.value is a Flutter TextSpan — .toString() returns
// "TextSpan(...)" debug text, NOT the string content. Always use this helper.
String _cellStr(List<Data?> row, int col) {
  if (col >= row.length) return '';
  final cell = row[col];
  if (cell == null) return '';
  final v = cell.value;
  if (v == null) return '';
  if (v is TextCellValue) return v.value.text?.trim() ?? '';
  return v.toString().trim();
}

// A row is empty unless it has at least one TextCellValue cell with non-empty
// text. This skips phantom rows that the Excel library creates for column-width
// metadata (stored as IntCellValue / DoubleCellValue, not text).
bool _isRowEmpty(List<Data?> row) {
  if (row.isEmpty) return true;
  return !row.any((cell) {
    if (cell == null || cell.value == null) return false;
    if (cell.value is! TextCellValue) return false;
    return ((cell.value as TextCellValue).value.text?.trim() ?? '').isNotEmpty;
  });
}

bool _isYesNo(String s) =>
    s.isEmpty || s.toUpperCase() == 'YES' || s.toUpperCase() == 'NO';

bool _parseBool(String s, {required bool defaultValue}) {
  if (s.isEmpty) return defaultValue;
  return s.toUpperCase() == 'YES';
}

bool _isValidTime(String s) =>
    RegExp(r'^\d{2}:\d{2}$').hasMatch(s);

double? _parsePrice(List<Data?> row) {
  final str = _cellStr(row, _colPrice);
  if (str.isEmpty) return null;
  return double.tryParse(str);
}

// ── Template generation ───────────────────────────────────────────────────────

void generateAndDownloadTemplate(DraftData draft) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Menu Items');
  final sheet = excel['Menu Items'];

  final headerStyle = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.green800,
    fontColorHex: ExcelColor.white,
  );
  final bannerStyle = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.yellow50,
    fontColorHex: ExcelColor.black87,
  );

  // Row 0: instruction banner across all 12 columns
  const bannerText =
      'Fill from row 3. Max 100 items per upload. '
      'Type a NEW section name to create one. '
      'Section Icon is optional (emoji). '
      'Leave optional columns blank for defaults.';
  for (int c = 0; c < 12; c++) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    cell.value = c == 0 ? TextCellValue(bannerText) : TextCellValue('');
    cell.cellStyle = bannerStyle;
  }

  // Row 1: headers
  const headers = [
    'Section', 'Section Icon', 'Item Name', 'Price (₹)',
    'Description', 'Ingredients', 'Veg', 'Bestseller',
    'Available', 'Available From', 'Available Till', 'Active (Visible)',
  ];
  for (int c = 0; c < headers.length; c++) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1));
    cell.value = TextCellValue(headers[c]);
    cell.cellStyle = headerStyle;
  }

  // Rows 2-4: example rows
  final sectionExamples = draft.sections.isNotEmpty
      ? [
          draft.sections[0].name,
          draft.sections.length > 1 ? draft.sections[1].name : draft.sections[0].name,
          draft.sections[0].name,
        ]
      : ['Coffee', 'Snacks', 'Coffee'];
  final iconExamples = draft.sections.isNotEmpty
      ? [
          draft.sections[0].icon,
          draft.sections.length > 1 ? draft.sections[1].icon : draft.sections[0].icon,
          draft.sections[0].icon,
        ]
      : ['☕', '🍟', '☕'];

  final examples = [
    [sectionExamples[0], iconExamples[0], 'Masala Chai', '30', 'Strong spiced tea', 'Tea, Milk, Spices', 'YES', 'YES', 'YES', '', '', 'YES'],
    [sectionExamples[1], iconExamples[1], 'Veg Sandwich', '80', 'Grilled sandwich', 'Bread, Veggies, Cheese', 'YES', 'NO', 'YES', '08:00', '22:00', 'YES'],
    [sectionExamples[2], iconExamples[2], 'Filter Coffee', '40', '', '', 'YES', 'NO', 'YES', '', '', 'YES'],
  ];

  for (int r = 0; r < examples.length; r++) {
    for (int c = 0; c < examples[r].length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 2))
          .value = TextCellValue(examples[r][c]);
    }
  }

  // Column widths
  sheet.setColumnWidth(0, 18);
  sheet.setColumnWidth(1, 12);
  sheet.setColumnWidth(2, 22);
  sheet.setColumnWidth(3, 10);
  sheet.setColumnWidth(4, 25);
  sheet.setColumnWidth(5, 25);
  sheet.setColumnWidth(6, 6);
  sheet.setColumnWidth(7, 10);
  sheet.setColumnWidth(8, 10);
  sheet.setColumnWidth(9, 14);
  sheet.setColumnWidth(10, 14);
  sheet.setColumnWidth(11, 14);

  excel.save(fileName: 'menu_import_template.xlsx');
}

// ── Parse & validate ──────────────────────────────────────────────────────────

BulkImportResult parseAndValidate(Uint8List bytes, DraftData draft) {
  final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (_) {
    return BulkImportResult.errors([
      BulkImportError(0, 'Could not read the file. Make sure it is a valid .xlsx file.'),
    ]);
  }

  // Rule 0a: sheet name
  if (!excel.sheets.containsKey('Menu Items')) {
    return BulkImportResult.errors([
      BulkImportError(
          0, "Sheet 'Menu Items' not found. Download the sample template to get the correct format."),
    ]);
  }

  final sheet = excel.sheets['Menu Items']!;
  final allRows = sheet.rows;
  final dataRows = allRows.length > 2 ? allRows.sublist(2) : <List<Data?>>[];
  final nonEmptyRows = dataRows.where((r) => !_isRowEmpty(r)).toList();

  // Rule 0b: row cap
  if (nonEmptyRows.length > 100) {
    return BulkImportResult.errors([
      BulkImportError(
          0, 'File has ${nonEmptyRows.length} items. Maximum allowed per upload is 100.'),
    ]);
  }

  final errors = <BulkImportError>[];
  final seenNames = <String>{}; // for Rule 13 duplicate-in-sheet
  final existingNames =
      draft.items.map((i) => i.name.toLowerCase()).toSet(); // for Rule 14

  // Collect per-section icon (first occurrence wins)
  final sectionIconMap = <String, String>{}; // normalised name → icon

  for (int i = 0; i < dataRows.length; i++) {
    final row = dataRows[i];
    if (_isRowEmpty(row)) continue;
    final sheetRow = i + 3;

    final sectionRaw = _cellStr(row, _colSection);
    final icon = _cellStr(row, _colIcon);
    final itemName = _cellStr(row, _colName);
    final vegStr = _cellStr(row, _colVeg).toUpperCase();
    final bestStr = _cellStr(row, _colBest).toUpperCase();
    final availStr = _cellStr(row, _colAvail).toUpperCase();
    final fromStr = _cellStr(row, _colFrom);
    final tillStr = _cellStr(row, _colTill);
    final activeStr = _cellStr(row, _colActive).toUpperCase();

    // Rule 2
    if (sectionRaw.isEmpty) {
      errors.add(BulkImportError(sheetRow, 'Section is required'));
      continue;
    }

    final sectionNorm = sectionRaw.toLowerCase();
    if (!sectionIconMap.containsKey(sectionNorm)) {
      sectionIconMap[sectionNorm] = icon;
    }

    // Rule 3
    if (itemName.isEmpty) {
      errors.add(BulkImportError(sheetRow, 'Item Name is required'));
      continue;
    }

    // Rule 4
    final price = _parsePrice(row);
    if (price == null) {
      errors.add(BulkImportError(sheetRow, 'Price must be a number'));
      continue;
    }

    // Rule 5
    if (price < 0) {
      errors.add(BulkImportError(sheetRow, 'Price cannot be negative'));
      continue;
    }

    // Rule 6
    if (vegStr != 'YES' && vegStr != 'NO') {
      errors.add(BulkImportError(sheetRow, 'Veg must be YES or NO'));
    }

    // Rule 7
    if (!_isYesNo(bestStr)) {
      errors.add(BulkImportError(sheetRow, 'Bestseller must be YES, NO, or blank'));
    }

    // Rule 8
    if (!_isYesNo(availStr)) {
      errors.add(BulkImportError(sheetRow, 'Available must be YES, NO, or blank'));
    }

    // Rule 9
    if (fromStr.isNotEmpty && !_isValidTime(fromStr)) {
      errors.add(BulkImportError(sheetRow, 'Available From must be HH:MM (e.g. 07:00)'));
    }

    // Rule 10
    if (tillStr.isNotEmpty && !_isValidTime(tillStr)) {
      errors.add(BulkImportError(sheetRow, 'Available Till must be HH:MM (e.g. 23:00)'));
    }

    // Rule 11
    if ((fromStr.isNotEmpty) != (tillStr.isNotEmpty)) {
      errors.add(BulkImportError(
          sheetRow, 'Set both Available From and Available Till together, or leave both blank'));
    }

    // Rule 12
    if (!_isYesNo(activeStr)) {
      errors.add(BulkImportError(sheetRow, 'Active must be YES, NO, or blank'));
    }

    // Rule 13
    final nameLower = itemName.toLowerCase();
    if (seenNames.contains(nameLower)) {
      errors.add(BulkImportError(sheetRow, 'Item name "$itemName" appears more than once in this file'));
    } else {
      seenNames.add(nameLower);
    }

    // Rule 14
    if (existingNames.contains(nameLower)) {
      errors.add(BulkImportError(sheetRow, 'Item "$itemName" already exists in the menu draft'));
    }
  }

  if (errors.isNotEmpty) {
    return BulkImportResult.errors(errors);
  }

  // ── Build preview ─────────────────────────────────────────────────────────

  final now = DateTime.now();
  // Resolve or create sections
  final resolvedSections = <String, String>{}; // normalised name → sectionId
  for (final s in draft.sections) {
    resolvedSections[s.name.toLowerCase()] = s.id;
  }

  final newSections = <DraftSectionModel>[];
  int nextSectionOrder = draft.sections.isEmpty
      ? 0
      : draft.sections.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

  // First pass: collect all unique section names from sheet in order
  final sheetSectionNames = <String>[];
  for (final row in dataRows) {
    if (_isRowEmpty(row)) continue;
    final name = _cellStr(row, _colSection);
    if (name.isEmpty) continue;
    final norm = name.toLowerCase();
    if (!resolvedSections.containsKey(norm)) {
      if (!sheetSectionNames.contains(norm)) {
        sheetSectionNames.add(norm);
      }
    }
  }

  // Create new sections
  for (final normName in sheetSectionNames) {
    // Find display name (first occurrence in sheet)
    String displayName = normName;
    for (final row in dataRows) {
      if (_isRowEmpty(row)) continue;
      final name = _cellStr(row, _colSection);
      if (name.toLowerCase() == normName) {
        displayName = name;
        break;
      }
    }
    final icon = sectionIconMap[normName] ?? '';
    final section = DraftSectionModel(
      id: _newId(),
      name: displayName,
      icon: icon,
      sortOrder: nextSectionOrder++,
      active: true,
      businessId: 'default',
      createdAt: now,
      updatedAt: now,
    );
    newSections.add(section);
    resolvedSections[normName] = section.id;
  }

  // Pre-compute max existing sortOrder per sectionId
  final maxExistingPerSection = <String, int>{};
  for (final item in draft.items) {
    final cur = maxExistingPerSection[item.sectionId] ?? -1;
    if (item.sortOrder > cur) {
      maxExistingPerSection[item.sectionId] = item.sortOrder;
    }
  }

  // Per-section counter for items being added in this import
  final sectionItemCounts = <String, int>{};

  final newItems = <DraftItemModel>[];
  for (int i = 0; i < dataRows.length; i++) {
    final row = dataRows[i];
    if (_isRowEmpty(row)) continue;

    final sectionRaw = _cellStr(row, _colSection);
    if (sectionRaw.isEmpty) continue;

    final sectionId = resolvedSections[sectionRaw.toLowerCase()]!;
    final base = maxExistingPerSection[sectionId] ?? -1;
    final idx = sectionItemCounts[sectionId] ?? 0;
    sectionItemCounts[sectionId] = idx + 1;

    newItems.add(DraftItemModel(
      id: _newId(),
      sectionId: sectionId,
      name: _cellStr(row, _colName),
      price: _parsePrice(row)!,
      description: _cellStr(row, _colDesc),
      ingredients: _cellStr(row, _colIngr),
      imageUrl: '',
      cloudinaryPublicId: '',
      active: _parseBool(_cellStr(row, _colActive).toUpperCase(), defaultValue: true),
      isVeg: _cellStr(row, _colVeg).toUpperCase() == 'YES',
      isBestseller: _parseBool(_cellStr(row, _colBest).toUpperCase(), defaultValue: false),
      available: _parseBool(_cellStr(row, _colAvail).toUpperCase(), defaultValue: true),
      availableFrom: _cellStr(row, _colFrom),
      availableTill: _cellStr(row, _colTill),
      sortOrder: base + 1 + idx,
      businessId: 'default',
      createdAt: now,
      updatedAt: now,
    ));
  }

  return BulkImportResult.preview(
    BulkImportPreview(newSections: newSections, newItems: newItems),
  );
}
