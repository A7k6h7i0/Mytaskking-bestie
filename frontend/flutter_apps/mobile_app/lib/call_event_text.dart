/// Parses and personalises CALL_EVENT message bodies (missed / ended / etc.).
class CallEventText {
  CallEventText._();

  static ({String display, String? callId, String? status, String? initiatorId})
      parseBody(String raw) {
    final marker = raw.lastIndexOf('|call:');
    if (marker < 0) {
      return (display: raw, callId: null, status: null, initiatorId: null);
    }
    final display = raw.substring(0, marker);
    final tail = raw.substring(marker + 6);
    final parts = tail.split(':');
    return (
      display: display,
      callId: parts.isNotEmpty ? parts[0] : null,
      status: parts.length > 1 ? parts[1] : null,
      initiatorId: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
    );
  }

  /// WhatsApp-style: callee sees "Missed call from Priya", caller sees "No answer".
  static String displayForViewer({
    required String rawDisplay,
    required String? status,
    required String? initiatorId,
    required String? viewerId,
  }) {
    if (status != 'MISSED' || initiatorId == null || viewerId == null) {
      return rawDisplay;
    }
    if (viewerId != initiatorId) return rawDisplay;
    final time = _extractTrailingTime(rawDisplay);
    return time == null ? '📞 No answer' : '📞 No answer · $time';
  }

  static String previewForViewer({
    required String rawBody,
    required String? viewerId,
    String? authorIdFallback,
  }) {
    final parsed = parseBody(rawBody);
    final text = displayForViewer(
      rawDisplay: parsed.display,
      status: parsed.status,
      initiatorId: parsed.initiatorId ?? authorIdFallback,
      viewerId: viewerId,
    );
    return text.replaceFirst(RegExp(r'^📞\s*'), '');
  }

  static String? _extractTrailingTime(String body) {
    final dot = body.lastIndexOf('·');
    if (dot < 0) return null;
    return body.substring(dot + 1).trim();
  }
}
