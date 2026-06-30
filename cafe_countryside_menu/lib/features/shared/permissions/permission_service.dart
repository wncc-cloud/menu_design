import '../models/admin_model.dart';

// Single source of truth for role-based permissions (per plan.md).
// Used everywhere — do not duplicate permission logic in widgets.
class PermissionService {
  final AdminModel admin;
  const PermissionService(this.admin);

  bool get canManageSections => _ownerOrManager;
  bool get canManageItems => _ownerOrManager;
  bool get canManagePrices => _ownerOrManager;
  bool get canManageTimings => _ownerOrManager;
  bool get canPublish => _ownerOrManager;
  bool get canManageBusinessSettings => admin.role == AdminRole.owner;
  bool get canManageAdmins => admin.role == AdminRole.owner;
  // All roles (owner, manager, staff) can toggle item availability.
  bool get canToggleAvailability => true;

  bool get _ownerOrManager =>
      admin.role == AdminRole.owner || admin.role == AdminRole.manager;
}
