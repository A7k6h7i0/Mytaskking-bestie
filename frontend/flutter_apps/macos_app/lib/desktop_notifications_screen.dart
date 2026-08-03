import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/state.dart';

enum _NotifFilter { all, unread, tasks, meetings, calls, system }

/// Windows notifications — matches the Notifications UI HTML.
/// Data: `GET /notifications` (paginated), live via [notificationsProvider].
class DesktopNotificationsScreen extends ConsumerStatefulWidget {
  const DesktopNotificationsScreen({super.key});

  @override
  ConsumerState<DesktopNotificationsScreen> createState() =>
      _DesktopNotificationsScreenState();
}

class _DesktopNotificationsScreenState
    extends ConsumerState<DesktopNotificationsScreen> {
  static const _pageSize = 30;

  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = [];

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  int _total = 0;
  int _unread = 0;
  Map<_NotifFilter, int> _filterCounts = {};

  _NotifFilter _filter = _NotifFilter.all;
  bool _hideRead = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadCounts(), _refresh()]);
  }

  Future<void> _loadCounts() async {
    try {
      final res = await ref.read(apiProvider).get(
            '/notifications',
            query: {'page': 1, 'pageSize': 100},
          );
      final batch =
          ((res['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _total = (res['total'] as num?)?.toInt() ?? batch.length;
        _unread = (res['unread'] as num?)?.toInt() ?? 0;
        _filterCounts = _computeFilterCounts(batch, _total, _unread);
      });
    } catch (_) {}
  }

  Map<_NotifFilter, int> _computeFilterCounts(
    List<Map<String, dynamic>> sample,
    int total,
    int unread,
  ) {
    int catCount(String cat) =>
        sample.where((n) => _notifCategory(n) == cat).length;

    final tasks = catCount('tasks');
    final meetings = catCount('meetings');
    final calls = catCount('calls');
    final system = catCount('system');

    return {
      _NotifFilter.all: total,
      _NotifFilter.unread: unread,
      _NotifFilter.tasks: tasks,
      _NotifFilter.meetings: meetings,
      _NotifFilter.calls: calls,
      _NotifFilter.system: system,
    };
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.offset;
    if (remaining < 240 && _hasMore && !_loading) {
      unawaited(_loadMore());
    }
  }

  Future<void> _refresh() async {
    _page = 1;
    _hasMore = true;
    _items.clear();
    await _loadMore();
    unawaited(_loadCounts());
  }

  Future<void> _loadMore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).get(
            '/notifications',
            query: {'page': _page, 'pageSize': _pageSize},
          );
      final batch =
          ((res['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _total = (res['total'] as num?)?.toInt() ?? _total;
        _unread = (res['unread'] as num?)?.toInt() ?? _unread;
        _items.addAll(batch);
        _page++;
        _hasMore = batch.length >= _pageSize;
        _loading = false;
        _filterCounts = _computeFilterCounts(_items, _total, _unread);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(apiProvider).markAllNotificationsRead();
      ref.invalidate(notificationsProvider);
      await _refresh();
      if (mounted) {
        bestieToast(context, 'All notifications marked read',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not update',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _onTapNotification(Map<String, dynamic> n) async {
    final id = n['id']?.toString();
    if (id != null && n['readAt'] == null) {
      try {
        await ref.read(apiProvider).markNotificationRead(id);
        ref.invalidate(notificationsProvider);
        setState(() {
          n['readAt'] = DateTime.now().toUtc().toIso8601String();
          _unread = (_unread - 1).clamp(0, _total);
          _filterCounts = _computeFilterCounts(_items, _total, _unread);
        });
      } catch (_) {}
    }
    final route = _routeForNotification(n);
    if (route != null && mounted) context.push(route);
  }

  void _toggleTheme() {
    final cur = ref.read(themeModeProvider);
    ref.read(themeModeProvider.notifier).state =
        cur == core.ThemeMode.dark ? core.ThemeMode.light : core.ThemeMode.dark;
  }

  List<Map<String, dynamic>> get _visibleItems {
    return _items.where((n) {
      if (_hideRead && n['readAt'] != null) return false;
      return _matchesFilter(n, _filter);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationsProvider, (prev, next) {
      if (next.hasValue && prev?.valueOrNull != next.valueOrNull) {
        unawaited(_refresh());
      }
    });

    final visible = _visibleItems;
    final sections = _groupBySection(visible);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ColoredBox(
      color: isDark ? const Color(0xFF111827) : _NotifUi.bgPage,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              onToggleTheme: _toggleTheme,
              onMarkAllRead: _markAllRead,
              isDark: isDark,
            ),
            const SizedBox(height: 24),
            _FiltersRow(
              filter: _filter,
              counts: _filterCounts,
              onFilter: (f) => setState(() => _filter = f),
              onOpenFilter: () => _openFilterSheet(),
              isDark: isDark,
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _error != null && _items.isEmpty
                  ? BestieEmptyState(
                      icon: Icons.error_outline_rounded,
                      iconColor: _NotifUi.statusRed,
                      title: 'Could not load notifications',
                      description: formatApiError(_error!),
                    )
                  : _loading && _items.isEmpty
                      ? const Center(child: BestieSpinner())
                      : visible.isEmpty
                          ? BestieEmptyState(
                              icon: Icons.notifications_none_outlined,
                              title: 'You\'re all caught up',
                              description: _filter == _NotifFilter.unread
                                  ? 'No unread notifications.'
                                  : 'New notifications will appear here in realtime.',
                            )
                          : CustomScrollView(
                              controller: _scroll,
                              slivers: [
                                for (final section in sections.entries) ...[
                                  SliverToBoxAdapter(
                                    child: _SectionHeader(
                                      title: section.key,
                                      showLive: section.key == 'Today',
                                    ),
                                  ),
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (ctx, i) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _NotificationCard(
                                          item: section.value[i],
                                          onTap: () =>
                                              _onTapNotification(section.value[i]),
                                          isDark: isDark,
                                        ),
                                      ),
                                      childCount: section.value.length,
                                    ),
                                  ),
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 12),
                                  ),
                                ],
                                if (!_hasMore && visible.isNotEmpty)
                                  const SliverToBoxAdapter(
                                    child: _EndFooter(),
                                  ),
                                if (_loading)
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 16),
                                      child: Center(child: BestieSpinner()),
                                    ),
                                  ),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    var hideRead = _hideRead;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Filter',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Hide read notifications'),
                      value: hideRead,
                      onChanged: (v) => setSt(() => hideRead = v),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() => _hideRead = hideRead);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _NotifUi {
  static const bgPage = Color(0xFFF9FAFB);
  static const bgSurface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);
  static const borderLight = Color(0xFFF3F4F6);
  static const border = Color(0xFFE5E7EB);
  static const primaryBlue = Color(0xFF3B82F6);
  static const pillCountBg = Color(0xFFF3F4F6);
  static const pillCountText = Color(0xFF6B7280);
  static const pillActiveCountBg = Color(0xFF60A5FA);
  static const statusGreen = Color(0xFF10B981);
  static const statusRed = Color(0xFFEF4444);
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onToggleTheme,
    required this.onMarkAllRead,
    required this.isDark,
  });

  final VoidCallback onToggleTheme;
  final VoidCallback onMarkAllRead;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Notifications',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.02 * 24,
            color: isDark ? Colors.white : _NotifUi.textPrimary,
          ),
        ),
        const Spacer(),
        Material(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onToggleTheme,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 16,
                color: isDark ? Colors.white : const Color(0xFF374151),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onMarkAllRead,
          style: OutlinedButton.styleFrom(
            foregroundColor:
                isDark ? Colors.white : const Color(0xFF374151),
            backgroundColor:
                isDark ? const Color(0xFF1F2937) : _NotifUi.bgSurface,
            side: BorderSide(
              color: isDark ? const Color(0xFF374151) : _NotifUi.border,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          icon: const Icon(Icons.check, size: 16, color: _NotifUi.primaryBlue),
          label: const Text(
            'Mark all as read',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({
    required this.filter,
    required this.counts,
    required this.onFilter,
    required this.onOpenFilter,
    required this.isDark,
  });

  final _NotifFilter filter;
  final Map<_NotifFilter, int> counts;
  final ValueChanged<_NotifFilter> onFilter;
  final VoidCallback onOpenFilter;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const pills = [
      (_NotifFilter.all, 'All'),
      (_NotifFilter.unread, 'Unread'),
      (_NotifFilter.tasks, 'Tasks'),
      (_NotifFilter.meetings, 'Meetings'),
      (_NotifFilter.calls, 'Calls'),
      (_NotifFilter.system, 'System'),
    ];

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (f, label) in pills)
                _FilterPill(
                  label: label,
                  count: counts[f] ?? 0,
                  active: filter == f,
                  onTap: () => onFilter(f),
                  isDark: isDark,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onOpenFilter,
          style: OutlinedButton.styleFrom(
            foregroundColor:
                isDark ? Colors.white : const Color(0xFF374151),
            backgroundColor:
                isDark ? const Color(0xFF1F2937) : _NotifUi.bgSurface,
            side: BorderSide(
              color: isDark ? const Color(0xFF374151) : _NotifUi.border,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          icon: Icon(Icons.filter_list_rounded,
              size: 14, color: isDark ? Colors.white70 : _NotifUi.textSecondary),
          label: const Text(
            'Filter',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? _NotifUi.primaryBlue
          : (isDark ? const Color(0xFF1F2937) : _NotifUi.bgSurface),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? _NotifUi.primaryBlue
                  : (isDark ? const Color(0xFF374151) : _NotifUi.border),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x05000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: active
                      ? Colors.white
                      : (isDark ? Colors.white70 : const Color(0xFF4B5563)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? _NotifUi.pillActiveCountBg
                      : (isDark
                          ? const Color(0xFF374151)
                          : _NotifUi.pillCountBg),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? Colors.white
                        : (isDark
                            ? Colors.white60
                            : _NotifUi.pillCountText),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.showLive});

  final String title;
  final bool showLive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _NotifUi.textPrimary,
            ),
          ),
          const Spacer(),
          if (showLive)
            const Row(
              children: [
                _LiveDot(),
                SizedBox(width: 6),
                Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _NotifUi.statusGreen,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: _NotifUi.statusGreen,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
    required this.isDark,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(item);
    final created = DateTime.tryParse('${item['createdAt']}')?.toLocal();
    final unread = item['readAt'] == null;
    final data = (item['data'] as Map?)?.cast<String, dynamic>();
    final taskId = data?['taskId']?.toString();

    return Material(
      color: isDark ? const Color(0xFF1F2937) : _NotifUi.bgSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF374151) : _NotifUi.borderLight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x05000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: visual.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(visual.icon, size: 18, color: visual.fg),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['title'] ?? 'Notification'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : _NotifUi.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Subtitle(
                      body: '${item['body'] ?? ''}',
                      taskId: taskId,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(created),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : _NotifUi.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (unread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _NotifUi.primaryBlue,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(width: 8, height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({
    required this.body,
    this.taskId,
    required this.isDark,
  });

  final String body;
  final String? taskId;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (body.isEmpty) return const SizedBox.shrink();

    final parts = body.split(' • ');
    if (taskId != null && parts.isNotEmpty) {
      final linkText = parts.first.trim();
      final rest = parts.length > 1 ? parts.sublist(1).join(' • ') : null;
      return Text.rich(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        TextSpan(
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white60 : _NotifUi.textSecondary,
          ),
          children: [
            TextSpan(
              text: linkText,
              style: const TextStyle(decoration: TextDecoration.underline),
            ),
            if (rest != null) TextSpan(text: ' • $rest'),
          ],
        ),
      );
    }

    return Text(
      body,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white60 : _NotifUi.textSecondary,
      ),
    );
  }
}

class _EndFooter extends StatelessWidget {
  const _EndFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(right: 16),
              color: _NotifUi.border,
            ),
          ),
          const Text(
            'You\'ve reached the end',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _NotifUi.textTertiary,
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(left: 16),
              color: _NotifUi.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifVisual {
  const _NotifVisual(this.bg, this.fg, this.icon);
  final Color bg;
  final Color fg;
  final IconData icon;
}

_NotifVisual _visualFor(Map<String, dynamic> n) {
  final kind = (n['kind'] ?? '').toString().toUpperCase();
  final title = (n['title'] ?? '').toString().toLowerCase();

  if (kind == 'TASK' && title.contains('completed')) {
    return const _NotifVisual(
      Color(0xFFEFF6FF),
      Color(0xFF3B82F6),
      Icons.check_circle_outline,
    );
  }
  if (kind == 'TASK' &&
      (title.contains('overdue') ||
          title.contains('due') ||
          title.contains('still'))) {
    final palette = [
      (const Color(0xFFFEFCE8), const Color(0xFFEAB308)),
      (const Color(0xFFFEF2F2), const Color(0xFFEF4444)),
      (const Color(0xFFFAF5FF), const Color(0xFFA855F7)),
      (const Color(0xFFF0FDF4), const Color(0xFF22C55E)),
    ];
    final idx = (n['id']?.hashCode ?? 0).abs() % palette.length;
    return _NotifVisual(
      palette[idx].$1,
      palette[idx].$2,
      Icons.error_outline_rounded,
    );
  }
  if (kind == 'CALL') {
    return const _NotifVisual(
      Color(0xFFFEF2F2),
      Color(0xFFEF4444),
      Icons.call_outlined,
    );
  }
  if (_notifCategory(n) == 'meetings') {
    return const _NotifVisual(
      Color(0xFFFAF5FF),
      Color(0xFFA855F7),
      Icons.calendar_month_outlined,
    );
  }
  if (kind == 'SYSTEM' || kind == 'LEAD_FOLLOWUP') {
    return const _NotifVisual(
      Color(0xFFF0FDF4),
      Color(0xFF22C55E),
      Icons.campaign_outlined,
    );
  }
  if (kind == 'CHAT' || kind == 'MENTION') {
    return const _NotifVisual(
      Color(0xFFEFF6FF),
      Color(0xFF3B82F6),
      Icons.chat_bubble_outline,
    );
  }
  return const _NotifVisual(
    Color(0xFFEFF6FF),
    Color(0xFF3B82F6),
    Icons.notifications_outlined,
  );
}

String _notifCategory(Map<String, dynamic> n) {
  final kind = (n['kind'] ?? '').toString().toUpperCase();
  if (kind == 'TASK') return 'tasks';
  if (kind == 'CALL') return 'calls';
  if (kind == 'SYSTEM' || kind == 'LEAD_FOLLOWUP') return 'system';
  if (_isMeetingNotification(n)) return 'meetings';
  return 'other';
}

bool _isMeetingNotification(Map<String, dynamic> n) {
  final data = (n['data'] as Map?)?.cast<String, dynamic>();
  if (data?['meetingSlug'] != null || data?['eventId'] != null) return true;
  final blob =
      '${n['title'] ?? ''} ${n['body'] ?? ''}'.toLowerCase();
  return blob.contains('meeting') ||
      blob.contains('calendar') ||
      blob.contains('review');
}

bool _matchesFilter(Map<String, dynamic> n, _NotifFilter filter) {
  switch (filter) {
    case _NotifFilter.all:
      return true;
    case _NotifFilter.unread:
      return n['readAt'] == null;
    case _NotifFilter.tasks:
      return _notifCategory(n) == 'tasks';
    case _NotifFilter.meetings:
      return _notifCategory(n) == 'meetings';
    case _NotifFilter.calls:
      return _notifCategory(n) == 'calls';
    case _NotifFilter.system:
      return _notifCategory(n) == 'system';
  }
}

Map<String, List<Map<String, dynamic>>> _groupBySection(
  List<Map<String, dynamic>> items,
) {
  final out = <String, List<Map<String, dynamic>>>{};
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  for (final n in items) {
    final created = DateTime.tryParse('${n['createdAt']}')?.toLocal();
    final label = _sectionLabel(created, today);
    out.putIfAbsent(label, () => []).add(n);
  }
  return out;
}

String _sectionLabel(DateTime? dt, DateTime today) {
  if (dt == null) return 'Earlier';
  final date = DateTime(dt.year, dt.month, dt.day);
  if (date == today) return 'Today';
  if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _formatTime(DateTime? dt) {
  if (dt == null) return '';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String? _routeForNotification(Map<String, dynamic> n) {
  final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  final taskId = data['taskId']?.toString();
  if (taskId != null && taskId.isNotEmpty) return '/tasks/$taskId';

  final channelId = data['channelId']?.toString();
  if (channelId != null && channelId.isNotEmpty) return '/chat/$channelId';

  final callId = data['callId']?.toString();
  if (callId != null && callId.isNotEmpty) {
    final mode =
        data['mode']?.toString().toLowerCase() == 'voice' ? 'voice' : 'video';
    return '/call/$callId?mode=$mode';
  }

  final meetingSlug = data['meetingSlug']?.toString();
  if (meetingSlug != null && meetingSlug.isNotEmpty) {
    final mode =
        data['mode']?.toString().toLowerCase() == 'voice' ? 'voice' : 'video';
    return '/meeting/$meetingSlug?mode=$mode';
  }

  final eventId = data['eventId']?.toString();
  if (eventId != null && eventId.isNotEmpty) return '/calendar';

  if ((n['kind'] ?? '').toString().toUpperCase() == 'LEAD_FOLLOWUP') {
    return '/telecaller';
  }

  return null;
}
