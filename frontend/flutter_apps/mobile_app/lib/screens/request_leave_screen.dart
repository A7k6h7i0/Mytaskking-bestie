import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import '../widgets/bestie_picker_theme.dart';

class RequestLeaveScreen extends ConsumerStatefulWidget {
  const RequestLeaveScreen({super.key});

  @override
  ConsumerState<RequestLeaveScreen> createState() => _RequestLeaveScreenState();
}

class _RequestLeaveScreenState extends ConsumerState<RequestLeaveScreen> {
  static const _types = [
    ('FULL_DAY', 'Full day'),
    ('HALF_DAY', 'Half day'),
    ('PERMISSION', 'Permission'),
  ];

  String _leaveType = 'FULL_DAY';
  DateTime _fromDate = DateTime.now();
  DateTime? _toDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final _hoursCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _submitting = false;
  List<Map<String, dynamic>> _mine = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    try {
      final items = await ref.read(apiProvider).listOrgLeaves(mine: true);
      if (!mounted) return;
      setState(() {
        _mine = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _timeKey(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await bestiePickDate(
      context,
      initial: isFrom ? _fromDate : (_toDate ?? _fromDate),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate != null && _toDate!.isBefore(_fromDate)) {
          _toDate = _fromDate;
        }
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await bestiePickTime(
      context,
      initialTime: start
          ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
          : (_endTime ?? const TimeOfDay(hour: 13, minute: 0)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _submit() async {
    final description = _descCtrl.text.trim();
    if (description.length < 5) {
      bestieToast(context, 'Please describe your leave',
          kind: BestieToastKind.error);
      return;
    }
    if (_leaveType == 'HALF_DAY' &&
        (_startTime == null || _endTime == null)) {
      bestieToast(context, 'Select start and end time for half day',
          kind: BestieToastKind.error);
      return;
    }
    if (_leaveType == 'PERMISSION' &&
        _startTime == null &&
        _endTime == null &&
        _hoursCtrl.text.trim().isEmpty) {
      bestieToast(context, 'Add time range or permission hours',
          kind: BestieToastKind.error);
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(apiProvider).createOrgLeave({
        'leaveType': _leaveType,
        'fromDate': _dateKey(_fromDate),
        if (_leaveType == 'FULL_DAY' && _toDate != null)
          'toDate': _dateKey(_toDate!),
        if (_leaveType != 'FULL_DAY' && _toDate != null)
          'toDate': _dateKey(_toDate!),
        if (_startTime != null) 'startTime': _timeKey(_startTime!),
        if (_endTime != null) 'endTime': _timeKey(_endTime!),
        if (_leaveType == 'PERMISSION' && _hoursCtrl.text.trim().isNotEmpty)
          'permissionHours': double.tryParse(_hoursCtrl.text.trim()),
        'description': description,
      });
      if (!mounted) return;
      _descCtrl.clear();
      _hoursCtrl.clear();
      bestieToast(context, 'Leave request submitted',
          kind: BestieToastKind.success);
      await _loadMine();
    } catch (e) {
      if (!mounted) return;
      bestieToast(context, 'Could not submit leave',
          body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'APPROVED':
        return 'Approved';
      case 'REJECTED':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final role = ref.watch(authStoreProvider).user?.role ?? '';
    if (role == 'ADMIN' || role == 'SUPER_ADMIN') {
      return Scaffold(
        appBar: AppBar(title: const Text('Request a leave')),
        body: BestieEmptyState(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Admins review leave only',
          description:
              'Organisation admins approve employee leave under More → Leave requests.',
        ),
      );
    }
    final needsTime = _leaveType == 'HALF_DAY' || _leaveType == 'PERMISSION';

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(title: const Text('Request a leave')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Submit a leave request to your organisation admin. Approved leave pauses location tracking.',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Leave type'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _leaveType,
                items: _types
                    .map((t) =>
                        DropdownMenuItem(value: t.$1, child: Text(t.$2)))
                    .toList(),
                onChanged: (v) => setState(() => _leaveType = v ?? 'FULL_DAY'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pickDate(isFrom: true),
            icon: Icon(Icons.event_outlined, size: 18, color: c.text),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.text,
              side: BorderSide(color: c.border),
            ),
            label: Text('From ${_dateKey(_fromDate)}'),
          ),
          if (_leaveType == 'FULL_DAY') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: false),
              icon: Icon(Icons.event_outlined, size: 18, color: c.text),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.border),
              ),
              label: Text(
                _toDate != null
                    ? 'To ${_dateKey(_toDate!)}'
                    : 'To (optional, same day)',
              ),
            ),
          ],
          if (_leaveType == 'PERMISSION') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: false),
              icon: Icon(Icons.date_range_outlined, size: 18, color: c.text),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.border),
              ),
              label: Text(
                _toDate != null
                    ? 'End date ${_dateKey(_toDate!)}'
                    : 'End date (optional)',
              ),
            ),
          ],
          if (needsTime) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(start: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.text,
                      side: BorderSide(color: c.border),
                    ),
                    child: Text(
                      _startTime != null
                          ? 'Start ${_timeKey(_startTime!)}'
                          : 'Start time',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(start: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.text,
                      side: BorderSide(color: c.border),
                    ),
                    child: Text(
                      _endTime != null
                          ? 'End ${_timeKey(_endTime!)}'
                          : 'End time',
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_leaveType == 'PERMISSION') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _hoursCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Permission hours (optional)',
                hintText: 'e.g. 2',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Reason for leave…',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit request'),
          ),
          const SizedBox(height: 28),
          Text('Your requests',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: c.text)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: BestieSpinner()),
            )
          else if (_mine.isEmpty)
            Text('No leave requests yet.',
                style: TextStyle(color: c.textMuted, fontSize: 13))
          else
            ..._mine.map((row) {
              final status = row['status']?.toString() ?? 'PENDING';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['leaveType']} · ${_statusLabel(status)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${row['fromDate']}${row['toDate'] != null ? ' → ${row['toDate']}' : ''}',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                    if (row['description'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(row['description'].toString(),
                            style: TextStyle(fontSize: 13, color: c.textSoft)),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
