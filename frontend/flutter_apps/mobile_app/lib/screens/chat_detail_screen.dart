import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show FontFeature;

import 'package:audioplayers/audioplayers.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state.dart';

/// Resolves the SharedPreferences instance once and shares it across widgets
/// that need to read/write local-only chat state (e.g. "delete for me" hides).
final _prefsProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);

/// Per-channel set of message ids the local user has hidden via "delete for
/// me". The chat detail filters these out of the rendered list. Other
/// members still see the original message — this is a client-side mask only.
final _hiddenMessageIdsProvider = FutureProvider.family.autoDispose<Set<String>, String>(
  (ref, channelId) async {
    final prefs = await ref.watch(_prefsProvider.future);
    final list = prefs.getStringList('chat.hidden.$channelId') ?? const <String>[];
    return list.toSet();
  },
);

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String channelId;
  const ChatDetailScreen({super.key, required this.channelId});
  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> with WidgetsBindingObserver {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _attaching = false;
  Map<String, dynamic>? _channel;
  // Tracks which incoming messages we've already receipted in this session so
  // we don't spam the backend on every rebuild / scroll.
  final Set<String> _ackedDelivered = {};
  final Set<String> _ackedSeen = {};
  // Optimistic outgoing messages — rendered with kind 'TEXT' + status
  // 'SENDING' immediately when the user taps send. Removed from the list
  // once the matching message lands from the server.
  final List<Map<String, dynamic>> _pendingOutgoing = [];
  // Most-recently-known message-id count, so we can detect "new arrival"
  // and animate to the latest message.
  int _lastCount = 0;
  // Voice-note recording state.
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChannel();
    _listenForReceiptEvents();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composer.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user backgrounds + returns, mark the visible thread seen again.
    if (state == AppLifecycleState.resumed) _markSeenSoon();
  }

  Future<void> _loadChannel() async {
    try {
      final c = await ref.read(apiProvider).getChannel(widget.channelId);
      if (mounted) setState(() => _channel = c);
    } catch (_) { /* header falls back to generic title */ }
  }

  /// Listens to socket receipt events and patches the locally-cached message
  /// list, so the sender's tick marks update live without re-fetching.
  void _listenForReceiptEvents() {
    final rt = ref.read(realtimeProvider);
    rt.onAny('chat.message.receipt', ([data]) {
      if (data is! Map) return;
      final mid = data['messageId']?.toString();
      final state = data['state']?.toString();
      if (mid == null || state == null) return;
      // Cheapest path: invalidate the messages provider so the rebuild pulls
      // the new aggregate status. The bulk endpoint is fast and idempotent.
      if (mounted) ref.invalidate(messagesProvider(widget.channelId));
    });
  }

  /// Sends DELIVERED for every incoming message we haven't acked yet, then
  /// (separately) SEEN for the same set if the screen is currently mounted.
  /// Posting both is what gives WhatsApp's "✓✓ grey → ✓✓ blue" transition.
  Future<void> _ackReceipts(List<dynamic> items, {required bool seen}) async {
    final me = ref.read(authStoreProvider).user;
    if (me == null) return;
    final incomingIds = items
        .whereType<Map>()
        .where((m) => (m['author'] as Map?)?['id'] != me.id)
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .toList();
    if (incomingIds.isEmpty) return;

    final toDeliver = incomingIds.where((id) => !_ackedDelivered.contains(id)).toList();
    if (toDeliver.isNotEmpty) {
      _ackedDelivered.addAll(toDeliver);
      ref.read(apiProvider).sendReceipts(widget.channelId, toDeliver, 'DELIVERED').catchError((_) {
        // On failure, allow a retry on the next batch.
        _ackedDelivered.removeAll(toDeliver);
        return null;
      });
    }
    if (seen) {
      final toSee = incomingIds.where((id) => !_ackedSeen.contains(id)).toList();
      if (toSee.isNotEmpty) {
        _ackedSeen.addAll(toSee);
        ref.read(apiProvider).sendReceipts(widget.channelId, toSee, 'SEEN').catchError((_) {
          _ackedSeen.removeAll(toSee);
          return null;
        });
      }
    }
  }

  /// Schedules a SEEN ack for the next frame, useful from lifecycle callbacks
  /// where the messages list might still be loading.
  void _markSeenSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(messagesProvider(widget.channelId));
      final items = state.asData?.value ?? const [];
      if (items.isNotEmpty) _ackReceipts(items, seen: true);
    });
  }

  Future<void> _send({List<String>? attachmentIds, String? overrideBody}) async {
    final body = overrideBody ?? _composer.text.trim();
    if (body.isEmpty && (attachmentIds == null || attachmentIds.isEmpty)) return;
    final me = ref.read(authStoreProvider).user;
    if (me == null) return;

    // Optimistic stub — render the bubble immediately with a clock icon, then
    // replace it when the server's row lands in the messages provider.
    final tempId = 'pending_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = <String, dynamic>{
      'id': tempId,
      'kind': attachmentIds != null && attachmentIds.isNotEmpty ? 'FILE' : 'TEXT',
      'body': body.isEmpty ? null : body,
      'status': 'SENDING',
      'createdAt': DateTime.now().toIso8601String(),
      'channelId': widget.channelId,
      'author': {
        'id': me.id,
        'name': me.name,
        'avatarUrl': me.avatarUrl,
        'isClient': me.isClient,
        'role': me.role,
      },
      'attachments': const [],
      'receipts': const [],
    };
    setState(() {
      _pendingOutgoing.add(optimistic);
      _sending = true;
    });
    if (overrideBody == null) _composer.clear();
    _scrollToLatestSoon();

    try {
      await ref.read(apiProvider).sendMessage(
        widget.channelId,
        body: body.isEmpty ? null : body,
        attachmentIds: attachmentIds,
        kind: attachmentIds != null && attachmentIds.isNotEmpty ? 'FILE' : 'TEXT',
      );
      // Server-side message now exists; drop the optimistic stub on next
      // refresh. The realtime socket also pushes a chat.message.created that
      // invalidates the provider — this is a belt-and-suspenders.
      ref.invalidate(messagesProvider(widget.channelId));
    } catch (e) {
      // Mark the optimistic message as failed so the user can see why.
      setState(() {
        final i = _pendingOutgoing.indexWhere((m) => m['id'] == tempId);
        if (i >= 0) _pendingOutgoing[i]['status'] = 'FAILED';
      });
      if (mounted) bestieToast(context, 'Could not send',
          body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Start recording a voice note to a temp file. Mic permission is requested
  /// once by the recorder package itself; on denial the gesture is silently
  /// cancelled with a toast.
  Future<void> _startVoiceRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) bestieToast(context, 'Mic permission needed',
            body: 'Enable microphone access in Settings.', kind: BestieToastKind.warning);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000, sampleRate: 32000),
        path: path,
      );
      _recordPath = path;
    } catch (e) {
      if (mounted) bestieToast(context, 'Couldn\'t start recording',
          body: e.toString(), kind: BestieToastKind.error);
    }
  }

  /// Stop recording and return the path of the captured file. Caller is
  /// responsible for deciding whether to upload + send it.
  Future<String?> _stopVoiceRecording() async {
    try {
      final path = await _recorder.stop();
      return path ?? _recordPath;
    } catch (_) {
      return null;
    }
  }

  /// Upload the recorded clip as a FileAsset and post it as a VOICE_NOTE
  /// message in the channel.
  Future<void> _sendVoiceNote(String path) async {
    setState(() => _attaching = true);
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final asset = await ref.read(apiProvider).uploadFile(
        bytes: bytes,
        filename: 'voice-note-${DateTime.now().millisecondsSinceEpoch}.m4a',
        mimeType: 'audio/mp4',
      );
      final id = asset['id']?.toString();
      if (id == null) throw 'Upload returned no asset id';
      await ref.read(apiProvider).sendMessage(
        widget.channelId,
        attachmentIds: [id],
        kind: 'VOICE_NOTE',
      );
      ref.invalidate(messagesProvider(widget.channelId));
      // Best-effort cleanup of the temp file.
      try { await file.delete(); } catch (_) {}
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not send voice note',
          body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  /// After a frame, animate to the latest message. With `reverse: true` the
  /// list's "bottom" is `offset: 0`, so we just scroll to the top of the
  /// reversed axis.
  void _scrollToLatestSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
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
    // Subscribe to the auth store *stream* so a login or token refresh
    // re-renders the message list — otherwise own messages can appear on
    // the wrong side until the screen is rebuilt.
    final me = ref.watch(currentUserProvider).asData?.value
        ?? ref.read(authStoreProvider).user;
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
            data: (serverItemsRaw) {
              // "Delete for me" — drop locally-hidden ids before any further work.
              final hidden = ref.watch(_hiddenMessageIdsProvider(widget.channelId)).asData?.value
                  ?? const <String>{};
              final serverItems = hidden.isEmpty
                  ? serverItemsRaw
                  : serverItemsRaw.where((m) => !hidden.contains(m['id']?.toString())).toList();
              // Mark inbound messages as DELIVERED + SEEN now that they're on screen.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _ackReceipts(serverItems, seen: true);
              });

              // Drop optimistic stubs the server has already replaced with
              // real rows (matched by body + author + close-in-time).
              final serverIds = serverItems
                  .whereType<Map>()
                  .map((m) => m['id']?.toString())
                  .toSet();
              _pendingOutgoing.removeWhere((p) {
                final pid = p['id']?.toString();
                if (pid != null && serverIds.contains(pid)) return true;
                // Heuristic dedupe: server message with same body + my author
                // landed within the last 30s — assume it's our optimistic stub.
                final body = (p['body'] ?? '').toString();
                final meId = (p['author'] as Map?)?['id'];
                final now = DateTime.now();
                final matched = serverItems.whereType<Map>().any((s) {
                  if ((s['body'] ?? '') != body) return false;
                  if ((s['author'] as Map?)?['id'] != meId) return false;
                  final t = DateTime.tryParse(s['createdAt']?.toString() ?? '');
                  return t != null && now.difference(t).inSeconds.abs() < 30;
                });
                return matched;
              });

              // Combined list: server messages then optimistic outgoing.
              final items = [...serverItems, ..._pendingOutgoing];

              // Auto-scroll to the newest message on arrival.
              if (items.length != _lastCount) {
                _lastCount = items.length;
                _scrollToLatestSoon();
              }

              if (items.isEmpty) {
                return const BestieEmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'No messages yet',
                  description: 'Send the first message to break the ice.',
                );
              }

              // `reverse: true` pins the newest message at the bottom (above
              // the composer) so the visual order matches WhatsApp. We render
              // the *reversed* list so index 0 = newest.
              final reversed = items.reversed.toList();
              return ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: reversed.length,
                itemBuilder: (_, i) {
                  final m = reversed[i];
                  final kindStr = (m['kind'] ?? 'TEXT').toString();
                  if (kindStr == 'SYSTEM' || kindStr == 'CALL_EVENT') {
                    return _SystemBubble(message: m);
                  }
                  final author = (m['author'] as Map?)?.cast<String, dynamic>() ?? const {};
                  final mine = me?.id != null && author['id'] == me!.id;
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
          onStartRecording: _startVoiceRecording,
          onStopRecording: _stopVoiceRecording,
          onSendVoice: _sendVoiceNote,
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

class _Composer extends StatefulWidget {
  final BestieColors colors;
  final TextEditingController controller;
  final bool sending;
  final bool attaching;
  final Future<void> Function({List<String>? attachmentIds, String? overrideBody}) onSend;
  final VoidCallback onAttach;
  final Future<void> Function() onStartRecording;
  final Future<String?> Function() onStopRecording;
  final Future<void> Function(String path) onSendVoice;

  const _Composer({
    required this.colors,
    required this.controller,
    required this.sending,
    required this.attaching,
    required this.onSend,
    required this.onAttach,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onSendVoice,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hasText = false;
  bool _recording = false;
  int _seconds = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _hasText = widget.controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  /// Bottom-sheet emoji picker. Inserts at the current cursor position so the
  /// user can mix text + emoji naturally.
  Future<void> _showEmojiPicker() async {
    final c = BestieColors.of(context);
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      builder: (ctx) => SizedBox(
        height: 320,
        child: EmojiPicker(
          onEmojiSelected: (cat, emoji) {
            final ctl = widget.controller;
            final sel = ctl.selection;
            final start = sel.start < 0 ? ctl.text.length : sel.start;
            final end = sel.end < 0 ? ctl.text.length : sel.end;
            final newText = ctl.text.replaceRange(start, end, emoji.emoji);
            ctl.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: start + emoji.emoji.length),
            );
          },
          config: Config(
            height: 320,
            checkPlatformCompatibility: true,
            emojiViewConfig: EmojiViewConfig(
              backgroundColor: c.surface,
              columns: 8,
              emojiSizeMax: 28,
            ),
            categoryViewConfig: CategoryViewConfig(
              backgroundColor: c.surface,
              indicatorColor: c.brand,
              iconColor: c.textMuted,
              iconColorSelected: c.brand,
            ),
            bottomActionBarConfig: BottomActionBarConfig(
              backgroundColor: c.surface,
              buttonColor: c.surface,
              buttonIconColor: c.textMuted,
            ),
            searchViewConfig: SearchViewConfig(
              backgroundColor: c.surface,
              buttonIconColor: c.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startRecording() async {
    setState(() { _recording = true; _seconds = 0; });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    await widget.onStartRecording();
  }

  Future<void> _stopAndSend({bool cancelled = false}) async {
    _ticker?.cancel();
    final path = await widget.onStopRecording();
    setState(() { _recording = false; _seconds = 0; });
    if (!cancelled && path != null) {
      await widget.onSendVoice(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: _recording
            ? _recordingBar(colors)
            : _normalBar(colors),
      ),
    );
  }

  Widget _normalBar(BestieColors colors) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      widget.attaching
          ? const Padding(padding: EdgeInsets.all(12), child: BestieSpinner(size: 18))
          : IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, color: colors.textSoft),
              onPressed: widget.onAttach,
              tooltip: 'Attach',
            ),
      IconButton(
        icon: Icon(Icons.emoji_emotions_outlined, color: colors.textSoft),
        onPressed: _showEmojiPicker,
        tooltip: 'Emoji',
      ),
      Expanded(
        child: TextField(
          controller: widget.controller,
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
          onSubmitted: (_) => widget.onSend(),
        ),
      ),
      const SizedBox(width: 6),
      widget.sending
          ? const Padding(padding: EdgeInsets.all(10), child: BestieSpinner(size: 18))
          : (_hasText
              ? IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: BestieTokens.cBrand,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  onPressed: () => widget.onSend(),
                )
              : GestureDetector(
                  onLongPress: _startRecording,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: BestieTokens.cBrand,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.mic_rounded, size: 18),
                    // Single tap also starts — long-press is the WhatsApp gesture
                    // but a tap is more discoverable on first use.
                    onPressed: _startRecording,
                  ),
                )),
    ]);
  }

  Widget _recordingBar(BestieColors colors) {
    final mm = (_seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_seconds % 60).toString().padLeft(2, '0');
    return Row(children: [
      IconButton(
        icon: Icon(Icons.delete_outline_rounded, color: colors.danger),
        tooltip: 'Cancel',
        onPressed: () => _stopAndSend(cancelled: true),
      ),
      Expanded(
        child: Row(children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: colors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text('Recording  ', style: TextStyle(color: colors.textSoft, fontSize: 13)),
          Text('$mm:$ss',
              style: TextStyle(
                color: colors.text,
                fontWeight: BestieTokens.fwBold,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
      ),
      IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: BestieTokens.cSuccess,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.send_rounded, size: 18),
        tooltip: 'Send voice note',
        onPressed: () => _stopAndSend(),
      ),
    ]);
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

class _MessageBubble extends ConsumerWidget {
  final Map<String, dynamic> message;
  final Map<String, dynamic> author;
  final bool mine;
  const _MessageBubble({required this.message, required this.author, required this.mine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final body = message['body'] as String? ?? '';
    final attachments = (message['attachments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final isClient = author['isClient'] == true;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = mine ? c.brand : c.surface;
    final fg = mine ? Colors.white : c.text;
    final timeStr = _formatTime(message['createdAt']?.toString());
    final status = (message['status'] ?? 'SENT').toString();
    final isDeleted = message['deletedAt'] != null;
    final isEdited = message['editedAt'] != null;

    return GestureDetector(
      onLongPress: isDeleted ? null : () => _showActions(context, ref),
      child: Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isDeleted ? c.surface2 : bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: (mine && !isDeleted) ? null : Border.all(color: c.border),
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
            if (!isDeleted) for (final a in attachments) ...[
              _Attachment(asset: a, mine: mine, colors: c),
              const SizedBox(height: 4),
            ],
            if (isDeleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.block_rounded, size: 13, color: c.textMuted),
                  const SizedBox(width: 6),
                  Text('Message deleted',
                      style: TextStyle(
                        color: c.textMuted, fontSize: 13,
                        fontStyle: FontStyle.italic,
                      )),
                ]),
              )
            else if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                child: Text(body, style: TextStyle(color: fg, fontSize: 14, height: 1.35)),
              ),
            // WhatsApp-style footer: time + (only on my messages) tick marks.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 4, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (isEdited && !isDeleted) ...[
                  Text('edited · ',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: mine ? Colors.white.withOpacity(0.70) : c.textFaint,
                      )),
                ],
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: BestieTokens.fwMedium,
                    color: mine && !isDeleted ? Colors.white.withOpacity(0.78) : c.textMuted,
                  ),
                ),
                if (mine && !isDeleted) ...[
                  const SizedBox(width: 4),
                  _StatusTicks(status: status),
                ],
              ]),
            ),
          ],
        ),
      ),
    ));
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final canEdit = mine && (message['body'] ?? '').toString().isNotEmpty;
    final canDeleteForEveryone = mine;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: c.borderStrong, borderRadius: BorderRadius.circular(BestieTokens.rPill),
            ),
          ),
          ListTile(
            leading: Icon(Icons.copy_rounded, color: c.textSoft),
            title: Text('Copy', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: (message['body'] ?? '').toString()));
              if (context.mounted) bestieToast(context, 'Copied', kind: BestieToastKind.success);
            },
          ),
          if (canEdit)
            ListTile(
              leading: Icon(Icons.edit_outlined, color: c.textSoft),
              title: Text('Edit', style: TextStyle(color: c.text)),
              onTap: () { Navigator.pop(ctx); _editMessage(context, ref); },
            ),
          if (canDeleteForEveryone)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: c.danger),
              title: Text('Delete for everyone',
                  style: TextStyle(color: c.danger, fontWeight: BestieTokens.fwSemibold)),
              onTap: () { Navigator.pop(ctx); _deleteForEveryone(context, ref); },
            ),
          ListTile(
            leading: Icon(Icons.visibility_off_outlined, color: c.textSoft),
            title: Text('Delete for me', style: TextStyle(color: c.text)),
            onTap: () { Navigator.pop(ctx); _deleteForMe(context, ref); },
          ),
        ]),
      ),
    );
  }

  Future<void> _editMessage(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: (message['body'] ?? '').toString());
    final c = BestieColors.of(context);
    final newBody = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Edit message', style: TextStyle(color: c.text)),
        content: TextField(
          controller: controller, autofocus: true,
          minLines: 1, maxLines: 6,
          style: TextStyle(color: c.text),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: BestieTokens.cBrand),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newBody == null || newBody.isEmpty) return;
    try {
      await ref.read(apiProvider).editMessage(message['id'] as String, newBody);
      ref.invalidate(messagesProvider(message['channelId'] as String));
    } catch (e) {
      if (context.mounted) bestieToast(context, 'Edit failed',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<void> _deleteForEveryone(BuildContext context, WidgetRef ref) async {
    final ok = await bestieConfirm(context,
        title: 'Delete for everyone?',
        description: 'This will replace the message with "Message deleted" for all members.',
        confirmLabel: 'Delete');
    if (!ok) return;
    try {
      await ref.read(apiProvider).deleteMessageForEveryone(message['id'] as String);
      ref.invalidate(messagesProvider(message['channelId'] as String));
    } catch (e) {
      if (context.mounted) bestieToast(context, 'Delete failed',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  /// Local-only hide — adds the message id to a SharedPreferences set so we
  /// filter it out of the displayed list. The backend never sees this and
  /// other members still see the original message. Mirrors WhatsApp's
  /// "Delete for me".
  Future<void> _deleteForMe(BuildContext context, WidgetRef ref) async {
    final ok = await bestieConfirm(context,
        title: 'Delete for me?',
        description: 'The message stays visible to others, but it will disappear from your chat.',
        confirmLabel: 'Delete');
    if (!ok) return;
    try {
      final prefs = await ref.read(_prefsProvider.future);
      final key = 'chat.hidden.${message['channelId']}';
      final hidden = prefs.getStringList(key)?.toSet() ?? <String>{};
      hidden.add(message['id'] as String);
      await prefs.setStringList(key, hidden.toList());
      ref.invalidate(_hiddenMessageIdsProvider(message['channelId'] as String));
    } catch (_) { /* silent — local-only */ }
  }

  String _formatTime(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

/// WhatsApp-style status indicator:
///   SENT       → single grey ✓
///   DELIVERED  → double grey ✓✓
///   SEEN       → double blue ✓✓
///   SENDING    → small clock
///   FAILED     → red exclamation
class _StatusTicks extends StatelessWidget {
  final String status;
  const _StatusTicks({required this.status});

  @override
  Widget build(BuildContext context) {
    const seenBlue = Color(0xFF53BDEB); // matches WhatsApp's read-receipt blue
    final greyOnBrand = Colors.white.withOpacity(0.86);

    switch (status) {
      case 'SENDING':
        return Icon(Icons.access_time_rounded, size: 12, color: greyOnBrand);
      case 'FAILED':
        return const Icon(Icons.error_outline_rounded, size: 12, color: Color(0xFFFFB4B4));
      case 'SEEN':
        return const _DoubleTick(color: seenBlue);
      case 'DELIVERED':
        return _DoubleTick(color: greyOnBrand);
      case 'SENT':
      default:
        return _SingleTick(color: greyOnBrand);
    }
  }
}

class _SingleTick extends StatelessWidget {
  final Color color;
  const _SingleTick({required this.color});
  @override
  Widget build(BuildContext context) => Icon(Icons.check_rounded, size: 14, color: color);
}

class _DoubleTick extends StatelessWidget {
  final Color color;
  const _DoubleTick({required this.color});
  @override
  Widget build(BuildContext context) {
    // Two overlapping checks — leans on Stack instead of `done_all` so the
    // colors render crisply against the bubble background.
    return SizedBox(
      width: 18, height: 14,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 0, child: Icon(Icons.check_rounded, size: 14, color: color)),
        Positioned(left: 5, child: Icon(Icons.check_rounded, size: 14, color: color)),
      ]),
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
    final isAudio = mime.startsWith('audio/');
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
    if (isAudio && url.isNotEmpty) {
      return _VoiceNote(url: url, mine: mine, colors: colors);
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

/// Voice-note bubble — play/pause + duration + minimal waveform-style bars
/// that fill as playback progresses. Self-contained: owns its AudioPlayer.
class _VoiceNote extends StatefulWidget {
  final String url;
  final bool mine;
  final BestieColors colors;
  const _VoiceNote({required this.url, required this.mine, required this.colors});

  @override
  State<_VoiceNote> createState() => _VoiceNoteState();
}

class _VoiceNoteState extends State<_VoiceNote> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }),
      _player.onDurationChanged.listen((d) => mounted ? setState(() => _duration = d) : null),
      _player.onPositionChanged.listen((p) => mounted ? setState(() => _position = p) : null),
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() { _playing = false; _position = Duration.zero; });
      }),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) { s.cancel(); }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final c = widget.colors;
    final accent = mine ? Colors.white : BestieTokens.cBrand;
    final fg = mine ? Colors.white : c.text;
    final dur = _duration.inMilliseconds > 0 ? _duration : const Duration(seconds: 1);
    final progress = (_position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    final remaining = _playing ? (_duration - _position) : _duration;
    final mm = (remaining.inSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (mine ? Colors.white : c.surface2).withOpacity(mine ? 0.14 : 1),
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: mine ? BestieTokens.cBrand : Colors.white,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 22,
              child: Row(children: List.generate(28, (i) {
                final filled = (i / 28) < progress;
                final h = 4 + ((i * 3 + 7) % 14).toDouble();
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: h,
                    decoration: BoxDecoration(
                      color: filled ? accent : accent.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              })),
            ),
            const SizedBox(height: 2),
            Text('$mm:$ss',
              style: TextStyle(color: fg.withOpacity(0.85), fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      ]),
    );
  }
}
