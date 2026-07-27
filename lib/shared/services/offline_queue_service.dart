import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Stores failed report submissions locally when offline
/// They are retried when internet returns
class OfflineQueueService {
  static const String _boxName = 'offline_reports';
  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Save a report payload to offline queue
  static Future<void> enqueue(Map<String, dynamic> payload) async {
    final box = _box ?? await Hive.openBox(_boxName);
    final key = 'report_${DateTime.now().millisecondsSinceEpoch}';
    await box.put(key, jsonEncode(payload));
    debugPrint('Offline queue: saved $key');
  }

  /// Get all queued reports
  static List<Map<String, dynamic>> getAll() {
    final box = _box;
    if (box == null) return [];
    return box.values
      .map((v) {
        try { return Map<String, dynamic>.from(jsonDecode(v)); }
        catch (_) { return null; }
      })
      .whereType<Map<String, dynamic>>()
      .toList();
  }

  /// Remove a successfully submitted report from queue
  static Future<void> remove(String key) async {
    await _box?.delete(key);
  }

  /// Clear all queued items
  static Future<void> clear() async {
    await _box?.clear();
  }

  /// Get queue length
  static int get length => _box?.length ?? 0;

  static bool get hasItems => (_box?.length ?? 0) > 0;
}