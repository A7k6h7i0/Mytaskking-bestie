import 'package:dio/dio.dart';
import 'api_client.dart';

/// MyTaskKing API — typed convenience wrappers around the bare [BestieApi] client.
/// Mirrors the React `services/api.ts` surface so screens look the same on
/// both platforms.
///
/// Every method returns a plain `Map<String, dynamic>` or `List<...>`; we
/// don't impose model classes yet because the dashboard / chat / task shapes
/// evolve quickly. Promote to typed models once the surface freezes.
extension BestieApiExt on BestieApi {
  // ---- dashboard ----
  Future<Map<String, dynamic>> dashboardOverview() => get('/dashboard/overview');

  // ---- channels ----
  Future<List<Map<String, dynamic>>> listChannels() =>
      get('/channels').then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<Map<String, dynamic>> getChannel(String id) => get('/channels/$id');
  Future<Map<String, dynamic>> createChannel({
    required String kind,
    String? name,
    String? description,
    List<String>? memberIds,
  }) =>
      post('/channels', body: {
        'kind': kind,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (memberIds != null) 'memberIds': memberIds,
      });

  // ---- chat ----
  Future<Map<String, dynamic>> listMessages(String channelId, {String? cursor, int limit = 40}) =>
      get('/chat/channels/$channelId/messages', query: {
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      });
  Future<Map<String, dynamic>> sendMessage(
    String channelId, {
    String? body,
    List<String>? attachmentIds,
    String? replyToId,
    String? threadRootId,
    String kind = 'TEXT',
  }) =>
      post('/chat/channels/$channelId/messages', body: {
        if (body != null) 'body': body,
        if (attachmentIds != null) 'attachmentIds': attachmentIds,
        if (replyToId != null) 'replyToId': replyToId,
        if (threadRootId != null) 'threadRootId': threadRootId,
        'kind': kind,
      });
  Future<Map<String, dynamic>> listThread(String rootId, {int limit = 100}) =>
      get('/chat/threads/$rootId', query: {'limit': limit});
  Future<void> markChannelRead(String channelId) async {
    await post('/chat/channels/$channelId/read');
  }
  Future<void> sendReceipts(String channelId, List<String> messageIds, String state) async {
    await post('/chat/channels/$channelId/receipts/bulk',
        body: {'messageIds': messageIds, 'state': state});
  }

  // ---- tasks ----
  Future<Map<String, dynamic>> listTasks({String view = 'kanban', String? status}) =>
      get('/tasks', query: {'view': view, if (status != null) 'status': status});
  Future<Map<String, dynamic>> createTask({
    required String title,
    String? description,
    String? status,
    String? priority,
    List<String>? assigneeIds,
  }) =>
      post('/tasks', body: {
        'title': title,
        if (description != null) 'description': description,
        if (status != null) 'status': status,
        if (priority != null) 'priority': priority,
        if (assigneeIds != null) 'assigneeIds': assigneeIds,
      });
  Future<Map<String, dynamic>> moveTask(String id, {required String status, int? order}) =>
      post('/tasks/$id/move', body: {'status': status, if (order != null) 'order': order});
  Future<Map<String, dynamic>> getTask(String id) => get('/tasks/$id');
  Future<Map<String, dynamic>> acceptTask(String id)   => post('/tasks/$id/accept');
  Future<Map<String, dynamic>> declineTask(String id)  => post('/tasks/$id/decline');
  Future<Map<String, dynamic>> completeTask(String id) => post('/tasks/$id/complete');
  Future<Map<String, dynamic>> leaderboard({int limit = 20, int sinceDays = 30}) =>
      get('/tasks/leaderboard', query: {'limit': limit, 'sinceDays': sinceDays});

  // ---- calls + meetings ----
  Future<Map<String, dynamic>> callHistory({int page = 1, int pageSize = 25}) =>
      get('/calls/history', query: {'page': page, 'pageSize': pageSize});
  Future<Map<String, dynamic>> initiateCall({
    required List<String> participantIds,
    String kind = 'ONE_TO_ONE',
    String? channelId,
  }) =>
      post('/calls/initiate', body: {
        'participantIds': participantIds,
        'kind': kind,
        if (channelId != null) 'channelId': channelId,
      });
  Future<List<Map<String, dynamic>>> listMeetings() =>
      get('/meetings').then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<Map<String, dynamic>> createMeeting({required String name, String mode = 'VIDEO'}) =>
      post('/meetings', body: {'name': name, 'mode': mode});
  Future<Map<String, dynamic>> meetingToken(String slug) => post('/meetings/$slug/token');
  Future<void> endMeeting(String slug) async {
    await post('/meetings/$slug/end');
  }

  // ---- calendar ----
  Future<List<Map<String, dynamic>>> listEvents(DateTime from, DateTime to, {String view = 'week'}) =>
      get('/calendar', query: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'view': view,
      }).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));

  // ---- notifications ----
  Future<Map<String, dynamic>> notificationsGrouped() => get('/notifications/grouped');
  Future<void> markAllNotificationsRead() async {
    await post('/notifications/read-all');
  }
  Future<void> registerDevice({required String token, required String platform}) async {
    await post('/notifications/devices', body: {'token': token, 'platform': platform});
  }

  // ---- presence ----
  Future<void> setPresence({required String status, String? customStatus}) async {
    await dio.put('/presence/me', data: {
      'status': status,
      if (customStatus != null) 'customStatus': customStatus,
    });
  }
  Future<List<Map<String, dynamic>>> presenceFor(List<String> userIds) =>
      get('/presence/users', query: {'userIds': userIds.join(',')})
          .then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));

  // ---- sessions ----
  Future<List<Map<String, dynamic>>> mySessions() =>
      get('/sessions/mine').then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<void> revokeSession(String id) async {
    await dio.delete('/sessions/$id');
  }
  Future<void> signOutEverywhere() async {
    await post('/sessions/mine/sign-out-everywhere');
  }

  // ---- announcements ----
  Future<List<Map<String, dynamic>>> listAnnouncements() =>
      get('/announcements').then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<void> ackAnnouncement(String id) async {
    await post('/announcements/$id/ack');
  }

  // ---- search ----
  Future<Map<String, dynamic>> search(String q, {int perEntity = 6, String? kinds}) =>
      get('/search', query: {
        'q': q,
        'perEntity': perEntity,
        if (kinds != null) 'kinds': kinds,
      });

  // ---- saved items ----
  Future<List<Map<String, dynamic>>> listSaved({String? kind}) =>
      get('/saved', query: {if (kind != null) 'kind': kind})
          .then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<void> saveItem({required String kind, required String refId, String? note}) async {
    await post('/saved', body: {'kind': kind, 'refId': refId, if (note != null) 'note': note});
  }

  // ---- feature flags ----
  Future<Map<String, dynamic>> myFlags() => get('/flags/mine');

  // ---- telecaller ----
  Future<List<Map<String, dynamic>>> listLeads({String? q, String? status}) =>
      get('/telecaller/leads', query: {
        if (q != null) 'q': q,
        if (status != null) 'status': status,
      }).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<Map<String, dynamic>> callLead(String leadId) =>
      post('/telecaller/leads/$leadId/call');

  // ---- employees + clients (admin) ----
  Future<List<Map<String, dynamic>>> listEmployees({String? q}) =>
      get('/employees', query: {if (q != null) 'q': q})
          .then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<List<Map<String, dynamic>>> listClients({String? q}) =>
      get('/clients', query: {if (q != null) 'q': q})
          .then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));

  // ---- chat message lifecycle ----
  /// Edit an existing text message in place. Backend uses PATCH so we hit
  /// dio directly (the convenience helpers only cover get/post).
  Future<Map<String, dynamic>> editMessage(String id, String body) async {
    final r = await dio.patch('/chat/messages/$id', data: {'body': body});
    return r.data as Map<String, dynamic>;
  }

  /// Soft-delete a message for everyone in the channel. Server marks
  /// `deletedAt` and emits `chat.message.deleted`; all clients hide the row.
  Future<void> deleteMessageForEveryone(String id) async {
    await dio.delete('/chat/messages/$id');
  }

  // ---- attendance (workday log: check-in / lunch / check-out) ----
  /// Today's workday log row + computed lunch state. The response also
  /// carries the server config (minRequiredWords, lunch window, etc.) so
  /// a single round trip is enough to render the whole screen.
  Future<Map<String, dynamic>> attendanceToday({String? timezone}) =>
      get('/attendance/today', query: {if (timezone != null) 'timezone': timezone});

  /// Submit the morning plan (≥ 100 words) and clock in.
  Future<Map<String, dynamic>> attendanceCheckIn({required String plan, String? timezone}) =>
      post('/attendance/check-in', body: {
        'plan': plan,
        if (timezone != null) 'timezone': timezone,
      });

  /// Toggle lunch — first call starts the break, second ends it.
  Future<Map<String, dynamic>> attendanceLunch({String? note, String? timezone}) =>
      post('/attendance/lunch', body: {
        if (note != null) 'note': note,
        if (timezone != null) 'timezone': timezone,
      });

  /// Submit the evening report (≥ 100 words) and clock out.
  Future<Map<String, dynamic>> attendanceCheckOut({required String report, String? timezone}) =>
      post('/attendance/check-out', body: {
        'report': report,
        if (timezone != null) 'timezone': timezone,
      });

  // ---- call participant management ----
  /// Adds one or more existing users to an in-flight call.
  /// Mirrors `POST /calls/:id/participants` on the backend.
  Future<Map<String, dynamic>> addCallParticipants(String callId, List<String> userIds) =>
      post('/calls/$callId/participants', body: {'userIds': userIds});

  // ---- file upload (multipart) ----
  /// Uploads [bytes] to `POST /files/upload` and returns the created file
  /// asset (`{ id, url, mimeType, size, ... }`). The chat composer then sends
  /// the message with `attachmentIds: [asset.id]`.
  Future<Map<String, dynamic>> uploadFile({
    required List<int> bytes,
    required String filename,
    String? mimeType,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: mimeType != null ? DioMediaType.parse(mimeType) : null,
      ),
    });
    final r = await dio.post('/files/upload', data: form);
    return Map<String, dynamic>.from(r.data as Map);
  }
}

// BestieApi already exposes `get(path, query:)` and `post(path, body:)`
// directly on the class; the extension above calls into them.
