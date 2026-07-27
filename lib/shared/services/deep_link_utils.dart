/// Parses staff-invite tokens from app / universal / intent deep links.
class DeepLinkUtils {
  DeepLinkUtils._();

  /// Supports:
  /// - https://app.proofitapp.in/invite/:token
  /// - proofit://invite/:token
  /// - intent://invite/:token#Intent;scheme=proofit;...
  static String? inviteTokenFromUri(Uri? uri) {
    if (uri == null) return null;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (uri.host == 'invite') {
      if (segments.isNotEmpty) return _cleanToken(segments.first);
      final path = uri.path.replaceFirst(RegExp(r'^/'), '');
      if (path.isNotEmpty) return _cleanToken(path.split('/').first);
    }

    if (uri.path.startsWith('/invite/')) {
      return _cleanToken(uri.path.replaceFirst('/invite/', '').split('/').first);
    }

    final inviteIdx = segments.indexOf('invite');
    if (inviteIdx >= 0 && inviteIdx + 1 < segments.length) {
      return _cleanToken(segments[inviteIdx + 1]);
    }

    final queryToken = uri.queryParameters['token'];
    if (queryToken != null && queryToken.isNotEmpty) {
      return _cleanToken(queryToken);
    }

    return null;
  }

  static String? _cleanToken(String raw) {
    final token = Uri.decodeComponent(raw.split('?').first.split('#').first).trim();
    return token.isEmpty ? null : token;
  }
}
