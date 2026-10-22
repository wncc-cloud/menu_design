import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/client_log.dart';
import '../../menu/models/item_model.dart' show chefOnlySectionId;
import '../../menu/presentation/popup_logic.dart' show chefSectionVisible;
import '../../shared/models/admin_copy.dart';
import '../../shared/models/draft_ops.dart';
import '../../shared/models/item_validators.dart';
import '../auth/auth_provider.dart';
import '../items/widgets/item_form.dart' show formatPriceForEditing;
import '../sections/sections_provider.dart';
import 'admin_ops.dart';
import 'op_toast.dart';
import 'section_flows.dart';

/// What a quick-edit dialog hands back.
sealed class _Result {
  const _Result();
}

class _Saved extends _Result {
  final OpOutcome outcome;
  const _Saved(this.outcome);
}

class _MergeRequested extends _Result {
  const _MergeRequested();
}

class _DeleteRequested extends _Result {
  const _DeleteRequested();
}

class _MoreRequested extends _Result {
  const _MoreRequested();
}

/// Opens the quick-edit dialog for one item (plan B.3): name, price, section,
/// Chef Special, visibility, notes, the LIVE sold-out switch, and "More…" to the
/// full form. Owner/manager only for edits; staff get it read-only with just
/// the live sold-out switch (R13).
Future<void> showQuickEditItem(BuildContext context, WidgetRef ref, String itemId) async {
  final messenger = ScaffoldMessenger.of(context);
  final draft = ref.read(draftStreamProvider).asData?.value;
  if (draft == null || !draft.items.any((i) => i.id == itemId)) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(AdminCopy.itemGone), backgroundColor: Colors.red));
    return;
  }
  final result = await showDialog<_Result>(
    context: context,
    builder: (_) => QuickEditItemDialog(itemId: itemId),
  );
  if (result is _Saved) showOpOutcome(messenger, result.outcome);
  if (result is _MoreRequested && context.mounted) context.go('/admin/items?edit=$itemId');
}

/// Same, for a section: name, visibility, Merge into…, Delete.
Future<void> showQuickEditSection(BuildContext context, WidgetRef ref, String sectionId) async {
  final messenger = ScaffoldMessenger.of(context);
  final draft = ref.read(draftStreamProvider).asData?.value;
  final section = draft?.sections.where((s) => s.id == sectionId).firstOrNull;
  if (section == null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(AdminCopy.sectionGoneSave), backgroundColor: Colors.red));
    return;
  }
  final result = await showDialog<_Result>(
    context: context,
    builder: (_) => QuickEditSectionDialog(sectionId: sectionId),
  );
  if (!context.mounted) return;
  switch (result) {
    case _Saved(:final outcome):
      showOpOutcome(messenger, outcome);
    case _MergeRequested():
      await openMergeDialog(context, ref, section);
    case _DeleteRequested():
      await startSectionDelete(context, ref, section);
    default:
      break;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Item
// ═══════════════════════════════════════════════════════════════════════════

class QuickEditItemDialog extends ConsumerStatefulWidget {
  final String itemId;
  const QuickEditItemDialog({super.key, required this.itemId});

  @override
  ConsumerState<QuickEditItemDialog> createState() => _QuickEditItemDialogState();
}

class _QuickEditItemDialogState extends ConsumerState<QuickEditItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late String _sectionId;
  late bool _chef;
  late bool _only;
  late bool _active;
  late bool _notes;

  bool _busy = false;
  String? _error;
  OpContext? _ctx;

  @override
  void initState() {
    super.initState();
    final i = ref.read(draftStreamProvider).asData!.value!.items.firstWhere((x) => x.id == widget.itemId);
    _name = TextEditingController(text: i.name);
    _price = TextEditingController(text: formatPriceForEditing(i.price));
    _sectionId = i.sectionId;
    _chef = i.isChefSpecial || i.sectionId == chefOnlySectionId;
    _only = i.chefOnly;
    _active = i.active;
    _notes = i.noteAllowed;
    _loadContext();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    OpContext ctx;
    try {
      final biz = await ref.read(freshBusinessLoaderProvider)();
      ctx = OpContext(now: DateTime.now(), chefSectionVisible: chefSectionVisible(biz));
    } catch (e, st) {
      logClientWarn('Draft.businessRead', e, stackTrace: st);
      ctx = OpContext(now: DateTime.now());
    }
    if (mounted) setState(() => _ctx = ctx);
  }

  QuickItemEdit _edit() => QuickItemEdit(
        name: _name.text,
        price: double.tryParse(_price.text.trim()) ?? 0,
        sectionId: _sectionId,
        isChefSpecial: _chef,
        chefOnly: _only,
        active: _active,
        noteAllowed: _notes,
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref.read(draftProvider.notifier).saveQuickItem(widget.itemId, _edit());
    if (!mounted) return;
    if (outcome.keepDialogOpen) {
      setState(() {
        _busy = false;
        _error = outcome.message;
      });
      return;
    }
    Navigator.of(context).pop(_Saved(outcome));
  }

  Future<void> _toggleSoldOut() async {
    final messenger = ScaffoldMessenger.of(context);
    final now = await ref.read(draftProvider.notifier).toggleItemAvailable(widget.itemId);
    if (now == null) return;
    final name = _name.text.trim();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(now ? 'Live now: $name is available again.' : 'Live now: $name is sold out.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftStreamProvider).asData?.value;
    final item = draft?.items.where((i) => i.id == widget.itemId).firstOrNull;
    final readOnly = !(ref.watch(permissionServiceProvider)?.canManageItems ?? false);
    final reserved = _sectionId == chefOnlySectionId;
    final ctx = _ctx;

    final warnings = (draft != null && ctx != null) ? quickEditWarnings(draft, _edit(), ctx) : const <String>[];
    final tip = quickEditNameTip(_name.text);

    final sections = <DropdownMenuItem<String>>[
      if (draft != null)
        for (final s in draft.sortedSections)
          DropdownMenuItem(value: s.id, child: Text('${s.name}${s.active ? '' : ' (hidden)'}')),
      const DropdownMenuItem(value: chefOnlySectionId, child: Text(AdminCopy.reservedSectionLabel)),
    ];

    return AlertDialog(
      title: Text(readOnly ? 'Item (view only)' : 'Quick edit'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const Key('qe-name'),
                  controller: _name,
                  enabled: !readOnly && !_busy,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: validateItemName,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('qe-price'),
                        controller: _price,
                        enabled: !readOnly && !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                        decoration: const InputDecoration(labelText: 'Price (₹)', prefixText: '₹ '),
                        validator: validateItemPrice,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Section'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const Key('qe-section'),
                            value: sections.any((m) => m.value == _sectionId) ? _sectionId : null,
                            isExpanded: true,
                            items: sections,
                            onChanged: (readOnly || _busy)
                                ? null
                                : (v) => setState(() {
                                      final wasReserved = _sectionId == chefOnlySectionId;
                                      _sectionId = v!;
                                      if (v == chefOnlySectionId) {
                                        _chef = true;
                                        _only = true;
                                      } else if (wasReserved) {
                                        _only = false; // like Move: leaving the Chef-only list
                                      }
                                    }),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const Key('qe-chef'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Chef Special${reserved ? ' (locked on: lives only in Chef Special)' : ''}'),
                  value: _chef || reserved,
                  onChanged: (readOnly || reserved || _busy) ? null : (v) => setState(() => _chef = v),
                ),
                if (_chef && !reserved)
                  SwitchListTile(
                    key: const Key('qe-only'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Show only in Chef Special (not in All or its section)'),
                    value: _only,
                    onChanged: (readOnly || _busy) ? null : (v) => setState(() => _only = v),
                  ),
                SwitchListTile(
                  key: const Key('qe-active'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Visible on menu'),
                  value: _active,
                  onChanged: (readOnly || _busy) ? null : (v) => setState(() => _active = v),
                ),
                SwitchListTile(
                  key: const Key('qe-notes'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Customers can add a note'),
                  value: _notes,
                  onChanged: (readOnly || _busy) ? null : (v) => setState(() => _notes = v),
                ),
                SwitchListTile(
                  key: const Key('qe-soldout'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Sold out  (LIVE — not a draft change)'),
                  value: !(item?.available ?? true),
                  onChanged: (item == null || !(item.active)) ? null : (_) => _toggleSoldOut(),
                ),
                if (warnings.isNotEmpty || tip != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    key: const Key('qe-warnings'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7F8),
                      border: Border.all(color: const Color(0xFFE0E6E9)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in warnings) Text('⚠ $w', style: const TextStyle(color: Color(0xFF8A5300))),
                        if (tip != null) Text('💡 $tip', style: const TextStyle(color: Color(0xFF37474F))),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (!readOnly)
          TextButton(
            key: const Key('qe-more'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(const _MoreRequested()),
            child: const Text('More…'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(readOnly ? 'Close' : 'Cancel'),
        ),
        if (!readOnly)
          FilledButton(
            key: const Key('qe-save'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section
// ═══════════════════════════════════════════════════════════════════════════

class QuickEditSectionDialog extends ConsumerStatefulWidget {
  final String sectionId;
  const QuickEditSectionDialog({super.key, required this.sectionId});

  @override
  ConsumerState<QuickEditSectionDialog> createState() => _QuickEditSectionDialogState();
}

class _QuickEditSectionDialogState extends ConsumerState<QuickEditSectionDialog> {
  late final TextEditingController _name;
  late bool _active;
  bool _busy = false;
  String? _error;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final s = ref.read(draftStreamProvider).asData!.value!.sections.firstWhere((x) => x.id == widget.sectionId);
    _name = TextEditingController(text: s.name);
    _active = s.active;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Name is required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _nameError = null;
    });
    final outcome =
        await ref.read(draftProvider.notifier).saveQuickSection(widget.sectionId, name: _name.text, active: _active);
    if (!mounted) return;
    if (outcome.keepDialogOpen) {
      setState(() {
        _busy = false;
        _error = outcome.message;
      });
      return;
    }
    Navigator.of(context).pop(_Saved(outcome));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftStreamProvider).asData?.value;
    final canManage = ref.watch(permissionServiceProvider)?.canManageSections ?? false;
    final canMerge = canManage && (ref.watch(permissionServiceProvider)?.canManageItems ?? false);
    final readOnly = !canManage;
    final n = draft?.items.where((i) => i.sectionId == widget.sectionId).length ?? 0;
    final dup = draft != null && duplicateSectionName(draft, _name.text, exceptId: widget.sectionId);

    return AlertDialog(
      title: Text(readOnly ? 'Section (view only)' : 'Quick edit section'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('qs-name'),
                controller: _name,
                enabled: !readOnly && !_busy,
                decoration: InputDecoration(labelText: 'Name', errorText: _nameError),
                onChanged: (_) => setState(() => _nameError = null),
              ),
              if (dup)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('⚠ ${AdminCopy.duplicateSectionWarning}', style: TextStyle(color: Color(0xFF8A5300))),
                ),
              SwitchListTile(
                key: const Key('qs-active'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Visible on menu'),
                value: _active,
                onChanged: (readOnly || _busy) ? null : (v) => setState(() => _active = v),
              ),
              Text('$n item${n == 1 ? '' : 's'} in this section', style: const TextStyle(fontSize: 12)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (canMerge) ...[
          TextButton(
            key: const Key('qs-merge'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(const _MergeRequested()),
            child: const Text('Merge into…'),
          ),
          TextButton(
            key: const Key('qs-delete'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(const _DeleteRequested()),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(readOnly ? 'Close' : 'Cancel'),
        ),
        if (!readOnly)
          FilledButton(
            key: const Key('qs-save'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
      ],
    );
  }
}
