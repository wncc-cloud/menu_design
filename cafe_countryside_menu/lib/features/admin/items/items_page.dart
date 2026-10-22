import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../menu/models/item_model.dart' show chefOnlySectionId;
import '../../shared/models/admin_copy.dart';
import '../../shared/models/draft_item_model.dart';
import '../../shared/models/draft_ops.dart';
import '../../shared/models/draft_section_model.dart';
import '../../shared/widgets/publish_banner.dart';
import '../auth/auth_provider.dart';
import '../ops/admin_ops.dart';
import '../ops/op_toast.dart';
import '../ops/price_dialog.dart';
import '../ops/quick_edit.dart';
import '../ops/row_tag.dart';
import '../ops/select_bar.dart';
import '../ops/target_dialog.dart';
import '../sections/sections_provider.dart';
import 'items_provider.dart';
import 'widgets/item_form.dart';

class ItemsPage extends ConsumerStatefulWidget {
  /// `?find=` deep link: prefills the search box.
  final String? initialFind;

  /// `?edit=<id>` deep link: opens the existing FULL Edit form once, then the
  /// parameter is removed from the address.
  final String? editId;
  const ItemsPage({super.key, this.initialFind, this.editId});

  @override
  ConsumerState<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends ConsumerState<ItemsPage> {
  String? _filterSectionId; // null = show all

  // Select mode (Phase 1a): an explicit button, checkboxes, a bottom bar.
  // Changing the chip clears the selection, so nothing is ever selected out
  // of sight.
  bool _selecting = false;
  final Set<String> _picked = {};

  // Search (Phase 1a): client-side over the draft already loaded, 0 extra reads.
  // The text is applied 150 ms after typing stops. While it is non-empty the
  // chip filter is ignored, the reorder arrows are hidden (they act on the
  // VISIBLE list) and the selection is cleared whenever the text changes.
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _handledEdit = false;

  bool get _searching => _query.trim().isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _query = v;
          _picked.clear();
        });
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _picked.clear();
    });
  }

  /// `?edit=<id>`: open the full form ONCE after the draft has loaded, then
  /// strip the parameter so a refresh or Back does not reopen it.
  void _maybeOpenDeepLinkEdit(List<DraftItemModel> items, List<DraftSectionModel> sections) {
    final id = widget.editId;
    if (id == null || _handledEdit) return;
    _handledEdit = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GoRouter.maybeOf(context)?.go('/admin/items');
      final item = items.where((i) => i.id == id).firstOrNull;
      if (item == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(AdminCopy.itemGone), backgroundColor: Colors.red));
        return;
      }
      if (ref.read(permissionServiceProvider)?.canManageItems ?? false) {
        _showEditDialog(item, sections);
      } else {
        showQuickEditItem(context, ref, id);
      }
    });
  }

  void _setFilter(String? id) => setState(() {
        _filterSectionId = id;
        _picked.clear();
      });

  void _toggleSelecting() => setState(() {
        _selecting = !_selecting;
        _picked.clear();
      });

  void _pick(String id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));

  /// Shows what happened. Uses a messenger captured BEFORE the await.
  void _afterOp(OpOutcome? o, ScaffoldMessengerState messenger) {
    if (o == null) return;
    showOpOutcome(messenger, o);
    if (o.ok && mounted) setState(_picked.clear);
  }

  Future<void> _openMove() async {
    final ids = _picked.toList();
    final notifier = ref.read(draftProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showDialog<OpOutcome>(
      context: context,
      builder: (_) => TargetDialog(
        title: 'Move ${ids.length} item${ids.length == 1 ? '' : 's'}',
        fieldLabel: 'Move to',
        confirmLabel: 'Move',
        preview: (d, target, _, c) => moveItems(d, ids, target, c),
        apply: (target, _) => notifier.moveSelected(ids, target),
      ),
    );
    _afterOp(outcome, messenger);
  }

  Future<void> _openPrice() async {
    final ids = _picked.toList();
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showDialog<OpOutcome>(
      context: context,
      builder: (_) => PriceDialog(ids: ids),
    );
    _afterOp(outcome, messenger);
  }

  Future<void> _bulk(BulkAction a) async {
    if (a == BulkAction.move) return _openMove();
    if (a == BulkAction.price) return _openPrice();
    final ids = _picked.toList();
    final notifier = ref.read(draftProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    if (a == BulkAction.delete) {
      final draft = ref.read(draftStreamProvider).asData?.value;
      final names = [
        for (final id in ids)
          if (draft?.items.where((i) => i.id == id).firstOrNull case final i?) i.name,
      ];
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete ${names.length} item${names.length == 1 ? '' : 's'}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final n in names.take(5)) Text('• $n'),
              if (names.length > 5) Text('…and ${names.length - 5} more'),
              const SizedBox(height: 8),
              const Text('Undo is available for 60 s. Carts that hold them are fixed at checkout.',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final OpOutcome o = switch (a) {
      BulkAction.show => await notifier.bulkActive(ids, true),
      BulkAction.hide => await notifier.bulkActive(ids, false),
      BulkAction.chefOn => await notifier.bulkChef(ids, true),
      BulkAction.chefOff => await notifier.bulkChef(ids, false),
      BulkAction.notesOn => await notifier.bulkNotes(ids, true),
      BulkAction.notesOff => await notifier.bulkNotes(ids, false),
      BulkAction.delete => await notifier.deleteSelected(ids),
      BulkAction.move || BulkAction.price => const OpOutcome(OpStatus.nothing, ''),
    };
    _afterOp(o, messenger);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialFind != null && widget.initialFind!.trim().isNotEmpty) {
      _searchCtrl.text = widget.initialFind!;
      _query = widget.initialFind!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(draftProvider.notifier).initializeDraftIfNeeded();
    });
  }

  Future<void> _showAddDialog(List<DraftSectionModel> sections) async {
    if (sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one section first.')));
      return;
    }
    final result = await showDialog<DraftItemModel>(
      context: context,
      builder: (_) => ItemFormDialog(sections: sections),
    );
    if (result == null || !mounted) return;
    await ref.read(draftProvider.notifier).addItem(result);
  }

  Future<void> _showEditDialog(
      DraftItemModel item, List<DraftSectionModel> sections) async {
    final result = await showDialog<DraftItemModel>(
      context: context,
      builder: (_) => ItemFormDialog(sections: sections, existing: item),
    );
    if (result == null || !mounted) return;
    // "Available now" is LIVE (not part of the draft): keep the draft's old
    // value in this write and flip the three documents together afterwards.
    final availabilityChanged = result.available != item.available;
    await ref.read(draftProvider.notifier).updateItem(
          availabilityChanged ? result.copyWith(available: item.available) : result,
        );
    if (availabilityChanged) {
      await ref.read(draftProvider.notifier).setItemAvailableLive(item.id, result.available);
      if (mounted) _liveToast(result.name, result.available);
    }
  }

  void _liveToast(String name, bool available) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(available
            ? 'Live now: $name is available again. Customers see it on their next refresh (≤ 20 min) and at checkout.'
            : 'Live now: $name is sold out. Customers see it on their next refresh (≤ 20 min) and at checkout.'),
      ));
  }

  Future<void> _confirmDelete(DraftItemModel item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Delete "${item.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(draftProvider.notifier).deleteItem(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(draftStreamProvider);
    final canManage =
        ref.watch(permissionServiceProvider)?.canManageItems ?? false;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selecting) _toggleSelecting();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      bottomNavigationBar:
          _selecting && _picked.isNotEmpty ? SelectBar(count: _picked.length, onAction: _bulk) : null,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title:
            const Text('Items', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (canManage) ...[
            TextButton.icon(
              key: const Key('select-toggle'),
              onPressed: _toggleSelecting,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: Icon(_selecting ? Icons.check : Icons.checklist, size: 18),
              label: Text(_selecting ? 'Done' : 'Select'),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Bulk Import',
              onPressed: () => context.go('/admin/items/import'),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add item',
              onPressed: () {
                final sections =
                    draftAsync.asData?.value?.sortedSections ?? [];
                _showAddDialog(sections);
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          const PublishBanner(),
          Expanded(
            child: draftAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (draft) {
                if (draft == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final sections = draft.sortedSections;
                final allItems = draft.sortedItems;
                final chefOnlyCount = allItems.where((i) => i.sectionId == chefOnlySectionId).length;
                _maybeOpenDeepLinkEdit(allItems, sections);
                final searching = _searching;
                final List<DraftItemModel> visibleItems;
                if (searching) {
                  final ids = searchItems(draft, _query).map((i) => i.id).toSet();
                  visibleItems = allItems.where((i) => ids.contains(i.id)).toList();
                } else if (_filterSectionId == null) {
                  visibleItems = allItems;
                } else {
                  visibleItems = allItems.where((i) => i.sectionId == _filterSectionId).toList();
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: TextField(
                        key: const Key('items-search'),
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search items, ingredients, sections…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  key: const Key('items-search-clear'),
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Clear search',
                                  onPressed: _clearSearch,
                                ),
                          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                        ),
                      ),
                    ),
                    if (searching)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${visibleItems.length} match${visibleItems.length == 1 ? '' : 'es'} for “${_query.trim()}” '
                            '(chip filter ignored while searching; hidden items included)',
                            key: const Key('items-search-count'),
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                      ),
                    // Section filter chips
                    if (sections.isNotEmpty || chefOnlyCount > 0)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          children: [
                            _FilterChip(
                              label: 'All (${allItems.length})',
                              selected: !searching && _filterSectionId == null,
                              onTap: () => _setFilter(null),
                            ),
                            // Items that live only in Chef Special have no section chip.
                            if (chefOnlyCount > 0)
                              _FilterChip(
                                label: '${AdminCopy.reservedSectionLabel} ($chefOnlyCount)',
                                selected: !searching && _filterSectionId == chefOnlySectionId,
                                onTap: () => _setFilter(chefOnlySectionId),
                              ),
                            ...sections.map((s) => _FilterChip(
                                  label:
                                      '${s.name} (${draft.itemsForSection(s.id).length})',
                                  selected: !searching && _filterSectionId == s.id,
                                  onTap: () => _setFilter(s.id),
                                )),
                          ],
                        ),
                      ),
                    if (_filterSectionId != null && canManage && !searching)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Notes for this section:',
                                style: TextStyle(fontSize: 12)),
                            TextButton(
                              onPressed: () => ref
                                  .read(draftProvider.notifier)
                                  .setNotesAllowedForSection(
                                      _filterSectionId!, true),
                              child: const Text('Allow notes for all'),
                            ),
                            TextButton(
                              onPressed: () => ref
                                  .read(draftProvider.notifier)
                                  .setNotesAllowedForSection(
                                      _filterSectionId!, false),
                              child: const Text('Turn notes off for all'),
                            ),
                          ],
                        ),
                      ),
                    if (_selecting)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Select mode · ', style: TextStyle(fontSize: 12)),
                            TextButton(
                              key: const Key('select-all'),
                              onPressed: () => setState(() => _picked.addAll(visibleItems.map((i) => i.id))),
                              child: Text('Select all (${visibleItems.length}) in this view'),
                            ),
                            const Text(' · changing the chip or search clears the selection', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    Expanded(
                      child: visibleItems.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.set_meal,
                                      size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  Text(searching ? 'No items match “${_query.trim()}”.' : 'No items yet.',
                                      style: const TextStyle(color: Colors.grey)),
                                  if (canManage && !searching) ...[
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: () =>
                                          _showAddDialog(sections),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add Item'),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: visibleItems.length,
                              itemBuilder: (context, index) {
                                final item = visibleItems[index];
                                final sectionName = item.sectionId == chefOnlySectionId
                                    ? '🍳 Chef Special only'
                                    : sections
                                    .firstWhere((s) => s.id == item.sectionId,
                                        orElse: () => DraftSectionModel(
                                              id: '',
                                              name: '—',
                                              icon: '',
                                              sortOrder: 0,
                                              active: false,
                                              businessId: '',
                                              createdAt: DateTime.now(),
                                              updatedAt: DateTime.now(),
                                            ))
                                    .name;
                                // Arrows only while ONE section is selected: that is
                                // the list whose order they change.
                                final canMove = canManage && _filterSectionId != null && !_selecting && !searching;
                                return _ItemTile(
                                  item: item,
                                  onMoveUp: canMove && index > 0
                                      ? () => ref.read(draftProvider.notifier).moveItem(item.id, -1)
                                      : null,
                                  onMoveDown: canMove && index < visibleItems.length - 1
                                      ? () => ref.read(draftProvider.notifier).moveItem(item.id, 1)
                                      : null,
                                  showMoveHint: canMove,
                                  sectionName: sectionName,
                                  canManage: canManage,
                                  selecting: _selecting,
                                  picked: _picked.contains(item.id),
                                  onPick: () => _pick(item.id),
                                  onQuickEdit: () => showQuickEditItem(context, ref, item.id),
                                  onEdit: () =>
                                      _showEditDialog(item, sections),
                                  onDelete: () => _confirmDelete(item),
                                  onToggleAvailable: () async {
                                    final now = await ref
                                        .read(draftProvider.notifier)
                                        .toggleItemAvailable(item.id);
                                    if (now != null && mounted) _liveToast(item.name, now);
                                  },
                                  onToggleActive: () => ref
                                      .read(draftProvider.notifier)
                                      .toggleItemActive(item.id),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xFF2E7D32).withValues(alpha: 0.2),
        checkmarkColor: const Color(0xFF2E7D32),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final DraftItemModel item;
  final String sectionName;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onQuickEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleAvailable;
  final VoidCallback onToggleActive;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool showMoveHint;
  final bool selecting;
  final bool picked;
  final VoidCallback? onPick;

  const _ItemTile({
    this.selecting = false,
    this.picked = false,
    this.onPick,
    this.onMoveUp,
    this.onMoveDown,
    this.showMoveHint = false,
    required this.item,
    required this.sectionName,
    required this.canManage,
    required this.onEdit,
    required this.onQuickEdit,
    required this.onDelete,
    required this.onToggleAvailable,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: picked ? const Color(0xFFF1F8E9) : null,
      child: ListTile(
        onTap: selecting ? onPick : onQuickEdit,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selecting)
              Semantics(
                label: 'Select ${item.name}',
                child: Checkbox(
                  key: Key('pick-${item.id}'),
                  value: picked,
                  onChanged: (_) => onPick?.call(),
                ),
              ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: item.isVeg ? const Color(0xFF2E7D32) : Colors.red,
                  width: 2,
                ),
                color: item.isVeg ? const Color(0xFF2E7D32) : Colors.red,
              ),
            ),
          ],
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: !item.active
                ? Colors.grey
                : item.available
                    ? null
                    : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AdminCopy.rupees(item.price)}  ·  $sectionName'
              '${item.isBestseller ? '  ·  ⭐' : ''}'
              '${item.noteAllowed ? '' : '  ·  no note'}',
              style: TextStyle(fontSize: 12, color: !item.active ? Colors.orange[700] : null),
            ),
            if (itemRowTags(item).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [for (final t in itemRowTags(item)) RowTag(t)],
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMoveHint) ...[
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                tooltip: 'Move up',
                onPressed: onMoveUp,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                tooltip: 'Move down',
                onPressed: onMoveDown,
              ),
            ],
            if (item.active)
              Tooltip(
                message: 'Live sold-out: changes what customers see right now',
                child: Switch(
                  value: item.available,
                  onChanged: (_) => onToggleAvailable(),
                  activeThumbColor: const Color(0xFF2E7D32),
                ),
              ),
            if (canManage) ...[
              IconButton(
                icon: Icon(
                  item.active
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: item.active ? null : Colors.orange[700],
                ),
                tooltip: item.active ? 'Hide from menu' : 'Show on menu',
                onPressed: onToggleActive,
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
