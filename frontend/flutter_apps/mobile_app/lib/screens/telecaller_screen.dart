import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state.dart';
import '../telecaller_pending_call.dart';
import '../telecaller_phone_recorder.dart';
import '../telecaller_recording_setup.dart';
import '../telecaller_recording_uploader.dart';

/// Telecaller leads — searchable, status-filtered list with a one-tap call.
class TelecallerScreen extends ConsumerStatefulWidget {
  const TelecallerScreen({super.key, this.embeddedInShell = false});

  /// When true (Windows workspace shell), hides duplicate chrome/back button.
  final bool embeddedInShell;

  @override
  ConsumerState<TelecallerScreen> createState() => _TelecallerScreenState();
}

class _TelecallerScreenState extends ConsumerState<TelecallerScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  String? _status;
  Timer? _debounce;
  List<Map<String, dynamic>> _leads = const [];
  bool _loading = true;
  bool _showingOutcomeSheet = false;
  String? _error;
  String? _pendingCallId;
  Map<String, dynamic>? _pendingCallLead;
  bool _phoneRecordingActive = false;
  Timer? _resumeTimer;
  DateTime? _callStartedAt;

  static const _statuses = ['ALL', 'NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'];

  bool get _isDesktopClient =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetch();
    if (_isDesktopClient) {
      unawaited(TelecallerPendingCall.clear());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverPendingCall());
    }
  }

  /// Restore call state if Android killed the app during a phone call.
  Future<void> _recoverPendingCall() async {
    if (_isDesktopClient) {
      await TelecallerPendingCall.clear();
      return;
    }
    if (_pendingCallId != null || _showingOutcomeSheet) return;
    final saved = await TelecallerPendingCall.load();
    if (saved == null || !mounted) return;
    _pendingCallId = saved.callId;
    _pendingCallLead = saved.lead;
    _callStartedAt = saved.startedAt;
    _phoneRecordingActive = saved.micActive;
    await _handleReturnFromCall();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(TelecallerPhoneRecorder.instance.dispose());
    _search.dispose();
    _debounce?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDesktopClient) return;
    if (state == AppLifecycleState.resumed &&
        _pendingCallId != null &&
        !_showingOutcomeSheet) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(milliseconds: 1500), () async {
        if (!mounted) return;
        await _handleReturnFromCall();
      });
    }
  }

  Future<void> _handleReturnFromCall() async {
    if (_pendingCallId == null || _showingOutcomeSheet) {
      return;
    }
    await _showCallOutcomeSheet(includeRecordingStep: true);
  }

  Future<void> _cleanupPendingCall() async {
    if (_phoneRecordingActive) {
      await TelecallerPhoneRecorder.instance.stop();
      _phoneRecordingActive = false;
    }
    _pendingCallId = null;
    _pendingCallLead = null;
    _callStartedAt = null;
    await TelecallerPendingCall.clear();
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _fetch);
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await ref.read(apiProvider).listLeads(
        q: _search.text.isEmpty ? null : _search.text,
        status: _status == null || _status == 'ALL' ? null : _status,
      );
      if (!mounted) return;
      setState(() { _leads = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = formatApiError(e); _loading = false; });
    }
  }

  Future<void> _call(Map<String, dynamic> lead) async {
    if (Platform.isWindows) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Use mobile app'),
          content: const Text('Please use your mobile app to complete call.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final leadId = lead['id'] as String;
    final phone = (lead['phone'] ?? '')
        .toString()
        .trim()
        .replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isEmpty) {
      bestieToast(context, 'Lead has no phone number',
          kind: BestieToastKind.warning);
      return;
    }

    try {
      final response =
          await ref.read(apiProvider).callLead(leadId, mode: 'PHONE');
      final call = response['call'] as Map?;
      final callId = call?['id']?.toString();
      if (callId == null) throw 'Could not start call log';

      _pendingCallId = callId;
      _pendingCallLead = lead;
      _callStartedAt = DateTime.now();

      await TelecallerRecordingSetup.load();
      final useMic = !TelecallerRecordingSetup.hasLinkedFolder;

      if (useMic && TelecallerPhoneRecorder.supported) {
        _phoneRecordingActive =
            await TelecallerPhoneRecorder.instance.start(callId);
      }

      await TelecallerPendingCall.save(
        callId: callId,
        lead: lead,
        startedAt: _callStartedAt!,
        micActive: _phoneRecordingActive,
      );

      final launched = await launchUrl(
        Uri(scheme: 'tel', path: phone),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await _cleanupPendingCall();
        throw 'Could not open phone app';
      }
      if (mounted) {
        final hasFolder = TelecallerRecordingSetup.hasLinkedFolder;
        bestieToast(
          context,
          'Phone call opened',
          body: hasFolder
              ? 'When you return, we\'ll scan your recordings folder and upload automatically.'
              : _phoneRecordingActive
                  ? 'Recording in background. Use speakerphone when possible.'
                  : 'Log the call outcome when you return.',
          kind: BestieToastKind.info,
        );
      }
    } catch (e) {
      await _cleanupPendingCall();
      if (mounted) {
        bestieToast(context, 'Could not call',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _showCallOutcomeSheet({bool includeRecordingStep = false}) async {
    if (_isDesktopClient) return;
    final callId = _pendingCallId;
    final lead = _pendingCallLead;
    if (callId == null || lead == null || _showingOutcomeSheet) return;

    _showingOutcomeSheet = true;
    final micWasActive = _phoneRecordingActive;
    _phoneRecordingActive = false;
    final saved = await bestieBottomSheet<bool>(
      context,
      title: includeRecordingStep ? 'Call recording & outcome' : 'Call outcome',
      builder: (_) => _CallOutcomeSheet(
        ref: ref,
        callId: callId,
        lead: lead,
        callStartedAt: _callStartedAt,
        phoneRecordingActive: includeRecordingStep ? micWasActive : false,
        runRecordingUpload: includeRecordingStep,
      ),
    );
    _showingOutcomeSheet = false;
    if (saved == true) {
      _pendingCallId = null;
      _pendingCallLead = null;
      _callStartedAt = null;
      await TelecallerPendingCall.clear();
      await _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final canManageLeads = user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN';

    if (_isDesktopClient) {
      return _DesktopTelecallerLayout(
        embeddedInShell: widget.embeddedInShell,
        colors: c,
        canManageLeads: canManageLeads,
        search: _search,
        statuses: _statuses,
        statusFilter: _status,
        leads: _leads,
        loading: _loading,
        error: _error,
        onQuery: _onQuery,
        onStatusSelected: (s) {
          setState(() => _status = s == 'ALL' ? null : s);
          _fetch();
        },
        onRefresh: _fetch,
        onCreateLead: _showCreateLeadSheet,
        onBulkAssign: _showBulkAssignSheet,
        onUpdateLeadStatus: _updateLeadStatusInline,
        toneFor: _toneFor,
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Telecaller'),
        actions: [
          if (canManageLeads)
            IconButton(
              tooltip: 'Bulk assign leads',
              icon: const Icon(Icons.upload_file_rounded),
              onPressed: _showBulkAssignSheet,
            ),
          IconButton(
            tooltip: 'Add lead',
            icon: const Icon(Icons.add_rounded),
            onPressed: _showCreateLeadSheet,
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onQuery,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, color: c.textMuted, size: 18),
              hintText: 'Find a lead',
              filled: true,
              fillColor: c.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _statuses.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final s = _statuses[i];
              final active = (s == 'ALL' && _status == null) || s == _status;
              return ChoiceChip(
                label: Text(s),
                selected: active,
                onSelected: (_) {
                  setState(() => _status = s == 'ALL' ? null : s);
                  _fetch();
                },
                selectedColor: c.brandSoft,
                labelStyle: TextStyle(
                  color: active ? c.brandStrong : c.textSoft,
                  fontWeight: BestieTokens.fwSemibold,
                  fontSize: 11,
                ),
                shape: StadiumBorder(side: BorderSide(color: active ? c.brand : c.border)),
                backgroundColor: c.surface2,
              );
            },
          ),
        ),
        Expanded(
          child: _loading && _leads.isEmpty
              ? const Center(child: BestieSpinner())
              : _error != null
                  ? BestieEmptyState(
                      icon: Icons.error_outline_rounded, iconColor: c.danger,
                      title: 'Could not load leads', description: _error,
                    )
                  : _leads.isEmpty
                      ? const BestieEmptyState(
                          icon: Icons.headset_mic_outlined,
                          title: 'No leads match',
                          description: 'Try a different filter or search term.',
                        )
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          child: ListView.separated(
                            itemCount: _leads.length,
                            separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: c.border),
                            itemBuilder: (ctx, i) {
                              final l = _leads[i];
                              final name = (l['name'] ?? '—').toString();
                              final company = (l['company'] ?? '').toString();
                              final phone = (l['phone'] ?? '').toString();
                              final st = (l['status'] ?? 'NEW').toString();
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: c.brandSoft,
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: TextStyle(color: c.brandStrong, fontWeight: BestieTokens.fwBold),
                                  ),
                                ),
                                title: Text(name,
                                    style: TextStyle(fontWeight: BestieTokens.fwSemibold, color: c.text)),
                                subtitle: Text(
                                  [company, phone].where((s) => s.isNotEmpty).join(' · '),
                                  style: TextStyle(color: c.textMuted, fontSize: 12),
                                ),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  GestureDetector(
                                    onTap: () => _showStatusSheet(l),
                                    child: BestieBadge(
                                      tone: _toneFor(st),
                                      child: Text(st),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(Icons.call_rounded, color: c.success),
                                    tooltip: 'Call',
                                    onPressed: () => _call(l),
                                  ),
                                ]),
                                onTap: () => _call(l),
                                onLongPress: () => _showStatusSheet(l),
                              );
                            },
                          ),
                        ),
        ),
      ]),
      bottomNavigationBar: SizedBox(
        height: 70.0 + MediaQuery.of(context).padding.bottom - 18,
      ),
    );
  }

  BestieTone _toneFor(String status) => switch (status) {
        'WON'        => BestieTone.success,
        'CONTACTED'  => BestieTone.info,
        'INTERESTED' => BestieTone.warning,
        'FOLLOWUP'   => BestieTone.warning,
        'LOST'       => BestieTone.danger,
        _            => BestieTone.brand,
      };

  Future<void> _showCreateLeadSheet() async {
    final created = await bestieBottomSheet<bool>(
      context,
      title: 'Add lead',
      builder: (_) => _CreateLeadSheet(ref: ref),
    );
    if (created == true) {
      await _fetch();
    }
  }

  Future<void> _showBulkAssignSheet() async {
    final assigned = await bestieBottomSheet<bool>(
      context,
      title: 'Bulk assign leads',
      builder: (_) => _BulkAssignLeadsSheet(ref: ref),
    );
    if (assigned == true) {
      await _fetch();
    }
  }

  Future<void> _showStatusSheet(Map<String, dynamic> lead) async {
    final updated = await bestieBottomSheet<bool>(
      context,
      title: 'Change status',
      builder: (_) => _LeadStatusSheet(ref: ref, lead: lead),
    );
    if (updated == true) {
      await _fetch();
    }
  }

  Future<void> _updateLeadStatusInline(String leadId, String status) async {
    try {
      await ref.read(apiProvider).updateLeadStatus(leadId, status);
      await _fetch();
      if (mounted) {
        bestieToast(context, 'Lead status updated',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not update status',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }
}

/// Windows / desktop telecaller — admin-style leads board (matches web app).
/// No phone-call recording or outcome logging on desktop.
class _DesktopTelecallerLayout extends StatefulWidget {
  const _DesktopTelecallerLayout({
    this.embeddedInShell = false,
    required this.colors,
    required this.canManageLeads,
    required this.search,
    required this.statuses,
    required this.statusFilter,
    required this.leads,
    required this.loading,
    required this.error,
    required this.onQuery,
    required this.onStatusSelected,
    required this.onRefresh,
    required this.onCreateLead,
    required this.onBulkAssign,
    required this.onUpdateLeadStatus,
    required this.toneFor,
  });

  final bool embeddedInShell;
  final BestieColors colors;
  final bool canManageLeads;
  final TextEditingController search;
  final List<String> statuses;
  final String? statusFilter;
  final List<Map<String, dynamic>> leads;
  final bool loading;
  final String? error;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onStatusSelected;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreateLead;
  final Future<void> Function() onBulkAssign;
  final Future<void> Function(String leadId, String status) onUpdateLeadStatus;
  final BestieTone Function(String status) toneFor;

  @override
  State<_DesktopTelecallerLayout> createState() =>
      _DesktopTelecallerLayoutState();
}

class _DesktopTelecallerLayoutState extends State<_DesktopTelecallerLayout> {
  static const _leadStatuses = [
    'NEW',
    'CONTACTED',
    'INTERESTED',
    'FOLLOWUP',
    'WON',
    'LOST',
  ];

  String? _selectedLeadId;
  bool _statusSaving = false;

  Map<String, dynamic>? get _selectedLead {
    if (_selectedLeadId == null) return null;
    for (final lead in widget.leads) {
      if (lead['id']?.toString() == _selectedLeadId) return lead;
    }
    return null;
  }

  Future<void> _promptUseMobileApp() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use mobile app'),
        content: const Text('Please use your mobile app to complete call.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String? _formatFollowUp(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    if (raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return dt.toLocal().toString().split('.').first;
  }

  Widget _statusChip(String s, BestieColors c) {
    final active =
        (s == 'ALL' && widget.statusFilter == null) || s == widget.statusFilter;
    return ChoiceChip(
      label: Text(s),
      selected: active,
      onSelected: (_) => widget.onStatusSelected(s),
      selectedColor: c.brandSoft,
      labelStyle: TextStyle(
        color: active ? c.brandStrong : c.textSoft,
        fontWeight: BestieTokens.fwSemibold,
        fontSize: 11,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: StadiumBorder(
        side: BorderSide(color: active ? c.brand : c.border),
      ),
      backgroundColor: c.surface2,
    );
  }

  Widget _buildListPanel(BestieColors c, double width) {
    return SizedBox(
      width: width,
      child: ColoredBox(
        color: c.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Leads',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.canManageLeads)
                        OutlinedButton.icon(
                          onPressed: widget.onBulkAssign,
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: const Text('Bulk assign'),
                        ),
                      FilledButton.icon(
                        onPressed: widget.onCreateLead,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add lead'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: widget.search,
                onChanged: widget.onQuery,
                decoration: InputDecoration(
                  prefixIcon:
                      Icon(Icons.search_rounded, color: c.textMuted, size: 18),
                  hintText: 'Search by name, phone, company',
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rPill),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rPill),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in widget.statuses) _statusChip(s, c),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Expanded(
              child: widget.loading && widget.leads.isEmpty
                  ? const Center(child: BestieSpinner())
                  : widget.error != null
                      ? BestieEmptyState(
                          icon: Icons.error_outline_rounded,
                          iconColor: c.danger,
                          title: 'Could not load leads',
                          description: widget.error,
                        )
                      : widget.leads.isEmpty
                          ? const BestieEmptyState(
                              icon: Icons.headset_mic_outlined,
                              title: 'No leads match',
                              description:
                                  'Try a different filter or search term.',
                            )
                          : RefreshIndicator(
                              onRefresh: widget.onRefresh,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: widget.leads.length,
                                separatorBuilder: (_, __) =>
                                    Divider(height: 1, color: c.border),
                                itemBuilder: (ctx, i) {
                                  final lead = widget.leads[i];
                                  final id = lead['id']?.toString() ?? '';
                                  final name = (lead['name'] ?? '—').toString();
                                  final company =
                                      (lead['company'] ?? '').toString();
                                  final phone =
                                      (lead['phone'] ?? '').toString();
                                  final st =
                                      (lead['status'] ?? 'NEW').toString();
                                  final active = id == _selectedLeadId;
                                  return Material(
                                    color: active
                                        ? c.brandSoft
                                        : Colors.transparent,
                                    child: ListTile(
                                      dense: true,
                                      selected: active,
                                      title: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: BestieTokens.fwSemibold,
                                          color: c.text,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [company, phone]
                                            .where((s) => s.isNotEmpty)
                                            .join(' · '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: BestieBadge(
                                        tone: widget.toneFor(st),
                                        child: Text(st),
                                      ),
                                      onTap: () =>
                                          setState(() => _selectedLeadId = id),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailField(
    BestieColors c, {
    required String label,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: c.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailsPanel(BestieColors c, Map<String, dynamic>? selected) {
    if (selected == null) {
      return ColoredBox(
        color: c.bg,
        child: Center(
          child: Text(
            'Select a lead to see details.',
            style: TextStyle(color: c.textMuted, fontSize: 16),
          ),
        ),
      );
    }

    return ColoredBox(
      color: c.bg,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (selected['name'] ?? 'Lead').toString(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: c.text,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                (selected['company'] ?? '').toString(),
                                (selected['phone'] ?? '').toString(),
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: TextStyle(color: c.textMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _promptUseMobileApp,
                        icon: const Icon(Icons.phone_rounded, size: 18),
                        label: const Text('Click to call'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCol = constraints.maxWidth >= 480;
                      final statusField = _detailField(
                        c,
                        label: 'Status',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(
                            '${selected['id']}-${selected['status']}',
                          ),
                          initialValue: _leadStatuses.contains(selected['status'])
                              ? selected['status'] as String
                              : 'NEW',
                          isExpanded: true,
                          items: _leadStatuses
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ))
                              .toList(),
                          onChanged: _statusSaving
                              ? null
                              : (value) async {
                                  final id = selected['id']?.toString();
                                  if (id == null || value == null) return;
                                  setState(() => _statusSaving = true);
                                  await widget.onUpdateLeadStatus(id, value);
                                  if (mounted) {
                                    setState(() => _statusSaving = false);
                                  }
                                },
                          decoration: _fieldDecoration(c, 'Lead status'),
                        ),
                      );
                      final followUpField = _detailField(
                        c,
                        label: 'Next follow up',
                        child: Text(
                          _formatFollowUp(selected['nextFollowAt']) ?? '—',
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                      if (!twoCol) {
                        return Column(
                          children: [
                            statusField,
                            const SizedBox(height: 12),
                            followUpField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: statusField),
                          const SizedBox(width: 12),
                          Expanded(child: followUpField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _detailField(
                    c,
                    label: 'Notes',
                    child: Text(
                      (selected['notes'] ?? 'No notes yet.').toString(),
                      style: TextStyle(color: c.text, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final selected = _selectedLead;

    return Scaffold(
      backgroundColor: widget.embeddedInShell ? Colors.transparent : c.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embeddedInShell)
            Material(
              color: c.surface,
              elevation: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => context.go('/dashboard'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Text(
                        'Telecaller Leads',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!widget.embeddedInShell) Divider(height: 1, color: c.border),
          if (widget.embeddedInShell)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                'Telecaller Leads',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final listWidth =
                    (constraints.maxWidth * 0.34).clamp(300.0, 400.0);
                return Padding(
                  padding: widget.embeddedInShell
                      ? const EdgeInsets.fromLTRB(12, 12, 12, 12)
                      : EdgeInsets.zero,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(
                        widget.embeddedInShell ? BestieTokens.rLg : 0,
                      ),
                      border: widget.embeddedInShell
                          ? Border.all(color: c.borderSoft)
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        widget.embeddedInShell ? BestieTokens.rLg : 0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildListPanel(c, listWidth),
                          VerticalDivider(width: 1, color: c.border),
                          Expanded(child: _buildDetailsPanel(c, selected)),
                        ],
                      ),
                    ),
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

class _CreateLeadSheet extends StatefulWidget {
  const _CreateLeadSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_CreateLeadSheet> createState() => _CreateLeadSheetState();
}

class _CreateLeadSheetState extends State<_CreateLeadSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _source = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _company.dispose();
    _email.dispose();
    _source.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      bestieToast(context, 'Name and phone are required',
          kind: BestieToastKind.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.ref.read(apiProvider).createLead({
        'name': name,
        'phone': phone,
        if (_company.text.trim().isNotEmpty) 'company': _company.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        'status': 'NEW',
        if (_source.text.trim().isNotEmpty) 'source': _source.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      bestieToast(context, 'Lead created', kind: BestieToastKind.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not create lead',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LeadField(controller: _name, label: 'Lead name *'),
              const SizedBox(height: 10),
              _LeadField(
                controller: _phone,
                label: 'Phone *',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              _LeadField(controller: _company, label: 'Company'),
              const SizedBox(height: 10),
              _LeadField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),
              _LeadField(controller: _source, label: 'Source'),
              const SizedBox(height: 10),
              _LeadField(controller: _notes, label: 'Notes', maxLines: 3),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(_saving ? 'Saving...' : 'Create lead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkAssignLeadsSheet extends StatefulWidget {
  const _BulkAssignLeadsSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_BulkAssignLeadsSheet> createState() => _BulkAssignLeadsSheetState();
}

class _BulkAssignLeadsSheetState extends State<_BulkAssignLeadsSheet> {
  final _quota = TextEditingController(text: '100');
  final _source = TextEditingController(text: 'mobile-admin-upload');
  final _rows = TextEditingController();
  final Set<String> _selectedTelecallerIds = {};
  List<Map<String, dynamic>> _telecallers = const [];
  PlatformFile? _pickedFile;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _loadingTelecallers = true;
  bool _saving = false;
  String? _assignError;

  @override
  void initState() {
    super.initState();
    _loadTelecallers();
  }

  @override
  void dispose() {
    _quota.dispose();
    _source.dispose();
    _rows.dispose();
    super.dispose();
  }

  Future<void> _loadTelecallers() async {
    try {
      final items = await widget.ref.read(apiProvider).listEmployees(
            role: 'TELECALLER',
            pageSize: 100,
          );
      if (!mounted) return;
      setState(() {
        _telecallers = items;
        _loadingTelecallers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingTelecallers = false);
      bestieToast(context, 'Could not load telecallers',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  String _dateLabel(DateTime value) {
    final local = DateTime(value.year, value.month, value.day);
    return [
      local.year.toString().padLeft(4, '0'),
      local.month.toString().padLeft(2, '0'),
      local.day.toString().padLeft(2, '0'),
    ].join('-');
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  String _leadFileExtension(PlatformFile file) {
    final rawExtension = file.extension;
    if (rawExtension != null && rawExtension.trim().isNotEmpty) {
      return rawExtension.toLowerCase().trim();
    }
    final name = file.name.toLowerCase().trim();
    final dot = name.lastIndexOf('.');
    return dot >= 0 && dot < name.length - 1 ? name.substring(dot + 1) : '';
  }

  bool _looksLikeOpenXmlExcel(PlatformFile file) {
    final bytes = file.bytes;
    if (bytes == null || bytes.length < 4) return false;
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
        (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
  }

  bool _isSupportedLeadFile(PlatformFile file) {
    final extension = _leadFileExtension(file);
    return extension == 'xlsx' ||
        extension == 'xlsm' ||
        extension == 'csv' ||
        _looksLikeOpenXmlExcel(file);
  }

  Future<void> _pickLeadFile() async {
    final result = await FilePicker.platform.pickFiles(
      // Use the broad Android picker so providers like WPS Office can appear.
      // We validate the selected extension below before uploading.
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    if (!_isSupportedLeadFile(file)) {
      if (!mounted) return;
      bestieToast(
        context,
        'Unsupported file',
        body: 'Please choose an Excel .xlsx/.xlsm or CSV .csv file.',
        kind: BestieToastKind.warning,
      );
      return;
    }
    setState(() => _pickedFile = file);
  }

  List<Map<String, dynamic>> _parseRows() {
    final lines = _rows.text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final dataLines =
        lines.isNotEmpty && lines.first.toLowerCase().contains('phone')
            ? lines.skip(1)
            : lines;
    final records = <Map<String, dynamic>>[];
    for (final line in dataLines) {
      final parts = line.split(',').map((part) => part.trim()).toList();
      final name = parts.isNotEmpty ? parts[0] : '';
      final phone = parts.length > 1 ? parts[1] : '';
      if (name.isEmpty || phone.isEmpty) {
        throw 'Use format: name, phone, company, email, notes';
      }
      records.add({
        'name': name,
        'phone': phone,
        if (parts.length > 2 && parts[2].isNotEmpty) 'company': parts[2],
        if (parts.length > 3 && parts[3].isNotEmpty) 'email': parts[3],
        if (parts.length > 4 && parts.skip(4).join(', ').trim().isNotEmpty)
          'notes': parts.skip(4).join(', ').trim(),
      });
    }
    if (records.isEmpty) throw 'Paste at least one customer row';
    return records;
  }

  Future<void> _assign() async {
    if (_selectedTelecallerIds.isEmpty) {
      bestieToast(context, 'Select at least one telecaller',
          kind: BestieToastKind.warning);
      return;
    }

    final quota = int.tryParse(_quota.text.trim()) ?? 100;
    setState(() {
      _saving = true;
      _assignError = null;
    });
    try {
      late final Map<String, dynamic> result;
      if (_pickedFile != null) {
        final bytes = _pickedFile!.bytes;
        if (bytes == null) throw 'Could not read selected file';
        result = await widget.ref.read(apiProvider).bulkDistributeLeadsFile(
              bytes: bytes,
              filename: _pickedFile!.name,
              telecallerIds: _selectedTelecallerIds.toList(),
              startDate: _dateLabel(_startDate),
              endDate: _dateLabel(_endDate),
              recordsPerTelecallerPerDay: quota,
              source: _source.text.trim().isEmpty ? null : _source.text.trim(),
            );
      } else {
        late final List<Map<String, dynamic>> records;
        try {
          records = _parseRows();
        } catch (e) {
          bestieToast(context, 'Invalid customer data',
              body: e.toString(), kind: BestieToastKind.warning);
          return;
        }
        result = await widget.ref.read(apiProvider).bulkDistributeLeads({
          'telecallerIds': _selectedTelecallerIds.toList(),
          'startDate': _dateLabel(_startDate),
          'endDate': _dateLabel(_endDate),
          'recordsPerTelecallerPerDay': quota,
          if (_source.text.trim().isNotEmpty) 'source': _source.text.trim(),
          'records': records,
        });
      }
      if (!mounted) return;
      bestieToast(
        context,
        'Leads assigned',
        body:
            '${result['assigned'] ?? 0} leads distributed to ${_selectedTelecallerIds.length} telecaller(s).',
        kind: BestieToastKind.success,
      );
      Navigator.pop(context, true);
    } catch (e) {
      final message = formatApiError(e);
      setState(() => _assignError = message);
      if (mounted) {
        bestieToast(context, 'Could not assign leads',
            body: message, kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select telecallers',
                style: TextStyle(
                  color: c.text,
                  fontWeight: BestieTokens.fwBold,
                ),
              ),
              const SizedBox(height: 8),
              if (_loadingTelecallers)
                const Center(child: BestieSpinner())
              else if (_telecallers.isEmpty)
                Text(
                  'No TELECALLER users found. Create them from Employees first.',
                  style: TextStyle(color: c.textMuted),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _telecallers.length,
                    itemBuilder: (_, index) {
                      final person = _telecallers[index];
                      final id = person['id']?.toString();
                      final name = (person['name'] ?? person['userId'] ?? '')
                          .toString();
                      if (id == null) return const SizedBox.shrink();
                      return CheckboxListTile(
                        value: _selectedTelecallerIds.contains(id),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(name),
                        subtitle: Text(
                          (person['userId'] ?? '').toString(),
                          style: TextStyle(color: c.textMuted),
                        ),
                        onChanged: _saving
                            ? null
                            : (checked) => setState(() {
                                  if (checked == true) {
                                    _selectedTelecallerIds.add(id);
                                  } else {
                                    _selectedTelecallerIds.remove(id);
                                  }
                                }),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickDate(start: true),
                      icon: const Icon(Icons.event_rounded),
                      label: Text('From ${_dateLabel(_startDate)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickDate(start: false),
                      icon: const Icon(Icons.event_available_rounded),
                      label: Text('To ${_dateLabel(_endDate)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _LeadField(
                controller: _quota,
                label: 'Records per telecaller per day',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _LeadField(controller: _source, label: 'Source'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickLeadFile,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(_pickedFile == null
                    ? 'Browse Excel/CSV from phone, Drive, or WPS'
                    : _pickedFile!.name),
              ),
              const SizedBox(height: 8),
              _LeadField(
                controller: _rows,
                label: _pickedFile == null
                    ? 'Customer data: name, phone, company, email, notes'
                    : 'Customer data disabled because file is selected',
                maxLines: 8,
              ),
              const SizedBox(height: 6),
              Text(
                'Paste one customer per line. Example: Ravi Kumar, 9876543210, ABC Traders, ravi@example.com, interested',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              if (_assignError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    border: Border.all(color: c.danger.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    _assignError!,
                    style: TextStyle(
                      color: c.danger,
                      fontWeight: BestieTokens.fwSemibold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _assign,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded),
                label: Text(_saving ? 'Assigning...' : 'Assign leads'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallOutcomeSheet extends StatefulWidget {
  const _CallOutcomeSheet({
    required this.ref,
    required this.callId,
    required this.lead,
    this.callStartedAt,
    this.phoneRecordingActive = false,
    this.runRecordingUpload = false,
  });

  final WidgetRef ref;
  final String callId;
  final Map<String, dynamic> lead;
  final DateTime? callStartedAt;
  final bool phoneRecordingActive;
  final bool runRecordingUpload;

  @override
  State<_CallOutcomeSheet> createState() => _CallOutcomeSheetState();
}

class _CallOutcomeSheetState extends State<_CallOutcomeSheet> {
  static const _primaryBlue = Color(0xFF3B99F6);
  static const _outcomes = [
    ('REACHABLE', 'Reachable'),
    ('NO_ANSWER', 'No answer'),
    ('NOT_RESPONDED', 'Call not responded'),
    ('BUSY', 'Busy'),
    ('SWITCHED_OFF', 'Switched off'),
    ('FOLLOWUP_REQUIRED', 'Follow-up required'),
    ('WRONG_NUMBER', 'Wrong number'),
    ('NOT_INTERESTED', 'Not interested'),
  ];

  final _notes = TextEditingController();
  String _outcome = 'REACHABLE';
  bool _saving = false;
  RecordingProcessState _recordingState = const RecordingProcessState(
    phase: RecordingProcessPhase.idle,
    detail: 'Waiting…',
  );
  bool _recordingFinished = false;
  bool _manualPickBusy = false;

  @override
  void initState() {
    super.initState();
    if (widget.runRecordingUpload) {
      unawaited(TelecallerRecordingSetup.load().then((_) {
        if (mounted) setState(() {});
      }));
      WidgetsBinding.instance.addPostFrameCallback((_) => _runRecordingUpload());
    } else {
      _recordingFinished = true;
    }
  }

  Future<void> _runRecordingUpload() async {
    final uploader = TelecallerRecordingUploader(widget.ref);
    await uploader.runAutoUpload(
      callId: widget.callId,
      callStartedAt: widget.callStartedAt,
      phoneRecordingActive: widget.phoneRecordingActive,
      onState: (s) {
        if (mounted) setState(() => _recordingState = s);
      },
    );
    if (mounted) {
      setState(() {
        _recordingFinished =
            _recordingState.phase == RecordingProcessPhase.success ||
                _recordingState.phase == RecordingProcessPhase.failed;
      });
    }
  }

  Future<void> _pickRecordingManual() async {
    if (_manualPickBusy) return;
    setState(() => _manualPickBusy = true);
    final uploader = TelecallerRecordingUploader(widget.ref);
    await uploader.uploadManualPick(
      callId: widget.callId,
      onState: (s) {
        if (mounted) setState(() => _recordingState = s);
      },
    );
    if (mounted) {
      setState(() {
        _manualPickBusy = false;
        _recordingFinished =
            _recordingState.phase == RecordingProcessPhase.success ||
                _recordingState.phase == RecordingProcessPhase.failed;
      });
    }
  }

  void _skipRecording() {
    setState(() {
      _recordingFinished = true;
      _recordingState = const RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        detail: 'Skipped — log outcome only',
        error: 'Recording not uploaded',
      );
    });
  }

  Widget _recordingSection(BestieColors c) {
    if (!widget.runRecordingUpload) return const SizedBox.shrink();

    final phase = _recordingState.phase;
    final busy = phase != RecordingProcessPhase.success &&
        phase != RecordingProcessPhase.failed &&
        phase != RecordingProcessPhase.idle;
    final failed = phase == RecordingProcessPhase.failed;
    final success = phase == RecordingProcessPhase.success;
    final folderLabel = TelecallerRecordingSetup.folderLabel;
    final hasFolder = TelecallerRecordingSetup.hasLinkedFolder;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
        border: Border.all(
          color: success
              ? c.success.withValues(alpha: 0.4)
              : failed
                  ? c.danger.withValues(alpha: 0.35)
                  : _primaryBlue.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Call recording upload',
            style: TextStyle(
              color: c.text,
              fontWeight: BestieTokens.fwBold,
              fontSize: 15,
            ),
          ),
          if (folderLabel != null && hasFolder) ...[
            const SizedBox(height: 4),
            Text(
              'Folder: $folderLabel',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ] else if (!hasFolder) ...[
            const SizedBox(height: 4),
            Text(
              'No recordings folder linked — use manual pick below or re-run setup.',
              style: TextStyle(color: c.warning, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  success
                      ? Icons.check_circle_rounded
                      : failed
                          ? Icons.error_outline_rounded
                          : Icons.folder_open_rounded,
                  color: success
                      ? c.success
                      : failed
                          ? c.danger
                          : _primaryBlue,
                  size: 20,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _recordingState.detail ?? 'Processing recording…',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (_recordingState.fileName != null) ...[
            const SizedBox(height: 6),
            Text(
              _recordingState.fileName!,
              style: TextStyle(color: c.textMuted, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (_recordingState.error != null) ...[
            const SizedBox(height: 6),
            Text(
              _recordingState.error!,
              style: TextStyle(color: c.danger, fontSize: 12),
            ),
          ],
          if (failed && !_manualPickBusy) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickRecordingManual,
              icon: const Icon(Icons.audio_file_outlined, size: 18),
              label: const Text('Choose recording file manually'),
            ),
            TextButton(
              onPressed: _skipRecording,
              child: const Text('Skip recording — save outcome only'),
            ),
          ],
          if (success) ...[
            const SizedBox(height: 8),
            Text(
              'Admin panel → Recordings will show this call.',
              style: TextStyle(color: c.success, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.ref.read(apiProvider).updateTelecallerCallOutcome(
            widget.callId,
            outcome: _outcome,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      bestieToast(context, 'Call outcome saved',
          body: 'Admin report will include this result.',
          kind: BestieToastKind.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save outcome',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final name = (widget.lead['name'] ?? 'Lead').toString();
    final phone = (widget.lead['phone'] ?? '').toString();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: c.text,
                  fontWeight: BestieTokens.fwBold,
                  fontSize: 18,
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(phone, style: TextStyle(color: c.textMuted)),
              ],
              _recordingSection(c),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _outcome,
                isExpanded: true,
                decoration: _fieldDecoration(c, 'What happened in the call?'),
                items: _outcomes
                    .map((item) => DropdownMenuItem(
                          value: item.$1,
                          child: Text(item.$2),
                        ))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _outcome = value ?? _outcome),
              ),
              const SizedBox(height: 12),
              _LeadField(
                controller: _notes,
                label: 'Notes (optional)',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_saving || (widget.runRecordingUpload && !_recordingFinished))
                    ? null
                    : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _saving
                      ? 'Saving...'
                      : widget.runRecordingUpload && !_recordingFinished
                          ? 'Waiting for recording…'
                          : 'Save outcome',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadStatusSheet extends StatefulWidget {
  const _LeadStatusSheet({required this.ref, required this.lead});

  final WidgetRef ref;
  final Map<String, dynamic> lead;

  @override
  State<_LeadStatusSheet> createState() => _LeadStatusSheetState();
}

class _LeadStatusSheetState extends State<_LeadStatusSheet> {
  static const _statuses = ['NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'];

  late String _status = _statuses.contains(widget.lead['status'])
      ? widget.lead['status'] as String
      : 'NEW';
  bool _saving = false;

  Future<void> _save() async {
    final id = widget.lead['id'] as String?;
    if (id == null) return;

    setState(() => _saving = true);
    try {
      await widget.ref.read(apiProvider).updateLeadStatus(id, _status);
      if (!mounted) return;
      bestieToast(context, 'Lead status updated',
          kind: BestieToastKind.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not update status',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final name = (widget.lead['name'] ?? 'Lead').toString();
    final phone = (widget.lead['phone'] ?? '').toString();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name,
              style: TextStyle(
                color: c.text,
                fontWeight: BestieTokens.fwBold,
                fontSize: 18,
              ),
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(phone, style: TextStyle(color: c.textMuted)),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: _statuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _status = value ?? 'NEW'),
              decoration: _fieldDecoration(c, 'Lead status'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving...' : 'Update status'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadField extends StatelessWidget {
  const _LeadField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _fieldDecoration(c, label),
    );
  }
}

InputDecoration _fieldDecoration(BestieColors c, String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: c.surface2,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rSm),
      borderSide: BorderSide(color: c.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rSm),
      borderSide: BorderSide(color: c.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rSm),
      borderSide: BorderSide(color: c.brand),
    ),
  );
}
