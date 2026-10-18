import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-level (never auto-disposed) holder for "has the automatic pop-up
/// already been considered during this page load?" (plan C.4 #1).
///
/// It must NOT live in MenuPage's State: MenuPage is rebuilt every time the
/// user comes back through `context.go('/')`, which would re-fire a widget-
/// local guard. A plain [Notifier] provider is kept alive for the whole app
/// run and only resets on a real browser reload. Phase 1b builds the
/// PopupCoordinator on top of this.
class PopupState {
  final bool started;
  const PopupState({this.started = false});
}

class PopupStateNotifier extends Notifier<PopupState> {
  @override
  PopupState build() => const PopupState();

  /// Returns true exactly once per page load.
  bool claimStart() {
    if (state.started) return false;
    state = const PopupState(started: true);
    return true;
  }
}

final popupStateProvider =
    NotifierProvider<PopupStateNotifier, PopupState>(PopupStateNotifier.new);
