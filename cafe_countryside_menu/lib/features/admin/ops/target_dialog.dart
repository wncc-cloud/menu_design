import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../menu/models/item_model.dart' show chefOnlySectionId;
import '../../menu/presentation/popup_logic.dart' show chefSectionVisible;
import '../../shared/models/admin_copy.dart';
import '../../shared/models/draft_data.dart';
import '../../shared/models/draft_ops.dart';
import '../sections/sections_provider.dart';
import 'admin_ops.dart';
import '../../../core/logging/client_log.dart';

/// Shared "choose a section" dialog for Move (items) and Merge (a section).
///
/// * The target starts EMPTY ("Choose a section…") and Apply stays disabled
///   until one is picked, so Enter can never merge into whatever happens to be
///   first (plan A.1 "Dialog defaults"). [initialTarget] is only for the Menu
///   check's Fix button, and still needs the Apply press.
/// * The preview is the same pure function that runs inside the transaction,
///   evaluated on the draft the page already has; Apply re-runs it on the
///   FRESH draft.
/// * A definite failure keeps the dialog open; a timeout / success closes it.
class TargetDialog extends ConsumerStatefulWidget {
  final String title;
  final String fieldLabel;
  final String confirmLabel;

  /// Left out of the list (a section cannot merge into itself).
  final String? excludeSectionId;
  final String? initialTarget;
  final bool showDeleteBox;
  final OpResult Function(DraftData d, String? target, bool deleteSource, OpContext c) preview;
  final Future<OpOutcome> Function(String? target, bool deleteSource) apply;

  const TargetDialog({
    super.key,
    required this.title,
    required this.fieldLabel,
    required this.confirmLabel,
    required this.preview,
    required this.apply,
    this.excludeSectionId,
    this.initialTarget,
    this.showDeleteBox = false,
  });

  @override
  ConsumerState<TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends ConsumerState<TargetDialog> {
  String? _target;
  bool _delete = true; // "Delete the emptied section" is ticked by default
  bool _busy = false;
  String? _error;

  // Fresh business read for the preview (pop-up choice, Chef Special visible).
  OpContext? _ctx;

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _loadContext();
  }

  Future<void> _loadContext() async {
    final load = ref.read(freshBusinessLoaderProvider);
    OpContext ctx;
    try {
      final biz = await load();
      ctx = OpContext(
        now: DateTime.now(),
        chefSectionVisible: chefSectionVisible(biz),
        firstLoadChoice: biz?.firstLoadPopup.choice ?? 'none',
      );
    } catch (e, st) {
      logClientWarn('Draft.businessRead', e, stackTrace: st);
      ctx = OpContext(now: DateTime.now(), firstLoadChoice: null);
    }
    if (mounted) setState(() => _ctx = ctx);
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.apply(_target, _delete);
    if (!mounted) return;
    if (outcome.keepDialogOpen) {
      setState(() {
        _busy = false;
        _error = outcome.message;
      });
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftStreamProvider).asData?.value;
    final ctx = _ctx;
    final preview = (draft != null && ctx != null) ? widget.preview(draft, _target, _delete, ctx) : null;
    final canApply = !_busy && preview != null && !preview.isBlocked && preview.hasChanges;

    final sections = draft == null
        ? <DropdownMenuItem<String>>[]
        : [
            for (final s in draft.sortedSections)
              if (s.id != widget.excludeSectionId)
                DropdownMenuItem(value: s.id, child: Text('${s.name}${s.active ? '' : ' (hidden)'}')),
            const DropdownMenuItem(value: chefOnlySectionId, child: Text(AdminCopy.reservedSectionLabel)),
          ];

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Controlled (not initialValue): if another admin deletes the chosen
              // target while this dialog is open the list changes under it. The
              // preview then says "changed meanwhile"; the field just goes blank.
              InputDecorator(
                decoration: InputDecoration(labelText: widget.fieldLabel, border: const OutlineInputBorder()),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: sections.any((i) => i.value == _target) ? _target : null,
                    isExpanded: true,
                    hint: const Text('Choose a section…'),
                    items: sections,
                    onChanged: _busy ? null : (v) => setState(() => _target = v),
                  ),
                ),
              ),
              if (widget.showDeleteBox) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: _delete,
                  onChanged: _busy ? null : (v) => setState(() => _delete = v ?? false),
                  title: const Text('Delete the emptied section'),
                ),
              ],
              const SizedBox(height: 8),
              _Preview(result: preview),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: canApply ? _apply : null,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  final OpResult? result;
  const _Preview({required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final box = BoxDecoration(
      color: const Color(0xFFF5F7F8),
      border: Border.all(color: const Color(0xFFE0E6E9)),
      borderRadius: BorderRadius.circular(8),
    );
    if (r.isBlocked) {
      return Container(
        key: const Key('op-preview'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: box,
        child: Text(r.blocked!, style: const TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w600)),
      );
    }
    return Container(
      key: const Key('op-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in r.lines) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $l')),
          for (final w in r.warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('⚠ $w', style: const TextStyle(color: Color(0xFF8A5300))),
            ),
          if (r.tip != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('💡 ${r.tip}', style: const TextStyle(color: Color(0xFF37474F)))),
        ],
      ),
    );
  }
}
