import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'socket_client.dart';

/// MyTaskKing — realtime event hub.
///
/// Wraps the underlying Socket.IO connection with a [Stream]-style API the
/// Riverpod providers consume. Reconnects on its own, debounces re-subscribe
/// storms, replays handlers after a late connect, and lets consumers tear
/// down listeners cleanly when their widget unmounts.
///
/// Connection lifecycle quirks this handles:
///   • Subscribers register handlers BEFORE login (e.g. global overlays at
///     app boot). The handler list is held even when `_socket == null`, then
///     bound when [connect] finally succeeds.
///   • Auth token changes (logout / refresh) — `BestieSocket.connect()` reads
///     a fresh token each call, so on auth change we tear down + reconnect.
///   • Multiple [connect] callers race — second/third are no-ops while a
///     connect is in flight.
///
/// Event surface (matches what the backend `sockets/index.js` emits):
///   • presence.update / presence.status
///   • chat.message.created / .updated / .deleted / .receipt / .thread.reply
///   • chat.typing
///   • task.created / .updated / .moved / .deleted / .comment
///   • call.incoming / .invited / .declined / .participant.joined / .left
///   • announcement.published
///   • calendar.event.created / .updated
///   • activity.recorded
class BestieRealtime {
  final BestieSocket _client;
  io.Socket? _socket;
  final Map<String, List<void Function(dynamic data)>> _handlers = {};
  bool _connecting = false;

  BestieRealtime(this._client);

  /// Open the underlying socket. Idempotent + safe to call before auth has
  /// loaded — silently bails and the next call retries.
  void connect() {
    if (_socket != null && _socket!.connected) return;
    if (_connecting) return;
    _connecting = true;
    try {
      final s = _client.connect();
      _socket = s
        ..onConnect((_) {
          // Re-bind every previously-registered handler. Without this, any
          // handler attached before the socket actually opened would never
          // receive events (the root cause of "no incoming call ringer").
          _rebindAll();
        })
        ..onDisconnect((_) {})
        ..onConnectError((_) {})
        ..onError((_) {});

      // If the socket-io client is already connected synchronously (rare),
      // attach handlers right away too.
      if (s.connected) _rebindAll();
    } catch (_) {
      // No-op — auth token typically not ready before login. The next read
      // (e.g. after login) will retry.
    } finally {
      _connecting = false;
    }
  }

  /// Tear down + reconnect with a (presumably) fresh auth token. Use when
  /// the auth store fires a login event — the previous socket was either
  /// never opened (token missing) or holds a stale token.
  void reconnect() {
    try {
      _socket?.off('connect');
      _socket?.dispose();
    } catch (_) {/* ignore */}
    _socket = null;
    _client.disconnect();
    connect();
  }

  /// Bind every registered handler to the active socket. Safe to call
  /// multiple times — we always `off()` first so duplicates can't accumulate.
  void _rebindAll() {
    final s = _socket;
    if (s == null) return;
    for (final entry in _handlers.entries) {
      final topic = entry.key;
      s.off(topic);
      for (final h in entry.value) {
        s.on(topic, (raw) {
          try { h(raw); } catch (_) {}
        });
      }
    }
  }

  /// Subscribe to a topic. Returns an unsubscribe closure. Works whether
  /// the socket is connected yet or not — the handler is queued and bound
  /// on (re)connect.
  void Function() on<T>(String topic, void Function(T data) handler) {
    final list = _handlers.putIfAbsent(topic, () => <void Function(dynamic)>[]);
    void wrapped(dynamic raw) {
      try { handler(raw as T); } catch (_) {}
    }
    list.add(wrapped);
    // Attempt to connect lazily — typical first call into a provider.
    if (_socket == null || !_socket!.connected) connect();
    // If we have an open socket, bind right away.
    _socket?.on(topic, wrapped);
    return () {
      list.remove(wrapped);
      _socket?.off(topic);
      // Re-bind the surviving handlers so we don't lose them when we just
      // wanted to drop one.
      for (final h in list) {
        _socket?.on(topic, h);
      }
    };
  }

  /// Listen for a topic with a typeless handler — common when the caller
  /// just wants "did anything happen?" (e.g. invalidating a provider).
  void Function() onAny(String topic, [void Function([dynamic data])? handler]) {
    return on<dynamic>(topic, (raw) => handler?.call(raw));
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

  /// True iff the socket is currently open. Useful for debug overlays.
  bool get isConnected => _socket?.connected ?? false;

  /// Tear everything down — handlers, socket, queued state.
  void dispose() {
    for (final topic in _handlers.keys) {
      _socket?.off(topic);
    }
    _handlers.clear();
    try { _socket?.dispose(); } catch (_) {}
    _client.disconnect();
    _socket = null;
  }
}
