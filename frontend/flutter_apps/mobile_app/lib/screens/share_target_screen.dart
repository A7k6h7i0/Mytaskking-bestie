import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Landing screen for content the user shared *into* MyTaskKing from
/// another app via the system share sheet. The shared payload (text,
/// image, or file path) is passed in via the constructor; the user
/// picks a channel and we send the message.
class ShareTargetScreen extends ConsumerStatefulWidget {
  final String? sharedText;
  final List<String> sharedFilePaths;
  const ShareTargetScreen({
    super.key,
    this.sharedText,
    this.sharedFilePaths = const [],
  });

  @override
  ConsumerState<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends ConsumerState<ShareTargetScreen> {
  final _captionCtl = TextEditingController();
  String _search = '';
  String? _selectedChannelId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the composer with the shared text if it isn't a bare URL —
    // bare URLs are most useful as the entire message body.
    if (widget.sharedText != null && widget.sharedText!.isNotEmpty) {
      _captionCtl.text = widget.sharedText!;
    }
  }

  @override
  void dispose() {
    _captionCtl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_selectedChannelId == null) return;
    setState(() => _sending = true);
    final api = ref.read(apiProvider);
    try {
      final attachmentIds = <String>[];
      for (final path in widget.sharedFilePaths) {
        try {
          final file = File(path);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          final filename = path.split('/').last;
          final uploaded = await api.uploadFile(
            bytes: bytes,
            filename: filename,
          );
          final id = uploaded['id']?.toString();
          if (id != null) attachmentIds.add(id);
        } catch (_) {/* keep going on individual failures */}
      }
      final body = _captionCtl.text.trim();
      await api.sendMessage(
        _selectedChannelId!,
        body: body.isEmpty ? null : body,
        attachmentIds: attachmentIds.isEmpty ? null : attachmentIds,
        kind: attachmentIds.isNotEmpty ? 'FILE' : 'TEXT',
      );
      if (!mounted) return;
      bestieToast(context, 'Shared', kind: BestieToastKind.success);
      context.go('/chat/$_selectedChannelId');
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not share',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final channels = ref.watch(channelsProvider);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Share to channel'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/chat'),
        ),
        actions: [
          TextButton.icon(
            onPressed:
                _selectedChannelId == null || _sending ? null : _send,
            icon: const Icon(Icons.send_rounded, size: 16),
            label: Text(_sending ? 'Sending…' : 'Send'),
          ),
        ],
      ),
      body: Column(children: [
        // Preview of the payload (image thumbs + caption field).
        if (widget.sharedFilePaths.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              scrollDirection: Axis.horizontal,
              itemCount: widget.sharedFilePaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final path = widget.sharedFilePaths[i];
                final ext = path.split('.').last.toLowerCase();
                final isImage = const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}
                    .contains(ext);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(BestieTokens.rSm),
                  child: Container(
                    width: 80, height: 80,
                    color: c.surface2,
                    child: isImage
                        ? Image.file(File(path), fit: BoxFit.cover)
                        : Center(
                            child: Icon(Icons.description_rounded,
                                color: c.textSoft, size: 32),
                          ),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: BestieTextField(
            label: widget.sharedFilePaths.isEmpty
                ? 'Message'
                : 'Add a caption (optional)',
            controller: _captionCtl,
            hint: 'Say something about this…',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              hintText: 'Search chats',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: channels.when(
            loading: () => const Center(child: BestieSpinner()),
            error: (e, _) => BestieEmptyState(
              icon: Icons.error_outline_rounded,
              iconColor: c.danger,
              title: 'Couldn\'t load chats',
              description: formatApiError(e),
            ),
            data: (items) {
              final filtered = _search.isEmpty
                  ? items
                  : items
                      .where((c) =>
                          (c['name'] ?? '')
                              .toString()
                              .toLowerCase()
                              .contains(_search))
                      .toList();
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: c.border),
                itemBuilder: (_, i) {
                  final ch = filtered[i];
                  final id = ch['id']?.toString();
                  final selected = id == _selectedChannelId;
                  final kind = (ch['kind'] ?? '').toString();
                  final isClient = ch['isClientChannel'] == true;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isClient ? c.clientSoft : c.brandSoft,
                      child: Icon(
                        kind == 'DM'
                            ? Icons.chat_bubble_outline_rounded
                            : (kind == 'CLIENT'
                                ? Icons.business_center_outlined
                                : Icons.groups_outlined),
                        color: isClient ? c.client : c.brandStrong,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      (ch['name'] ?? 'Direct message').toString(),
                      style: TextStyle(
                          color: c.text,
                          fontWeight: BestieTokens.fwSemibold),
                    ),
                    trailing: selected
                        ? Icon(Icons.check_circle_rounded,
                            color: c.brand, size: 20)
                        : null,
                    onTap: () => setState(() => _selectedChannelId = id),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
