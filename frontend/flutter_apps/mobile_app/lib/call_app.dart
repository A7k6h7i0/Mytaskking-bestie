const String kLocalClientApp = 'mytaskking';

/// Other MyTaskKing-family builds that share the backend but must not ring here.
const _blockedClientApps = {
  'mdl',
  'office_tracking',
  'office_tracking_app',
  'office-traking-app',
};

bool isCallEventForThisApp(Map<String, dynamic>? data) {
  if (data == null) return true;
  final app = data['clientApp']?.toString().trim().toLowerCase();
  if (app == null || app.isEmpty) return true;
  if (_blockedClientApps.contains(app)) return false;
  return app == kLocalClientApp;
}

/// Terminal call events (ended / declined / missed) must reach mobile even when
/// the call was started from web or desktop — otherwise the UI stays on
/// "Reconnecting…" after the other party hangs up.
bool isTerminalCallEventForThisApp(Map<String, dynamic>? data) {
  if (data == null) return true;
  final app = data['clientApp']?.toString().trim().toLowerCase();
  if (app == null || app.isEmpty) return true;
  if (_blockedClientApps.contains(app)) return false;
  return app == kLocalClientApp || app == 'web';
}

bool isIncomingCallPushForThisApp(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  if (type != 'call.incoming' && type != 'meeting.invited') return false;
  return isCallEventForThisApp(data);
}
