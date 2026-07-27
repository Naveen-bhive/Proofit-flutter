import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/api_error_utils.dart';

class GoogleSignInResult {
  final Map<String, dynamic>? data;
  final String? error;
  final bool cancelled;

  const GoogleSignInResult({this.data, this.error, this.cancelled = false});
}

class DriveAccessResult {
  final bool ok;
  final String? error;

  const DriveAccessResult({required this.ok, this.error});
}

class GoogleAuthService {
  // Web OAuth client ID from google-services.json (client_type 3)
  static final GoogleSignIn _authSignIn = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: AppConstants.googleServerClientId,
  );

  static GoogleSignIn? _driveSignIn;
  static GoogleSignInAccount? _currentUser;
  static http.Client? _authClient;
  static drive.DriveApi? _driveApi;

  static GoogleSignIn get _drive => _driveSignIn ??= GoogleSignIn(
    scopes: AppConstants.googleScopes,
    serverClientId: AppConstants.googleServerClientId,
  );

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
    return friendlyErrorMessage(e, fallback: 'Google sign-in failed. Please try again.');
  }

  /// Sign in or sign up — same Google flow; backend creates account if new.
  static Future<GoogleSignInResult> signIn() async {
    try {
      // Clear cached account so the account picker works reliably after logout.
      try { await _authSignIn.signOut(); } catch (_) {}

      final account = await _authSignIn.signIn();
      if (account == null) {
        return const GoogleSignInResult(cancelled: true);
      }

      _currentUser = account;
      final auth = await account.authentication;

      if ((auth.accessToken == null || auth.accessToken!.isEmpty) &&
          (auth.idToken == null || auth.idToken!.isEmpty)) {
        return const GoogleSignInResult(error: 'Google did not return credentials. Try again.');
      }

      return GoogleSignInResult(data: {
        'idToken':     auth.idToken,
        'accessToken': auth.accessToken,
        'email':       account.email,
        'name':        account.displayName,
        'photoUrl':    account.photoUrl,
        'googleId':    account.id,
      });
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      return GoogleSignInResult(error: _mapError(e));
    }
  }

  /// Request Drive scope for photo uploads. Uses silent sign-in only unless [interactive].
  /// Avoid interactive sign-in during uploads — OAuth "Testing" apps block non-test users (403).
  static Future<DriveAccessResult> ensureDriveAccess({bool interactive = false}) async {
    try {
      var account = await _drive.signInSilently();
      if (account == null && interactive) {
        account = await _drive.signIn();
      }
      if (account == null) {
        return const DriveAccessResult(
          ok: false,
          error: 'Google Drive not linked on this device. Photos will upload via server backup.',
        );
      }

      _currentUser = account;
      _authClient = await _drive.authenticatedClient();
      if (_authClient == null) {
        return const DriveAccessResult(
          ok: false,
          error: 'Could not authorize Google Drive. Sign in with Google and allow Drive access.',
        );
      }
      _driveApi = drive.DriveApi(_authClient!);
      return const DriveAccessResult(ok: true);
    } catch (e) {
      debugPrint('Drive auth error: $e');
      return DriveAccessResult(ok: false, error: _mapError(e));
    }
  }

  static Future<void> signOut() async {
    await Future.wait([
      _authSignIn.signOut(),
      if (_driveSignIn != null) _driveSignIn!.signOut(),
    ]);
    _currentUser = null;
    _authClient  = null;
    _driveApi    = null;
  }

  static drive.DriveApi? get driveApi => _driveApi;
  static GoogleSignInAccount? get currentUser => _currentUser;

  static Future<bool> refreshIfNeeded() async {
    try {
      if (_currentUser == null) return false;
      final client = _driveSignIn != null
          ? await _drive.authenticatedClient()
          : await _authSignIn.authenticatedClient();
      if (client == null) return false;
      _authClient = client;
      if (_driveSignIn != null) _driveApi = drive.DriveApi(_authClient!);
      return true;
    } catch (_) { return false; }
  }
}
