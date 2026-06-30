import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/models/admin_model.dart';
import '../../shared/permissions/permission_service.dart';
import '../../shared/repositories/admin_repository.dart';
import 'auth_service.dart';

part 'auth_provider.g.dart';

@riverpod
AuthService authService(Ref ref) => AuthService(FirebaseAuth.instance);

@riverpod
AdminRepository adminRepository(Ref ref) =>
    AdminRepository(FirebaseFirestore.instance);

@riverpod
Stream<User?> authStateChanges(Ref ref) =>
    FirebaseAuth.instance.authStateChanges();

// keepAlive: admin status is session-scoped — re-fetches only when auth changes.
@Riverpod(keepAlive: true)
Future<AdminModel?> currentAdmin(Ref ref) async {
  final user = ref.watch(authStateChangesProvider).asData?.value;
  if (user == null) return null;
  return ref.read(adminRepositoryProvider).fetchAdmin(user.uid);
}

@riverpod
PermissionService? permissionService(Ref ref) {
  final admin = ref.watch(currentAdminProvider).asData?.value;
  if (admin == null) return null;
  return PermissionService(admin);
}
