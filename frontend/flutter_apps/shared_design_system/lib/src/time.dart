/// Tiny date-formatting utilities shared across screens.
///
/// Avoids pulling in `intl` for one-off "5m ago" style strings — the chat
/// list, calls history, and notifications all need the same heuristic and
/// the standard library is plenty for it.
class BestieTime {
  BestieTime._();

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  /// "now / 5m / 2h / Yesterday / Tue / Mar 18 / Mar 18 2023" — WhatsApp-
  /// style relative timestamp that auto-tightens older entries. Returns
  /// the empty string if `iso` is null or unparseable.
  static String shortRelative(String? iso) {
    final dt = _toLocal(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 45)  return 'now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m';
    if (diff.inHours < 24 && dt.day == now.day) return '${diff.inHours}h';
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final theirDay = DateTime(dt.year, dt.month, dt.day);
    if (theirDay == yesterday) return 'Yesterday';
    if (diff.inDays < 7) return _days[(dt.weekday - 1) % 7];
    if (dt.year == now.year) return '${_months[dt.month - 1]} ${dt.day}';
    return '${_months[dt.month - 1]} ${dt.day} ${dt.year}';
  }

  /// Parse an ISO timestamp to local time, treating a timezone-less string as
  /// UTC (the backend stores UTC) so times aren't shown off by the user's
  /// offset.
  static DateTime? _toLocal(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    var dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    final hasTz =
        iso.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
    if (!dt.isUtc && !hasTz) {
      dt = DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute,
          dt.second, dt.millisecond, dt.microsecond);
    }
    return dt.toLocal();
  }

  /// HH:MM 12-hour clock — used inside message bubbles and on call events.
  static String clock(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final m = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }
}
