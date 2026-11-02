import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/logging/client_log.dart';

/// What a pop-up route shows. Passed as `extra`, so a cold load of `/popup`
/// (no extra) is redirected to the menu instead of showing an empty page.
class PopupSpec {
  final WidgetBuilder builder;
  final String label;
  const PopupSpec({required this.builder, required this.label});
}

const popupPath = '/popup';

/// Pop-ups are REAL routes (spike S1, Plan A): go_router owns the browser
/// history entry, so the Back button closes the pop-up and leaves the menu
/// (state, scroll, search) untouched underneath. No hand-written popstate code.
Future<T?> showPopup<T>(BuildContext context, PopupSpec spec) =>
    context.push<T>(popupPath, extra: spec);

String? popupRedirect(Object? extra) => extra is PopupSpec ? null : '/';

Page<void> popupPage(BuildContext context, GoRouterState state) {
  final spec = state.extra;
  if (spec is! PopupSpec) return _bounceToMenuPage(state);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    barrierLabel: 'Close',
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    child: Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: spec.label,
      child: Builder(builder: spec.builder),
    ),
    transitionsBuilder: (context, animation, _, child) {
      // Reduced motion: no animation.
      if (MediaQuery.of(context).disableAnimations) return child;
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

/// `popupRedirect` normally sends a missing `extra` to `/`, but go_router can
/// still build this page without it (Bug Logs 2 Nov 2026: a `null as PopupSpec`
/// crash on 62 customers, e.g. a restored history entry). Show nothing and go
/// to the menu instead of throwing.
Page<void> _bounceToMenuPage(GoRouterState state) {
  logClientWarn('Popup.missingExtra', 'popupPage: missing PopupSpec',
      message: 'popupPage built without a PopupSpec; sent to the menu [extra=${state.extra.runtimeType}]');
  return NoTransitionPage<void>(key: state.pageKey, child: const _BounceToMenu());
}

class _BounceToMenu extends StatefulWidget {
  const _BounceToMenu();

  @override
  State<_BounceToMenu> createState() => _BounceToMenuState();
}

class _BounceToMenuState extends State<_BounceToMenu> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
