import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../models/org_model.dart';
import '../../core/constants/app_constants.dart';

class AuthStorage {
  static const _storage = FlutterSecureStorage();

  static Future<void> saveSession({
    required String token,
    required UserModel user,
    required OrgModel org,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.tokenKey, value: token),
      _storage.write(key: AppConstants.userKey,  value: jsonEncode(user.toJson())),
      _storage.write(key: AppConstants.orgKey,   value: jsonEncode(org.toJson())),
    ]);
  }

  static Future<void> updateOrg(OrgModel org) async {
    await _storage.write(key: AppConstants.orgKey, value: jsonEncode(org.toJson()));
  }

  static Future<String?> getToken() => _storage.read(key: AppConstants.tokenKey);

  static Future<UserModel?> getUser() async {
    final raw = await _storage.read(key: AppConstants.userKey);
    if (raw == null) return null;
    return UserModel.fromJson(jsonDecode(raw));
  }

  static Future<OrgModel?> getOrg() async {
    final raw = await _storage.read(key: AppConstants.orgKey);
    if (raw == null) return null;
    return OrgModel.fromJson(jsonDecode(raw));
  }

  static Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: AppConstants.tokenKey),
      _storage.delete(key: AppConstants.userKey),
      _storage.delete(key: AppConstants.orgKey),
    ]);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}