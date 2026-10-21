import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/draft_section_model.dart';
import '../../shared/widgets/publish_banner.dart';
import '../auth/auth_provider.dart';
import 'widgets/special_sections_block.dart';
import 'section_delete_flow.dart';
import '../ops/admin_ops.dart';
import '../ops/target_dialog.dart';
import '../../shared/models/draft_ops.dart';
import 'sections_provider.dart';
import 'widgets/section_form.dart';

class SectionsPage extends ConsumerStatefulWidget {
  const SectionsPage({super.key});

  @override
  ConsumerState<SectionsPage> createState() => _SectionsPageState();
}

class _SectionsPageState extends ConsumerState<SectionsPage> {
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

  Future<void> _openMerge(DraftSectionModel section, {String? initialTarget}) async {
    final notifier = ref.read(draftProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showDialog<OpOutcome>(
      context: context,
      builder: (_) => TargetDialog(
        title: 'Merge “${section.name}” into…',
        fieldLabel: 'Merge into',
        confirmLabel: 'Merge',
        excludeSectionId: section.id,
        initialTarget: initialTarget,
        showDeleteBox: true,
        preview: (d, target, del, c) => mergeSections(d, from: section.id, into: target, deleteSource: del, c: c),
        apply: (target, del) => notifier.mergeSection(section.id, target, deleteSource: del),
      ),
    );
    if (outcome == null) return;
    final warnings = outcome.result?.warnings ?? const <String>[];
    final text = outcome.status == OpStatus.nothing && outcome.message.isEmpty
        ? 'Nothing to change.'
        : [outcome.message, ...warnings].where((t) => t.isNotEmpty).join(' — ');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 7),
        backgroundColor: (outcome.status == OpStatus.failed || outcome.status == OpStatus.timedOut) ? Colors.red : null,
      ));
  }

  bool get _canMerge {
    final p = ref.read(permissionServiceProvider);
    return p != null && p.canManageItems && p.canManageSections;
  }

  Future<void> _confirmDelete(DraftSectionModel section) => confirmAndDeleteSection(
        context: context,
        section: section,
        currentDraft: () => ref.read(draftStreamProvider).asData?.value,
        // A FRESH read, never the cached customer copy (the first-load pop-up
        // may point at this section).
        fetchFreshBusiness: ref.read(freshBusinessLoaderProvider),
        deleteSection: (id) => ref.read(draftProvider.notifier).deleteSection(id),
        isMounted: () => mounted,
        onOfferMerge: _canMerge ? () => _openMerge(section) : null,
      );

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(draftStreamProvider);
    final canManage =
        ref.watch(permissionServiceProvider)?.canManageSections ?? false;
    final canMerge = canManage && (ref.watch(permissionServiceProvider)?.canManageItems ?? false);

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
                if (canManage) {
                  return ReorderableListView.builder(
                    header: const SpecialSectionsBlock(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: sections.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final list = [...sections];
                      final moved = list.removeAt(oldIndex);
                      list.insert(newIndex, moved);
                      ref
                          .read(draftProvider.notifier)
                          .reorderSections(list);
                    },
                    itemBuilder: (context, index) {
                      final s = sections[index];
                      return _SectionTile(
                        key: ValueKey(s.id),
                        section: s,
                        canManage: true,
                        onEdit: () => _showEditDialog(s),
                        onMerge: canMerge ? () => _openMerge(s) : null,
                        onDelete: () => _confirmDelete(s),
                        onToggleActive: () => ref
                            .read(draftProvider.notifier)
                            .toggleSectionActive(s.id),
                      );
                    },
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sections.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return const SpecialSectionsBlock();
                    final s = sections[index - 1];
                    return _SectionTile(
                      key: ValueKey(s.id),
                      section: s,
                      canManage: false,
                      onEdit: () {},
                      onDelete: () {},
                      onToggleActive: () {},
                    );
                  },
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

  const _SectionTile({
    super.key,
    this.onMerge,
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
        subtitle: Text(
          section.active ? 'Visible on menu' : 'Hidden from menu',
          style: TextStyle(
            fontSize: 12,
            color: section.active
                ? const Color(0xFF2E7D32)
                : Colors.grey,
          ),
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
