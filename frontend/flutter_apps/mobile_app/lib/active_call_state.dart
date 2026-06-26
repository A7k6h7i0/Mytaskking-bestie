import 'package:flutter/foundation.dart';

class ActiveCallInfo {
  final String? callId;
  final String? meetingSlug;
  final String mode;
  final String title;
  /// When the call session began (ringing / joining).
  final DateTime startedAt;
  /// When talk time actually started (callee answered / remote joined).
  final DateTime? connectedAt;
  final List<String> participants;

  const ActiveCallInfo({
    required this.callId,
    required this.meetingSlug,
    required this.mode,
    required this.title,
    required this.startedAt,
    this.connectedAt,
    this.participants = const [],
  });

  String get route {
    if (meetingSlug != null) return '/meeting/$meetingSlug?mode=$mode';
    return '/call/$callId?mode=$mode';
  }

  ActiveCallInfo copyWith({
    String? title,
    List<String>? participants,
    DateTime? connectedAt,
  }) {
    return ActiveCallInfo(
      callId: callId,
      meetingSlug: meetingSlug,
      mode: mode,
      title: title ?? this.title,
      startedAt: startedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      participants: participants ?? this.participants,
    );
  }
}

class ActiveCallState {
  static final current = ValueNotifier<ActiveCallInfo?>(null);

  static void start({
    required String? callId,
    required String? meetingSlug,
    required String mode,
    required String title,
  }) {
    current.value = ActiveCallInfo(
      callId: callId,
      meetingSlug: meetingSlug,
      mode: mode,
      title: title,
      startedAt: DateTime.now(),
    );
  }

  static void update({
    String? title,
    List<String>? participants,
  }) {
    final value = current.value;
    if (value == null) return;
    current.value = value.copyWith(title: title, participants: participants);
  }

  static void markConnected(DateTime at) {
    final value = current.value;
    if (value == null) return;
    if (value.connectedAt != null) return;
    current.value = value.copyWith(connectedAt: at);
  }

  static void clear() {
    current.value = null;
  }
}
