import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../chat_media_saver.dart';
import '../state.dart';

class RecordingsScreen extends ConsumerStatefulWidget {
  const RecordingsScreen({super.key});

  @override
  ConsumerState<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends ConsumerState<RecordingsScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiProvider).listRecordings();
  }

  Future<void> _refresh() async {
    setState(() => _future = ref.read(apiProvider).listRecordings());
    await _future;
  }

  Future<void> _download(String url, {String? name}) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final path = await ChatMediaSaver.saveUrlWithSaveDialog(
        url,
        suggestedName: name,
      );
      if (!mounted) return;
      if (path == null) return;
      bestieToast(
        context,
        'Recording saved',
        body: path,
        kind: BestieToastKind.success,
      );
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not download recording',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  List<Map<String, dynamic>> _filesOf(Map<String, dynamic> item) {
    final raw = item['files'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => (e['url']?.toString() ?? '').isNotEmpty)
          .toList();
    }
    final url = item['recordingUrl']?.toString() ?? '';
    if (url.isEmpty) return const [];
    return [
      {'name': 'recording', 'kind': 'audio', 'url': url},
    ];
  }

  String _sourceLabel(String source) {
    switch (source.toUpperCase()) {
      case 'MEDIASOUP':
        return 'SFU call';
      case 'TELECALLER':
        return 'Telecaller';
      case 'MEETING':
        return 'Meeting';
      case 'CALL':
        return 'Uploaded call';
      default:
        return source;
    }
  }

  IconData _sourceIcon(String source) {
    switch (source.toUpperCase()) {
      case 'MEETING':
        return Icons.videocam_outlined;
      case 'TELECALLER':
        return Icons.headset_mic_outlined;
      case 'MEDIASOUP':
        return Icons.podcasts_rounded;
      default:
        return Icons.phone_outlined;
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final title = (item['title'] ?? 'this recording').toString();
    final source = (item['source'] ?? '').toString().toUpperCase();
    final ok = await bestieConfirm(
      context,
      title: 'Delete recording?',
      description: source == 'MEDIASOUP'
          ? 'This deletes the SFU recording "$title" from connect.'
          : 'This removes "$title" from the recordings list.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;

    try {
      await ref.read(apiProvider).deleteRecording(
            source,
            (item['id'] ?? '').toString(),
          );
      await _refresh();
      if (mounted) {
        bestieToast(context, 'Recording deleted',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not delete recording',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _openFilesSheet(Map<String, dynamic> item) async {
    final files = _filesOf(item);
    if (files.isEmpty) return;
    if (files.length == 1) {
      await _download(
        files.first['url']!.toString(),
        name: files.first['name']?.toString(),
      );
      return;
    }
    final c = BestieColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in files)
              ListTile(
                leading: Icon(
                  (f['kind']?.toString() ?? '') == 'video'
                      ? Icons.videocam_outlined
                      : Icons.audiotrack_rounded,
                  color: c.brand,
                ),
                title: Text(
                  (f['kind']?.toString() ?? 'file').toUpperCase(),
                  style: TextStyle(color: c.text),
                ),
                subtitle: Text(
                  (f['name'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                onTap: _downloading
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _download(
                          f['url']!.toString(),
                          name: f['name']?.toString(),
                        );
                      },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final role = ref.watch(authStoreProvider).user?.role;
    final canDelete = role == 'SUPER_ADMIN' || role == 'ADMIN';
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Recordings'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: BestieSpinner());
          }
          if (snapshot.hasError) {
            return BestieEmptyState(
              icon: Icons.error_outline_rounded,
              iconColor: c.danger,
              title: 'Could not load recordings',
              description: formatApiError(snapshot.error!),
            );
          }
          final items = ((snapshot.data?['items'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          if (items.isEmpty) {
            return const BestieEmptyState(
              icon: Icons.fiber_manual_record_outlined,
              title: 'No recordings yet',
              description:
                  'SFU calls are recorded automatically. Uploaded call, meeting, and telecaller recordings also appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
              itemBuilder: (context, index) {
                final item = items[index];
                final source = (item['source'] ?? 'CALL').toString();
                final people = ((item['participants'] as List?) ?? const [])
                    .map((e) => e.toString())
                    .where((e) => e.isNotEmpty)
                    .join(', ');
                final files = _filesOf(item);
                final label = _sourceLabel(source);
                final subtitle = people.isEmpty
                    ? '$label · ${files.length} file${files.length == 1 ? '' : 's'}'
                    : '$label · $people';
                return ListTile(
                  leading: Icon(_sourceIcon(source), color: c.brand),
                  title: Text(
                    (item['title'] ?? 'Recording').toString(),
                    style: TextStyle(
                        color: c.text, fontWeight: BestieTokens.fwSemibold),
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textMuted),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Download recording',
                        onPressed: _downloading || files.isEmpty
                            ? null
                            : () => _openFilesSheet(item),
                        icon: _downloading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.brand,
                                ),
                              )
                            : const Icon(Icons.download_rounded),
                      ),
                      if (canDelete)
                        IconButton(
                          tooltip: 'Delete recording',
                          onPressed: () => _delete(item),
                          color: c.danger,
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                    ],
                  ),
                  onTap: _downloading || files.isEmpty
                      ? null
                      : () => _openFilesSheet(item),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
