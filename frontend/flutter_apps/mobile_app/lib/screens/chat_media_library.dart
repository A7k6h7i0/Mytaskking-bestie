import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

final _urlPattern = RegExp(
  r'(https?://[^\s<>"\)]+)',
  caseSensitive: false,
);

String? chatFirstUrl(String text) {
  if (text.isEmpty) return null;
  return _urlPattern.firstMatch(text)?.group(1);
}

/// Browse shared media, links, and documents in a channel (WhatsApp-style).
void showChatMediaLibrarySheet(
  BuildContext context, {
  required List<Map<String, dynamic>> messages,
  required String channelName,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChatMediaLibrarySheet(
      messages: messages,
      channelName: channelName,
    ),
  );
}

class _ChatMediaLibrarySheet extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String channelName;

  const _ChatMediaLibrarySheet({
    required this.messages,
    required this.channelName,
  });

  @override
  State<_ChatMediaLibrarySheet> createState() => _ChatMediaLibrarySheetState();
}

class _ChatMediaLibrarySheetState extends State<_ChatMediaLibrarySheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _mediaItems {
    final out = <Map<String, dynamic>>[];
    for (final m in widget.messages) {
      if (m['deletedAt'] != null) continue;
      final kind = (m['kind'] ?? '').toString();
      if (kind == 'IMAGE') {
        final attachments =
            (m['attachments'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];
        for (final a in attachments) {
          out.add({...a, '_messageId': m['id']});
        }
        continue;
      }
      if (kind == 'VOICE_NOTE') {
        final attachments =
            (m['attachments'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];
        for (final a in attachments) {
          out.add({...a, '_messageId': m['id'], '_voice': true});
        }
        continue;
      }
      final attachments =
          (m['attachments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final a in attachments) {
        final mime = (a['mimeType'] ?? '').toString();
        if (mime.startsWith('image/') || mime.startsWith('video/')) {
          out.add({...a, '_messageId': m['id']});
        }
      }
    }
    return out.reversed.toList();
  }

  List<(String url, String preview)> get _linkItems {
    final seen = <String>{};
    final out = <(String, String)>[];
    for (final m in widget.messages) {
      if (m['deletedAt'] != null) continue;
      final body = (m['body'] ?? '').toString();
      final url = chatFirstUrl(body);
      if (url != null && seen.add(url)) {
        out.add((url, body.length > 80 ? '${body.substring(0, 80)}…' : body));
      }
    }
    return out.reversed.toList();
  }

  List<Map<String, dynamic>> get _docItems {
    final out = <Map<String, dynamic>>[];
    for (final m in widget.messages) {
      if (m['deletedAt'] != null) continue;
      final attachments =
          (m['attachments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final a in attachments) {
        final mime = (a['mimeType'] ?? '').toString();
        if (mime.startsWith('image/') ||
            mime.startsWith('video/') ||
            mime.startsWith('audio/')) {
          continue;
        }
        out.add({...a, '_messageId': m['id']});
      }
    }
    return out.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(BestieTokens.rXl),
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.borderStrong,
              borderRadius: BorderRadius.circular(BestieTokens.rPill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Media, links and docs',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: BestieTokens.fwBold,
                      color: c.text,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: c.textMuted),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: c.brand,
            unselectedLabelColor: c.textMuted,
            indicatorColor: c.brand,
            tabs: [
              Tab(text: 'Media (${_mediaItems.length})'),
              Tab(text: 'Links (${_linkItems.length})'),
              Tab(text: 'Docs (${_docItems.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _MediaGrid(items: _mediaItems, colors: c),
                _LinksList(items: _linkItems, colors: c),
                _DocsList(items: _docItems, colors: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final BestieColors colors;

  const _MediaGrid({required this.items, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const BestieEmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No media yet',
        description: 'Photos and videos shared in this chat appear here.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final url = item['url']?.toString() ?? '';
        final isVoice = item['_voice'] == true;
        if (isVoice) {
          return Container(
            color: colors.surface2,
            child: Icon(Icons.mic_rounded, color: colors.brand),
          );
        }
        return GestureDetector(
          onTap: url.isEmpty
              ? null
              : () => showDialog<void>(
                    context: context,
                    builder: (dialogCtx) => Dialog(
                      backgroundColor: Colors.black,
                      insetPadding: EdgeInsets.zero,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          InteractiveViewer(
                            child: Image.network(url, fit: BoxFit.contain),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white),
                              onPressed: () => Navigator.pop(dialogCtx),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          child: url.isEmpty
              ? Container(color: colors.surface2)
              : Image.network(url, fit: BoxFit.cover),
        );
      },
    );
  }
}

class _LinksList extends StatelessWidget {
  final List<(String url, String preview)> items;
  final BestieColors colors;

  const _LinksList({required this.items, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const BestieEmptyState(
        icon: Icons.link_rounded,
        title: 'No links yet',
        description: 'Links shared in this chat appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(color: colors.border, height: 1),
      itemBuilder: (ctx, i) {
        final (url, preview) = items[i];
        return ListTile(
          leading: Icon(Icons.link_rounded, color: colors.brand),
          title: Text(url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.text, fontSize: 14)),
          subtitle: preview.isNotEmpty
              ? Text(preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted, fontSize: 12))
              : null,
          onTap: () => launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication),
        );
      },
    );
  }
}

class _DocsList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final BestieColors colors;

  const _DocsList({required this.items, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const BestieEmptyState(
        icon: Icons.description_outlined,
        title: 'No documents yet',
        description: 'Files shared in this chat appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(color: colors.border, height: 1),
      itemBuilder: (ctx, i) {
        final item = items[i];
        final name = (item['originalName'] ?? 'Document').toString();
        final url = item['url']?.toString();
        final mime = (item['mimeType'] ?? '').toString();
        final icon = mime.contains('pdf')
            ? Icons.picture_as_pdf_rounded
            : Icons.description_rounded;
        return ListTile(
          leading: Icon(icon, color: colors.brand),
          title: Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.text)),
          onTap: url == null || url.isEmpty
              ? null
              : () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
        );
      },
    );
  }
}
