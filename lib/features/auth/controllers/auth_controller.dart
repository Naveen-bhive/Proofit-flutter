import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/models/org_model.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/services/apple_auth_service.dart';
import '../../../shared/services/drive_service.dart';
import '../../../shared/services/google_auth_service.dart';
import '../../../shared/services/notification_service.dart';

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<void>>(
  (ref) => AuthController(ref.read(apiServiceProvider)));

class AuthController extends StateNotifier<AsyncValue<void>> {
  final ApiService _api;
  AuthController(this._api) : super(const AsyncData(null));

  Future<String?> _fcmToken() async {
    try {
      return await NotificationService.getToken()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendOtp(String phone) async {
    try {
      final res = await _api.post('/auth/send-otp', data: {'phone': phone});
      return res.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resendOtp(String phone) async {
    try {
      final res = await _api.post('/auth/resend-otp', data: {'phone': phone});
      return res.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> verifyOtp(String phone, String otp) async {
    try {
      final fcmToken = await _fcmToken();
      final res = await _api.post('/auth/verify-otp', data: {
        'phone': phone,
        'otp': otp,
        if (fcmToken != null) 'fcmToken': fcmToken,
      });
      if (res.data['success'] != true) return null;
      final data = res.data['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      await _saveSession(data);
      return data['user']['role'] ?? 'owner';
    } catch (_) {
      return null;
    }
  }

  // Returns: 'owner' | 'new_owner' | 'staff' | null
  Future<String?> signInWithPassword(String email, String password, {String? inviteToken}) async {
    try {
      state = const AsyncLoading();
      final fcmToken = await _fcmToken();

      final res = await _api.post('/auth/login', data: {
        'email':    email.trim(),
        'password': password,
        if (fcmToken != null) 'fcmToken': fcmToken,
        if (inviteToken != null) 'inviteToken': inviteToken,
      });

      if (res.data['success'] != true) {
        state = AsyncError(res.data['message'] ?? 'Login failed', StackTrace.current);
        return null;
      }

      final data = res.data['data'];
      if (data['isNewOwner'] == true) {
        await _saveSession(data);
        state = const AsyncData(null);
        return 'new_owner';
      }

      await _saveSession(data);
      state = const AsyncData(null);
      return data['user']['role'] ?? 'owner';
    } catch (e, st) {
      state = AsyncError(friendlyErrorMessage(e, fallback: 'Sign in failed. Please try again.'), st);
      return null;
    }
  }

  // Google Sign-In / Sign-Up — new users register as owners (then company setup)
  Future<String?> signInWithGoogle({String? inviteToken}) async {
    return _googleAuth(inviteToken: inviteToken);
  }

  /// Alias — same flow; backend creates owner account if email is new.
  Future<String?> signUpWithGoogle() => _googleAuth();

  Future<String?> _googleAuth({String? inviteToken}) async {
    try {
      state = const AsyncLoading();

      final googleResult = await GoogleAuthService.signIn();
      if (googleResult.cancelled) {
        state = const AsyncData(null);
        return null;
      }
      if (googleResult.error != null) {
        state = AsyncError(googleResult.error!, StackTrace.current);
        return null;
      }
      final googleData = googleResult.data;
      if (googleData == null) {
        state = const AsyncData(null);
        return null;
      }

      final fcmToken = await _fcmToken();
      final res = await _api.post('/auth/google', data: {
        if (googleData['idToken'] != null) 'idToken': googleData['idToken'],
        if (googleData['accessToken'] != null) 'accessToken': googleData['accessToken'],
        'email':    googleData['email'],
        'name':     googleData['name'],
        'photoUrl': googleData['photoUrl'],
        'googleId': googleData['googleId'],
        if (fcmToken != null) 'fcmToken': fcmToken,
        if (inviteToken != null) 'inviteToken': inviteToken,
      });

      if (res.data['success'] != true) {
        state = AsyncError(res.data['message'] ?? 'Google sign-in failed', StackTrace.current);
        return null;
      }

      final data = res.data['data'];
      final route = await _completeAuth(data);
      state = const AsyncData(null);
      return route;
    } catch (e, st) {
      state = AsyncError(friendlyErrorMessage(e, fallback: 'Google sign-in failed. Please try again.'), st);
      return null;
    }
  }

  // Sign in with Apple — new users register as owners (then company setup),
  // mirrors _googleAuth. Existing Google/email login are untouched by this.
  Future<String?> signInWithApple({String? inviteToken}) async {
    try {
      state = const AsyncLoading();

      final appleResult = await AppleAuthService.signIn();
      if (appleResult.cancelled) {
        state = const AsyncData(null);
        return null;
      }
      if (appleResult.error != null) {
        state = AsyncError(appleResult.error!, StackTrace.current);
        return null;
      }
      final appleData = appleResult.data;
      if (appleData == null) {
        state = const AsyncData(null);
        return null;
      }

      final fcmToken = await _fcmToken();
      final res = await _api.post('/auth/apple', data: {
        'identityToken': appleData['identityToken'],
        if (appleData['name'] != null) 'name': appleData['name'],
        if (fcmToken != null) 'fcmToken': fcmToken,
        if (inviteToken != null) 'inviteToken': inviteToken,
      });

      if (res.data['success'] != true) {
        state = AsyncError(res.data['message'] ?? 'Apple sign-in failed', StackTrace.current);
        return null;
      }

      final data = res.data['data'];
      final route = await _completeAuth(data);
      state = const AsyncData(null);
      return route;
    } catch (e, st) {
      state = AsyncError(friendlyErrorMessage(e, fallback: 'Apple sign-in failed. Please try again.'), st);
      return null;
    }
  }

  Future<String?> _completeAuth(Map<String, dynamic> data) async {
    if (data['isNewOwner'] == true) {
      await _saveSession(data);
      return 'new_owner';
    }
    await _saveSession(data);
    return data['user']['role'] ?? 'owner';
  }

  Future<String?> restoreSession() async {
    try {
      if (!await AuthStorage.isLoggedIn()) return null;

      final res = await _api.post('/auth/refresh-token');
      if (res.data['success'] == true) {
        final data = res.data['data'] as Map<String, dynamic>;
        await _api.saveToken(data['token'] as String);
        if (data['user'] != null) {
          await _saveSession({
            'token': data['token'],
            'user':  data['user'],
            'org':   data['org'] ?? {},
          });
        }
        await syncFcmToken();
        final user = await AuthStorage.getUser();
        return user?.role;
      }

      await logout();
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await logout();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> syncFcmToken() async {
    try {
      if (!await AuthStorage.isLoggedIn()) return;
      final token = await _fcmToken();
      if (token != null) {
        await _api.post('/notifications/fcm-token', data: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        });
      }
    } catch (_) {}
  }

  /// Fetch latest org from API and persist locally (company name, plan, etc.).
  Future<OrgModel?> syncOrgFromServer() async {
    try {
      if (!await AuthStorage.isLoggedIn()) return null;
      final res = await _api.get('/auth/org');
      if (res.data['success'] != true || res.data['data'] == null) return null;
      final org = OrgModel.fromJson(Map<String, dynamic>.from(res.data['data']));
      await AuthStorage.updateOrg(org);
      return org;
    } catch (_) {
      return null;
    }
  }

  Future<bool> setupOwner(String companyName, {String? ownerName}) async {
    try {
      final res = await _api.post('/auth/owner-setup', data: {
        'companyName': companyName,
        if (ownerName != null && ownerName.isNotEmpty) 'ownerName': ownerName,
      });
      if (res.data['success'] != true) {
        final msg = res.data['message'] as String?;
        state = AsyncError(msg ?? 'Setup failed', StackTrace.current);
        return false;
      }
      await _saveSession(res.data['data']);
      return true;
    } catch (e, st) {
      state = AsyncError(
        friendlyErrorMessage(e, fallback: 'Could not create your account. Please try again.'),
        st,
      );
      return false;
    }
  }

  Future<Map<String, dynamic>?> getInviteDetails(String token) async {
    try {
      final res = await _api.get('/auth/invite/$token');
      return res.data['success'] == true ? res.data['data'] : null;
    } catch (_) { return null; }
  }

  Future<bool> acceptInvite(String token) async {
    try {
      return (await _api.post('/auth/invite/$token/accept')).data['success'] == true;
    } catch (_) { return false; }
  }

  Future<({bool success, String message})> requestPasswordReset(String email) async {
    try {
      final res = await _api.post('/auth/forgot-password', data: {'email': email.trim()});
      if (res.data['success'] == true) {
        return (success: true, message: res.data['message'] as String? ?? 'Reset code sent if the account exists.');
      }
      return (success: false, message: res.data['message'] as String? ?? 'Could not send reset code');
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? e.response?.data['message'] as String? : null;
      return (success: false, message: friendlyErrorMessage(msg ?? e, fallback: 'Could not send reset code'));
    } catch (e) {
      return (success: false, message: friendlyErrorMessage(e, fallback: 'Could not send reset code'));
    }
  }

  Future<({bool success, String message})> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    try {
      final res = await _api.post('/auth/reset-password', data: {
        'email':    email.trim(),
        'code':     code.trim(),
        'password': password,
      });
      if (res.data['success'] == true) {
        return (success: true, message: res.data['message'] as String? ?? 'Password updated');
      }
      return (success: false, message: res.data['message'] as String? ?? 'Could not reset password');
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? e.response?.data['message'] as String? : null;
      return (success: false, message: friendlyErrorMessage(msg ?? e, fallback: 'Could not reset password'));
    } catch (e) {
      return (success: false, message: friendlyErrorMessage(e, fallback: 'Could not reset password'));
    }
  }

  Future<({bool hasPassword, String email})?> fetchAccountInfo() async {
    try {
      if (!await AuthStorage.isLoggedIn()) return null;
      final res = await _api.get('/auth/account');
      if (res.data['success'] != true) return null;
      final data = res.data['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      return (
        hasPassword: data['hasPassword'] == true,
        email: data['email'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<({bool success, String message})> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    try {
      final res = await _api.put('/auth/change-password', data: {
        if (currentPassword != null && currentPassword.isNotEmpty) 'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
      if (res.data['success'] == true) {
        return (success: true, message: res.data['message'] as String? ?? 'Password updated');
      }
      return (success: false, message: res.data['message'] as String? ?? 'Could not update password');
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? e.response?.data['message'] as String? : null;
      return (success: false, message: friendlyErrorMessage(msg ?? e, fallback: 'Could not update password'));
    } catch (e) {
      return (success: false, message: friendlyErrorMessage(e, fallback: 'Could not update password'));
    }
  }

  Future<void> logout() async {
    try {
      final fcm = await _fcmToken();
      if (fcm != null) {
        await _api.post('/notifications/fcm-clear', data: {'token': fcm});
      }
    } catch (_) {}
    try {
      await GoogleAuthService.signOut().timeout(const Duration(seconds: 4));
    } catch (_) {}
    DriveService.clearCache();
    await AuthStorage.clear();
    await _api.clearToken();
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    await _api.saveToken(data['token']);
    final user = UserModel.fromJson(data['user']);
    final org  = OrgModel.fromJson(data['org'] ?? {});
    await AuthStorage.saveSession(token: data['token'], user: user, org: org);
    await syncFcmToken();
  }
}
