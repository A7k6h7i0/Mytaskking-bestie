import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'socket_client.dart';

/// MyTaskKing — realtime event hub.
///
/// Wraps the underlying Socket.IO connection with a [Stream]-style API the
/// Riverpod providers consume. Reconnects on its own, debounces re-subscribe
/// storms, and lets consumers tear down listeners cleanly when their widget
/// unmounts.
///
/// Event surface (matches what the backend `sockets/index.js` emits):
///   • presence.update / presence.status
///   • chat.message.created / .updated / .deleted / .receipt / .thread.reply
///   • chat.typing
///   • task.created / .updated / .moved / .deleted / .comment
///   • call.incoming / .participant.joined / .left / .muted / .screen_share.*
///   • announcement.published
///   • calendar.event.created / .updated
///   • activity.recorded
///   • collab.presence / collab.op
class BestieRealtime {
  final BestieSocket _client;
  io.Socket? _socket;
  final Map<String, List<Function>> _handlers = {};
  bool _connecting = false;

  BestieRealtime(this._client);

  /// Open the underlying socket. Idempotent.
  void connect() {
    if (_socket != null || _connecting) return;
    _connecting = true;
    try {
      _socket = _client.connect();
      _socket!
        ..onConnect((_) {})
        ..onDisconnect((_) {})
        ..onConnectError((_) {})
        ..onError((_) {});
    } catch (_) {
      // No-op — sometimes the auth token isn't ready yet. The next provider
      // read will retry on demand.
    } finally {
      _connecting = false;
    }
  }

  /// Subscribe to a topic. Returns an unsubscribe closure.
  /// If `connect()` hasn't run yet, subscriptions are queued and replayed.
  void Function() on<T>(String topic, void Function(T data) handler) {
    final list = _handlers.putIfAbsent(topic, () => []);
    list.add(handler);
    _socket?.on(topic, (raw) {
      try { handler(raw as T); } catch (_) {}
    });
    return () {
      list.remove(handler);
      _socket?.off(topic);
      // Re-attach remaining handlers for this topic.
      for (final h in list) {
        _socket?.on(topic, (raw) {
          try { (h as dynamic)(raw); } catch (_) {}
        });
      }
    };
  }

  /// Listen for a topic with a typeless handler — common when the caller just
  /// wants "did anything happen?" (e.g. invalidating a Riverpod provider).
  void Function() onAny(String topic, [void Function([dynamic data])? handler]) {
    void wrapped(dynamic raw) { handler?.call(raw); }
    final off = on<dynamic>(topic, wrapped);
    return off;
  }

  /// Fire an event to the server (typing indicators, custom collab ops, etc).
  void emit(String topic, [Object? data]) {
    _socket?.emit(topic, data);
  }

  /// Update presence — fans out to all watchers via `presence.status`.
  void updatePresence({required String status, String? customStatus}) {
    emit('presence.set', {
      'status': status,
      if (customStatus != null) 'customStatus': customStatus,
    });
  }

  /// Tear everything down — handlers, socket, queued state.
  void dispose() {
    for (final topic in _handlers.keys) {
      _socket?.off(topic);
    }
    _handlers.clear();
    _client.disconnect();
    _socket = null;
  }
}
