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

final authStoreProvider = Provider<BestieAuthStore>(
    (_) => throw UnimplementedError('override in main'));
final apiProvider =
    Provider<BestieApi>((_) => throw UnimplementedError('override in main'));
final socketProvider =
    Provider<BestieSocket>((_) => throw UnimplementedError('override in main'));

/// Watches the auth store for sign-in / sign-out and rebuilds dependents.
final currentUserProvider = StreamProvider<BestieUser?>((ref) {
  final store = ref.watch(authStoreProvider);
  return store.changes;
});

/// Realtime hub — opens the socket on first watch, hands out an event stream.
/// Re-opens whenever the auth store changes (login/logout/token refresh) so
/// global listeners like the incoming-call ringer don't sit on a dead socket
/// with a stale token.
final realtimeProvider = Provider<BestieRealtime>((ref) {
  final socket = ref.watch(socketProvider);
  final auth = ref.watch(authStoreProvider);
  final rt = BestieRealtime(socket);

  // Initial connect — safely no-ops if auth token isn't ready yet.
  rt.connect();

  // Reconnect on auth change. The first event a brand-new login fires is the
  // user becoming non-null; reconnect tears down the (token-less) socket and
  // opens a fresh one with the access token in the handshake.
  StreamSubscription? sub;
  sub = auth.changes.listen((_) => rt.reconnect());

  ref.onDispose(() {
    sub?.cancel();
    rt.dispose();
  });
  return rt;
});

/// Kicks the realtime provider so listeners stay subscribed at boot, even
/// before any screen explicitly watches them. Read this in your top-level
/// widget so the global incoming-call overlay receives `call.incoming`
/// regardless of which screen the user is currently on.
final realtimeBootProvider = Provider<bool>((ref) {
  ref.watch(realtimeProvider);
  return true;
});

// ----- dashboard -----
final dashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(apiProvider).dashboardOverview();
});

// ----- channels -----
final channelsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Re-fetch whenever a new chat message lands so the unread counters in the
  // sidebar stay live without polling. The unsubscribe is registered with
  // onDispose so the listener is removed when the provider rebuilds — without
  // this, every invalidateSelf() leaked another handler (quadratic growth →
  // refetch storms).
  final unsub = ref
      .watch(realtimeProvider)
      .onAny('chat.message.created', ([_]) => ref.invalidateSelf());
  ref.onDispose(unsub);
  return ref.watch(apiProvider).listChannels();
});

// ----- chat history for a specific channel -----
final messagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, channelId) async {
  final api = ref.watch(apiProvider);
  final rt = ref.watch(realtimeProvider);
  // Register listeners with onDispose unsubscribes so a rebuild
  // (invalidateSelf on each incoming message) doesn't leak duplicate handlers.
  ref.onDispose(rt.onAny('chat.message.created', ([data]) {
    if (data is Map && data['channelId'] == channelId) {
      ref.invalidateSelf();
    }
  }));
  ref.onDispose(rt.onAny('chat.message.receipt', ([data]) {
    if (data is Map) {
      ref.invalidateSelf();
    }
  }));
  ref.onDispose(rt.onAny('chat.message.receipts.bulk', ([data]) {
    if (data is Map && data['channelId'] == channelId) {
      ref.invalidateSelf();
    }
  }));
  final data = await api.listMessages(channelId);
  final items =
      (data['items'] as List? ?? const []).cast<Map<String, dynamic>>();
  return items;
});

// ----- tasks (kanban) -----
final tasksKanbanProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref
      .watch(realtimeProvider)
      .onAny('task.created', ([_]) => ref.invalidateSelf());
  ref
      .watch(realtimeProvider)
      .onAny('task.moved', ([_]) => ref.invalidateSelf());
  ref
      .watch(realtimeProvider)
      .onAny('task.auto_promoted', ([_]) => ref.invalidateSelf());
  ref
      .watch(realtimeProvider)
      .onAny('task.assignment.changed', ([_]) => ref.invalidateSelf());
  return ref.watch(apiProvider).listTasks(view: 'kanban');
});

final taskReportsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final rt = ref.watch(realtimeProvider);
  rt.onAny('task.report.created', ([_]) => ref.invalidateSelf());
  rt.onAny('task.report.updated', ([_]) => ref.invalidateSelf());
  rt.onAny('task.report.response', ([_]) => ref.invalidateSelf());
  return ref.watch(apiProvider).listReports();
});

// ----- meetings -----
final meetingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(apiProvider).listMeetings();
});

// ----- calendar -----
final calendarRangeProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({DateTime from, DateTime to})>(
        (ref, range) async {
  return ref.watch(apiProvider).listEvents(range.from, range.to);
});

// ----- notifications -----
final notificationsProvider =
    StreamProvider.autoDispose<Map<String, dynamic>>((ref) async* {
  final api = ref.watch(apiProvider);
  final rt = ref.watch(realtimeProvider);
  // Initial fetch + a re-fetch each time the server fires `activity.recorded`.
  yield await api.notificationsGrouped();
  final controller = StreamController<void>();
  rt.onAny('notification.created', ([_]) => controller.add(null));
  rt.onAny('activity.recorded', ([_]) => controller.add(null));
  rt.onAny('announcement.published', ([_]) => controller.add(null));
  ref.onDispose(() => controller.close());
  await for (final _ in controller.stream) {
    try {
      yield await api.notificationsGrouped();
    } catch (_) {}
  }
});

// ----- saved + announcements + flags + sessions -----
final savedProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
    (ref) => ref.watch(apiProvider).listSaved());
final announcementsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) => ref.watch(apiProvider).listAnnouncements());
final flagsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.watch(apiProvider).myFlags());
final mySessionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) => ref.watch(apiProvider).mySessions());

// ----- presence (current user) -----
final presenceStatusProvider = StateProvider<String>((_) => 'ACTIVE');

// ----- search -----
final searchQueryProvider = StateProvider<String>((_) => '');

/// Filter to scope search to a single kind. `null` = all kinds.
/// Mirrors the React command palette's chip filter.
final searchKindProvider = StateProvider<String?>((_) => null);

final searchResultsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
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

final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.light);

// ----- accessibility -----
/// User-set system font scale multiplier (1.0 = system default). Applied
/// app-wide via MediaQuery so every Text widget picks it up.
final fontScaleProvider = StateProvider<double>((_) => 1.0);

/// When true, the app skips long page transitions and decorative
/// animations. Useful for users with vestibular sensitivities.
final reduceMotionProvider = StateProvider<bool>((_) => false);

// ----- helpers exposed to screens -----
extension RefBestie on Ref {
  /// Convenience — every screen calls this to grab the api client.
  BestieApi get api => read(apiProvider);
  BestieRealtime get rt => read(realtimeProvider);
}

/// Surface a Dio error as a short human string for toasts/banners.
///
/// Maps the noisy default Dio messages (and any wrapped exceptions) into
/// terse user-facing copy. Anything we can't classify becomes a generic
/// "Something went wrong" so we never dump the raw `DioException` thrown
/// because the response has a status code of …` blob into a snackbar.
String formatApiError(Object err) {
  if (err is DioException) {
    // 1. Server-provided structured error wins: `{ error: { message } }`.
    final body = err.response?.data;
    if (body is Map && body['error'] is Map) {
      final m = (body['error']['message'] as String?);
      if (m != null && m.isNotEmpty) return m;
    }
    // 2. Plain-string body (some routes return `{"message":"..."}`).
    if (body is Map && body['message'] is String) {
      return body['message'] as String;
    }

    // 3. Translate status code into something users can act on.
    final code = err.response?.statusCode;
    if (code != null) {
      if (code == 429)
        return 'Too many requests — please wait a moment and try again.';
      if (code == 401) return 'You need to sign in again.';
      if (code == 403) return 'You don\'t have permission for that.';
      if (code == 404) return 'That isn\'t available anymore.';
      if (code == 408) return 'Request timed out — please retry.';
      if (code == 413) return 'That file is too large.';
      if (code >= 500) return 'Server hiccup — try again in a moment.';
      return 'Request failed (HTTP $code)';
    }

    // 4. Connection-level issue (no response at all).
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Slow connection — please retry.';
      case DioExceptionType.connectionError:
        return 'Can\'t reach the server. Check your internet.';
      case DioExceptionType.cancel:
        return 'Cancelled.';
      default:
        return 'Network error.';
    }
  }
  // Non-Dio: return the first line so we don't paste a stack trace into a toast.
  final s = err.toString();
  final firstLine = s.split('\n').first.trim();
  return firstLine.isEmpty ? 'Something went wrong.' : firstLine;
}
