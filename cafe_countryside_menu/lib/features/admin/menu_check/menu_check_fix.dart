import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../menu/models/item_model.dart' show chefOnlySectionId;
import '../../shared/models/draft_ops.dart';
import '../../shared/models/promotion_models.dart' show chefSpecialKey;
import '../auth/auth_provider.dart';
import '../ops/admin_tools_switch.dart';
import '../ops/quick_edit.dart';
import '../ops/section_flows.dart';
import '../sections/sections_provider.dart';

/// Fix buttons open the editors that can actually repair a problem, so only
/// people who may edit see them (staff cannot).
/// Their targets (quick edit, Merge) are among the tools the owner can switch
/// off (1a-F): the list stays, the Fix buttons go.
bool canFixProblems(WidgetRef ref) =>
    (ref.watch(permissionServiceProvider)?.canManageItems ?? false) && ref.watch(adminToolsOnProvider);

/// Opens the right editor for [p]. Never changes anything by itself: Merge still
/// needs its Apply, quick edit its Save.
Future<void> runFix(BuildContext context, WidgetRef ref, MenuProblem p) async {
  switch (p.kind) {
    case ProblemKind.systemNameClash:
      final section = ref.read(draftStreamProvider).asData?.value?.sections.where((s) => s.id == p.sectionId).firstOrNull;
      if (section == null) return showQuickEditSection(context, ref, p.sectionId ?? '');
      // A section named like the built-in Chef chip: the obvious target is
      // "Chef Special only" (still needs the Merge press).
      return openMergeDialog(context, ref, section,
          initialTarget: p.systemKey == chefSpecialKey ? chefOnlySectionId : null);
    case ProblemKind.duplicateSectionName:
    case ProblemKind.emptySection:
      return showQuickEditSection(context, ref, p.sectionId ?? '');
    case ProblemKind.itemDropped:
    case ProblemKind.zeroPrice:
    case ProblemKind.longName:
      return showQuickEditItem(context, ref, p.itemId ?? '');
    case ProblemKind.popupTarget:
      GoRouter.maybeOf(context)?.push('/admin/promotions');
  }
}
