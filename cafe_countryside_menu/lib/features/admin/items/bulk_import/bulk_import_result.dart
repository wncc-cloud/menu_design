import '../../../shared/models/draft_section_model.dart';
import '../../../shared/models/draft_item_model.dart';

class BulkImportError {
  // rowNumber is the 1-based SHEET row number: dataRows[i] → rowNumber = i + 3
  final int rowNumber;
  final String message;
  BulkImportError(this.rowNumber, this.message);
}

class BulkImportPreview {
  final List<DraftSectionModel> newSections;
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
