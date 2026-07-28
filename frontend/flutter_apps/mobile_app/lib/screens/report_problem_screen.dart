import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Settings → Report a problem: submit issue + check status by reference number.
class ReportProblemScreen extends ConsumerStatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  ConsumerState<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends ConsumerState<ReportProblemScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _issueTypes = const [];
  List<Map<String, dynamic>> _myTickets = const [];
  String? _selectedIssueType;
  String? _selectedTicketNumber;
  final _descriptionCtrl = TextEditingController();
  bool _loadingMeta = true;
  bool _submitting = false;
  bool _checking = false;
  Map<String, dynamic>? _checkedTicket;
  String? _createdTicketNumber;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadMeta();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final api = ref.read(apiProvider);
      final meta = await api.supportTicketMeta();
      final mine = await api.listMySupportTickets();
      if (!mounted) return;
      setState(() {
        _issueTypes =
            List<Map<String, dynamic>>.from(meta['issueTypes'] ?? const []);
        _selectedIssueType = _issueTypes.isNotEmpty
            ? _issueTypes.first['value']?.toString()
            : null;
        _myTickets = mine;
        _selectedTicketNumber = _myTickets.isNotEmpty
            ? _myTickets.first['ticketNumber']?.toString()
            : null;
        _loadingMeta = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMeta = false);
      bestieToast(context, 'Could not load report settings',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<void> _copyReference(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    bestieToast(context, 'Reference number copied',
        kind: BestieToastKind.success);
  }

  Future<void> _submit() async {
    final issueType = _selectedIssueType;
    final description = _descriptionCtrl.text.trim();
    if (issueType == null || description.length < 10) {
      bestieToast(context, 'Describe the problem (at least 10 characters)',
          kind: BestieToastKind.warning);
      return;
    }
    setState(() => _submitting = true);
    try {
      final ticket = await ref.read(apiProvider).createSupportTicket(
            issueType: issueType,
            description: description,
          );
      if (!mounted) return;
      final refNo = ticket['ticketNumber']?.toString();
      setState(() {
        _createdTicketNumber = refNo;
        _descriptionCtrl.clear();
      });
      await _loadMeta();
      if (refNo != null) {
        setState(() => _selectedTicketNumber = refNo);
      }
      bestieToast(
        context,
        'Issue submitted',
        body: 'Reference: $refNo',
        kind: BestieToastKind.success,
      );
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not submit issue',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _checkStatus() async {
    final ticketNumber = _selectedTicketNumber?.trim() ?? '';
    if (ticketNumber.length < 6) {
      bestieToast(context, 'Select a reference number',
          kind: BestieToastKind.warning);
      return;
    }
    setState(() {
      _checking = true;
      _checkedTicket = null;
    });
    try {
      final ticket = await ref.read(apiProvider).checkSupportTicketStatus(
            ticketNumber: ticketNumber,
          );
      if (!mounted) return;
      setState(() => _checkedTicket = ticket);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not load issue',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final canPop = context.canPop();
    final showAssignee =
        ref.watch(authStoreProvider).user?.isPlatformSuperAdmin ?? false;

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        foregroundColor: c.textMuted,
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text('Report a problem'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Report'),
            Tab(text: 'Check problem'),
          ],
        ),
      ),
      body: _loadingMeta
          ? const Center(child: BestieSpinner())
          : TabBarView(
              controller: _tabs,
              children: [
                _ReportTab(
                  colors: c,
                  issueTypes: _issueTypes,
                  myTickets: _myTickets,
                  selectedIssueType: _selectedIssueType,
                  descriptionCtrl: _descriptionCtrl,
                  submitting: _submitting,
                  createdTicketNumber: _createdTicketNumber,
                  onIssueTypeChanged: (v) =>
                      setState(() => _selectedIssueType = v),
                  onSubmit: _submit,
                  onCopy: _copyReference,
                ),
                _CheckStatusTab(
                  colors: c,
                  myTickets: _myTickets,
                  selectedTicketNumber: _selectedTicketNumber,
                  checking: _checking,
                  ticket: _checkedTicket,
                  showAssignee: showAssignee,
                  onTicketChanged: (v) =>
                      setState(() => _selectedTicketNumber = v),
                  onCheck: _checkStatus,
                  onCopy: _copyReference,
                ),
              ],
            ),
    );
  }
}

class _ReportTab extends StatelessWidget {
  final BestieColors colors;
  final List<Map<String, dynamic>> issueTypes;
  final List<Map<String, dynamic>> myTickets;
  final String? selectedIssueType;
  final TextEditingController descriptionCtrl;
  final bool submitting;
  final String? createdTicketNumber;
  final ValueChanged<String?> onIssueTypeChanged;
  final VoidCallback onSubmit;
  final Future<void> Function(String) onCopy;

  const _ReportTab({
    required this.colors,
    required this.issueTypes,
    required this.myTickets,
    required this.selectedIssueType,
    required this.descriptionCtrl,
    required this.submitting,
    required this.createdTicketNumber,
    required this.onIssueTypeChanged,
    required this.onSubmit,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Tell us what went wrong. A super admin will review and assign someone to help.',
          style: TextStyle(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: selectedIssueType,
          decoration: const InputDecoration(
            labelText: 'Issue type',
            border: OutlineInputBorder(),
          ),
          items: issueTypes
              .map(
                (t) => DropdownMenuItem<String>(
                  value: t['value']?.toString(),
                  child: Text(t['label']?.toString() ?? ''),
                ),
              )
              .toList(),
          onChanged: onIssueTypeChanged,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: descriptionCtrl,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'What happened? Include steps if you can.',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: submitting ? null : onSubmit,
          style: FilledButton.styleFrom(backgroundColor: colors.brand),
          child: submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit issue'),
        ),
        if (createdTicketNumber != null) ...[
          const SizedBox(height: 24),
          _ReferenceCard(
            colors: colors,
            referenceNumber: createdTicketNumber!,
            subtitle: 'Copy this reference number or find it in Check problem.',
            onCopy: onCopy,
          ),
        ],
        if (myTickets.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Your reference numbers', style: TextStyle(color: colors.textMuted)),
          const SizedBox(height: 8),
          ...myTickets.map(
            (t) => _ReferenceListTile(
              colors: colors,
              ticketNumber: t['ticketNumber']?.toString() ?? '',
              subtitle: [
                t['issueTypeLabel']?.toString(),
                t['statusLabel']?.toString(),
              ].whereType<String>().join(' · '),
              onCopy: onCopy,
            ),
          ),
        ],
      ],
    );
  }
}

class _CheckStatusTab extends StatelessWidget {
  final BestieColors colors;
  final List<Map<String, dynamic>> myTickets;
  final String? selectedTicketNumber;
  final bool checking;
  final Map<String, dynamic>? ticket;
  final bool showAssignee;
  final ValueChanged<String?> onTicketChanged;
  final VoidCallback onCheck;
  final Future<void> Function(String) onCopy;

  const _CheckStatusTab({
    required this.colors,
    required this.myTickets,
    required this.selectedTicketNumber,
    required this.checking,
    required this.ticket,
    required this.showAssignee,
    required this.onTicketChanged,
    required this.onCheck,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Pick one of your reported issues to check its status.',
          style: TextStyle(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        if (myTickets.isEmpty)
          Text(
            'No reported issues yet. Submit one on the Report tab.',
            style: TextStyle(color: colors.textMuted),
          )
        else
          DropdownButtonFormField<String>(
            value: selectedTicketNumber,
            decoration: const InputDecoration(
              labelText: 'Reference number',
              border: OutlineInputBorder(),
            ),
            items: myTickets
                .map(
                  (t) => DropdownMenuItem<String>(
                    value: t['ticketNumber']?.toString(),
                    child: Text(
                      '${t['ticketNumber']} · ${t['statusLabel'] ?? t['status']}',
                    ),
                  ),
                )
                .toList(),
            onChanged: onTicketChanged,
          ),
        if (selectedTicketNumber != null) ...[
          const SizedBox(height: 12),
          _ReferenceCard(
            colors: colors,
            referenceNumber: selectedTicketNumber!,
            subtitle: 'Copy reference number',
            onCopy: onCopy,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: checking || myTickets.isEmpty ? null : onCheck,
          style: FilledButton.styleFrom(backgroundColor: colors.brand),
          child: checking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Check problem'),
        ),
        if (ticket != null) ...[
          const SizedBox(height: 24),
          _TicketStatusCard(
            ticket: ticket!,
            colors: colors,
            showAssignee: showAssignee,
          ),
        ],
      ],
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  final BestieColors colors;
  final String referenceNumber;
  final String subtitle;
  final Future<void> Function(String) onCopy;

  const _ReferenceCard({
    required this.colors,
    required this.referenceNumber,
    required this.subtitle,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reference number', style: TextStyle(color: colors.textMuted)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    referenceNumber,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: () => onCopy(referenceNumber),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: colors.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _ReferenceListTile extends StatelessWidget {
  final BestieColors colors;
  final String ticketNumber;
  final String subtitle;
  final Future<void> Function(String) onCopy;

  const _ReferenceListTile({
    required this.colors,
    required this.ticketNumber,
    required this.subtitle,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(ticketNumber),
        subtitle: Text(subtitle),
        trailing: IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded),
          onPressed: () => onCopy(ticketNumber),
        ),
      ),
    );
  }
}

class _TicketStatusCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final BestieColors colors;
  final bool showAssignee;

  const _TicketStatusCard({
    required this.ticket,
    required this.colors,
    this.showAssignee = false,
  });

  BestieTone _toneForStatus(String status) {
    switch (status) {
      case 'RESOLVED':
      case 'CLOSED':
        return BestieTone.success;
      case 'IN_PROGRESS':
      case 'ASSIGNED':
        return BestieTone.info;
      default:
        return BestieTone.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ticket['status']?.toString() ?? 'OPEN';
    final statusLabel = ticket['statusLabel']?.toString() ?? status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticket['ticketNumber']?.toString() ?? '',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                BestieBadge(
                  tone: _toneForStatus(status),
                  child: Text(statusLabel),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Row(label: 'Type', value: ticket['issueTypeLabel']?.toString()),
            _Row(label: 'Reported', value: _formatDate(ticket['createdAt'])),
            if (showAssignee && ticket['assignee'] != null)
              _Row(
                label: 'Assigned to',
                value: (ticket['assignee'] as Map)['name']?.toString(),
              ),
            if (ticket['resolutionNotes']?.toString().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('Resolution notes', style: TextStyle(color: colors.textMuted)),
              const SizedBox(height: 4),
              Text(ticket['resolutionNotes'].toString()),
            ],
          ],
        ),
      ),
    );
  }

  String? _formatDate(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;

  const _Row({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value!)),
        ],
      ),
    );
  }
}
