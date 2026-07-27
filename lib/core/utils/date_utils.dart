import 'package:intl/intl.dart';
DateTime? parseApiDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.isUtc ? value.toLocal() : value;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

String formatApiTime(dynamic value, {String pattern = 'h:mm a'}) {
  final dt = parseApiDate(value);
  if (dt == null) return '--:--';
  return DateFormat(pattern).format(dt);
}

String formatApiDate(dynamic value, {String pattern = 'EEE, d MMM yyyy'}) {
  final dt = parseApiDate(value);
  if (dt == null) return '';
  return DateFormat(pattern).format(dt);
}

/// yyyy-MM-dd for API date filters (device local calendar day).
String todayDateString() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
