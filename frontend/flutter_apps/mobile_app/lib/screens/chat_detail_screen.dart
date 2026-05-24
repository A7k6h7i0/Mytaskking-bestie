import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String channelId;
  const ChatDetailScreen({super.key, required this.channelId});
  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  Map<String, dynamic>? _channel;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChannel() async {
    try {
      final c = await ref.read(apiProvider).getChannel(widget.channelId);
      if (mounted) setState(() => _channel = c);
    } catch (_) {/* header falls back to generic title */}
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiProvider).sendMessage(widget.channelId, body: body);
      _composer.clear();
      ref.invalidate(messagesProvider(widget.channelId));
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not send', body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startCall({required String kind}) async {
    if (_channel == null) {
      bestieToast(context, 'Hold on', body: 'Loading channel info…', kind: BestieToastKind.info);
      return;
    }
    final me = ref.read(authStoreProvider).user;
    final members = (_channel!['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final participantIds = members
        .map((m) => m['userId'] as String?)
        .whereType<String>()
        .where((id) => id != me?.id)
        .toList();
    if (participantIds.isEmpty) {
      bestieToast(context, 'No one to call', body: 'Add a teammate to this channel first.',
          kind: BestieToastKind.warning);
      return;
    }
    try {
      final ch = _channel!['kind'] == 'DM' ? 'ONE_TO_ONE' : 'GROUP';
      final res = await ref.read(apiProvider).initiateCall(
        participantIds: participantIds,
        kind: ch,
        channelId: widget.channelId,
      );
      final call = (res['call'] as Map?)?.cast<String, dynamic>() ?? res;
      final callId = call['id']?.toString();
      if (callId != null && mounted) {
        context.go('/call/$callId?mode=$kind');
      } else if (mounted) {
        bestieToast(context, 'Call started', body: 'Ringing teammates…',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not start call',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  String _headerTitle() {
    if (_channel == null) return 'Chat';
    final kind = (_channel!['kind'] ?? '').toString();
    if (kind == 'DM') {
      final me = ref.read(authStoreProvider).user;
      final members = (_channel!['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final other = members.firstWhere(
        (m) => m['userId'] != me?.id,
        orElse: () => const {},
      );
      final u = other['user'] as Map?;
      if (u != null && u['name'] != null) return u['name'].toString();
    }
    return (_channel!['name'] ?? 'Chat').toString();
  }

  String _headerSubtitle() {
    if (_channel == null) return '';
    final kind = (_channel!['kind'] ?? '').toString();
    final members = (_channel!['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    switch (kind) {
      case 'DM':     return 'Direct message';
      case 'CLIENT': return '${members.length} members · client';
      default:       return '${members.length} members';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final messages = ref.watch(messagesProvider(widget.channelId));
    final me = ref.watch(authStoreProvider).user;
    final isClient = _channel?['isClientChannel'] == true;
    final kind = (_channel?['kind'] ?? '').toString();
    final isDm = kind == 'DM';

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/chat'),
        ),
        titleSpacing: 0,
        title: Row(children: [
          if (_channel != null)
            isDm
                ? BestieAvatar(
                    name: _headerTitle(),
                    imageUrl: ((_channel!['members'] as List?)
                            ?.cast<Map<String, dynamic>>()
                            .firstWhere((m) => m['userId'] != me?.id, orElse: () => const {})['user']
                          as Map?)?['avatarUrl']
                        ?.toString(),
                    isClient: isClient,
                    size: 32,
                  )
                : Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: isClient ? colors.clientSoft : colors.brandSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      kind == 'CLIENT' ? Icons.business_center_outlined : Icons.groups_outlined,
                      color: isClient ? colors.client : colors.brandStrong,
                      size: 18,
                    ),
                  ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_headerTitle(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: BestieTokens.fwBold,
                      color: isClient ? colors.client : colors.text,
                      letterSpacing: BestieTokens.lsSnug,
                    )),
                Text(_headerSubtitle(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textMuted)),
              ],
            ),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Voice call',
            onPressed: () => _startCall(kind: 'voice'),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Video call',
            onPressed: () => _startCall(kind: 'video'),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Channel info',
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: messages.when(
            loading: () => const Center(child: BestieSpinner()),
            error: (e, _) => BestieEmptyState(
              icon: Icons.error_outline,
              iconColor: colors.danger,
              title: 'Couldn\'t load messages',
              description: formatApiError(e),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const BestieEmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'No messages yet',
                  description: 'Send the first message to break the ice.',
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final m = items[i];
                  final author = (m['author'] as Map?)?.cast<String, dynamic>() ?? const {};
                  final mine = author['id'] == me?.id;
                  return _MessageBubble(message: m, author: author, mine: mine);
                },
              );
            },
          ),
        ),
        _Composer(
          colors: colors,
          controller: _composer,
          sending: _sending,
          onSend: _send,
          onAttach: () => bestieToast(context, 'Attachments',
              body: 'Coming soon — use the web app to attach files for now.',
              kind: BestieToastKind.info),
        ),
      ]),
    );
  }

  void _showInfo(BuildContext context) {
    if (_channel == null) return;
    final colors = BestieColors.of(context);
    final members = (_channel!['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_headerTitle(),
                  style: TextStyle(
                    fontSize: 18, fontWeight: BestieTokens.fwBold, color: colors.text,
                    letterSpacing: BestieTokens.lsTight,
                  )),
              const SizedBox(height: 4),
              Text(_headerSubtitle(),
                  style: TextStyle(color: colors.textMuted, fontSize: 13)),
              const Divider(height: 24),
              Text('MEMBERS',
                  style: TextStyle(
                    fontSize: 11, fontWeight: BestieTokens.fwBold,
                    color: colors.textMuted, letterSpacing: BestieTokens.lsEyebrow,
                  )),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in members)
                      _MemberTile(member: m, colors: colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final BestieColors colors;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  const _Composer({
    required this.colors,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded, color: colors.textSoft),
            onPressed: onAttach,
            tooltip: 'Attach',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1, maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: colors.text),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                hintText: 'Write a message…',
                hintStyle: TextStyle(color: colors.textMuted, fontWeight: BestieTokens.fwRegular),
                filled: true,
                fillColor: colors.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  borderSide: const BorderSide(color: BestieTokens.cBrand, width: 1.4),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          sending
              ? const Padding(padding: EdgeInsets.all(10), child: BestieSpinner(size: 18))
              : IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: BestieTokens.cBrand,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  onPressed: onSend,
                ),
        ]),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Map<String, dynamic> member;
  final BestieColors colors;
  const _MemberTile({required this.member, required this.colors});

  @override
  Widget build(BuildContext context) {
    final u = (member['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = (u['name'] ?? '—').toString();
    final isClient = u['isClient'] == true;
    final role = (member['role'] ?? 'member').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        BestieAvatar(name: name, imageUrl: u['avatarUrl']?.toString(), isClient: isClient, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              BestieUserName(name: name, isClient: isClient,
                style: TextStyle(fontSize: 13.5, fontWeight: BestieTokens.fwSemibold, color: colors.text)),
              Text((u['role'] ?? '').toString().replaceAll('_', ' ').toLowerCase(),
                  style: TextStyle(fontSize: 11, color: colors.textMuted)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
          ),
          child: Text(role, style: TextStyle(
            fontSize: 10, fontWeight: BestieTokens.fwSemibold,
            color: colors.textSoft, letterSpacing: BestieTokens.lsWide,
          )),
        ),
      ]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final Map<String, dynamic> author;
  final bool mine;
  const _MessageBubble({required this.message, required this.author, required this.mine});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final body = message['body'] as String? ?? '';
    final isClient = author['isClient'] == true;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = mine ? c.brand : c.surface;
    final fg = mine ? Colors.white : c.text;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: BestieUserName(
                  name: author['name'] ?? '',
                  isClient: isClient,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: BestieTokens.fwBold,
                    color: isClient ? c.client : c.brand,
                  ),
                ),
              ),
            Text(body, style: TextStyle(color: fg, fontSize: 14, height: 1.35)),
          ],
        ),
      ),
    );
  }
}
