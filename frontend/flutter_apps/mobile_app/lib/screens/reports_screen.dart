import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final reports = ref.watch(taskReportsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: const Text('Reports'),
          backgroundColor: c.surface,
          foregroundColor: c.text,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My reports'),
              Tab(text: 'Reported to me'),
            ],
          ),
        ),
        body: reports.when(
          loading: () => const BestieSkeletonList(
              itemCount: 4, shape: BestieSkeletonShape.card),
          error: (e, _) => BestieEmptyState(
            icon: Icons.error_outline,
            iconColor: c.danger,
            title: 'Could not load reports',
            description: formatApiError(e),
          ),
          data: (data) {
            final mine = (data['mine'] as List? ?? const [])
                .cast<Map<String, dynamic>>();
            final received = (data['received'] as List? ?? const [])
                .cast<Map<String, dynamic>>();
            return TabBarView(
              children: [
                _ReportList(items: mine, mode: _ReportMode.mine),
                _ReportList(items: received, mode: _ReportMode.received),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _ReportMode { mine, received }

class _ReportList extends ConsumerWidget {
  final List<Map<String, dynamic>> items;
  final _ReportMode mode;
  const _ReportList({required this.items, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return BestieEmptyState(
        icon: Icons.article_outlined,
        title: mode == _ReportMode.mine
            ? 'No reports yet'
            : 'Nothing reported to you',
        description: mode == _ReportMode.mine
            ? 'Complete a task and submit a report to see it here.'
            : 'When someone reports a completed task to you, it appears here.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(taskReportsProvider.future),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
        itemBuilder: (_, i) => _ReportCard(report: items[i], mode: mode),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: items.length,
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  final Map<String, dynamic> report;
  final _ReportMode mode;
  const _ReportCard({required this.report, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final task = (report['task'] as Map?)?.cast<String, dynamic>() ?? const {};
    final author =
        (report['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    final recipients = (report['recipients'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final me = ref.read(authStoreProvider).user;
    final myRecipient = recipients.firstWhere(
      (r) => r['userId'] == me?.id,
      orElse: () => const {},
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          BestieBadge(
            tone: _priorityTone(task['priority']),
            dot: true,
            child: Text('${task['priority'] ?? 'TASK'}'),
          ),
          const Spacer(),
          Text(_fmt(report['createdAt']),
              style: TextStyle(color: c.textMuted, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Text(
          task['title']?.toString() ?? 'Task report',
          style: TextStyle(
              fontSize: 17, fontWeight: BestieTokens.fwBold, color: c.text),
        ),
        const SizedBox(height: 12),
        _PersonLine(
            user: author,
            subtitle:
                'Completion report - ${report['wordCount'] ?? 0}/120 words'),
        const SizedBox(height: 8),
        Text(report['body']?.toString() ?? '',
            style: TextStyle(color: c.text, height: 1.35)),
        const SizedBox(height: 12),
        ...recipients.map((r) {
          final user = (r['user'] as Map?)?.cast<String, dynamic>() ?? const {};
          final response = r['responseBody']?.toString();
          return Container(
            margin: const EdgeInsets.only(top: 8, left: 22),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(BestieTokens.rSm),
              border: Border.all(color: c.border),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PersonLine(
                user: user,
                subtitle: response == null || response.isEmpty
                    ? 'No response yet'
                    : 'Responded ${_fmt(r['responseUpdatedAt'] ?? r['respondedAt'])}',
              ),
              if (response != null && response.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(response, style: TextStyle(color: c.text)),
              ],
            ]),
          );
        }),
        const SizedBox(height: 12),
        if (mode == _ReportMode.mine)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit report'),
              onPressed: () => _editReport(context, ref, report),
            ),
          )
        else if (myRecipient.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: const Icon(Icons.reply_rounded, size: 16),
              label: Text((myRecipient['responseBody'] ?? '').toString().isEmpty
                  ? 'Send response'
                  : 'Edit response'),
              onPressed: () => _respond(context, ref, report, myRecipient),
            ),
          ),
      ]),
    );
  }

  Future<void> _editReport(
      BuildContext context, WidgetRef ref, Map<String, dynamic> report) async {
    final result = await bestieBottomSheet<_ReportEditResult>(
      context,
      title: 'Edit report',
      builder: (_) => _ReportEditSheet(ref: ref, report: report),
    );
    if (result == null) return;
    try {
      await ref.read(apiProvider).updateTaskReport(
            report['id'].toString(),
            body: result.body,
            recipientIds: result.recipientIds,
          );
      ref.invalidate(taskReportsProvider);
      if (context.mounted) {
        bestieToast(context, 'Report updated', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        bestieToast(context, 'Could not update report',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> report,
    Map<String, dynamic> recipient,
  ) async {
    final result = await bestieBottomSheet<String>(
      context,
      title: (recipient['responseBody'] ?? '').toString().isEmpty
          ? 'Send response'
          : 'Edit response',
      builder: (_) => _ReportResponseSheet(
          initialBody: recipient['responseBody']?.toString() ?? ''),
    );
    if (result == null) return;
    try {
      await ref
          .read(apiProvider)
          .respondToTaskReport(report['id'].toString(), body: result);
      ref.invalidate(taskReportsProvider);
      if (context.mounted) {
        bestieToast(context, 'Response saved', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        bestieToast(context, 'Could not save response',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }
}

class _PersonLine extends StatelessWidget {
  final Map<String, dynamic> user;
  final String subtitle;
  const _PersonLine({required this.user, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Row(children: [
      BestieAvatar(
        name: user['name'] ?? '?',
        imageUrl: user['avatarUrl'],
        isClient: user['isClient'] ?? false,
        size: 28,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BestieUserName(
            name: user['name'] ?? '',
            isClient: user['isClient'] ?? false,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(subtitle, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ]),
      ),
    ]);
  }
}

class _ReportEditResult {
  final String body;
  final List<String> recipientIds;
  const _ReportEditResult({required this.body, required this.recipientIds});
}

class _ReportEditSheet extends StatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic> report;
  const _ReportEditSheet({required this.ref, required this.report});

  @override
  State<_ReportEditSheet> createState() => _ReportEditSheetState();
}

class _ReportEditSheetState extends State<_ReportEditSheet> {
  late final TextEditingController _body;
  final _peopleQuery = TextEditingController();
  late final List<Map<String, dynamic>> _picked;
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    _body =
        TextEditingController(text: widget.report['body']?.toString() ?? '');
    _picked = ((widget.report['recipients'] as List? ?? const [])
        .map((r) => (r as Map)['user'])
        .whereType<Map>()
        .map((u) => u.cast<String, dynamic>())
        .toList());
    _loadPeople();
  }

  @override
  void dispose() {
    _body.dispose();
    _peopleQuery.dispose();
    super.dispose();
  }

  int get _words =>
      _body.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  Future<void> _loadPeople([String? q]) async {
    try {
      final items = await widget.ref.read(apiProvider).listEmployees(q: q);
      if (mounted) setState(() => _people = items);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final pickedIds = _picked.map((p) => p['id']).toSet();
    final candidates =
        _people.where((p) => !pickedIds.contains(p['id'])).take(8).toList();
    final canSave =
        _body.text.trim().isNotEmpty && _words <= 120 && _picked.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: ListView(shrinkWrap: true, children: [
        const Text('Report (120 words max)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: _body,
          minLines: 4,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text('$_words/120 words',
              style: TextStyle(
                  color: _words > 120 ? c.danger : c.textMuted, fontSize: 12)),
        ),
        const SizedBox(height: 12),
        const Text('Report to', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(
          spacing: 6,
          children: _picked
              .map((p) => InputChip(
                    label: Text(p['name'] ?? ''),
                    onDeleted: () => setState(
                        () => _picked.removeWhere((x) => x['id'] == p['id'])),
                  ))
              .toList(),
        ),
        BestieTextField(
          label: 'Search people',
          controller: _peopleQuery,
          icon: Icons.search,
          onChanged: (v) => _loadPeople(v),
        ),
        ...candidates.map((p) => ListTile(
              dense: true,
              leading: BestieAvatar(
                  name: p['name'] ?? '?',
                  imageUrl: p['avatarUrl'],
                  isClient: p['isClient'] ?? false,
                  size: 28),
              title: BestieUserName(
                  name: p['name'] ?? '', isClient: p['isClient'] ?? false),
              trailing: const Icon(Icons.add),
              onTap: () => setState(() {
                _picked.add(p);
                _peopleQuery.clear();
              }),
            )),
        const SizedBox(height: 14),
        BestiePrimaryButton(
          label: 'Save report',
          icon: Icons.save_outlined,
          onPressed: canSave
              ? () => Navigator.pop(
                    context,
                    _ReportEditResult(
                      body: _body.text.trim(),
                      recipientIds:
                          _picked.map((p) => p['id'] as String).toList(),
                    ),
                  )
              : null,
        ),
      ]),
    );
  }
}

class _ReportResponseSheet extends StatefulWidget {
  final String initialBody;
  const _ReportResponseSheet({required this.initialBody});

  @override
  State<_ReportResponseSheet> createState() => _ReportResponseSheetState();
}

class _ReportResponseSheetState extends State<_ReportResponseSheet> {
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    _body = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  int get _words =>
      _body.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final canSend = _body.text.trim().isNotEmpty && _words <= 120;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: ListView(shrinkWrap: true, children: [
        const Text('One-time response (editable)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: _body,
          minLines: 3,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              hintText: 'Send a simple response to this report...'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text('$_words/120 words',
              style: TextStyle(
                  color: _words > 120 ? c.danger : c.textMuted, fontSize: 12)),
        ),
        const SizedBox(height: 14),
        BestiePrimaryButton(
          label:
              widget.initialBody.isEmpty ? 'Send response' : 'Update response',
          icon: Icons.reply_rounded,
          onPressed:
              canSend ? () => Navigator.pop(context, _body.text.trim()) : null,
        ),
      ]),
    );
  }
}

BestieTone _priorityTone(dynamic priority) {
  switch (priority) {
    case 'URGENT':
      return BestieTone.danger;
    case 'HIGH':
      return BestieTone.warning;
    case 'MEDIUM':
      return BestieTone.info;
    default:
      return BestieTone.neutral;
  }
}

String _fmt(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, $h:$m';
}
