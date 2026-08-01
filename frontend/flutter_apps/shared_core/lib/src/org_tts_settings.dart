import 'meeting_presence.dart';

/// Org-wide caller voice prompts stored in workspace settings (calls scope).
class OrgTtsSettings {
  OrgTtsSettings({
    required this.voiceGender,
    required this.templates,
  });

  final String voiceGender;
  final Map<String, String> templates;

  static const voiceGenderKey = 'ttsVoiceGender';

  static const templateKeys = <String, String>{
    'ttsOnAnotherCall': 'Busy on another call',
    'ttsOnAnotherCallWaiting': 'Waiting on another call',
    'ttsCurrentlyOnAnotherCall': 'Currently on another call',
    'ttsCurrentlyOnAnotherCallLeaveMessage':
        'On another call (leave message)',
    'ttsMeeting': 'In a meeting (with times)',
    'ttsMeetingFallback': 'In a meeting (no times)',
    'ttsLunch': 'At lunch',
    'ttsLeave': 'On leave',
    'ttsBusy': 'Busy',
    'ttsAway': 'Away',
    'ttsGenericUnavailable': 'Other unavailable status',
    'ttsIncomingWaitingCall': 'Incoming while you are on a call',
  };

  static const defaultTemplates = <String, String>{
    'ttsOnAnotherCall':
        '{name} is busy with another call. Please call again later.',
    'ttsOnAnotherCallWaiting':
        '{name} is busy on another call. Waiting for them to respond.',
    'ttsCurrentlyOnAnotherCall':
        '{name} is currently on another call. Please call again later.',
    'ttsCurrentlyOnAnotherCallLeaveMessage':
        '{name} is currently on another call. Please leave a message.',
    'ttsMeeting': 'Sorry {name} is in a meeting from {start} to {end}',
    'ttsMeetingFallback': 'Sorry {name} is in a meeting',
    'ttsLunch': '{name} is at lunch. Please leave a message.',
    'ttsLeave': '{name} is on leave. Please leave a message.',
    'ttsBusy': '{name} is busy. Please leave a message.',
    'ttsAway': '{name} is away. Please leave a message.',
    'ttsGenericUnavailable': '{name} is {status}. Please leave a message.',
    'ttsIncomingWaitingCall':
        '{caller} is calling while you are on another call. Accept to add them, or reject.',
  };

  static OrgTtsSettings get defaults => OrgTtsSettings(
        voiceGender: 'female',
        templates: Map<String, String>.from(defaultTemplates),
      );

  factory OrgTtsSettings.fromCallsMap(Map<String, dynamic>? calls) {
    if (calls == null || calls.isEmpty) return defaults;
    final gender =
        (calls[voiceGenderKey] ?? 'female').toString().toLowerCase();
    final templates = Map<String, String>.from(defaultTemplates);
    for (final key in templateKeys.keys) {
      final raw = calls[key]?.toString().trim();
      if (raw != null && raw.isNotEmpty) templates[key] = raw;
    }
    return OrgTtsSettings(
      voiceGender: gender == 'male' ? 'male' : 'female',
      templates: templates,
    );
  }

  String render(String storageKey, Map<String, String> vars) {
    var text = templates[storageKey] ?? defaultTemplates[storageKey] ?? '';
    vars.forEach((key, value) {
      text = text.replaceAll('{$key}', value);
    });
    return text.trim();
  }

  String unavailableMessage(String name, Map<String, dynamic> presence) {
    final status = (presence['status'] ?? 'BUSY').toString();
    final custom = (presence['customStatus'] ?? '').toString().trim();
    final callBusy = status == 'ON_CALL' ||
        custom.toLowerCase().contains('another call');

    if (callBusy) {
      return render('ttsCurrentlyOnAnotherCall', {'name': name});
    }
    if (MeetingPresence.isMeetingMap(presence)) {
      final times = MeetingPresence.decodeTimes(custom);
      if (times != null) {
        return render('ttsMeeting', {
          'name': name,
          'start': times.start,
          'end': times.end,
        });
      }
      return render('ttsMeetingFallback', {'name': name});
    }
    if (custom.toLowerCase().contains('lunch')) {
      return render('ttsLunch', {'name': name});
    }
    if (custom.toLowerCase().contains('leave')) {
      return render('ttsLeave', {'name': name});
    }
    if (status == 'INVISIBLE') {
      return render('ttsAway', {'name': name});
    }
    if (status == 'BUSY') {
      return render('ttsBusy', {'name': name});
    }
    final statusLabel =
        custom.isNotEmpty ? custom : status.replaceAll('_', ' ');
    return render('ttsGenericUnavailable', {
      'name': name,
      'status': statusLabel,
    });
  }

  String chatListBlockedMessage(String name, Map<String, dynamic> presence) {
    final status = (presence['status'] ?? '').toString();
    final custom = (presence['customStatus'] ?? '').toString();
    if (status == 'ON_CALL' || custom.toLowerCase().contains('another call')) {
      return render('ttsOnAnotherCall', {'name': name});
    }
    return unavailableMessage(name, presence);
  }

  String chatListWaitingMessage(String name) =>
      render('ttsOnAnotherCallWaiting', {'name': name});

  String callBusyEventMessage(String name) =>
      render('ttsCurrentlyOnAnotherCallLeaveMessage', {'name': name});

  String incomingWaitingCallMessage(String caller) =>
      render('ttsIncomingWaitingCall', {'caller': caller});
}
