import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/client_log.dart';
import '../../shared/models/business_model.dart';
import '../../shared/models/draft_data.dart';
import '../../shared/models/draft_ops.dart';
import '../ops/admin_ops.dart';
import '../sections/sections_provider.dart';

/// The Menu check result for the current draft.
class MenuCheckState {
  final List<MenuProblem> all;

  /// False when the business document could not be read: the first-load
  /// pop-up check was skipped (said so on screen).
  final bool popupChecked;
  const MenuCheckState({required this.all, required this.popupChecked});

  List<MenuProblem> get problems => all.where((p) => p.level == ProblemLevel.problem).toList();
  List<MenuProblem> get tips => all.where((p) => p.level == ProblemLevel.tip).toList();
  int get problemCount => all.where((p) => p.level == ProblemLevel.problem).length;
}

/// How the check is computed. A provider so tests can count calls and prove the
/// result is computed ONCE per draft/business change, not once per widget.
typedef MenuCheckCompute = MenuCheckState Function(DraftData draft, BusinessModel? business);

MenuCheckState computeMenuCheck(DraftData draft, BusinessModel? business) => MenuCheckState(
      all: menuProblems(
        draft,
        systemSections: business?.resolvedSystemSections ?? const [],
        firstLoadChoice: business?.firstLoadPopup.choice,
      ),
      popupChecked: business != null,
    );

final menuCheckComputeProvider = Provider<MenuCheckCompute>((ref) => computeMenuCheck);

/// A FRESH read of the business document for the check (pop-up choice, built-in
/// chip names). null = it could not be read (the pop-up check is then skipped).
/// A missing document is the empty business (nothing opens on load).
final menuCheckBusinessProvider = FutureProvider.autoDispose<BusinessModel?>((ref) async {
  try {
    return await ref.watch(freshBusinessLoaderProvider)() ?? BusinessModel.empty();
  } catch (e, st) {
    logClientWarn('MenuCheck.business', e, stackTrace: st);
    return null;
  }
});

/// ONE computation, many readers: the Dashboard tile, the banner count and the
/// Menu check page all read this. Null until the draft has loaded, or when the
/// check itself failed (logged; Publish is never blocked by it).
final menuProblemsProvider = Provider.autoDispose<MenuCheckState?>((ref) {
  final compute = ref.watch(menuCheckComputeProvider);
  final draft = ref.watch(draftStreamProvider.select((a) => a.asData?.value));
  if (draft == null) return null;
  final biz = ref.watch(menuCheckBusinessProvider.select((a) => a.asData?.value));
  try {
    return compute(draft, biz);
  } catch (e, st) {
    logClientError('MenuCheck', e, stackTrace: st);
    return null;
  }
});

/// Just the number of problems (not tips): widgets watching this rebuild only
/// when it changes.
final menuProblemCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(menuProblemsProvider.select((s) => s?.problemCount ?? 0)),
);
