import 'package:mytaskking_core/mytaskking_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'field_offline_queue.dart';

/// Pulls master data and flushes queued offline field actions.
class FieldSyncService {
  static const _lastSyncKey = 'field_last_sync_at';

  static Future<void> syncAll(BestieApi api) async {
    await _flushOffline(api);
    await _pullMaster(api);
  }

  static Future<void> _pullMaster(BestieApi api) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastSyncKey);
    final resp = await api.fieldSyncPull(lastSyncedAt: last);
    await prefs.setString(
      _lastSyncKey,
      resp['syncedAt']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  static Future<void> _flushOffline(BestieApi api) async {
    final pending = await FieldOfflineQueue.snapshot();
    final visits = (pending['visits'] as List?) ?? const [];
    final gps = (pending['gps'] as List?) ?? const [];
    final incidents = (pending['incidents'] as List?) ?? const [];
    if (visits.isEmpty && gps.isEmpty && incidents.isEmpty) return;

    try {
      await api.fieldSyncBatch({
        'visits': visits,
        'gps': gps,
        'incidents': incidents,
      });
      await FieldOfflineQueue.clear();
    } catch (_) {
      // Keep queued items until the next sync attempt.
    }
  }
}
