import 'package:flutter/material.dart';

import '../../shared/models/business_model.dart';
import '../../shared/models/draft_data.dart';
import '../../shared/models/draft_ops.dart';
import '../../shared/models/draft_section_model.dart';
import '../../../core/logging/client_log.dart';

/// Deleting a section, in the only safe order (fixes the old bug where an EMPTY
/// section was deleted BEFORE the "Delete section?" dialog was even shown):
///
///  1. read the business document FRESH (the first-load pop-up may point here);
///     if it cannot be read the delete is BLOCKED (fail closed);
///  2. [canDeleteSection]: items left / pop-up points here -> explain, stop;
///  3. confirm dialog;
///  4. exactly ONE delete.
///
/// Everything it needs is passed in so it can be tested without Firebase.
Future<void> confirmAndDeleteSection({
  required BuildContext context,
  required DraftSectionModel section,
  required DraftData? Function() currentDraft,
  required Future<BusinessModel?> Function() fetchFreshBusiness,

  /// The existing notifier method; returns an error message or null.
  required Future<String?> Function(String sectionId) deleteSection,
  required bool Function() isMounted,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text), backgroundColor: Colors.red));

  final draft = currentDraft();
  if (draft == null) return;

  final String choice;
  try {
    choice = (await fetchFreshBusiness())?.firstLoadPopup.choice ?? 'none';
  } catch (e, st) {
    logClientWarn('Sections.deleteCheck', e, stackTrace: st);
    if (isMounted()) say("Couldn't check the pop-up — try again.");
    return;
  }
  if (!isMounted()) return;

  switch (canDeleteSection(draft, section.id, firstLoadChoice: choice)) {
    case SectionHasItems(:final count):
      say('This section has $count item${count == 1 ? '' : 's'}. Move or delete them first.');
      return;
    case SectionPopupPointsHere():
      say('The first-load pop-up opens this section. Change it in Promotions & pop-up first, then delete it.');
      return;
    case SectionDeleteOk():
      break;
  }

  // `isMounted()` was checked right above; the lint cannot see through it.
  final ok = await showDialog<bool>(
    // ignore: use_build_context_synchronously
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete section?'),
      content: Text('Delete "${section.name}"? This cannot be undone.'),
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
  if (ok != true || !isMounted()) return;

  final error = await deleteSection(section.id);
  if (error != null && isMounted()) say(error);
}
