# Bulk Import Plan — Cafe Countryside Menu

## Excel Sheet Structure

One sheet named **"Menu Items"**.

| Col | Header | Required | Type | Format / Notes |
|-----|--------|----------|------|----------------|
| A | Section | ✅ | Text | Type section name — matches existing (case-insensitive) or creates new |
| B | Section Icon | — | Text | Type an emoji e.g. ☕ 🍕 🥗 (blank = no icon) |
| C | Item Name | ✅ | Text | Free text |
| D | Price (₹) | ✅ | Number | Must be ≥ 0, whole or decimal |
| E | Description | — | Text | Free text |
| F | Ingredients | — | Text | Free text |
| G | Veg | ✅ | Text | Type YES or NO (case-insensitive, validated on import) |
| H | Bestseller | — | Text | YES / NO / blank (blank = NO) |
| I | Available | — | Text | YES / NO / blank (blank = YES) |
| J | Available From | — | Text | 24-hr format: HH:MM e.g. 07:00 (blank = always) |
| K | Available Till | — | Text | 24-hr format: HH:MM e.g. 23:00 (blank = always) |
| L | Active (Visible) | — | Text | YES / NO / blank (blank = YES) |

**Total columns: 12**

### Notes on the sheet
- Row 1: Instruction banner (light yellow bg, bold):
  `"Fill from row 3. Max 100 items per upload. Type a NEW section name to create one. Section Icon is optional (emoji). Leave optional columns blank for defaults."`
- Row 2: Headers (bold, dark green background, white text)
- Row 3–5: Pre-filled example rows so admin understands the format
- **No in-cell dropdowns** — the `excel 4.0.6` package has no DataValidation support. All validation (YES/NO, section names, time formats) is done in Dart on import.
- Columns G, H, I, L: plain text cells — admin types YES or NO (case-insensitive, validated on import)
- Column A: plain text cell — admin types the section name exactly as desired (existing match is case-insensitive, new names create a new section)
- Columns J and K: free text (time format validated on import, not in-sheet)

### Section Icon behaviour
- The icon is tied to the **section**, not the item. If two rows share the same section name but different icons, the **first occurrence wins**.
- If the section already exists in the draft, its icon is **not overwritten** — existing sections keep their current icon.
- Only newly created sections get the icon from the sheet.

---

## Validation Rules

All errors are collected first and shown together. Upload is blocked until every error is fixed.
**Pre-checks run before per-row validation. If a pre-check fails, stop immediately (do not continue to row validation).**

| # | Rule | Error message |
|---|------|---------------|
| 0a | No sheet named "Menu Items" in the file | "Sheet 'Menu Items' not found. Download the sample template to get the correct format." |
| 0b | More than 100 data rows | "File has N items. Maximum allowed per upload is 100." |
| 1 | Row completely empty → skip silently | — |
| 2 | Section (A) empty | Row N: Section is required |
| 3 | Item Name (C) empty | Row N: Item Name is required |
| 4 | Price (D) empty or not a number | Row N: Price must be a number |
| 5 | Price (D) < 0 | Row N: Price cannot be negative |
| 6 | Veg (G) not YES/NO | Row N: Veg must be YES or NO |
| 7 | Bestseller (H) not YES/NO/blank | Row N: Bestseller must be YES, NO, or blank |
| 8 | Available (I) not YES/NO/blank | Row N: Available must be YES, NO, or blank |
| 9 | Available From (J) set but not HH:MM | Row N: Available From must be HH:MM (e.g. 07:00) |
| 10 | Available Till (K) set but not HH:MM | Row N: Available Till must be HH:MM (e.g. 23:00) |
| 11 | Only one of From/Till is set | Row N: Set both Available From and Available Till together, or leave both blank |
| 12 | Active (L) not YES/NO/blank | Row N: Active must be YES, NO, or blank |
| 13 | Duplicate item name **within the uploaded sheet** | Row N: Item name "X" appears more than once in this file |
| 14 | Item name **already exists in the current draft** | Row N: Item "X" already exists in the menu draft |

---

## Append Logic

### Sections
1. Load all existing sections from the current draft.
2. For each unique section name in the Excel (case-insensitive match against existing):
   - **Match found** → use existing section `id`. Icon is NOT updated.
   - **No match** → create new `DraftSectionModel`: new UUID, `icon` from first occurrence in sheet (or `""` if blank), `sortOrder` = max existing + auto-increment, `active = true`.
3. New sections are appended to `draft.sections`.

### Items
1. For each valid row:
   - New UUID for `id`.
   - `sectionId` resolved from the section step above.
   - `sortOrder` = (max sortOrder of existing items in that section) + row position in sheet.
   - `imageUrl = ""`, `cloudinaryPublicId = ""` — user adds images manually.
   - All other fields from the parsed row using defaults for blanks.
2. New items appended to `draft.items`.
3. Single `saveDraft()` call writes everything at once.
4. Publish banner triggers: "Unsaved changes — Publish to go live".

### Defaults for blank optional columns

| Field | Default |
|-------|---------|
| Section Icon (B) | `""` |
| Description (E) | `""` |
| Ingredients (F) | `""` |
| Bestseller (H) | `false` |
| Available (I) | `true` |
| Available From (J) | `""` |
| Available Till (K) | `""` |
| Active (L) | `true` |

---

## UI Flow

### Entry point
Admin Items page AppBar → second icon button: `Icons.upload_file`, tooltip "Bulk Import".
Navigates to `/admin/items/import`.

### Bulk Import Page

**Step 1 — Landing**
```
Bulk Import

  [↓ Download Sample Sheet]   ← generates .xlsx with current sections in dropdown + example rows
  [↑ Upload Excel File]       ← file picker, .xlsx only
```

**Step 2a — Errors found**
```
❌ 3 errors found — fix the file and re-upload

  • Row 5: Price must be a number
  • Row 8: Veg must be YES or NO
  • Row 12: Item "Masala Chai" already exists in the menu draft

  [↑ Upload Again]
```

**Step 2b — Validation passed**
```
✅ Ready to import

  2 new sections:   Desserts · Specials
  14 new items

  ┌─────────────────────────────────────────────────────────────┐
  │ Section      │ Item Name      │ Price │ Veg │ Bestseller   │
  │ Desserts     │ Gulab Jamun    │ ₹80   │ YES │ NO           │
  │ ...          │ ...            │ ...   │ ... │ ...          │
  └─────────────────────────────────────────────────────────────┘

  [Cancel]   [Add to Draft]
```

**Step 3 — After confirming**
- Spinner while writing to Firestore
- Success snackbar: "14 items added to draft. Publish to go live."
- Navigate back to Items page

---

## New Package

`excel: ^4.x` — pure Dart, Flutter Web compatible.
Used for both generating the downloadable template and parsing the uploaded file.
No conflicts with existing packages.

---

## Files to Create / Modify

### New files
```
lib/features/admin/items/bulk_import/
  bulk_import_service.dart    — generate template xlsx, parse + validate uploaded file
  bulk_import_result.dart     — BulkImportResult, BulkImportError, BulkImportPreview models
  bulk_import_page.dart       — full UI (download, upload, errors, preview, confirm)
```

### Modified files

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `excel: ^4.x` |
| `lib/router.dart` | Add route `/admin/items/import` |
| `lib/features/admin/items/items_page.dart` | Add upload icon in AppBar |
| `lib/features/admin/sections/sections_provider.dart` | Add `appendBulkImport(newSections, newItems)` method on `DraftNotifier` (NOT draft_repository — must go through `_save()` to stamp `draftUpdatedAt` and `updatedBy`) |

---

## Implementation Technical Reference

This section contains all the API-level specifics needed to implement the plan. Do not guess — use exactly what is documented here.

---

### Package setup

```yaml
# pubspec.yaml — add under dependencies:
excel: ^4.0.6
```

Run `flutter pub get`. No code generation needed — excel is a plain Dart package.

---

### Imports for bulk_import_service.dart

New file is at: `lib/features/admin/items/bulk_import/bulk_import_service.dart`

```dart
import 'package:excel/excel.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data'; // for Uint8List
import 'package:cloud_firestore/cloud_firestore.dart'; // for UUID generation
import '../../../shared/models/draft_data.dart';
import '../../../shared/models/draft_section_model.dart';
import '../../../shared/models/draft_item_model.dart';
import 'bulk_import_result.dart'; // same directory — BulkImportResult, BulkImportPreview, BulkImportError
```

Path math (from `lib/features/admin/items/bulk_import/`):
- `../` → `lib/features/admin/items/`
- `../../` → `lib/features/admin/`
- `../../../` → `lib/features/`  ← shared is here
- `../../auth/` → `lib/features/admin/auth/`

---

### Creating and downloading the template

```dart
// Excel.createExcel() creates a workbook with one sheet named 'Sheet1'.
// Rename it to 'Menu Items'.
final excel = Excel.createExcel();
excel.rename('Sheet1', 'Menu Items');
final sheet = excel['Menu Items'];

// Row and column indexing is 0-based.
// Row 0 = instruction banner, Row 1 = headers, Rows 2-4 = example rows.

// Set cell value:
sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
    TextCellValue('Section');

// Set cell style:
sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).cellStyle =
    CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.green800,
      fontColorHex: ExcelColor.white,
    );

// Trigger browser download (no extra code needed — save() does it automatically):
excel.save(fileName: 'menu_import_template.xlsx');
```

**ExcelColor constants to use:**
- Instruction banner background: `ExcelColor.yellow50` (= `#FFFFFDE7`, very light yellow — confirmed exists)
- Header row background: `ExcelColor.green800` (= `#FF2E7D32` — exactly matches the app's green)
- Header row text: `ExcelColor.white`
- Example row background: none (leave default)

---

### Reading uploaded file — cell value helper

**CRITICAL**: `TextCellValue.value` is a Flutter `TextSpan`, and `TextSpan.toString()` does NOT return just the text string. Always use this helper:

```dart
String _cellStr(List<Data?> row, int col) {
  if (col >= row.length) return '';
  final cell = row[col];
  if (cell == null) return '';
  final v = cell.value;
  if (v == null) return '';
  if (v is TextCellValue) return v.value.text?.trim() ?? '';
  return v.toString().trim(); // works for IntCellValue, DoubleCellValue, BoolCellValue
}
```

**NEVER** use `cell.value?.toString()` directly for a TextCellValue — it returns `TextSpan(...)` debug text, not the content.

---

### Reading the uploaded file

```dart
// bytes is Uint8List from FileReader. Uint8List extends List<int> — passes directly.
final excel = Excel.decodeBytes(bytes);

// Check sheet exists:
if (!excel.sheets.containsKey('Menu Items')) {
  // return error: rule 0a
}

final sheet = excel.sheets['Menu Items']!;
final allRows = sheet.rows; // List<List<Data?>>  — 0-indexed

// Row 0 = instruction banner (skip)
// Row 1 = headers (skip)
// Data rows start at index 2:
final dataRows = allRows.length > 2 ? allRows.sublist(2) : <List<Data?>>[];

// Count non-empty rows for rule 0b:
final nonEmpty = dataRows.where((row) => !_isRowEmpty(row)).toList();
if (nonEmpty.length > 100) { /* rule 0b */ }

bool _isRowEmpty(List<Data?> row) =>
    row.every((cell) => cell == null || cell.value == null ||
        (cell.value is TextCellValue && (cell.value as TextCellValue).value.text?.trim().isEmpty == true));
```

---

### Row display number for error messages

Data rows are `allRows.sublist(2)` (0-indexed). Sheet row 1 = banner, row 2 = headers, row 3 = first data row.

```dart
for (int i = 0; i < dataRows.length; i++) {
  final row = dataRows[i];
  final sheetRowNumber = i + 3; // "Row 3", "Row 4", etc — matches what the user sees in Excel
  if (_isRowEmpty(row)) continue; // Rule 1: skip silently
  // ... validate row, produce errors as: BulkImportError(sheetRowNumber, 'message')
}
```

---

### File picker (dart:html — no new package)

```dart
void _pickFile(void Function(Uint8List bytes) onPicked) {
  final input = html.FileUploadInputElement()..accept = '.xlsx';
  input.click();
  input.onChange.listen((_) {
    final file = input.files?.first;
    if (file == null) return;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    reader.onLoadEnd.listen((_) {
      final bytes = (reader.result as html.ByteBuffer).asUint8List();
      onPicked(bytes);
    });
  });
}
```

---

### bulk_import_result.dart — model structure

New file is at: `lib/features/admin/items/bulk_import/bulk_import_result.dart`

```dart
import '../../../shared/models/draft_section_model.dart';
import '../../../shared/models/draft_item_model.dart';

// No imports from Riverpod or Firebase needed here — plain Dart models

class BulkImportError {
  // rowNumber is the 1-based SHEET row number (row 3 in sheet = rowNumber 3).
  // dataRows[i] → rowNumber = i + 3  (rows 1 and 2 are banner and headers)
  final int rowNumber;
  final String message;
  BulkImportError(this.rowNumber, this.message);
}

class BulkImportPreview {
  final List<DraftSectionModel> newSections; // only sections that did NOT exist before
  final List<DraftItemModel> newItems;
  BulkImportPreview({required this.newSections, required this.newItems});
}

class BulkImportResult {
  final List<BulkImportError>? errors;
  final BulkImportPreview? preview;

  BulkImportResult.errors(List<BulkImportError> e) : errors = e, preview = null;
  BulkImportResult.preview(BulkImportPreview p) : preview = p, errors = null;

  bool get hasErrors => errors != null && errors!.isNotEmpty;
}
```

---

### UUID generation (same as rest of codebase)

```dart
String _newId() => FirebaseFirestore.instance.collection('x').doc().id;
```

---

### No build_runner re-run needed

Adding `appendBulkImport` is just a new method on `DraftNotifier`. The generated file `sections_provider.g.dart` only covers the `build()` method and provider infrastructure — it does NOT need to be regenerated when adding extra methods to the notifier class. Do NOT run `build_runner` for this change.

The three new Dart files (`bulk_import_service.dart`, `bulk_import_result.dart`, `bulk_import_page.dart`) have no `@riverpod` annotations and no `part` directives — no code generation needed.

---

### BulkImportService is a pure Dart class (no Riverpod)

The service takes `DraftData` as input and returns results. The page reads the draft from `draftStreamProvider`, passes it to the service, then calls `draftProvider.notifier.appendBulkImport(...)` on success.

```dart
// bulk_import_service.dart — top-level functions or a plain class, no @riverpod

// Generate and download template xlsx (called on button tap):
void generateAndDownloadTemplate(DraftData draft) { ... }

// Parse and validate uploaded file:
BulkImportResult parseAndValidate(Uint8List bytes, DraftData draft) { ... }
// Returns either:
//   BulkImportResult.errors([BulkImportError(rowNumber, message), ...])
//   BulkImportResult.preview(BulkImportPreview(newSections, newItems))
```

---

### appendBulkImport method signature (goes in sections_provider.dart on DraftNotifier)

```dart
Future<void> appendBulkImport({
  required List<DraftSectionModel> newSections,
  required List<DraftItemModel> newItems,
}) async {
  state = const AsyncValue.loading();
  state = await AsyncValue.guard(() async {
    final draft = _draft();
    if (draft == null) return;
    await _save(draft.copyWith(
      sections: [...draft.sections, ...newSections],
      items: [...draft.items, ...newItems],
    ));
  });
}
```

---

### sortOrder for new sections (match existing pattern)

```dart
// Within bulk_import_service.dart, when building new DraftSectionModel list:
int nextSectionOrder = draft.sections.isEmpty
    ? 0
    : draft.sections.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

// For each new section:
DraftSectionModel(
  id: _newId(),
  name: sectionName,
  icon: iconFromSheet,
  sortOrder: nextSectionOrder++,   // increment for each new section
  active: true,
  businessId: 'default',
  createdAt: now,
  updatedAt: now,
)
```

---

### sortOrder for new items (match existing pattern)

Track a per-section counter so items within the same section get consecutive sortOrders:

```dart
// Pre-compute max existing sortOrder per sectionId ONCE (before looping rows):
final Map<String, int> maxExistingPerSection = {};
for (final item in draft.items) {
  final cur = maxExistingPerSection[item.sectionId] ?? -1;
  if (item.sortOrder > cur) maxExistingPerSection[item.sectionId] = item.sortOrder;
}

// Per-section counter to differentiate items added in this import:
final Map<String, int> sectionItemCounts = {};

// For each imported row:
final base = maxExistingPerSection[resolvedSectionId] ?? -1;
final idx = sectionItemCounts[resolvedSectionId] ?? 0;
sectionItemCounts[resolvedSectionId] = idx + 1;

DraftItemModel(
  sortOrder: base + 1 + idx, // e.g. existing max 5 → first new = 6, second = 7
  // ... other fields
)
```

---

### Provider names and import paths for bulk_import_page.dart

New file is at: `lib/features/admin/items/bulk_import/bulk_import_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../items_provider.dart';                        // exports draftProvider, draftStreamProvider
import '../../auth/auth_provider.dart';                // permissionServiceProvider
import '../../../shared/models/draft_data.dart';       // DraftData — NOT re-exported by items_provider
import 'bulk_import_service.dart';
import 'bulk_import_result.dart';

// Usage:
ref.watch(draftStreamProvider)             // AsyncValue<DraftData?>
ref.read(draftProvider.notifier)           // DraftNotifier instance
ref.watch(permissionServiceProvider)?.canManageItems ?? false
```

**Why `draft_data.dart` must be imported explicitly**: `items_provider.dart` exports `sections_provider.dart`, and `sections_provider.dart` imports `draft_data.dart` — but Dart does NOT automatically re-export transitive imports. Without this import, `DraftData` is an unresolved type.

**NOT** `'../../../auth/auth_provider.dart'` — that resolves to `lib/features/auth/` which does not exist.

---

### Router addition (in router.dart)

Add import and route — copy existing pattern exactly:

```dart
import 'features/admin/items/bulk_import/bulk_import_page.dart';

// Inside routes list, after '/admin/items':
GoRoute(
  path: '/admin/items/import',
  builder: (_, _) => const AdminGuard(child: BulkImportPage()),
),
```

---

### items_page.dart AppBar change

Add `import 'package:go_router/go_router.dart';` at top.

Add the bulk import icon BEFORE the existing add button in the actions list:

```dart
actions: [
  if (canManage) ...[
    IconButton(
      icon: const Icon(Icons.upload_file),
      tooltip: 'Bulk Import',
      onPressed: () => context.go('/admin/items/import'),
    ),
    IconButton(
      icon: const Icon(Icons.add),
      tooltip: 'Add item',
      onPressed: () { /* existing code */ },
    ),
  ],
],
```

---

### Number parsing for Price column (handles all cell types)

Users may type the price as a number in Excel (stored as DoubleCellValue/IntCellValue) or as text:

```dart
double? _parsePrice(List<Data?> row) {
  final str = _cellStr(row, 3); // col D = index 3
  if (str.isEmpty) return null;
  return double.tryParse(str); // works because _cellStr calls .toString() on numeric types
}
```

---

## Out of Scope

- Updating existing items via Excel (append only)
- Image upload via Excel
- Deleting items via Excel
- Reordering existing items via Excel
- Section icon update for existing sections (only applies to newly created sections)
