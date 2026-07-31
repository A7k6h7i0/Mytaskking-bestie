import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import 'state.dart';

/// Tracks which channels currently have someone typing, populated from
/// `chat.typing` socket events. Each channel entry self-expires ~4 s after
/// the last keystroke so the "typing…" tile label fades on its own.
final typingChannelsProvider =
    StateNotifierProvider<_TypingChannelsNotifier, Set<String>>((ref) {
  return _TypingChannelsNotifier(ref);
});

class _TypingChannelsNotifier extends StateNotifier<Set<String>> {
  final Ref _ref;
  final Map<String, Timer> _timers = {};
  void Function()? _unsub;

  _TypingChannelsNotifier(this._ref) : super(const {}) {
    final rt = _ref.read(realtimeProvider);
    _unsub = rt.onAny('chat.typing', ([data]) {
      if (data is! Map) return;
      final channelId = data['channelId']?.toString();
      if (channelId == null) return;
      final me = _ref.read(authStoreProvider).user;
      if (data['userId']?.toString() == me?.id) return;
      final typing = data['typing'] == true;
      _timers[channelId]?.cancel();
      if (!typing) {
        if (state.contains(channelId)) {
          state = {...state}..remove(channelId);
        }
        return;
      }
      if (!state.contains(channelId)) state = {...state, channelId};
      _timers[channelId] = Timer(const Duration(seconds: 4), () {
        _timers.remove(channelId);
        if (state.contains(channelId)) {
          state = {...state}..remove(channelId);
        }
      });
    });
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _unsub?.call();
    super.dispose();
  }
}
