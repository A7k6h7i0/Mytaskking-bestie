import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state.dart';

class RecordingsScreen extends ConsumerStatefulWidget {
  const RecordingsScreen({super.key});

  @override
  ConsumerState<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends ConsumerState<RecordingsScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiProvider).listRecordings();
  }

  Future<void> _refresh() async {
    setState(() => _future = ref.read(apiProvider).listRecordings());
    await _future;
  }

  Future<void> _download(String url) async {
    var opened = false;
    try {
      final uri = Uri.tryParse(url);
      opened = uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      if (mounted) {
        bestieToast(context, 'Could not open recording',
            kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final title = (item['title'] ?? 'this recording').toString();
    final ok = await bestieConfirm(
      context,
      title: 'Delete recording?',
      description: 'This removes "$title" from the recordings list.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;

    try {
      await ref.read(apiProvider).deleteRecording(
            (item['source'] ?? '').toString(),
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

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final canDelete = ref.watch(authStoreProvider).user?.role == 'SUPER_ADMIN';
    return Scaffold(
      backgroundColor: c.bg,
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
                  'Start recording during a call or meeting. Saved recordings will appear here.',
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
                final url = item['recordingUrl']?.toString() ?? '';
                return ListTile(
                  leading: Icon(
                    source == 'MEETING'
                        ? Icons.videocam_outlined
                        : Icons.phone_outlined,
                    color: c.brand,
                  ),
                  title: Text(
                    (item['title'] ?? 'Recording').toString(),
                    style: TextStyle(
                        color: c.text, fontWeight: BestieTokens.fwSemibold),
                  ),
                  subtitle: people.isEmpty
                      ? Text(source, style: TextStyle(color: c.textMuted))
                      : Text('$source · $people',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.textMuted)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Download recording',
                        onPressed: url.isEmpty ? null : () => _download(url),
                        icon: const Icon(Icons.download_rounded),
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
                  onTap: url.isEmpty ? null : () => _download(url),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
