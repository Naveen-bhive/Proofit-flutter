import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/api_error_utils.dart';

class GoogleSignInResult {
  final Map<String, dynamic>? data;
  final String? error;
  final bool cancelled;

  const GoogleSignInResult({this.data, this.error, this.cancelled = false});
}

class GoogleAuthService {
  // Web OAuth client ID from google-services.json (client_type 3)
  static final GoogleSignIn _authSignIn = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: AppConstants.googleServerClientId,
  );

  static GoogleSignInAccount? _currentUser;

  static String _mapError(Object e) {
    if (e is PlatformException) {
      final msg = e.message ?? '';
      if (msg.contains('access_denied') || msg.contains('403')) {
        return 'Google blocked sign-in. In Google Cloud Console → OAuth consent screen, add your Gmail under Test users, or publish the app.';
      }
      if (msg.contains('ApiException: 10')) {
        return 'Google Sign-In failed (developer config). Add this device\'s SHA-1 in Firebase → Project settings → Your apps → com.bhive.proofit, then download a new google-services.json and run flutter clean.';
      }
      if (msg.contains('ApiException: 12500')) {
        return 'Google Play Services error. Update Google Play Services on your device.';
      }
      return e.message ?? e.code;
    }
    return friendlyErrorMessage(e,
        fallback: 'Google sign-in failed. Please try again.');
  }

  /// Sign in or sign up — same Google flow; backend creates account if new.
  static Future<GoogleSignInResult> signIn() async {
    try {
      // Clear cached account so the account picker works reliably after logout.
      try {
        await _authSignIn.signOut();
      } catch (_) {}

      final account = await _authSignIn.signIn();
      if (account == null) {
        return const GoogleSignInResult(cancelled: true);
      }

      _currentUser = account;
      final auth = await account.authentication;

      if ((auth.accessToken == null || auth.accessToken!.isEmpty) &&
          (auth.idToken == null || auth.idToken!.isEmpty)) {
        return const GoogleSignInResult(
            error: 'Google did not return credentials. Try again.');
      }

      return GoogleSignInResult(data: {
        'idToken': auth.idToken,
        'accessToken': auth.accessToken,
        'email': account.email,
        'name': account.displayName,
        'photoUrl': account.photoUrl,
        'googleId': account.id,
      });
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      return GoogleSignInResult(error: _mapError(e));
    }
  }

  static Future<void> signOut() async {
    await _authSignIn.signOut();
    _currentUser = null;
  }

  static GoogleSignInAccount? get currentUser => _currentUser;
}
