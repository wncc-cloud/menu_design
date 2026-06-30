import 'package:cloud_firestore/cloud_firestore.dart';

enum AdminRole { owner, manager, staff }

class AdminModel {
  final String uid;
  final String email;
  final String name;
  final AdminRole role;
  final bool active;
  final DateTime createdAt;

  const AdminModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.active,
    required this.createdAt,
  });

  factory AdminModel.fromJson(Map<String, dynamic> json) {
    return AdminModel(
      uid: json['uid'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: _parseRole(json['role'] as String? ?? ''),
      active: json['active'] as bool? ?? false,
      createdAt:
          (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  static AdminRole _parseRole(String value) => switch (value) {
        'owner' => AdminRole.owner,
        'manager' => AdminRole.manager,
        _ => AdminRole.staff,
      };

  String get roleLabel => switch (role) {
        AdminRole.owner => 'Owner',
        AdminRole.manager => 'Manager',
        AdminRole.staff => 'Staff',
      };
}
