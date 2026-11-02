// Bug Logs 2 Nov 2026: `state.extra as PopupSpec` threw when extra was null.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cafe_countryside_menu/features/menu/presentation/popups/popup_route.dart';

void main() {
  testWidgets('popup page built without a PopupSpec sends the customer to the menu, no crash', (t) async {
    final router = GoRouter(
      initialLocation: popupPath,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('MENU')),
        // No redirect here on purpose: the page builder itself must cope.
        GoRoute(path: popupPath, pageBuilder: popupPage),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
    expect(find.text('MENU'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
