import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  final spec = state.extra as PopupSpec;
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
