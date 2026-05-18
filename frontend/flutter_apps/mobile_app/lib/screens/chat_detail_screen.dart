import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bestie_design/bestie_design.dart';

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

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.channelId));
    final me = ref.watch(authStoreProvider).user;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: BestieTokens.cSurface,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/chat')),
        title: const Text('Channel'),
        actions: [
          IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: messages.when(
            loading: () => const Center(child: BestieSpinner()),
            error: (e, _) => BestieEmptyState(
              icon: Icons.error_outline, iconColor: BestieTokens.cDanger,
              title: 'Couldn\'t load messages', description: formatApiError(e),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const BestieEmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'No messages yet',
                  description: 'Start the conversation.',
                );
              }
              return ListView.builder(
                controller: _scroll,
                reverse: false,
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
        SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: BestieTokens.cSurface,
              border: Border(top: BorderSide(color: BestieTokens.cBorder)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () {}),
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1, maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Write a message…',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              _sending
                  ? const Padding(padding: EdgeInsets.all(8), child: BestieSpinner(size: 18))
                  : IconButton.filled(
                      icon: const Icon(Icons.send, size: 18),
                      onPressed: _send,
                    ),
            ]),
          ),
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
    final body = message['body'] as String? ?? '';
    final isClient = author['isClient'] == true;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = mine ? BestieTokens.cBrand : BestieTokens.cSurface;
    final fg = mine ? Colors.white : BestieTokens.cText;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          border: mine ? null : Border.all(color: BestieTokens.cBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine) BestieUserName(
              name: author['name'] ?? '',
              isClient: isClient,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            Text(body, style: TextStyle(color: fg)),
          ],
        ),
      ),
    );
  }
}
