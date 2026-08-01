import 'package:flutter/material.dart';

/// Encodes/decodes meeting window in presence `customStatus` as `start|end`.
class MeetingPresence {
  MeetingPresence._();

  static const separator = '|';

  static String encodeTimes(String start, String end) =>
      '${start.trim()}$separator${end.trim()}';

  static ({String start, String end})? decodeTimes(String? customStatus) {
    if (customStatus == null || customStatus.trim().isEmpty) return null;
    final parts = customStatus.split(separator);
    if (parts.length != 2) return null;
    final start = parts[0].trim();
    final end = parts[1].trim();
    if (start.isEmpty || end.isEmpty) return null;
    return (start: start, end: end);
  }

  static bool isMeetingMap(Map<String, dynamic>? presence) {
    if (presence == null) return false;
    final status = (presence['status'] ?? '').toString();
    final custom = (presence['customStatus'] ?? '').toString();
    return status == 'IN_MEETING' ||
        custom.toLowerCase().contains('meeting') ||
        decodeTimes(custom) != null;
  }

  static String callerTtsMessage({
    required String name,
    required String start,
    required String end,
  }) =>
      'Sorry $name is in a meeting from $start to $end';

  static String callerTtsFromPresence(String name, Map<String, dynamic> presence) {
    final custom = (presence['customStatus'] ?? '').toString();
    final times = decodeTimes(custom);
    if (times != null) {
      return callerTtsMessage(name: name, start: times.start, end: times.end);
    }
    return 'Sorry $name is in a meeting';
  }

  static String displayLabel(String? start, String? end) {
    if (start != null && end != null && start.isNotEmpty && end.isNotEmpty) {
      return 'Meeting · $start – $end';
    }
    return 'Meeting';
  }

  /// Compact label for TTS/UI, e.g. 10AM, 12:30PM.
  static String formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    if (time.minute == 0) return '$hour$period';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute$period';
  }

  static TimeOfDay? parseTimeLabel(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    final raw = label.trim().toUpperCase();
    final match = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)$').firstMatch(raw);
    if (match == null) return null;
    var hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    final period = match.group(3);
    if (hour == null || minute > 59) return null;
    if (period == 'PM' && hour < 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return TimeOfDay(hour: hour, minute: minute);
  }
}

/// WhatsApp-style meeting start/end picker used from profile availability.
Future<({String start, String end})?> showMeetingTimeDialog(
  BuildContext context, {
  String? initialStart,
  String? initialEnd,
}) async {
  return showDialog<({String start, String end})>(
    context: context,
    builder: (ctx) => _MeetingTimeDialog(
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );
}

class _MeetingTimeDialog extends StatefulWidget {
  const _MeetingTimeDialog({this.initialStart, this.initialEnd});

  final String? initialStart;
  final String? initialEnd;

  @override
  State<_MeetingTimeDialog> createState() => _MeetingTimeDialogState();
}

class _MeetingTimeDialogState extends State<_MeetingTimeDialog> {
  late TimeOfDay _start;
  late TimeOfDay _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = TimeOfDay.now();
    _start = MeetingPresence.parseTimeLabel(widget.initialStart) ??
        TimeOfDay(hour: now.hour, minute: 0);
    _end = MeetingPresence.parseTimeLabel(widget.initialEnd) ??
        TimeOfDay(
          hour: (_start.hour + 1).clamp(0, 23),
          minute: _start.minute,
        );
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _end);
    if (picked != null) setState(() => _end = picked);
  }

  void _save() {
    final startMin = _start.hour * 60 + _start.minute;
    final endMin = _end.hour * 60 + _end.minute;
    if (endMin <= startMin) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }
    Navigator.pop(
      context,
      (
        start: MeetingPresence.formatTimeOfDay(_start),
        end: MeetingPresence.formatTimeOfDay(_end),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = MeetingPresence.formatTimeOfDay(_start);
    final endLabel = MeetingPresence.formatTimeOfDay(_end);
    return AlertDialog(
      title: const Text('Meeting time'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Set when your meeting starts and ends. Callers will hear this window.',
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start'),
            trailing: OutlinedButton(
              onPressed: _pickStart,
              child: Text(startLabel),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('End'),
            trailing: OutlinedButton(
              onPressed: _pickEnd,
              child: Text(endLabel),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
