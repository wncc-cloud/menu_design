import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../items_provider.dart';
import '../../auth/auth_provider.dart';
import '../../../shared/models/draft_data.dart';
import '../../../shared/models/draft_item_model.dart';
import 'bulk_import_service.dart';
import 'bulk_import_result.dart';

class BulkImportPage extends ConsumerStatefulWidget {
  const BulkImportPage({super.key});

  @override
  ConsumerState<BulkImportPage> createState() => _BulkImportPageState();
}

class _BulkImportPageState extends ConsumerState<BulkImportPage> {
  BulkImportResult? _result;
  bool _isConfirming = false;
  bool _isParsing = false;

  void _pickFile(DraftData draft) {
    final input = html.FileUploadInputElement()..accept = '.xlsx';
    // Must be in the DOM for Chrome to fire the file dialog and onChange.
    html.document.body?.append(input);
    input.click();
    input.onChange.listen((_) {
      final file = input.files?.first;
      input.remove();
      if (file == null) {
        debugPrint('[BulkImport] no file selected');
        return;
      }
      debugPrint('[BulkImport] file: ${file.name} (${file.size} bytes)');
      if (mounted) setState(() => _isParsing = true);
      final reader = html.FileReader();
      // Attach listeners BEFORE starting the read — for small files the read
      // can complete synchronously and the event fires before a late listener.
      reader.onLoad.listen((_) {
        debugPrint('[BulkImport] onLoad fired, result type: ${reader.result?.runtimeType}');
        try {
          final raw = reader.result;
          if (raw == null) throw StateError('FileReader result is null');
          final bytes = raw as Uint8List;
          debugPrint('[BulkImport] bytes: ${bytes.length}');
          final result = parseAndValidate(bytes, draft);
          debugPrint('[BulkImport] result: hasErrors=${result.hasErrors}, '
              'items=${result.preview?.newItems.length}, '
              'errors=${result.errors?.map((e) => "row${e.rowNumber}:${e.message}").toList()}');
          if (mounted) setState(() { _isParsing = false; _result = result; });
        } catch (e, st) {
          debugPrint('[BulkImport] parse error: $e\n$st');
          if (mounted) {
            setState(() {
              _isParsing = false;
              _result = BulkImportResult.errors(
                  [BulkImportError(0, 'Could not read the file: $e')]);
            });
          }
        }
      });
      reader.onError.listen((_) {
        debugPrint('[BulkImport] FileReader error: ${reader.error}');
        if (mounted) {
          setState(() {
            _isParsing = false;
            _result = BulkImportResult.errors(
                [BulkImportError(0, 'Failed to read the file. Please try again.')]);
          });
        }
      });
      reader.readAsArrayBuffer(file);
    });
  }

  Future<void> _confirm(BulkImportPreview preview) async {
    setState(() => _isConfirming = true);
    try {
      await ref.read(draftProvider.notifier).appendBulkImport(
            newSections: preview.newSections,
            newItems: preview.newItems,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConfirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isConfirming = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${preview.newItems.length} item${preview.newItems.length == 1 ? '' : 's'} added to draft. Publish to go live.',
      ),
    ));
    context.go('/admin/items');
  }

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(draftStreamProvider);
    final canManage =
        ref.watch(permissionServiceProvider)?.canManageItems ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Bulk Import',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: draftAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (draft) {
          if (draft == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!canManage) {
            return const Center(child: Text('Access denied.'));
          }
          if (_isParsing) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Reading file…'),
                ],
              ),
            );
          }
          return _BulkImportBody(
            draft: draft,
            result: _result,
            isConfirming: _isConfirming,
            onDownload: () => generateAndDownloadTemplate(draft),
            onUpload: () => _pickFile(draft),
            onConfirm: _confirm,
            onReset: () => setState(() => _result = null),
          );
        },
      ),
    );
  }
}

class _BulkImportBody extends StatelessWidget {
  final DraftData draft;
  final BulkImportResult? result;
  final bool isConfirming;
  final VoidCallback onDownload;
  final VoidCallback onUpload;
  final Future<void> Function(BulkImportPreview) onConfirm;
  final VoidCallback onReset;

  const _BulkImportBody({
    required this.draft,
    required this.result,
    required this.isConfirming,
    required this.onDownload,
    required this.onUpload,
    required this.onConfirm,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final preview = result?.preview;
    final errors = result?.errors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Step 1: Download + Upload ──────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Step 1 — Download sample template',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                const Text(
                  'Fill it in Excel or Google Sheets, then upload.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download Sample Sheet'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Step 2 — Upload filled sheet',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                const Text(
                  'Only .xlsx files. Max 100 rows.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onUpload,
                  icon: const Icon(Icons.upload_file),
                  label: Text(result == null ? 'Upload Excel File' : 'Upload Again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
          ),

          // ── Step 2a: Errors ────────────────────────────────────────────
          if (errors != null && errors.isNotEmpty) ...[
            const SizedBox(height: 24),
            _ErrorPanel(errors: errors, onUploadAgain: onUpload),
          ],

          // ── Step 2b: Preview ───────────────────────────────────────────
          if (preview != null) ...[
            const SizedBox(height: 24),
            _PreviewPanel(
              preview: preview,
              isConfirming: isConfirming,
              onConfirm: () => onConfirm(preview),
              onCancel: onReset,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      );
}

// ── Error panel ───────────────────────────────────────────────────────────────

class _ErrorPanel extends StatelessWidget {
  final List<BulkImportError> errors;
  final VoidCallback onUploadAgain;
  const _ErrorPanel({required this.errors, required this.onUploadAgain});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  '${errors.length} error${errors.length == 1 ? '' : 's'} found — fix the file and re-upload',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...errors.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    e.rowNumber == 0
                        ? '• ${e.message}'
                        : '• Row ${e.rowNumber}: ${e.message}',
                    style: const TextStyle(fontSize: 13),
                  ),
                )),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onUploadAgain,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preview panel ─────────────────────────────────────────────────────────────

class _PreviewPanel extends StatelessWidget {
  final BulkImportPreview preview;
  final bool isConfirming;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _PreviewPanel({
    required this.preview,
    required this.isConfirming,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final newSectionNames =
        preview.newSections.map((s) => s.icon.isNotEmpty ? '${s.icon} ${s.name}' : s.name).join(' · ');

    return Card(
      color: Colors.green.shade50,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32)),
                SizedBox(width: 8),
                Text(
                  'Ready to import',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                      fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (preview.newSections.isNotEmpty) ...[
              Text(
                '${preview.newSections.length} new section${preview.newSections.length == 1 ? '' : 's'}:  $newSectionNames',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '${preview.newItems.length} new item${preview.newItems.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            // Preview table
            _PreviewTable(items: preview.newItems),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(
                  onPressed: isConfirming ? null : onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: isConfirming ? null : onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                  ),
                  child: isConfirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add to Draft'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTable extends StatelessWidget {
  final List<DraftItemModel> items;
  const _PreviewTable({required this.items});

  @override
  Widget build(BuildContext context) {
    // Resolve section names for display from the items themselves — we have sectionId
    // The preview table shows Section (from item.sectionId resolved via newSections),
    // Item Name, Price, Veg, Bestseller. We don't have section names here directly,
    // but we can show the first 10 rows with available data.
    final display = items.take(10).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(Colors.grey.shade100),
          dataRowMinHeight: 32,
          dataRowMaxHeight: 40,
          headingRowHeight: 36,
          horizontalMargin: 12,
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('Item Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            DataColumn(label: Text('Price', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            DataColumn(label: Text('Veg', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            DataColumn(label: Text('Bestseller', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ],
          rows: [
            ...display.map((item) => DataRow(cells: [
                  DataCell(Text(item.name, style: const TextStyle(fontSize: 12))),
                  DataCell(Text('₹${item.price.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12))),
                  DataCell(Text(item.isVeg ? 'YES' : 'NO',
                      style: TextStyle(
                          fontSize: 12,
                          color: item.isVeg
                              ? const Color(0xFF2E7D32)
                              : Colors.red))),
                  DataCell(Text(item.isBestseller ? 'YES' : 'NO',
                      style: const TextStyle(fontSize: 12))),
                ])),
            if (items.length > 10)
              DataRow(cells: [
                DataCell(Text(
                  '… and ${items.length - 10} more',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic),
                )),
                const DataCell(Text('')),
                const DataCell(Text('')),
                const DataCell(Text('')),
              ]),
          ],
        ),
      ),
    );
  }
}
