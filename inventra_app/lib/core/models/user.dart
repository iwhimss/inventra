import 'dart:convert';

class User {
  final String id;
  final String staffId;
  final String passwordHash;
  final String role;
  final String? name;
  final Map<String, bool> permissions;

  User({
    required this.id,
    required this.staffId,
    required this.passwordHash,
    required this.role,
    this.name,
    Map<String, bool>? permissions,
  }) : permissions = permissions ?? _defaultPermissions(role);

  static Map<String, bool> _defaultPermissions(String role) {
    if (role == 'owner' || role == 'manager') {
      return {'pos': true, 'products': true, 'history': true, 'reports': true, 'labels': true, 'settings': true, 'converter': true, 'movements': true, 'clients': true};
    }
    return {'pos': true, 'products': false, 'history': false, 'reports': false, 'labels': false, 'settings': false, 'converter': false, 'movements': false, 'clients': false};
  }

  bool hasPermission(String key) => role == 'owner' || (permissions[key] ?? false);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'staff_id': staffId,
      'password_hash': passwordHash,
      'role': role,
      'name': name ?? '',
      'permissions': json.encode(permissions),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    Map<String, bool> perms;
    final permStr = map['permissions']?.toString() ?? '';
    try {
      if (permStr.startsWith('{')) {
        final decoded = json.decode(permStr) as Map<String, dynamic>;
        perms = decoded.map((k, v) => MapEntry(k, v == true));
      } else {
        perms = _defaultPermissions(map['role']?.toString() ?? 'staff');
      }
    } catch (_) {
      perms = _defaultPermissions(map['role']?.toString() ?? 'staff');
    }

    return User(
      id: map['id'],
      staffId: map['staff_id'],
      passwordHash: map['password_hash'],
      role: map['role'] ?? 'staff',
      name: (map['name'] != null && map['name'].toString().isNotEmpty)
          ? map['name'].toString()
          : null,
      permissions: perms,
    );
  }
}
