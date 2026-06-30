import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/draft_item_model.dart';
import '../../shared/models/draft_section_model.dart';
import '../../shared/widgets/publish_banner.dart';
import '../auth/auth_provider.dart';
import 'items_provider.dart';
import 'widgets/item_form.dart';

class ItemsPage extends ConsumerStatefulWidget {
  const ItemsPage({super.key});

  @override
  ConsumerState<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends ConsumerState<ItemsPage> {
  String? _filterSectionId; // null = show all

  @override
  void initState() {
    super.initState();
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
    await ref.read(draftProvider.notifier).updateItem(result);
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title:
            const Text('Items', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (canManage)
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
                final visibleItems = _filterSectionId == null
                    ? allItems
                    : allItems
                        .where((i) => i.sectionId == _filterSectionId)
                        .toList();

                return Column(
                  children: [
                    // Section filter chips
                    if (sections.isNotEmpty)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          children: [
                            _FilterChip(
                              label: 'All (${allItems.length})',
                              selected: _filterSectionId == null,
                              onTap: () =>
                                  setState(() => _filterSectionId = null),
                            ),
                            ...sections.map((s) => _FilterChip(
                                  label:
                                      '${s.name} (${draft.itemsForSection(s.id).length})',
                                  selected: _filterSectionId == s.id,
                                  onTap: () => setState(
                                      () => _filterSectionId = s.id),
                                )),
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
                                  const Text('No items yet.',
                                      style: TextStyle(color: Colors.grey)),
                                  if (canManage) ...[
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
                                final sectionName = sections
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
                                return _ItemTile(
                                  item: item,
                                  sectionName: sectionName,
                                  canManage: canManage,
                                  onEdit: () =>
                                      _showEditDialog(item, sections),
                                  onDelete: () => _confirmDelete(item),
                                  onToggleAvailable: () => ref
                                      .read(draftProvider.notifier)
                                      .toggleItemAvailable(item.id),
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
  final VoidCallback onDelete;
  final VoidCallback onToggleAvailable;
  final VoidCallback onToggleActive;

  const _ItemTile({
    required this.item,
    required this.sectionName,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleAvailable,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Container(
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
        subtitle: Text(
          !item.active
              ? 'Hidden from menu'
              : '₹${item.price.toStringAsFixed(0)}  ·  $sectionName'
                  '${item.isBestseller ? '  ·  ⭐' : ''}',
          style: TextStyle(
            fontSize: 12,
            color: !item.active ? Colors.orange[700] : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.active)
              Switch(
                value: item.available,
                onChanged: (_) => onToggleAvailable(),
                activeThumbColor: const Color(0xFF2E7D32),
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
