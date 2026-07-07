import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Survives app kill while the telecaller is in the system Phone app.
class TelecallerPendingCall {
  TelecallerPendingCall._();

  static const _key = 'telecaller_pending_call_v1';

  static Future<void> save({
    required String callId,
    required Map<String, dynamic> lead,
    required DateTime startedAt,
    required bool micActive,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'callId': callId,
        'lead': lead,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        'micActive': micActive,
      }),
    );
  }

  static Future<({
    String callId,
    Map<String, dynamic> lead,
    DateTime startedAt,
    bool micActive,
  })?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final callId = map['callId']?.toString();
      final lead = map['lead'];
      final startedAtMs = map['startedAtMs'];
      if (callId == null || lead is! Map) return null;
      return (
        callId: callId,
        lead: Map<String, dynamic>.from(lead),
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          (startedAtMs as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        micActive: map['micActive'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
