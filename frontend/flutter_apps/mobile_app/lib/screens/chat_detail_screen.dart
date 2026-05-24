import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
  bool _attaching = false;
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
    } catch (_) { /* header falls back to generic title */ }
  }

  Future<void> _send({List<String>? attachmentIds, String? overrideBody}) async {
    final body = overrideBody ?? _composer.text.trim();
    if (body.isEmpty && (attachmentIds == null || attachmentIds.isEmpty)) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiProvider).sendMessage(
        widget.channelId,
        body: body.isEmpty ? null : body,
        attachmentIds: attachmentIds,
        kind: attachmentIds != null && attachmentIds.isNotEmpty ? 'FILE' : 'TEXT',
      );
      if (overrideBody == null) _composer.clear();
      ref.invalidate(messagesProvider(widget.channelId));
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not send',
          body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Bottom-sheet attachment menu — camera, gallery, document picker.
  Future<void> _attach() async {
    final c = BestieColors.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: c.borderStrong,
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
              ),
            ),
            _ChooserTile(icon: Icons.photo_camera_rounded, label: 'Camera',
                colors: c, accent: c.brand, onTap: () => Navigator.pop(ctx, 'camera')),
            _ChooserTile(icon: Icons.image_rounded, label: 'Photo / video',
                colors: c, accent: c.accent, onTap: () => Navigator.pop(ctx, 'gallery')),
            _ChooserTile(icon: Icons.description_rounded, label: 'Document',
                colors: c, accent: c.info, onTap: () => Navigator.pop(ctx, 'document')),
          ]),
        ),
      ),
    );
    if (choice == null) return;
    await _pickAndUpload(choice);
  }

  Future<void> _pickAndUpload(String kind) async {
    setState(() => _attaching = true);
    try {
      List<int>? bytes;
      String? filename;
      String? mimeType;

      if (kind == 'camera' || kind == 'gallery') {
        final picker = ImagePicker();
        final source = kind == 'camera' ? ImageSource.camera : ImageSource.gallery;
        final x = await picker.pickImage(source: source, imageQuality: 85);
        if (x == null) return;
        bytes = await x.readAsBytes();
        filename = x.name;
        mimeType = x.mimeType ?? 'image/jpeg';
      } else {
        final res = await FilePicker.platform.pickFiles(withData: true);
        if (res == null || res.files.isEmpty) return;
        final f = res.files.first;
        bytes = f.bytes;
        filename = f.name;
        mimeType = _mimeFromExt(f.extension);
        if (bytes == null) throw 'Could not read the picked file';
      }

      final asset = await ref.read(apiProvider).uploadFile(
        bytes: bytes,
        filename: filename!,
        mimeType: mimeType,
      );
      final assetId = asset['id']?.toString();
      if (assetId == null) throw 'Upload succeeded but no asset id was returned';
      await _send(attachmentIds: [assetId]);
    } catch (e) {
      if (mounted) bestieToast(context, 'Attachment failed',
          body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  String? _mimeFromExt(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png':  return 'image/png';
      case 'gif':  return 'image/gif';
      case 'pdf':  return 'application/pdf';
      case 'mp4':  return 'video/mp4';
      case 'mp3':  return 'audio/mpeg';
      case 'wav':  return 'audio/wav';
      case 'doc':
      case 'docx': return 'application/msword';
      case 'xls':
      case 'xlsx': return 'application/vnd.ms-excel';
      default: return null;
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
                  final kindStr = (m['kind'] ?? 'TEXT').toString();
                  if (kindStr == 'SYSTEM' || kindStr == 'CALL_EVENT') {
                    return _SystemBubble(message: m);
                  }
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
          attaching: _attaching,
          onSend: _send,
          onAttach: _attach,
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

class _ChooserTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final BestieColors colors;
  final Color accent;
  final VoidCallback onTap;
  const _ChooserTile({
    required this.icon, required this.label, required this.colors,
    required this.accent, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
        ),
        child: Icon(icon, color: accent, size: 22),
      ),
      title: Text(label,
          style: TextStyle(color: colors.text, fontWeight: BestieTokens.fwSemibold)),
      onTap: onTap,
    );
  }
}

class _Composer extends StatelessWidget {
  final BestieColors colors;
  final TextEditingController controller;
  final bool sending;
  final bool attaching;
  final Future<void> Function({List<String>? attachmentIds, String? overrideBody}) onSend;
  final VoidCallback onAttach;

  const _Composer({
    required this.colors,
    required this.controller,
    required this.sending,
    required this.attaching,
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
          attaching
              ? const Padding(padding: EdgeInsets.all(12), child: BestieSpinner(size: 18))
              : IconButton(
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
                  onPressed: () => onSend(),
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

/// System message bubble — call events (missed / declined / ended), member
/// joined/left, channel renamed. Rendered as a centered chip, not a side
/// bubble. The backend posts these with `kind: 'CALL_EVENT'` or `'SYSTEM'`.
class _SystemBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  const _SystemBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final body = (message['body'] ?? '').toString();
    final meta = (message['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    final eventType = (meta['eventType'] ?? message['kind'] ?? '').toString().toLowerCase();
    final isMissed = eventType.contains('missed') || body.toLowerCase().contains('missed');
    final isDeclined = eventType.contains('declined') || body.toLowerCase().contains('declined');
    final isCall = eventType.contains('call') || body.toLowerCase().contains('call');

    Color accent;
    IconData icon;
    if (isMissed) {
      accent = c.danger;
      icon = Icons.call_missed_rounded;
    } else if (isDeclined) {
      accent = c.warning;
      icon = Icons.call_end_rounded;
    } else if (isCall) {
      accent = c.success;
      icon = Icons.call_rounded;
    } else {
      accent = c.textMuted;
      icon = Icons.info_outline_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
            border: Border.all(color: accent.withOpacity(0.20)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                body.isEmpty ? 'Call event' : body,
                style: TextStyle(
                  color: accent,
                  fontWeight: BestieTokens.fwSemibold,
                  fontSize: 12,
                  letterSpacing: BestieTokens.lsNormal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        ),
      ),
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
    final attachments = (message['attachments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final isClient = author['isClient'] == true;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = mine ? c.brand : c.surface;
    final fg = mine ? Colors.white : c.text;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
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
                padding: const EdgeInsets.only(left: 4, bottom: 2),
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
            for (final a in attachments) ...[
              _Attachment(asset: a, mine: mine, colors: c),
              const SizedBox(height: 4),
            ],
            if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                child: Text(body, style: TextStyle(color: fg, fontSize: 14, height: 1.35)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Attachment extends StatelessWidget {
  final Map<String, dynamic> asset;
  final bool mine;
  final BestieColors colors;
  const _Attachment({required this.asset, required this.mine, required this.colors});

  @override
  Widget build(BuildContext context) {
    final mime = (asset['mimeType'] ?? '').toString();
    final url = asset['url']?.toString() ?? '';
    final name = (asset['originalName'] ?? 'file').toString();
    final size = asset['size'];
    final isImage = mime.startsWith('image/');
    if (isImage && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 240),
          child: Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fileChip(mime, name, size)),
        ),
      );
    }
    return _fileChip(mime, name, size);
  }

  Widget _fileChip(String mime, String name, Object? size) {
    final accent = mine ? Colors.white : BestieTokens.cBrand;
    final fg = mine ? Colors.white : colors.text;
    final sizeStr = size is int ? _formatBytes(size) : '';
    final icon = mime.contains('pdf') ? Icons.picture_as_pdf_rounded :
                 mime.startsWith('video/') ? Icons.movie_rounded :
                 mime.startsWith('audio/') ? Icons.audiotrack_rounded :
                 Icons.description_rounded;
    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      decoration: BoxDecoration(
        color: (mine ? Colors.white : colors.surface2).withOpacity(mine ? 0.16 : 1),
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: accent.withOpacity(mine ? 0.25 : 0.12),
            borderRadius: BorderRadius.circular(BestieTokens.rXs),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 13, fontWeight: BestieTokens.fwSemibold)),
            if (sizeStr.isNotEmpty)
              Text(sizeStr, style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  String _formatBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
