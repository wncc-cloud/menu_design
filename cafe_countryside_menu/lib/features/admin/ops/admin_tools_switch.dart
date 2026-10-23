import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared_admin_business_provider.dart';

/// 1a-F: the owner's off switch (Settings → "Bulk & merge tools").
///
/// Read from the FRESH admin business document, so it takes effect the next
/// time a page opens. Anything unknown (still loading, unreadable, field
/// missing) counts as ON: a broken read must never take tools away, and "off"
/// only ever hides things, it never removes data.
///
/// ON  : Select mode + bulk bar, Merge, quick EDIT.
/// OFF : those are hidden (quick sheets become view-only); search, Find, Menu
///       check, the live sold-out switch and the old Edit / Delete / Hide stay.
final adminToolsOnProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(adminBusinessProvider).asData?.value.adminToolsEnabled ?? true,
);
