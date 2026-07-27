import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/api_error_utils.dart';

String authErrorMessage(AsyncValue<void> authState, {bool google = false}) {
  if (!authState.hasError) {
    if (google) {
      return 'Google sign-in was cancelled. If you saw "Access blocked", add your Gmail as a test user in Google Cloud Console → OAuth consent screen.';
    }
    return 'Invalid email or password';
  }
  return friendlyErrorMessage(
    authState.error,
    fallback: google
        ? 'Google sign-in failed. Please try again.'
        : 'Sign in failed. Please try again.',
  );
}

String? extractInviteToken(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    final segments = uri.pathSegments;
    final inviteIdx = segments.indexOf('invite');
    if (inviteIdx >= 0 && inviteIdx + 1 < segments.length) {
      return segments[inviteIdx + 1];
    }
    if (uri.path.startsWith('/invite/')) {
      return uri.path.replaceFirst('/invite/', '').split('/').first;
    }
  }
  if (trimmed.contains('/invite/')) {
    return trimmed.split('/invite/').last.split('/').first.split('?').first;
  }
  return trimmed;
}
