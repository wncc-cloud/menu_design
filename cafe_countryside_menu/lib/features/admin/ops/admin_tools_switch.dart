import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared_admin_business_provider.dart';

/// 1a-F: the owner's off switch (Settings → "Bulk & merge tools").
///
/// Read from the FRESH admin business document, so it takes effect the next
/// time a page opens (and right after a Settings save, which refreshes it).
///
///   * loading  → `null`: callers treat it as OFF, so while the answer is on its
///     way no editing tool is offered and a switched-off owner can never click
///     one before the read returns. The tools appear a moment later when ON.
///   * unreadable / field missing → `true` (ON): a broken read must never take
///     the tools away; "off" only ever hides things, it never removes data.
///
/// ON  : Select mode + bulk bar, Merge, quick EDIT.
/// OFF : those are hidden (quick sheets become view-only); search, Find, Menu
///       check, the live sold-out switch and the old Edit / Delete / Hide stay.
final adminToolsStateProvider = Provider.autoDispose<bool?>((ref) {
  final b = ref.watch(adminBusinessProvider);
  // A failed read stays ON even while Riverpod retries it in the background.
  if (b.hasError) return true;
  if (b.isLoading && !b.hasValue) return null;
  return b.asData?.value.adminToolsEnabled ?? true;
});

/// Convenience for widgets: true only when the tools are known to be ON.
final adminToolsOnProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(adminToolsStateProvider) ?? false,
);
