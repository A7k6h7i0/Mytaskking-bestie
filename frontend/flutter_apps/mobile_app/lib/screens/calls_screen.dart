import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Call history — recent calls with a one-tap "ring back" action.
/// Paginated 25 rows at a time so workspaces with high call volume
/// don't fall off a cliff once history grows past a few hundred entries.
class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});
  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  static const _pageSize = 25;
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.offset;
    if (remaining < 240 && _hasMore && !_loading) _loadMore();
  }

  Future<void> _loadMore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(apiProvider)
          .callHistory(page: _page, pageSize: _pageSize);
      final batch =
          ((res['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _items.addAll(batch);
        _hasMore = batch.length >= _pageSize;
        if (_hasMore) _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Calls'),
      ),
      body: _items.isEmpty && _loading
          ? const Center(child: BestieSpinner())
          : (_items.isEmpty && _error != null
              ? BestieEmptyState(
                  icon: Icons.error_outline_rounded,
                  iconColor: c.danger,
                  title: 'Could not load calls',
                  description: formatApiError(_error!),
                )
              : (_items.isEmpty
                  ? const BestieEmptyState(
                      icon: Icons.phone_outlined,
                      title: 'No calls yet',
                      description: 'Voice and video calls will show up here.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        _page = 1;
                        _hasMore = true;
                        _items.clear();
                        await _loadMore();
                      },
                      child: ListView.separated(
                        controller: _scroll,
                        itemCount: _items.length + 1,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, indent: 72, color: c.border),
                        itemBuilder: (ctx, i) {
                          if (i == _items.length) {
                            if (_loading) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            if (!_hasMore) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Text('End of history',
                                      style: TextStyle(
                                          fontSize: 11, color: c.textFaint)),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                          return _CallRow(call: _items[i], colors: c);
                        },
                      ),
                    ))),
    );
  }
}

class _CallRow extends ConsumerWidget {
  final Map<String, dynamic> call;
  final BestieColors colors;
  const _CallRow({required this.call, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.read(authStoreProvider).user;
    final initiator =
        (call['initiator'] as Map?)?.cast<String, dynamic>() ?? const {};
    final participants =
        (call['participants'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    final outgoing = initiator['id'] == me?.id;

    // Pick a "header" person — for outgoing calls the first non-me participant;
    // for incoming, the initiator.
    Map<String, dynamic> header = initiator;
    if (outgoing && participants.isNotEmpty) {
      final p = participants.firstWhere(
        (p) => (p['user'] as Map?)?['id'] != me?.id,
        orElse: () => participants.first,
      );
      header = (p['user'] as Map?)?.cast<String, dynamic>() ?? initiator;
    }

    final name = (header['name'] ?? '—').toString();
    final isClient = header['isClient'] == true;
    final status = (call['status'] ?? 'COMPLETED').toString();
    final kind = (call['kind'] ?? 'ONE_TO_ONE').toString();
    final mode = (call['mode'] ?? 'VIDEO').toString();
    final isVideo = mode == 'VIDEO';
    final viewerIsAdmin = me?.role == 'ADMIN' || me?.role == 'SUPER_ADMIN';
    final targetIsAdmin =
        header['role'] == 'ADMIN' || header['role'] == 'SUPER_ADMIN';
    final canCallBack = viewerIsAdmin || !targetIsAdmin;

    final Color statusColor = switch (status) {
      'MISSED' => colors.danger,
      'RINGING' => colors.warning,
      'ACTIVE' => colors.success,
      _ => colors.textMuted,
    };

    return ListTile(
      leading: BestieAvatar(
        name: name,
        imageUrl: header['avatarUrl']?.toString(),
        isClient: isClient,
        size: 40,
      ),
      title: BestieUserName(
          name: name,
          isClient: isClient,
          style: TextStyle(
              fontWeight: BestieTokens.fwSemibold, color: colors.text)),
      subtitle: Row(children: [
        Icon(
          outgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
          size: 12,
          color: status == 'MISSED' ? colors.danger : colors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          '${outgoing ? "Outgoing" : "Incoming"} · $kind · ${status.toLowerCase()}',
          style: TextStyle(color: statusColor, fontSize: 12),
        ),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: Icon(Icons.note_alt_outlined,
              color: (call['notes'] ?? '').toString().trim().isNotEmpty
                  ? colors.warning
                  : colors.textMuted),
          tooltip: 'Call notes',
          onPressed: () => _editNotes(context, ref),
        ),
        if (canCallBack)
          IconButton(
            icon: Icon(isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                color: colors.brand),
            tooltip: isVideo ? 'Video call back' : 'Call back',
            onPressed: () =>
                _ringBack(context, ref, header['id'] as String?, name, mode),
          ),
      ]),
    );
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref) async {
    final id = call['id']?.toString();
    if (id == null) return;
    final controller =
        TextEditingController(text: (call['notes'] ?? '').toString());
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Call notes'),
        content: TextField(
          controller: controller,
          minLines: 5,
          maxLines: 10,
          maxLength: 4000,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (notes == null) return;
    try {
      await ref
          .read(apiProvider)
          .dio
          .patch('/calls/$id/notes', data: {'notes': notes});
      call['notes'] = notes;
      if (context.mounted)
        bestieToast(context, 'Call notes saved', kind: BestieToastKind.success);
    } catch (e) {
      if (context.mounted)
        bestieToast(context, 'Could not save notes',
            body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<void> _ringBack(BuildContext context, WidgetRef ref, String? userId,
      String name, String mode) async {
    if (userId == null) return;
    try {
      final res = await ref.read(apiProvider).initiateCall(
        participantIds: [userId],
        kind: 'ONE_TO_ONE',
        // Mirror the original call's mode so a callback to a voice call
        // doesn't surprise the recipient with a video Accept button.
        mode: mode.toUpperCase() == 'VOICE' ? 'VOICE' : 'VIDEO',
      );
      final availability =
          (res['targetPresence'] as Map?)?.cast<String, dynamic>();
      if (availability != null) {
        final custom = (availability['customStatus'] ?? '').toString().trim();
        final status = (availability['status'] ?? 'BUSY').toString();
        final label = status == 'ON_CALL'
            ? 'on another call'
            : custom.toLowerCase().contains('lunch')
                ? 'at lunch'
                : custom.toLowerCase().contains('leave')
                    ? 'on leave'
                    : 'busy';
        if (status == 'ON_CALL' && res['waiting'] == true) {
          try {
            final tts = FlutterTts();
            await tts.setSpeechRate(0.36);
            await tts.speak(
                '$name is busy with another call. Please wait for them to respond or call again later.');
          } catch (_) {}
          if (context.mounted) {
            bestieToast(context, 'Call waiting',
                body: '$name can accept and add you to the current call.',
                kind: BestieToastKind.info);
          }
          return;
        }
        try {
          final tts = FlutterTts();
          await tts.setSpeechRate(0.36);
          await tts.speak('$name is $label. Please leave a message.');
        } catch (_) {}
        if (context.mounted) {
          bestieToast(context, '$name is unavailable',
              body: label, kind: BestieToastKind.warning);
        }
        return;
      }
      final id = ((res['call'] as Map?)?['id'] ?? res['id'])?.toString();
      if (id != null && context.mounted) {
        context.go('/call/$id?mode=${mode.toLowerCase()}');
      }
    } catch (e) {
      if (context.mounted)
        bestieToast(context, 'Could not call',
            body: formatApiError(e), kind: BestieToastKind.error);
    }
  }
}
