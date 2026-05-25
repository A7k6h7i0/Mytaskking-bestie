import 'package:flutter/foundation.dart';

class ActiveCallInfo {
  final String? callId;
  final String? meetingSlug;
  final String mode;
  final String title;
  final DateTime startedAt;
  final List<String> participants;

  const ActiveCallInfo({
    required this.callId,
    required this.meetingSlug,
    required this.mode,
    required this.title,
    required this.startedAt,
    this.participants = const [],
  });

  String get route {
    if (meetingSlug != null) return '/meeting/$meetingSlug?mode=$mode';
    return '/call/$callId?mode=$mode';
  }

  ActiveCallInfo copyWith({
    String? title,
    List<String>? participants,
  }) {
    return ActiveCallInfo(
      callId: callId,
      meetingSlug: meetingSlug,
      mode: mode,
      title: title ?? this.title,
      startedAt: startedAt,
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

  static void clear() {
    current.value = null;
  }
}
