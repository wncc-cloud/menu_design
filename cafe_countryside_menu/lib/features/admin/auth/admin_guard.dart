import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'access_denied_page.dart';
import 'auth_provider.dart';

/// Wraps every protected admin page.
/// Shows a spinner while the admins collection check is in-flight,
/// AccessDeniedPage if the user is not in the collection (or inactive),
/// or the actual page once confirmed.
class AdminGuard extends ConsumerWidget {
  final Widget child;
  const AdminGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminAsync = ref.watch(currentAdminProvider);
    return adminAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const AccessDeniedPage(),
      data: (admin) =>
          admin != null && admin.active ? child : const AccessDeniedPage(),
    );
  }
}
