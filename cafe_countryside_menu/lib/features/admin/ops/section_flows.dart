import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/draft_ops.dart';
import '../../shared/models/draft_section_model.dart';
import '../auth/auth_provider.dart';
import '../sections/section_delete_flow.dart';
import '../sections/sections_provider.dart';
import 'admin_ops.dart';
import 'op_toast.dart';
import 'target_dialog.dart';

/// Merge and Delete need BOTH permissions: they rewrite items AND remove a
/// section (plan S12).
bool canMergeSections(WidgetRef ref) {
  final p = ref.read(permissionServiceProvider);
  return p != null && p.canManageItems && p.canManageSections;
}

/// The Merge dialog, shared by the Sections page, the quick-edit sheet and the
/// Menu check's Fix button. [initialTarget] preselects (Fix only); Apply is
/// still a click.
Future<void> openMergeDialog(
  BuildContext context,
  WidgetRef ref,
  DraftSectionModel section, {
  String? initialTarget,
}) async {
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
  if (outcome != null) showOpOutcome(messenger, outcome);
}

/// Delete a section: fresh pop-up check, confirm FIRST, one delete; a section
/// with items offers Merge (when allowed).
Future<void> startSectionDelete(BuildContext context, WidgetRef ref, DraftSectionModel section) {
  return confirmAndDeleteSection(
    context: context,
    section: section,
    currentDraft: () => ref.read(draftStreamProvider).asData?.value,
    fetchFreshBusiness: ref.read(freshBusinessLoaderProvider),
    deleteSection: (id) => ref.read(draftProvider.notifier).deleteSection(id),
    isMounted: () => context.mounted,
    onOfferMerge: canMergeSections(ref) ? () => openMergeDialog(context, ref, section) : null,
  );
}
