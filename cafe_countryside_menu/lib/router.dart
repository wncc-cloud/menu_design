import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/auth/admin_guard.dart';
import 'features/admin/auth/login_page.dart';
import 'features/admin/dashboard/dashboard_page.dart';
import 'features/admin/items/items_page.dart';
import 'features/admin/items/bulk_import/bulk_import_page.dart';
import 'features/admin/profile/profile_page.dart';
import 'features/admin/sections/sections_page.dart';
import 'features/admin/settings/settings_page.dart';
import 'features/menu/presentation/menu_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable:
      _GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final loc = state.uri.path;

    // Unauthenticated users trying to reach any protected sub-path go to login.
    if (user == null && loc.startsWith('/admin/')) return '/admin';

    // Authenticated users hitting the login page go straight to dashboard.
    if (user != null && loc == '/admin') return '/admin/dashboard';

    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const MenuPage(),
    ),
    GoRoute(
      path: '/admin',
      builder: (_, _) => const LoginPage(),
    ),
    GoRoute(
      path: '/admin/dashboard',
      builder: (_, _) => const AdminGuard(child: DashboardPage()),
    ),
    GoRoute(
      path: '/admin/profile',
      builder: (_, _) => const AdminGuard(child: ProfilePage()),
    ),
    GoRoute(
      path: '/admin/sections',
      builder: (_, _) => const AdminGuard(child: SectionsPage()),
    ),
    GoRoute(
      path: '/admin/items',
      builder: (_, _) => const AdminGuard(child: ItemsPage()),
    ),
    GoRoute(
      path: '/admin/items/import',
      builder: (_, _) => const AdminGuard(child: BulkImportPage()),
    ),
    GoRoute(
      path: '/admin/settings',
      builder: (_, _) => const AdminGuard(child: SettingsPage()),
    ),
  ],
);

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
