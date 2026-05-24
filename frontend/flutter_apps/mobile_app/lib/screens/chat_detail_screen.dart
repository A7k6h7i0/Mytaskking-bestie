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

  // Show a "Jump to latest" FAB whenever the user has scrolled away from
  // the most recent message. With `reverse: true` the latest sits at offset
  // 0 — so anything >40px means we're a fair bit up the conversation.
  bool _showJumpToBottom = false;

  // Message being quoted (reply-to). When non-null the composer renders a
  // preview chip above the text field and `_send` includes the `replyToId`.
  Map<String, dynamic>? _replyingTo;

  // When >0 the chat detail is in "search mode": app bar is replaced with
  // a query field and the list filters to messages containing the term.
  String _searchQuery = '';
  bool _searching = false;

  // Typing-indicator state. We track which remote users are mid-typing
  // (keyed by userId) and bump a per-user timer on every `chat.typing`
  // event; if no follow-up arrives within 4 s we drop the indicator.
  final Map<String, ({String name, Timer timeout})> _typing = {};
  Timer? _myTypingThrottle;
  DateTime? _lastTypingEmit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChannel();
    _listenForReceiptEvents();
    _listenForTyping();
    _scroll.addListener(_onScroll);
    _composer.addListener(_onComposerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _composer.removeListener(_onComposerChanged);
    _myTypingThrottle?.cancel();
    _receiptInvalidate?.cancel();
    for (final t in _typing.values) { t.timeout.cancel(); }
    _composer.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  /// Reveal the "jump to latest" FAB whenever the user has scrolled away
  /// from the most recent message. Cheap — reads offset only, no rebuild
  /// unless the boolean flips.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final shouldShow = _scroll.offset > 80;
    if (shouldShow != _showJumpToBottom) {
      setState(() => _showJumpToBottom = shouldShow);
    }
  }

  /// Throttle outgoing typing events so we don't spam the socket on every
  /// keystroke. We emit at most one event every 2 s while the user is still
  /// typing, then a final emit with `typing: false` once they pause.
  void _onComposerChanged() {
    if (_composer.text.isEmpty) {
      _emitTyping(false);
      return;
    }
    final now = DateTime.now();
    if (_lastTypingEmit == null ||
        now.difference(_lastTypingEmit!).inMilliseconds > 2000) {
      _emitTyping(true);
      _lastTypingEmit = now;
    }
    _myTypingThrottle?.cancel();
    _myTypingThrottle = Timer(const Duration(seconds: 3), () => _emitTyping(false));
  }

  void _emitTyping(bool typing) {
    try {
      ref.read(realtimeProvider).emit('chat.typing', {
        'channelId': widget.channelId,
        'typing': typing,
      });
    } catch (_) { /* socket may be reconnecting */ }
  }

  /// Subscribe to incoming typing events. Each event refreshes a per-user
  /// timeout so the indicator naturally fades after the sender stops.
  void _listenForTyping() {
    final rt = ref.read(realtimeProvider);
    rt.onAny('chat.typing', ([data]) {
      if (data is! Map) return;
      if (data['channelId'] != widget.channelId) return;
      final me = ref.read(authStoreProvider).user;
      final uid = data['userId']?.toString();
      if (uid == null || uid == me?.id) return;
      final typing = data['typing'] == true;
      final existing = _typing[uid];
      existing?.timeout.cancel();
      if (!typing) {
        if (mounted && existing != null) setState(() => _typing.remove(uid));
        return;
      }
      final name = data['name']?.toString() ?? existing?.name ?? 'Someone';
      final timer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _typing.remove(uid));
      });
      if (mounted) setState(() => _typing[uid] = (name: name, timeout: timer));
    });
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

  /// Debounce timer for refreshing the messages list when receipts trickle
  /// in over the socket. Without this, a busy channel can fire dozens of
  /// `chat.message.receipt` events per second and every one would trigger a
  /// fetch + re-ack, hammering /chat/channels/:id/receipts/bulk into a 429.
  Timer? _receiptInvalidate;

  /// Listens to socket receipt events and patches the locally-cached message
  /// list, so the sender's tick marks update live without re-fetching. We
  /// only react to receipts for *our own* messages — incoming receipts for
  /// other senders are irrelevant to this client and triggering a refetch on
  /// every one is what blew up to 429 in the previous version.
  void _listenForReceiptEvents() {
    final rt = ref.read(realtimeProvider);
    rt.onAny('chat.message.receipt', ([data]) {
      if (data is! Map) return;
      // Only the recipient changed state — invalidating for events we
      // ourselves triggered would create the feedback loop.
      final me = ref.read(authStoreProvider).user;
      if (data['userId'] == me?.id) return;
      // Debounce: collapse bursts into a single refresh.
      _receiptInvalidate?.cancel();
      _receiptInvalidate = Timer(const Duration(milliseconds: 600), () {
        if (mounted) ref.invalidate(messagesProvider(widget.channelId));
      });
    });
  }

  /// Sends DELIVERED for every incoming message we haven't acked yet, then
  /// (separately) SEEN for the same set if the screen is currently mounted.
  /// Posting both is what gives WhatsApp's "✓✓ grey → ✓✓ blue" transition.
  ///
  /// Dedup is sticky-on-error: a 429 keeps the ids marked as acked so we
  /// don't retry instantly. They'll resync on next session / scroll. Without
  /// this, the previous version unblocked the dedup set on every failure
  /// and a single 429 turned into a thundering retry storm.
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
      // Fire-and-forget; failures stay quiet (no UI toast, no rollback of
      // the dedup set). Worst case the recipient ticks update on next open.
      ref.read(apiProvider)
          .sendReceipts(widget.channelId, toDeliver, 'DELIVERED')
          .catchError((_) => <String, dynamic>{});
    }
    if (seen) {
      final toSee = incomingIds.where((id) => !_ackedSeen.contains(id)).toList();
      if (toSee.isNotEmpty) {
        _ackedSeen.addAll(toSee);
        ref.read(apiProvider)
            .sendReceipts(widget.channelId, toSee, 'SEEN')
            .catchError((_) => <String, dynamic>{});
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

  /// Parses a slash command from the composer and runs its side effect.
  /// Returns `true` when the command was recognized and handled (whether
  /// it succeeded or failed) — the caller skips the regular message post
  /// in that case. Returns `false` for unknown slashes so they're sent as
  /// plain text (Slack-style fallback).
  Future<bool> _handleSlashCommand(String raw) async {
    final parts = raw.split(' ');
    final cmd = parts.first.toLowerCase();
    final args = parts.skip(1).join(' ').trim();
    switch (cmd) {
      case '/task':
        if (args.isEmpty) {
          bestieToast(context, 'Usage: /task <title>',
              kind: BestieToastKind.warning);
          _composer.clear();
          return true;
        }
        try {
          final due = DateTime.now()
              .add(const Duration(days: 1))
              .copyWith(hour: 17, minute: 0);
          await ref.read(apiProvider).post('/tasks', body: {
            'title': args,
            'priority': 'MEDIUM',
            'status': 'TODO',
            'dueAt': due.toUtc().toIso8601String(),
          });
          ref.invalidate(tasksKanbanProvider);
          _composer.clear();
          if (mounted) bestieToast(context, 'Task created', body: args,
              kind: BestieToastKind.success);
        } catch (e) {
          if (mounted) bestieToast(context, 'Could not create task',
              body: formatApiError(e), kind: BestieToastKind.error);
        }
        return true;

      case '/me':
        // Rewrites the composer to read "*Name* did X" so it lands in chat
        // as an action message, à la IRC. We fall through and let the
        // normal _send pipeline post it.
        final me = ref.read(authStoreProvider).user;
        if (args.isEmpty || me == null) {
          bestieToast(context, 'Usage: /me <action>',
              kind: BestieToastKind.warning);
          _composer.clear();
          return true;
        }
        _composer.text = '_${me.name} ${args}_';
        return false;

      case '/meet':
        final name = args.isEmpty ? 'Quick huddle' : args;
        try {
          final m = await ref.read(apiProvider).createMeeting(name: name);
          final slug = m['slug']?.toString();
          if (slug != null) {
            _composer.text = 'Join: https://mytaskking.com/meetings/join/$slug';
            return false; // let normal send post the link
          }
        } catch (e) {
          if (mounted) bestieToast(context, 'Could not start meeting',
              body: formatApiError(e), kind: BestieToastKind.error);
        }
        return true;

      case '/help':
        _composer.clear();
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Chat shortcuts'),
              content: const Text(
                '/task <title> — create a task\n'
                '/me <action> — post an action ("*you* did X")\n'
                '/meet [name] — start a meeting + share the link\n'
                '/help — show this list',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return true;

      default:
        return false;
    }
  }

  Future<void> _send({List<String>? attachmentIds, String? overrideBody}) async {
    final body = overrideBody ?? _composer.text.trim();
    if (body.isEmpty && (attachmentIds == null || attachmentIds.isEmpty)) return;
    final me = ref.read(authStoreProvider).user;
    if (me == null) return;

    // Slash commands intercept the send — they handle their own side
    // effects (create task, /me action, etc) and skip the regular message
    // post entirely. /me is the one exception: it still posts a chat
    // message but in the "third person" format.
    if (overrideBody == null &&
        attachmentIds == null &&
        body.startsWith('/')) {
      final handled = await _handleSlashCommand(body);
      if (handled) return;
    }

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

    final replyId = _replyingTo?['id'] as String?;
    // Capture before clearing — the user may have already typed their next
    // message by the time the network roundtrip lands.
    final wasReplying = _replyingTo != null;
    if (wasReplying) setState(() => _replyingTo = null);

    try {
      await ref.read(apiProvider).sendMessage(
        widget.channelId,
        body: body.isEmpty ? null : body,
        attachmentIds: attachmentIds,
        kind: attachmentIds != null && attachmentIds.isNotEmpty ? 'FILE' : 'TEXT',
        replyToId: replyId,
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

  /// Begin replying to [message] — composer gets a quoted preview above the
  /// text field, the next sendMessage call carries `replyToId`.
  void _startReply(Map<String, dynamic> message) {
    if (!mounted) return;
    setState(() => _replyingTo = message);
    // A frame later so the composer has rebuilt and the field's focus node
    // is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  /// True when `current` and `previous` are on different local calendar
  /// days — used to inject a "Today / Yesterday / Mar 18" divider chip
  /// between them. `previous` is null at the conversation's first message.
  bool _shouldShowDateDivider(Map<String, dynamic> current, Map<String, dynamic>? previous) {
    final ts = DateTime.tryParse(current['createdAt']?.toString() ?? '')?.toLocal();
    if (ts == null) return false;
    if (previous == null) return true;
    final prev = DateTime.tryParse(previous['createdAt']?.toString() ?? '')?.toLocal();
    if (prev == null) return true;
    return ts.year != prev.year || ts.month != prev.month || ts.day != prev.day;
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

  /// Parses the composer text up to the cursor and extracts an in-progress
  /// @handle (e.g. "Hey @pri" → "pri"). Returns `null` when the user isn't
  /// currently typing a mention — most keystrokes early-return this way.
  String? _activeMentionQuery() {
    final selection = _composer.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursor = selection.start;
    if (cursor <= 0 || cursor > _composer.text.length) return null;
    final upToCursor = _composer.text.substring(0, cursor);
    final atIndex = upToCursor.lastIndexOf('@');
    if (atIndex < 0) return null;
    // Bail when '@' is in the middle of a word (e.g. an email address).
    if (atIndex > 0) {
      final prev = upToCursor[atIndex - 1];
      if (prev != ' ' && prev != '\n') return null;
    }
    final fragment = upToCursor.substring(atIndex + 1);
    if (fragment.contains(' ') || fragment.contains('\n')) return null;
    return fragment;
  }

  Widget _mentionSuggestions(BestieColors c) {
    final query = _activeMentionQuery();
    if (query == null) return const SizedBox.shrink();
    final members = (_channel?['members'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    final me = ref.read(authStoreProvider).user;
    final q = query.toLowerCase();
    final matches = members
        .map((m) => (m['user'] as Map?)?.cast<String, dynamic>())
        .whereType<Map<String, dynamic>>()
        .where((u) {
          if (me?.id != null && u['id'] == me!.id) return false;
          final name = (u['name'] ?? '').toString().toLowerCase();
          return q.isEmpty || name.contains(q);
        })
        .take(5)
        .toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: matches.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemBuilder: (_, i) {
          final u = matches[i];
          return InkWell(
            onTap: () => _applyMention(u),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                BestieAvatar(
                  name: u['name']?.toString() ?? '?',
                  imageUrl: u['avatarUrl']?.toString(),
                  isClient: u['isClient'] ?? false,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BestieUserName(
                    name: u['name']?.toString() ?? '',
                    isClient: u['isClient'] ?? false,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.text,
                      fontWeight: BestieTokens.fwSemibold,
                    ),
                  ),
                ),
                Text(
                  (u['role'] ?? '').toString().replaceAll('_', ' '),
                  style: TextStyle(fontSize: 10, color: c.textMuted),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  /// Tap-handler for the suggestion list. Substitutes the `@fragment` at the
  /// cursor with `@Name ` (trailing space) and bumps the cursor past it so
  /// the user can continue typing immediately.
  void _applyMention(Map<String, dynamic> user) {
    final selection = _composer.selection;
    if (!selection.isValid) return;
    final cursor = selection.start;
    final text = _composer.text;
    final atIndex = text.substring(0, cursor).lastIndexOf('@');
    if (atIndex < 0) return;
    final name = (user['name'] ?? '').toString();
    final replacement = '@$name ';
    final newText = text.replaceRange(atIndex, cursor, replacement);
    _composer.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: atIndex + replacement.length,
      ),
    );
    setState(() {});
  }

  /// Thin banner above the messages list that surfaces messages someone has
  /// pinned in this channel. Tapping it opens a bottom sheet with the full
  /// list — handy when an admin pins a release plan, a checklist, or a
  /// "single source of truth" link in a busy group.
  Widget _pinnedBar(List<Map<String, dynamic>> items, BestieColors c) {
    final pinned = items.where((m) => m['pinned'] == true).toList();
    if (pinned.isEmpty) return const SizedBox.shrink();
    // The most recently pinned message is the most useful preview.
    pinned.sort((a, b) => '${b['updatedAt']}'.compareTo('${a['updatedAt']}'));
    final top = pinned.first;
    final author = (top['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    final body = (top['body'] ?? '').toString();
    final preview = body.length > 80 ? '${body.substring(0, 77)}…' : body;
    return Material(
      color: c.surface,
      child: InkWell(
        onTap: () => _openPinnedSheet(pinned, c),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(children: [
            Container(
              width: 4, height: 32,
              decoration: BoxDecoration(
                color: c.warning,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.push_pin_rounded, size: 14, color: c.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pinned.length > 1
                        ? 'Pinned · ${pinned.length} messages'
                        : 'Pinned by ${author['name'] ?? 'someone'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: BestieTokens.fwBold,
                      color: c.warning,
                      letterSpacing: BestieTokens.lsEyebrow,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview.isEmpty ? '(attachment)' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textSoft),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textFaint, size: 18),
          ]),
        ),
      ),
    );
  }

  Future<void> _openPinnedSheet(
      List<Map<String, dynamic>> pinned, BestieColors c) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Icon(Icons.push_pin_rounded, size: 18, color: c.warning),
                const SizedBox(width: 8),
                Text('Pinned messages',
                    style: TextStyle(
                      color: c.text, fontSize: 16,
                      fontWeight: BestieTokens.fwBold,
                    )),
                const Spacer(),
                Text('${pinned.length}',
                    style: TextStyle(color: c.textMuted, fontSize: 13)),
              ]),
            ),
            Divider(height: 1, color: c.border),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: pinned.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
                itemBuilder: (_, i) {
                  final m = pinned[i];
                  final author =
                      (m['author'] as Map?)?.cast<String, dynamic>() ?? const {};
                  final body = (m['body'] ?? '').toString();
                  return ListTile(
                    leading: BestieAvatar(
                      name: author['name']?.toString() ?? '?',
                      imageUrl: author['avatarUrl']?.toString(),
                      isClient: author['isClient'] ?? false,
                      size: 32,
                    ),
                    title: BestieUserName(
                      name: author['name']?.toString() ?? 'Someone',
                      isClient: author['isClient'] ?? false,
                      style: TextStyle(
                        color: c.text,
                        fontWeight: BestieTokens.fwSemibold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      body.isEmpty ? '(attachment)' : body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSoft, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.push_pin, size: 18, color: c.warning),
                      tooltip: 'Unpin',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await ref.read(apiProvider).unpinMessage(m['id'] as String);
                          ref.invalidate(messagesProvider(widget.channelId));
                          if (mounted) {
                            bestieToast(context, 'Unpinned',
                                kind: BestieToastKind.success);
                          }
                        } catch (e) {
                          if (mounted) {
                            bestieToast(context, 'Could not unpin',
                                body: formatApiError(e),
                                kind: BestieToastKind.error);
                          }
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Suggest 3 short canned replies based on the last message body.
  /// Returns an empty list when nothing useful applies (typing already,
  /// last message is mine, or already replying).
  List<String> _smartReplyOptions(String? lastBody) {
    if (_composer.text.trim().isNotEmpty) return const [];
    final b = (lastBody ?? '').toLowerCase().trim();
    if (b.isEmpty) return const [];
    // Question → confirmation-style replies.
    if (b.endsWith('?') || b.startsWith('can ') || b.startsWith('could ') ||
        b.startsWith('would ') || b.startsWith('shall ') || b.startsWith('any ')) {
      return const ['Yes 👍', 'Working on it', "Let me check"];
    }
    // Thanks → graceful acks.
    if (b.contains('thank')) return const ['Anytime 🙌', 'My pleasure', 'Happy to help'];
    // Greetings.
    if (b.contains('good morning') || b.contains('hi ') || b.startsWith('hi') ||
        b.contains('hello') || b.contains('hey')) {
      return const ['Hey 👋', 'Morning!', 'How can I help?'];
    }
    // Done / shipped / merged → praise.
    if (b.contains('done') || b.contains('shipped') || b.contains('merged') ||
        b.contains('deployed') || b.contains('finished')) {
      return const ['🎉 Nice!', 'Great work', 'Awesome'];
    }
    // Default — short, generic, useful.
    return const ['👍 Got it', 'On it', "Thanks!"];
  }

  Widget _smartReplies(BestieColors c, BestieUser? me) {
    final messages = ref.watch(messagesProvider(widget.channelId));
    final items = messages.asData?.value ?? const <Map<String, dynamic>>[];
    if (items.isEmpty || me == null) return const SizedBox.shrink();
    // The latest message (most recent createdAt) — the list is in chrono order.
    final last = items.last;
    final author = (last['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (author['id'] == me.id) return const SizedBox.shrink();
    final kind = (last['kind'] ?? 'TEXT').toString();
    if (kind != 'TEXT') return const SizedBox.shrink();
    final options = _smartReplyOptions(last['body']?.toString());
    if (options.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final text = options[i];
            return InkWell(
              borderRadius: BorderRadius.circular(BestieTokens.rPill),
              onTap: () => _send(overrideBody: text),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  border: Border.all(color: c.brand.withOpacity(0.25)),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: BestieTokens.fwSemibold,
                    color: c.brandStrong,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
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
        _pinnedBar(messages.asData?.value ?? const [], colors),
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
                  final author = (m['author'] as Map?)?.cast<String, dynamic>() ?? const {};
                  final mine = me?.id != null && author['id'] == me!.id;

                  // Date divider: when the message *below* this one (visually
                  // earlier in time) is from a different day, prepend a
                  // "Today / Yesterday / Mar 18" chip above the current
                  // message. With reverse:true that means rendering it AFTER
                  // the bubble (it appears above when reversed).
                  final next = i + 1 < reversed.length ? reversed[i + 1] : null;
                  final showDivider = _shouldShowDateDivider(m, next);
                  final divider = showDivider
                      ? _DateDivider(timestamp: m['createdAt']?.toString())
                      : null;

                  final bubble = kindStr == 'SYSTEM' || kindStr == 'CALL_EVENT'
                      ? _SystemBubble(message: m) as Widget
                      : _MessageBubble(message: m, author: author, mine: mine);

                  if (divider == null) return bubble;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [bubble, divider],
                  );
                },
              );
            },
          ),
        ),
        // Typing indicator sits just above the composer so it doesn't shift
        // the messages list when it appears/disappears.
        if (_typing.isNotEmpty) _TypingIndicator(typing: _typing.values.toList(), colors: colors),
        // @mention autocomplete — pops above the composer when the user is
        // mid-typing an @handle. Replaces the @-fragment with @Name on tap.
        _mentionSuggestions(colors),
        // Smart reply chips — surface 3 quick canned replies when the last
        // message is from someone else and the user hasn't started typing.
        if (_replyingTo == null) _smartReplies(colors, me),
        // Quoted-message preview when replying.
        if (_replyingTo != null) _ReplyComposerChip(
          message: _replyingTo!,
          colors: colors,
          onCancel: () => setState(() => _replyingTo = null),
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
      // Quick way back to the latest message after scrolling up. Mini-sized
      // so it doesn't compete with the composer for thumb space.
      floatingActionButton: _showJumpToBottom
          ? Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: FloatingActionButton.small(
                heroTag: 'chat_jump_to_bottom',
                onPressed: () {
                  if (_scroll.hasClients) {
                    _scroll.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    );
                  }
                  setState(() => _showJumpToBottom = false);
                },
                backgroundColor: colors.surface,
                foregroundColor: colors.text,
                elevation: 4,
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
            // Quoted "replying to X" preview inline at the top of the bubble.
            if (!isDeleted && message['replyTo'] is Map)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                child: _ReplyQuote(replyTo: message['replyTo'] as Map, mine: mine, colors: c),
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
            if (!isDeleted) _ReactionsBar(message: message),
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

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final c = BestieColors.of(context);
    final canEdit = mine && (message['body'] ?? '').toString().isNotEmpty;
    final canDeleteForEveryone = mine;
    // Pre-load the recents MRU before opening the sheet so the row paints
    // immediately rather than flashing the default set first.
    final recents = await _RecentEmojis.read();
    // Merged set: recents first, then defaults that aren't already in recents.
    final defaults = const ['👍','❤️','😂','😮','😢','🙏'];
    final merged = <String>[
      ...recents,
      ...defaults.where((e) => !recents.contains(e)),
    ].take(6).toList();
    if (!context.mounted) return;
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
          // Quick-react row: recently-used first (so the user's habits stay
          // one tap away), then the iMessage / WhatsApp defaults.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              for (final e in merged)
                _ReactionChip(emoji: e, onTap: () {
                  Navigator.pop(ctx);
                  _RecentEmojis.push(e);
                  _reactWith(context, ref, e);
                }),
            ]),
          ),
          Divider(height: 1, color: c.border),
          ListTile(
            leading: Icon(Icons.copy_rounded, color: c.textSoft),
            title: Text('Copy', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: (message['body'] ?? '').toString()));
              if (context.mounted) bestieToast(context, 'Copied', kind: BestieToastKind.success);
            },
          ),
          ListTile(
            leading: Icon(
              message['pinned'] == true ? Icons.push_pin : Icons.push_pin_outlined,
              color: c.textSoft,
            ),
            title: Text(message['pinned'] == true ? 'Unpin message' : 'Pin message',
                style: TextStyle(color: c.text)),
            onTap: () { Navigator.pop(ctx); _togglePin(context, ref); },
          ),
          ListTile(
            leading: Icon(Icons.reply_rounded, color: c.textSoft),
            title: Text('Reply', style: TextStyle(color: c.text)),
            onTap: () {
              Navigator.pop(ctx);
              // Look up the parent state in the widget tree so we can set
              // its `_replyingTo` and focus the composer.
              context.findAncestorStateOfType<_ChatDetailScreenState>()
                  ?._startReply(message);
            },
          ),
          ListTile(
            leading: Icon(Icons.bookmark_border_rounded, color: c.textSoft),
            title: Text('Save message', style: TextStyle(color: c.text)),
            onTap: () { Navigator.pop(ctx); _saveMessage(context, ref); },
          ),
          ListTile(
            leading: Icon(Icons.task_alt_rounded, color: c.textSoft),
            title: Text('Create task from message', style: TextStyle(color: c.text)),
            onTap: () { Navigator.pop(ctx); _createTaskFromMessage(context, ref); },
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

  Future<void> _saveMessage(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiProvider).saveItem(
        kind: 'MESSAGE',
        refId: message['id'] as String,
      );
      ref.invalidate(savedProvider);
      if (context.mounted) bestieToast(context, 'Saved to bookmarks',
          kind: BestieToastKind.success);
    } catch (e) {
      if (context.mounted) bestieToast(context, 'Could not save',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  /// Turn the highlighted chat message into a task. Prefills the title with
  /// the (possibly truncated) message body, prefills the description with
  /// the full body + author handle so context isn't lost, and assigns the
  /// task to the message's author unless that's the current user.
  Future<void> _createTaskFromMessage(BuildContext context, WidgetRef ref) async {
    final c = BestieColors.of(context);
    final body = (message['body'] ?? '').toString().trim();
    if (body.isEmpty) {
      bestieToast(context, 'Nothing to turn into a task',
          body: 'Pick a text message.', kind: BestieToastKind.warning);
      return;
    }
    final me = ref.read(authStoreProvider).user;
    final author = (message['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    final authorId = author['id']?.toString();
    final authorName = author['name']?.toString() ?? 'Someone';
    final title = body.length > 80 ? '${body.substring(0, 77)}…' : body;
    final ctl = TextEditingController(text: title);
    final dueDefault =
        DateTime.now().add(const Duration(days: 1)).copyWith(hour: 17, minute: 0);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.task_alt_rounded, color: c.brandStrong),
            const SizedBox(width: 8),
            Text('Create task',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: BestieTokens.fwBold,
                  color: c.text,
                )),
          ]),
          const SizedBox(height: 16),
          BestieTextField(
            label: 'Title',
            controller: ctl,
            hint: 'What needs to happen?',
          ),
          const SizedBox(height: 12),
          if (authorId != null && authorId != me?.id)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: c.brandSoft,
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                border: Border.all(color: c.brand.withOpacity(0.25)),
              ),
              child: Row(children: [
                Icon(Icons.person_outline, size: 16, color: c.brandStrong),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Will be assigned to $authorName',
                    style: TextStyle(
                      fontSize: 12, color: c.brandStrong,
                      fontWeight: BestieTokens.fwSemibold,
                    ),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Create'),
                style: FilledButton.styleFrom(
                  backgroundColor: BestieTokens.cBrand,
                ),
              ),
            ),
          ]),
        ]),
      ),
    );

    if (ok != true || !context.mounted) return;
    final fullTitle = ctl.text.trim();
    if (fullTitle.isEmpty) return;

    try {
      await ref.read(apiProvider).post('/tasks', body: {
        'title': fullTitle,
        'description': 'From $authorName in chat:\n\n"$body"',
        'priority': 'MEDIUM',
        'status': 'TODO',
        'dueAt': dueDefault.toUtc().toIso8601String(),
        if (authorId != null && authorId != me?.id)
          'assigneeIds': [authorId],
      });
      ref.invalidate(tasksKanbanProvider);
      if (context.mounted) {
        bestieToast(context, 'Task created',
            body: fullTitle, kind: BestieToastKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        bestieToast(context, 'Could not create task',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _reactWith(BuildContext context, WidgetRef ref, String emoji) async {
    try {
      await ref.read(apiProvider).reactMessage(message['id'] as String, emoji);
      ref.invalidate(messagesProvider(message['channelId'] as String));
    } catch (e) {
      if (context.mounted) bestieToast(context, 'Reaction failed',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiProvider);
    try {
      if (message['pinned'] == true) {
        await api.unpinMessage(message['id'] as String);
      } else {
        await api.pinMessage(message['id'] as String);
      }
      ref.invalidate(messagesProvider(message['channelId'] as String));
    } catch (e) {
      if (context.mounted) bestieToast(context, 'Pin failed',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
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

/// Tiny chip strip on top of a message bubble showing aggregated emoji
/// reactions ("👍 3"). Tapping a chip toggles your own reaction with that
/// emoji — adds if absent, removes if you already reacted.
class _ReactionsBar extends ConsumerWidget {
  final Map<String, dynamic> message;
  const _ReactionsBar({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final reactions = (message['reactions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (reactions.isEmpty) return const SizedBox.shrink();

    final me = ref.watch(currentUserProvider).asData?.value
        ?? ref.read(authStoreProvider).user;
    // Aggregate emoji → users[].
    final byEmoji = <String, List<String>>{};
    for (final r in reactions) {
      final e = r['emoji']?.toString();
      final uid = r['userId']?.toString();
      if (e == null || uid == null) continue;
      byEmoji.putIfAbsent(e, () => []).add(uid);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        for (final entry in byEmoji.entries)
          _ReactionPill(
            emoji: entry.key,
            count: entry.value.length,
            mine: me?.id != null && entry.value.contains(me!.id),
            colors: c,
            onTap: () async {
              try {
                final api = ref.read(apiProvider);
                if (me?.id != null && entry.value.contains(me!.id)) {
                  await api.unreactMessage(message['id'] as String, entry.key);
                } else {
                  await api.reactMessage(message['id'] as String, entry.key);
                }
                ref.invalidate(messagesProvider(message['channelId'] as String));
              } catch (_) {/* ignore — refresh will show truth */}
            },
          ),
      ]),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  final String emoji;
  final int count;
  final bool mine;
  final BestieColors colors;
  final VoidCallback onTap;
  const _ReactionPill({
    required this.emoji, required this.count, required this.mine,
    required this.colors, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestieTokens.rPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: mine ? BestieTokens.cBrand.withOpacity(0.16) : colors.surface2,
          border: Border.all(
            color: mine ? BestieTokens.cBrand.withOpacity(0.40) : colors.border,
          ),
          borderRadius: BorderRadius.circular(BestieTokens.rPill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11, fontWeight: BestieTokens.fwSemibold,
              color: mine ? BestieTokens.cBrand : colors.textSoft,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Compact preview chip above the composer showing which message you're
/// replying to. WhatsApp / iMessage standard.
class _ReplyComposerChip extends StatelessWidget {
  final Map<String, dynamic> message;
  final BestieColors colors;
  final VoidCallback onCancel;
  const _ReplyComposerChip({required this.message, required this.colors, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final author = (message['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    final body = (message['body'] ?? '').toString();
    final kind = (message['kind'] ?? 'TEXT').toString();
    final preview = body.isNotEmpty
        ? body
        : (kind == 'IMAGE' ? '📷 Photo' :
           kind == 'VOICE_NOTE' ? '🎙️ Voice note' :
           kind == 'FILE' ? '📎 File' : '');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(children: [
        Container(width: 3, height: 36, color: colors.brand),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Replying to ${author['name'] ?? 'message'}',
              style: TextStyle(
                fontSize: 11, fontWeight: BestieTokens.fwSemibold, color: colors.brand,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
          tooltip: 'Cancel reply',
          onPressed: onCancel,
        ),
      ]),
    );
  }
}

/// Inline quoted preview rendered inside a bubble that's a reply to another
/// message. Tap doesn't currently scroll to original (TODO) but visually it
/// already gives the same context users expect from WhatsApp threads.
class _ReplyQuote extends StatelessWidget {
  final Map replyTo;
  final bool mine;
  final BestieColors colors;
  const _ReplyQuote({required this.replyTo, required this.mine, required this.colors});

  @override
  Widget build(BuildContext context) {
    final body = (replyTo['body'] ?? '').toString();
    final author = replyTo['authorId']?.toString() ?? 'message';
    final bg = mine
        ? Colors.white.withOpacity(0.16)
        : colors.surface2;
    final accent = mine ? Colors.white.withOpacity(0.6) : colors.brand;
    final fg = mine ? Colors.white : colors.text;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BestieTokens.rXs),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(
          author,
          style: TextStyle(fontSize: 10, fontWeight: BestieTokens.fwBold, color: accent),
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: fg.withOpacity(0.85)),
          ),
        ],
      ]),
    );
  }
}

/// Date divider chip — "Today / Yesterday / Mar 18, 2024" pill inserted
/// between messages from different calendar days.
class _DateDivider extends StatelessWidget {
  final String? timestamp;
  const _DateDivider({required this.timestamp});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final label = _labelFor(timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
            border: Border.all(color: c.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: BestieTokens.fwSemibold,
              letterSpacing: BestieTokens.lsWide,
              color: c.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  String _labelFor(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final theirDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(theirDay).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    if (diff < 7) {
      const days = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
      return days[(dt.weekday - 1) % 7];
    }
    const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    if (dt.year == now.year) return '${months[dt.month - 1]} ${dt.day}';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

/// "Priya is typing…" row above the composer. Animated dots gently bounce
/// to signal the indicator is live (not stuck).
class _TypingIndicator extends StatefulWidget {
  final List<({String name, Timer timeout})> typing;
  final BestieColors colors;
  const _TypingIndicator({required this.typing, required this.colors});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _label() {
    final names = widget.typing.map((t) => t.name).toList();
    if (names.length == 1) return '${names.first} is typing';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing';
    return '${names[0]} and ${names.length - 1} others are typing';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
      color: widget.colors.surface,
      child: Row(children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (ctx, _) {
            return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
              final phase = ((_ctrl.value + i * 0.18) % 1.0);
              final scale = 0.65 + 0.35 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: widget.colors.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }));
          },
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            _label(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: widget.colors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Single-emoji react chip — bouncy hit target inside the message action
/// sheet for quick reactions.
class _ReactionChip extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  const _ReactionChip({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 44, height: 44,
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
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
  double _speed = 1.0;
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
      // Apply current speed after play() — setPlaybackRate before play()
      // is a no-op in audioplayers 6.x.
      await _player.setPlaybackRate(_speed);
    }
  }

  Future<void> _cycleSpeed() async {
    setState(() {
      _speed = switch (_speed) { 1.0 => 1.5, 1.5 => 2.0, _ => 1.0, };
    });
    if (_playing) await _player.setPlaybackRate(_speed);
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
        const SizedBox(width: 6),
        // Compact speed cycle — taps 1× → 1.5× → 2× → 1×. Mirrors WhatsApp.
        GestureDetector(
          onTap: _cycleSpeed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (mine ? Colors.white : accent).withOpacity(mine ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(BestieTokens.rXs),
            ),
            child: Text(
              _speed == 1.0 ? '1×' : (_speed == 1.5 ? '1.5×' : '2×'),
              style: TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: BestieTokens.fwBold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Tiny MRU cache of the last few emoji reactions the user picked, kept in
/// SharedPreferences so the bottom-sheet's reaction row can surface
/// frequently-used emoji first.
class _RecentEmojis {
  static const _key = 'chat.recentEmojis.v1';
  static const _max = 6;

  static Future<List<String>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> push(String emoji) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cur = (prefs.getStringList(_key) ?? const <String>[]).toList();
      cur.remove(emoji);
      cur.insert(0, emoji);
      if (cur.length > _max) cur.removeRange(_max, cur.length);
      await prefs.setStringList(_key, cur);
    } catch (_) {/* best-effort */}
  }
}
