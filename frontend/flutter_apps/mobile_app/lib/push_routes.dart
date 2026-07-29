/// Maps push / notification payloads to in-app GoRouter paths.
String? routeForPushData(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  if (type == 'call.ended' || type == 'emergency.alert') return null;

  if (type == 'call.active' || type == 'call.incoming') {
    final callId = data['callId']?.toString();
    if (callId == null || callId.isEmpty) return null;
    final mode =
        data['mode']?.toString().toLowerCase() == 'voice' ? 'voice' : 'video';
    return '/call/$callId?mode=$mode';
  }
  if (type == 'meeting.invited') {
    final slug = data['meetingSlug']?.toString();
    if (slug == null || slug.isEmpty) return null;
    final mode =
        data['mode']?.toString().toLowerCase() == 'voice' ? 'voice' : 'video';
    return '/meeting/$slug?mode=$mode';
  }

  final channelId = data['channelId']?.toString();
  if (channelId != null && channelId.isNotEmpty) return '/chat/$channelId';

  final taskId = data['taskId']?.toString();
  if (taskId != null && taskId.isNotEmpty) return '/tasks/$taskId';

  final callId = data['callId']?.toString();
  if (callId != null && callId.isNotEmpty) {
    final mode =
        data['mode']?.toString().toLowerCase() == 'voice' ? 'voice' : 'video';
    return '/call/$callId?mode=$mode';
  }
  final meetingSlug = data['meetingSlug']?.toString();
  if (meetingSlug != null && meetingSlug.isNotEmpty) return '/meetings';

  if (type == 'announcement.new' ||
      data['announcementId']?.toString().isNotEmpty == true) {
    return '/announcements';
  }
  if (type == 'support.ticket' ||
      data['ticketId']?.toString().isNotEmpty == true) {
    return '/support-issues';
  }

  final kind = data['kind']?.toString();
  if (type == 'lead.followup' || kind == 'LEAD_FOLLOWUP') return '/telecaller';
  if (type == 'system.notification' || kind == 'SYSTEM') {
    return '/notifications';
  }
  if (kind != null && kind.isNotEmpty) return '/notifications';
  return null;
}

String? routeForNotificationRecord(Map<String, dynamic> n) {
  final inner = (n['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  final merged = <String, dynamic>{...inner};
  final kind = n['kind']?.toString();
  if (kind != null && kind.isNotEmpty) merged['kind'] = kind;
  return routeForPushData(merged);
}

bool isEmergencyPush(Map<String, dynamic> data) =>
    data['type']?.toString() == 'emergency.alert';

bool isAndroidNativeDeepLinkPush(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  final kind = data['kind']?.toString();
  if (type == 'emergency.alert') return true;
  if (type == 'chat.message' ||
      ((kind == 'CHAT' || kind == 'MENTION') &&
          data['channelId']?.toString().isNotEmpty == true)) {
    return true;
  }
  if (type == 'task.update' ||
      (kind == 'TASK' && data['taskId']?.toString().isNotEmpty == true)) {
    return true;
  }
  if (type == 'lead.followup' || kind == 'LEAD_FOLLOWUP') return true;
  if (type == 'announcement.new' ||
      type == 'support.ticket' ||
      type == 'system.notification' ||
      kind == 'SYSTEM') {
    return true;
  }
  return false;
}
