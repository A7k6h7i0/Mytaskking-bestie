import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state.dart';

class DeletedChatsScreen extends ConsumerStatefulWidget {
  const DeletedChatsScreen({super.key});

  @override
  ConsumerState<DeletedChatsScreen> createState() => _DeletedChatsScreenState();
}

class _DeletedChatsScreenState extends ConsumerState<DeletedChatsScreen> {
  String _scope = 'org'; // 'org' or 'platform'
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final user = ref.read(authStoreProvider).user;
    final isPlatformAdmin = user?.isPlatformSuperAdmin == true;

    _future = ref.read(apiProvider).listDeletedMessages(
          page: 1,
          pageSize: 100,
          tenantId: isPlatformAdmin && _scope == 'org' ? 'default' : null,
        );
  }

  Future<void> _refresh() async {
    setState(() {
      _loadData();
    });
    await _future;
  }

  Future<void> _openAttachment(String url) async {
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
        bestieToast(context, 'Could not open attachment',
            kind: BestieToastKind.error);
      }
    }
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return '—';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final year = dt.year;
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$year-$month-$day $hour:$minute';
    } catch (_) {
      return isoString;
    }
  }

  String _receiverLabel({
    required Map<String, dynamic> author,
    required Map<String, dynamic> channel,
  }) {
    final members = ((channel['members'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final authorId = author['id']?.toString();
    final receivers = members
        .map((m) => (m['user'] as Map?)?.cast<String, dynamic>())
        .whereType<Map<String, dynamic>>()
        .where((u) => u['id']?.toString() != authorId)
        .map((u) => (u['name'] ?? u['userId'] ?? 'Unknown').toString())
        .where((name) => name.trim().isNotEmpty)
        .toList();

    if (receivers.isEmpty) {
      return (channel['name'] ?? 'Unknown').toString();
    }
    if (receivers.length <= 2) return receivers.join(', ');
    return '${receivers.take(2).join(', ')} +${receivers.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final isPlatformAdmin = user?.isPlatformSuperAdmin == true;

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Deleted chats'),
      ),
      body: Column(
        children: [
          if (isPlatformAdmin)
            Container(
              color: c.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_scope != 'org') {
                          setState(() {
                            _scope = 'org';
                            _loadData();
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _scope == 'org'
                              ? c.brand.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(BestieTokens.rSm),
                          border: Border.all(
                            color: _scope == 'org' ? c.brand : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'My Organisation',
                            style: TextStyle(
                              color: _scope == 'org' ? c.brand : c.textSoft,
                              fontWeight: _scope == 'org' ? BestieTokens.fwBold : BestieTokens.fwRegular,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_scope != 'platform') {
                          setState(() {
                            _scope = 'platform';
                            _loadData();
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _scope == 'platform'
                              ? c.brand.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(BestieTokens.rSm),
                          border: Border.all(
                            color: _scope == 'platform' ? c.brand : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.apartment_rounded,
                                size: 14,
                                color: _scope == 'platform' ? c.brand : c.textSoft,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'All Organisations',
                                style: TextStyle(
                                  color: _scope == 'platform' ? c.brand : c.textSoft,
                                  fontWeight: _scope == 'platform' ? BestieTokens.fwBold : BestieTokens.fwRegular,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: BestieSpinner());
                }
                if (snapshot.hasError) {
                  return BestieEmptyState(
                    icon: Icons.error_outline_rounded,
                    iconColor: c.danger,
                    title: 'Could not load deleted chats',
                    description: formatApiError(snapshot.error!),
                  );
                }

                final items = ((snapshot.data?['items'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>();

                if (items.isEmpty) {
                  return const BestieEmptyState(
                    icon: Icons.delete_outline_rounded,
                    title: 'No deleted messages found',
                    description: 'All employee conversations are fully intact.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(height: 24, color: c.border, thickness: 1),
                    itemBuilder: (context, index) {
                      final m = items[index];
                      final author = (m['author'] as Map?)?.cast<String, dynamic>() ?? const {};
                      final channel = (m['channel'] as Map?)?.cast<String, dynamic>() ?? const {};
                      final attachments = ((m['attachments'] as List?) ?? const [])
                          .cast<Map<String, dynamic>>();

                      final authorName = (author['name'] ?? 'System').toString();
                      final authorAvatar = author['avatarUrl']?.toString();
                      final authorId = (author['userId'] ?? '').toString();
                      final channelName = (channel['name'] ?? 'Channel (${channel['kind'] ?? 'DM'})').toString();
                      final receiverName = _receiverLabel(author: author, channel: channel);
                      final tenantId = channel['tenantId']?.toString();

                      final body = m['body']?.toString();
                      final createdAt = m['createdAt']?.toString();
                      final deletedAt = m['deletedAt']?.toString();

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BestieAvatar(
                              name: authorName,
                              imageUrl: authorAvatar,
                              isClient: author['isClient'] == true,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Sender: $authorName',
                                        style: TextStyle(
                                          color: c.text,
                                          fontWeight: BestieTokens.fwBold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (authorId.isNotEmpty)
                                        _MetaChip(
                                          label: authorId,
                                          background: c.surface3,
                                          color: c.textMuted,
                                        ),
                                      _MetaChip(
                                        label: channelName,
                                        background: c.surface2,
                                        color: c.textSoft,
                                      ),
                                      if (isPlatformAdmin && _scope == 'platform' && tenantId != null)
                                        _MetaChip(
                                          label: tenantId == 'default' ? 'MyTaskKing' : tenantId,
                                          background: c.brand.withValues(alpha: 0.12),
                                          color: c.brand,
                                          bold: true,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Receiver: $receiverName',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.textSoft,
                                      fontWeight: BestieTokens.fwSemibold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    body ?? 'Empty message body or deleted attachment-only message',
                                    style: TextStyle(
                                      color: body != null ? c.text : c.textMuted,
                                      fontStyle: body != null ? FontStyle.normal : FontStyle.italic,
                                      fontSize: 14,
                                      height: 1.35,
                                    ),
                                  ),
                                  if (attachments.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: attachments.map((file) {
                                        final name = (file['originalName'] ?? 'Attachment').toString();
                                        final url = (file['url'] ?? '').toString();
                                        final mime = file['mimeType']?.toString();
                                        final isImage = mime?.startsWith('image/') == true;

                                        return InkWell(
                                          onTap: url.isNotEmpty ? () => _openAttachment(url) : null,
                                          borderRadius: BorderRadius.circular(BestieTokens.rSm),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: c.surface2,
                                              border: Border.all(color: c.border),
                                              borderRadius: BorderRadius.circular(BestieTokens.rSm),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isImage ? Icons.image_outlined : Icons.description_outlined,
                                                  size: 14,
                                                  color: c.textSoft,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: c.textSoft,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    children: [
                                      _IconText(
                                        icon: Icons.calendar_today_outlined,
                                        label: 'Sent: ${_formatDateTime(createdAt)}',
                                        color: c.textMuted,
                                      ),
                                      _IconText(
                                        icon: Icons.delete_outline_rounded,
                                        label: 'Deleted: ${_formatDateTime(deletedAt)}',
                                        color: c.danger,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.background,
    required this.color,
    this.bold = false,
  });

  final String label;
  final Color background;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: bold ? BestieTokens.fwBold : BestieTokens.fwRegular,
        ),
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 11),
        ),
      ],
    );
  }
}
