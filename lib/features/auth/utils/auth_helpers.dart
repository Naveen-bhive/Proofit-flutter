import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/api_error_utils.dart';

/// [provider]: null for email/password, or 'google' / 'apple' for social sign-in.
String authErrorMessage(AsyncValue<void> authState, {String? provider, bool google = false}) {
  final resolvedProvider = provider ?? (google ? 'google' : null);

  if (!authState.hasError) {
    if (resolvedProvider == 'google') {
      return 'Google sign-in was cancelled. If you saw "Access blocked", add your Gmail as a test user in Google Cloud Console → OAuth consent screen.';
    }
    if (resolvedProvider == 'apple') {
      return 'Apple sign-in was cancelled.';
    }
    return 'Invalid email or password';
  }
  return friendlyErrorMessage(
    authState.error,
    fallback: switch (resolvedProvider) {
      'google' => 'Google sign-in failed. Please try again.',
      'apple'  => 'Apple sign-in failed. Please try again.',
      _        => 'Sign in failed. Please try again.',
    },
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
