import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/draft_section_model.dart';
import '../../shared/widgets/publish_banner.dart';
import '../auth/auth_provider.dart';
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

  Future<void> _confirmDelete(DraftSectionModel section) async {
    final error = await ref
        .read(draftProvider.notifier)
        .deleteSection(section.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete section?'),
        content:
            Text('Delete "${section.name}"? This cannot be undone.'),
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
    await ref
        .read(draftProvider.notifier)
        .deleteSection(section.id);
  }

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(draftStreamProvider);
    final canManage =
        ref.watch(permissionServiceProvider)?.canManageSections ?? false;

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
                  return Center(
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
                  );
                }
                if (canManage) {
                  return ReorderableListView.builder(
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
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    final s = sections[index];
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

  const _SectionTile({
    super.key,
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
