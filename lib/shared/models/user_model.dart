class UserModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? photoUrl;
  final String role;
  final String workLocation;
  final String orgId;
  final int dailyTarget;
  final int streak;
  final String? fcmToken;

  /// Owner features delegated to this staff member (AppPermissions ids).
  final List<String> permissions;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.photoUrl,
    required this.role,
    this.workLocation = 'wfo',
    required this.orgId,
    this.dailyTarget = 0,
    this.streak = 0,
    this.fcmToken,
    this.permissions = const [],
  });

  bool get isOwner => role == 'owner';
  bool get isStaff => role == 'staff';

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['_id'] ?? '',
        name: json['name'] ?? '',
        phone: json['phone'] ?? '',
        email: json['email'],
        photoUrl: json['photoUrl'],
        role: json['role'] ?? 'staff',
        workLocation: json['workLocation'] == 'office'
            ? 'wfo'
            : (json['workLocation'] ?? 'wfo'),
        orgId: json['orgId']?.toString() ?? '',
        dailyTarget: json['dailyTarget'] ?? 0,
        streak: json['streak'] ?? 0,
        fcmToken: json['fcmToken'],
        permissions:
            (json['permissions'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
      );

  UserModel copyWith({List<String>? permissions}) => UserModel(
        id: id,
        name: name,
        phone: phone,
        email: email,
        photoUrl: photoUrl,
        role: role,
        workLocation: workLocation,
        orgId: orgId,
        dailyTarget: dailyTarget,
        streak: streak,
        fcmToken: fcmToken,
        permissions: permissions ?? this.permissions,
      );

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'phone': phone,
        'role': role,
        'workLocation': workLocation,
        'orgId': orgId,
        'dailyTarget': dailyTarget,
        'streak': streak,
        'permissions': permissions,
      };
}
