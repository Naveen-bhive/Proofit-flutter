class UserModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? photoUrl;
  final String role;
  final String orgId;
  final int dailyTarget;
  final int streak;
  final String? fcmToken;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.photoUrl,
    required this.role,
    required this.orgId,
    this.dailyTarget = 0,
    this.streak = 0,
    this.fcmToken,
  });

  bool get isOwner => role == 'owner';
  bool get isStaff => role == 'staff';

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id:          json['_id'] ?? '',
    name:        json['name'] ?? '',
    phone:       json['phone'] ?? '',
    email:       json['email'],
    photoUrl:    json['photoUrl'],
    role:        json['role'] ?? 'staff',
    orgId:       json['orgId']?.toString() ?? '',
    dailyTarget: json['dailyTarget'] ?? 0,
    streak:      json['streak'] ?? 0,
    fcmToken:    json['fcmToken'],
  );

  Map<String, dynamic> toJson() => {
    '_id': id, 'name': name, 'phone': phone,
    'role': role, 'orgId': orgId,
    'dailyTarget': dailyTarget, 'streak': streak,
  };
}