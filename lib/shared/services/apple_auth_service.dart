import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../core/utils/api_error_utils.dart';

class AppleSignInResult {
  final Map<String, dynamic>? data;
  final String? error;
  final bool cancelled;

  const AppleSignInResult({this.data, this.error, this.cancelled = false});
}

class AppleAuthService {
  static Future<bool> isAvailable() => SignInWithApple.isAvailable();

  /// Apple sends the person's name only once — on the very first authorization
  /// this app ever performs for them — and only here on the client, never inside
  /// the identity token. The backend trusts it only when creating a brand-new user.
  static Future<AppleSignInResult> signIn() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      if (credential.identityToken == null || credential.identityToken!.isEmpty) {
        return const AppleSignInResult(error: 'Apple did not return credentials. Try again.');
      }

      final fullName = [credential.givenName, credential.familyName]
          .where((s) => s != null && s.trim().isNotEmpty)
          .join(' ')
          .trim();

      return AppleSignInResult(data: {
        'identityToken': credential.identityToken,
        if (fullName.isNotEmpty) 'name': fullName,
      });
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AppleSignInResult(cancelled: true);
      }
      debugPrint('Apple Sign-In error: ${e.code} ${e.message}');
      return AppleSignInResult(error: e.message.isNotEmpty ? e.message : 'Apple sign-in failed. Please try again.');
    } catch (e) {
      debugPrint('Apple Sign-In error: $e');
      return AppleSignInResult(error: friendlyErrorMessage(e, fallback: 'Apple sign-in failed. Please try again.'));
    }
  }
}
