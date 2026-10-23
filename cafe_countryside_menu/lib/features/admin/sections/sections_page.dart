import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/draft_ops.dart';
import '../../shared/models/draft_section_model.dart';
import '../../shared/widgets/publish_banner.dart';
import '../auth/auth_provider.dart';
import 'widgets/special_sections_block.dart';
import 'sections_provider.dart';
import '../ops/admin_tools_switch.dart';
import '../ops/quick_edit.dart';
import '../ops/row_tag.dart';
import '../ops/section_flows.dart';
import '../shared_admin_business_provider.dart';
import 'widgets/section_form.dart';

class SectionsPage extends ConsumerStatefulWidget {
  const SectionsPage({super.key});

  @override
  ConsumerState<SectionsPage> createState() => _SectionsPageState();
}

class _SectionsPageState extends ConsumerState<SectionsPage> {
  // Search (Phase 1a). While text is present the list is NOT reorderable: a drag
  // renumbers by index, and on a filtered subset that would scramble the real
  // order (S2). Clear the search to re-order.
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
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
      if (mounted) setState(() => _query = v);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(draftProvider.notifier).initializeDraftIfNeeded();
    });
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const SectionFormDialog(),
    );
    if (result == null) return;
    if (!mounted) return;
    await ref.read(draftProvider.notifier).addSection(
          name: result['name']!,
          icon: result['icon'] ?? '',
        );
  }

  Future<void> _showEditDialog(DraftSectionModel section) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => SectionFormDialog(existing: section),
    );
    if (result == null) return;
    if (!mounted) return;
    await ref.read(draftProvider.notifier).updateSection(
          section.copyWith(
            name: result['name'],
            icon: result['icon'],
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(draftStreamProvider);
    final canManage =
        ref.watch(permissionServiceProvider)?.canManageSections ?? false;
    // 1a-F: Merge is one of the tools the owner can switch off.
    final canMerge = canManage &&
        (ref.watch(permissionServiceProvider)?.canManageItems ?? false) &&
        ref.watch(adminToolsOnProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Sections',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add section',
              onPressed: _showAddDialog,
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
                if (sections.isEmpty) {
                  return ListView(children: [
                    const SpecialSectionsBlock(),
                    Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.category_outlined,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('No sections yet.',
                            style: TextStyle(color: Colors.grey)),
                        if (canManage) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _showAddDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Section'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ]);
                }
                final searching = _searching;
                final shown = searching
                    ? (searchSections(draft, _query).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
                    : sections;
                final popup = ref.watch(adminBusinessProvider).asData?.value.firstLoadPopup.choice;

                Widget header() => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SpecialSectionsBlock(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: TextField(
                            key: const Key('sections-search'),
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Search sections…',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchCtrl.text.isEmpty
                                  ? null
                                  : IconButton(
                                      key: const Key('sections-search-clear'),
                                      icon: const Icon(Icons.close),
                                      tooltip: 'Clear search',
                                      onPressed: _clearSearch,
                                    ),
                              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                            ),
                          ),
                        ),
                        if (searching && canManage)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(14, 6, 14, 0),
                            child: Text(
                              'Re-ordering is off while a search is active — clear the search to re-order.',
                              key: Key('sections-reorder-off'),
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ),
                        if (searching && shown.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('No sections match “${_query.trim()}”.', style: const TextStyle(color: Colors.grey)),
                          ),
                      ],
                    );

                _SectionTile tile(DraftSectionModel s) => _SectionTile(
                      key: ValueKey(s.id),
                      section: s,
                      canManage: canManage,
                      itemCount: draft.items.where((i) => i.sectionId == s.id).length,
                      tags: sectionRowTags(draft, s, firstLoadChoice: popup),
                      onTap: () => showQuickEditSection(context, ref, s.id),
                      onEdit: canManage ? () => _showEditDialog(s) : () {},
                      onMerge: canMerge ? () => openMergeDialog(context, ref, s) : null,
                      onDelete: canManage ? () => startSectionDelete(context, ref, s) : () {},
                      onToggleActive: canManage ? () => ref.read(draftProvider.notifier).toggleSectionActive(s.id) : () {},
                    );

                if (canManage && !searching) {
                  return ReorderableListView.builder(
                    header: header(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: shown.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final list = [...shown];
                      final moved = list.removeAt(oldIndex);
                      list.insert(newIndex, moved);
                      ref.read(draftProvider.notifier).reorderSections(list);
                    },
                    itemBuilder: (context, index) => tile(shown[index]),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: shown.length + 1,
                  itemBuilder: (context, index) => index == 0 ? header() : tile(shown[index - 1]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final DraftSectionModel section;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;
  final VoidCallback? onMerge;
  final VoidCallback onTap;
  final int itemCount;
  final List<String> tags;

  const _SectionTile({
    super.key,
    this.onMerge,
    required this.onTap,
    required this.itemCount,
    required this.tags,
    required this.section,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: section.icon.isNotEmpty
            ? Text(section.icon, style: const TextStyle(fontSize: 24))
            : const Icon(Icons.drag_handle, color: Colors.grey),
        title: Text(
          section.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: section.active ? null : Colors.grey,
            decoration:
                section.active ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${section.active ? 'Visible on menu' : 'Hidden from menu'}  ·  $itemCount item${itemCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 12,
                color: section.active ? const Color(0xFF2E7D32) : Colors.grey,
              ),
            ),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(spacing: 4, runSpacing: 2, children: [for (final t in tags) RowTag(t)]),
              ),
          ],
        ),
        trailing: canManage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: section.active,
                    onChanged: (_) => onToggleActive(),
                    activeThumbColor: const Color(0xFF2E7D32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                    onPressed: onEdit,
                  ),
                  if (onMerge != null)
                    IconButton(
                      key: Key('merge-${section.id}'),
                      icon: const Icon(Icons.merge_type),
                      tooltip: 'Merge into…',
                      onPressed: onMerge,
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
