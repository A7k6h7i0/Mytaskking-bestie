import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists offline field actions until connectivity returns.
class FieldOfflineQueue {
  FieldOfflineQueue._();
  static const _key = 'field_offline_queue_v1';

  static Future<Map<String, dynamic>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return {'visits': <dynamic>[], 'gps': <dynamic>[], 'incidents': <dynamic>[]};
    }
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  static Future<void> enqueueVisit(Map<String, dynamic> visit) async {
    final data = await _read();
    final list = List<Map<String, dynamic>>.from(
      (data['visits'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          const [],
    );
    list.add(visit);
    data['visits'] = list;
    await _write(data);
  }

  static Future<void> enqueueGps(Map<String, dynamic> gps) async {
    final data = await _read();
    final list = List<Map<String, dynamic>>.from(
      (data['gps'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          const [],
    );
    list.add(gps);
    data['gps'] = list;
    await _write(data);
  }

  static Future<void> enqueueIncident(Map<String, dynamic> incident) async {
    final data = await _read();
    final list = List<Map<String, dynamic>>.from(
      (data['incidents'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          const [],
    );
    list.add(incident);
    data['incidents'] = list;
    await _write(data);
  }

  static Future<void> completeQueuedVisit(
    String offlineId, {
    String? notes,
  }) async {
    final data = await _read();
    final list = List<Map<String, dynamic>>.from(
      (data['visits'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          const [],
    );
    for (var i = 0; i < list.length; i++) {
      final id = list[i]['offlineId']?.toString() ?? list[i]['offline_id']?.toString();
      if (id == offlineId) {
        list[i] = {
          ...list[i],
          'check_out_at': DateTime.now().toIso8601String(),
          'status': 'completed',
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        };
        break;
      }
    }
    data['visits'] = list;
    await _write(data);
  }

  static Future<Map<String, dynamic>> snapshot() => _read();

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
