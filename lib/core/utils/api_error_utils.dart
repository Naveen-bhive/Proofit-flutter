import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Converts API / network errors into short, user-facing text.
String friendlyErrorMessage(
  dynamic error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error == null) return fallback;
  if (error is String) {
    final text = error.trim();
    if (text.isEmpty) return fallback;
    if (_looksTechnical(text)) return fallback;
    return _humanizeBusinessMessage(text);
  }

  if (error is DioException) {
    final apiMessage = _messageFromResponseData(error.response?.data);
    if (apiMessage != null && apiMessage.isNotEmpty && !_looksTechnical(apiMessage)) {
      return _humanizeBusinessMessage(apiMessage);
    }

    final status = error.response?.statusCode;
    if (status == 400) return 'Please check your details and try again.';
    if (status == 401) return 'Please sign in again.';
    if (status == 403) {
      return 'This feature is not available on your current plan. Upgrade in Settings to continue.';
    }
    if (status == 404) return 'We couldn\'t find what you were looking for.';
    if (status == 409) return 'That conflicts with existing data. Try a different value.';
    if (status == 429) return 'Too many attempts. Please wait a few minutes.';
    if (status != null && status >= 500) {
      return 'Server error. Please try again in a moment.';
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection timed out. Check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'Cannot reach the server. Check your internet connection.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      default:
        break;
    }

    return fallback;
  }

  final text = error.toString();
  if (_looksTechnical(text)) return fallback;
  return fallback;
}

String? _messageFromResponseData(dynamic data) {
  if (data == null) return null;
  if (data is Map) {
    final msg = data['message'];
    if (msg is String && msg.trim().isNotEmpty) return msg.trim();
  }
  if (data is Uint8List || data is List<int>) {
    try {
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      final text = utf8.decode(bytes);
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final msg = decoded['message'];
        if (msg is String && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {}
  }
  if (data is String && data.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        final msg = decoded['message'];
        if (msg is String && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {}
  }
  return null;
}

String _humanizeBusinessMessage(String text) {
  return text
      .replaceAll('shareReport', 'Sharing report PDFs')
      .replaceAll('liveMap', 'Live staff map')
      .replaceAll('workingHours', 'Working hours')
      .replaceAll(RegExp(r'\bexport\b'), 'Exporting reports');
}

bool _looksTechnical(String text) {
  final lower = text.toLowerCase();
  return lower.contains('dioexception') ||
      lower.contains('socketexception') ||
      lower.contains('formatexception') ||
      lower.contains('validatestatus') ||
      lower.contains('stacktrace') ||
      lower.contains('bad response') ||
      lower.contains('httpexception');
}
