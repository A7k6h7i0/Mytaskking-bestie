import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import 'api.dart';
import 'api_client.dart';
import 'auth_store.dart';
import 'models.dart';
import 'realtime.dart';
import 'socket_client.dart';

/// MyTaskKing — Riverpod state graph.
///
/// `authStoreProvider`, `apiProvider`, `socketProvider` are overridden by the
/// app's `main.dart` with concrete instances (one shared across the app).
/// Everything downstream consumes them through Riverpod so screens stay pure.

final authStoreProvider = Provider<BestieAuthStore>((_) => throw UnimplementedError('override in main'));
final apiProvider       = Provider<BestieApi>((_) => throw UnimplementedError('override in main'));
final socketProvider    = Provider<BestieSocket>((_) => throw UnimplementedError('override in main'));

/// Watches the auth store for sign-in / sign-out and rebuilds dependents.
final currentUserProvider = StreamProvider<BestieUser?>((ref) {
  final store = ref.watch(authStoreProvider);
  return store.changes;
});

/// Realtime hub — opens the socket on first watch, hands out an event stream.
/// Auto-closes the connection when nothing's watching anymore.
final realtimeProvider = Provider<BestieRealtime>((ref) {
  final socket = ref.watch(socketProvider);
  final rt = BestieRealtime(socket);
  rt.connect();
  ref.onDispose(rt.dispose);
  return rt;
});

// ----- dashboard -----
final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(apiProvider).dashboardOverview();
});

// ----- channels -----
final channelsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Re-fetch whenever a new chat message lands so the unread counters in the
  // sidebar stay live without polling.
  ref.watch(realtimeProvider).onAny('chat.message.created', ([_]) => ref.invalidateSelf());
  return ref.watch(apiProvider).listChannels();
});

// ----- chat history for a specific channel -----
final messagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, channelId) async {
  final api = ref.watch(apiProvider);
  final rt = ref.watch(realtimeProvider);
  rt.onAny('chat.message.created', ([data]) {
    if (data is Map && data['channelId'] == channelId) {
      ref.invalidateSelf();
    }
  });
  final data = await api.listMessages(channelId);
  final items = (data['items'] as List? ?? const []).cast<Map<String, dynamic>>();
  return items;
});

// ----- tasks (kanban) -----
final tasksKanbanProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.watch(realtimeProvider).onAny('task.created', ([_]) => ref.invalidateSelf());
  ref.watch(realtimeProvider).onAny('task.moved',   ([_]) => ref.invalidateSelf());
  return ref.watch(apiProvider).listTasks(view: 'kanban');
});

// ----- meetings -----
final meetingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(apiProvider).listMeetings();
});

// ----- calendar -----
final calendarRangeProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({DateTime from, DateTime to})>((ref, range) async {
  return ref.watch(apiProvider).listEvents(range.from, range.to);
});

// ----- notifications -----
final notificationsProvider = StreamProvider.autoDispose<Map<String, dynamic>>((ref) async* {
  final api = ref.watch(apiProvider);
  final rt = ref.watch(realtimeProvider);
  // Initial fetch + a re-fetch each time the server fires `activity.recorded`.
  yield await api.notificationsGrouped();
  final controller = StreamController<void>();
  rt.onAny('activity.recorded',      ([_]) => controller.add(null));
  rt.onAny('announcement.published', ([_]) => controller.add(null));
  ref.onDispose(() => controller.close());
  await for (final _ in controller.stream) {
    try { yield await api.notificationsGrouped(); } catch (_) {}
  }
});

// ----- saved + announcements + flags + sessions -----
final savedProvider          = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(apiProvider).listSaved());
final announcementsProvider  = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(apiProvider).listAnnouncements());
final flagsProvider          = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(apiProvider).myFlags());
final mySessionsProvider     = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(apiProvider).mySessions());

// ----- presence (current user) -----
final presenceStatusProvider = StateProvider<String>((_) => 'ACTIVE');

// ----- search -----
final searchQueryProvider = StateProvider<String>((_) => '');

/// Filter to scope search to a single kind. `null` = all kinds.
/// Mirrors the React command palette's chip filter.
final searchKindProvider  = StateProvider<String?>((_) => null);

final searchResultsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final q = ref.watch(searchQueryProvider).trim();
  final kind = ref.watch(searchKindProvider);
  if (q.isEmpty) return {'results': const <String, dynamic>{}};
  // Tiny debounce — wait 180ms then check the query didn't change.
  await Future.delayed(const Duration(milliseconds: 180));
  if (ref.read(searchQueryProvider).trim() != q ||
      ref.read(searchKindProvider) != kind) {
    throw _DebounceDropped();
  }
  return ref.watch(apiProvider).search(q, kinds: kind);
});

class _DebounceDropped implements Exception {}

// ----- theme -----
enum ThemeMode { light, dark, system }
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);

// ----- helpers exposed to screens -----
extension RefBestie on Ref {
  /// Convenience — every screen calls this to grab the api client.
  BestieApi get api => read(apiProvider);
  BestieRealtime get rt => read(realtimeProvider);
}

/// Surface a Dio error as a short human string for toasts/banners.
String formatApiError(Object err) {
  if (err is DioException) {
    final body = err.response?.data;
    if (body is Map && body['error'] is Map) {
      return (body['error']['message'] as String?) ?? 'Request failed';
    }
    return err.message ?? 'Network error';
  }
  return err.toString();
}
