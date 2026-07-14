import 'dart:typed_data';

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
  Future<Map<String, dynamic>> dashboardOverview() =>
      get('/dashboard/overview');

  // ---- channels ----
  Future<List<Map<String, dynamic>>> listChannels() => get(
    '/channels',
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<List<Map<String, dynamic>>> listChannelDirectory({String? q}) => get(
    '/channels/directory',
    query: {if (q != null) 'q': q},
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<Map<String, dynamic>> getChannel(String id) => get('/channels/$id');
  Future<Map<String, dynamic>> createChannel({
    required String kind,
    String? name,
    String? description,
    String? iconUrl,
    List<String>? memberIds,
  }) => post(
    '/channels',
    body: {
      'kind': kind,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (iconUrl != null) 'iconUrl': iconUrl,
      if (memberIds != null) 'memberIds': memberIds,
    },
  );
  Future<Map<String, dynamic>> updateChannel(
    String id, {
    String? name,
    String? iconUrl,
    String? description,
  }) async {
    final r = await dio.patch('/channels/$id', data: {
      if (name != null) 'name': name,
      if (iconUrl != null) 'iconUrl': iconUrl,
      if (description != null) 'description': description,
    });
    return r.data as Map<String, dynamic>;
  }

  // ---- chat ----
  Future<Map<String, dynamic>> listMessages(
    String channelId, {
    String? cursor,
    int limit = 40,
  }) => get(
    '/chat/channels/$channelId/messages',
    query: {if (cursor != null) 'cursor': cursor, 'limit': limit},
  );
  Future<Map<String, dynamic>> sendMessage(
    String channelId, {
    String? body,
    List<String>? attachmentIds,
    String? replyToId,
    String? threadRootId,
    String kind = 'TEXT',
  }) => post(
    '/chat/channels/$channelId/messages',
    body: {
      if (body != null) 'body': body,
      if (attachmentIds != null) 'attachmentIds': attachmentIds,
      if (replyToId != null) 'replyToId': replyToId,
      if (threadRootId != null) 'threadRootId': threadRootId,
      'kind': kind,
    },
  );
  Future<Map<String, dynamic>> listThread(String rootId, {int limit = 100}) =>
      get('/chat/threads/$rootId', query: {'limit': limit});
  Future<void> markChannelRead(String channelId) async {
    await post('/chat/channels/$channelId/read');
  }

  Future<void> sendReceipts(
    String channelId,
    List<String> messageIds,
    String state,
  ) async {
    await post(
      '/chat/channels/$channelId/receipts/bulk',
      body: {'messageIds': messageIds, 'state': state},
    );
  }

  // ---- tasks ----
  Future<Map<String, dynamic>> listTasks({
    String view = 'kanban',
    String? status,
  }) => get(
    '/tasks',
    query: {'view': view, if (status != null) 'status': status},
  );

  /// Fetches OG metadata for a URL (title, description, image, host) so
  /// chat bubbles can render a Slack/Discord-style link preview card.
  /// The backend caches results for ~1 h so repeated unfurls are cheap.
  Future<Map<String, dynamic>> unfurl(String url) =>
      get('/unfurl', query: {'url': url});

  /// AI-drafted task completion report (≤120 words) built from the task +
  /// recent channel chat. Returns `{ draft, provider }`.
  Future<Map<String, dynamic>> draftCompletionReport(String taskId) =>
      post('/tasks/$taskId/draft-report');

  /// AI grammar / clarity correction for composer text. Returns
  /// `{ corrected, changed }`; `corrected` echoes the input when AI is off.
  Future<Map<String, dynamic>> correctText(String text) =>
      post('/chat/ai/correct', body: {'text': text});

  Future<Map<String, dynamic>> listDeletedMessages({
    int page = 1,
    int pageSize = 50,
    String? tenantId,
  }) => get(
    '/chat/deleted-messages',
    query: {
      'page': page,
      'pageSize': pageSize,
      if (tenantId != null) 'tenantId': tenantId,
    },
  );

  Future<Map<String, dynamic>> createTask({
    required String title,
    String? description,
    String? status,
    String? priority,
    List<String>? assigneeIds,
    DateTime? dueAt,
    DateTime? scheduledAt,
  }) => post(
    '/tasks',
    body: {
      'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (assigneeIds != null) 'assigneeIds': assigneeIds,
      if (dueAt != null) 'dueAt': dueAt.toUtc().toIso8601String(),
      if (scheduledAt != null)
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
    },
  );
  Future<Map<String, dynamic>> moveTask(
    String id, {
    required String status,
    int? order,
  }) => post(
    '/tasks/$id/move',
    body: {'status': status, if (order != null) 'order': order},
  );
  Future<Map<String, dynamic>> getTask(String id) => get('/tasks/$id');
  Future<Map<String, dynamic>> acceptTask(String id) =>
      post('/tasks/$id/accept');
  Future<Map<String, dynamic>> declineTask(String id) =>
      post('/tasks/$id/decline');
  Future<Map<String, dynamic>> completeTask(
    String id, {
    required String reportBody,
    required List<String> reportRecipientIds,
  }) => post(
    '/tasks/$id/complete',
    body: {'reportBody': reportBody, 'reportRecipientIds': reportRecipientIds},
  );
  Future<Map<String, dynamic>> listReports() => get('/reports');
  Future<Map<String, dynamic>> updateTaskReport(
    String id, {
    required String body,
    required List<String> recipientIds,
  }) async {
    final r = await dio.patch(
      '/reports/$id',
      data: {'body': body, 'recipientIds': recipientIds},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> respondToTaskReport(
    String id, {
    required String body,
  }) async {
    final r = await dio.put('/reports/$id/response', data: {'body': body});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> leaderboard({
    int limit = 20,
    int sinceDays = 30,
  }) => get(
    '/tasks/leaderboard',
    query: {'limit': limit, 'sinceDays': sinceDays},
  );

  // ---- calls + meetings ----
  Future<Map<String, dynamic>> callHistory({int page = 1, int pageSize = 25}) =>
      get('/calls/history', query: {'page': page, 'pageSize': pageSize});
  Future<Map<String, dynamic>> joinCall(String callId) =>
      post('/calls/$callId/join');
  Future<Map<String, dynamic>> initiateCall({
    required List<String> participantIds,
    String kind = 'ONE_TO_ONE',
    String? channelId,
    String mode = 'VIDEO',
  }) => post(
    '/calls/initiate',
    body: {
      'participantIds': participantIds,
      'kind': kind,
      'mode': mode,
      if (channelId != null) 'channelId': channelId,
    },
  );
  Future<List<Map<String, dynamic>>> listMeetings() => get(
    '/meetings',
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<Map<String, dynamic>> createMeeting({
    required String name,
    String mode = 'VIDEO',
    List<String>? participantIds,
    DateTime? scheduledAt,
  }) => post(
    '/meetings',
    body: {
      'name': name,
      'mode': mode,
      if (participantIds != null && participantIds.isNotEmpty)
        'participantIds': participantIds,
      if (scheduledAt != null)
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
    },
  );
  Future<Map<String, dynamic>> inviteMeetingParticipants(
    String slug,
    List<String> participantIds,
  ) => post(
    '/meetings/$slug/participants',
    body: {'participantIds': participantIds},
  );
  Future<Map<String, dynamic>> meetingToken(String slug) =>
      post('/meetings/$slug/token');
  Future<void> endMeeting(String slug) async {
    await post('/meetings/$slug/end');
  }

  // ---- calendar ----
  Future<List<Map<String, dynamic>>> listEvents(
    DateTime from,
    DateTime to, {
    String view = 'week',
  }) => get(
    '/calendar',
    query: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
      'view': view,
    },
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));

  // ---- notifications ----
  Future<Map<String, dynamic>> notificationsGrouped({int pageSize = 100}) =>
      get('/notifications/grouped', query: {'pageSize': pageSize});
  Future<void> markNotificationRead(String id) async {
    await post('/notifications/$id/read');
  }
  Future<void> markAllNotificationsRead() async {
    await post('/notifications/read-all');
  }

  Future<void> registerDevice({
    required String token,
    required String platform,
  }) async {
    await post(
      '/notifications/devices',
      body: {'token': token, 'platform': platform},
    );
  }

  // ---- presence ----
  Future<void> setPresence({
    required String status,
    String? customStatus,
  }) async {
    await dio.put(
      '/presence/me',
      data: {'status': status, 'customStatus': customStatus},
    );
  }

  Future<List<Map<String, dynamic>>> presenceFor(List<String> userIds) => get(
    '/presence/users',
    query: {'userIds': userIds.join(',')},
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));

  // ---- sessions ----
  Future<List<Map<String, dynamic>>> mySessions() => get(
    '/sessions/mine',
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<void> revokeSession(String id) async {
    await dio.delete('/sessions/$id');
  }

  Future<void> signOutEverywhere({String? exceptSessionId}) async {
    await post('/sessions/mine/sign-out-everywhere', body: {
      if (exceptSessionId != null && exceptSessionId.isNotEmpty)
        'exceptSessionId': exceptSessionId,
    });
  }

  Future<Map<String, dynamic>> sessionActivity({
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 100,
  }) => get(
    '/sessions/activity',
    query: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      'page': page,
      'pageSize': pageSize,
    },
  );

  Future<Uint8List> sessionSelfieBytes(String sessionId) async {
    final r = await dio.get(
      '/sessions/$sessionId/selfie',
      options: Options(responseType: ResponseType.bytes),
    );
    final data = r.data;
    if (data == null) return Uint8List(0);
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    return Uint8List(0);
  }

  // ---- AI review (telecaller voice analysis) ----
  Future<List<Map<String, dynamic>>> aiReviewRecordings() => get(
    '/ai-review/recordings',
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));

  Future<Map<String, dynamic>> submitAiReviewAnalyse(String callId) =>
      post('/ai-review/analyse', body: {'callId': callId});

  Future<Map<String, dynamic>> getAiReviewJob(String jobId) =>
      get('/ai-review/job/$jobId');

  // ---- announcements ----
  Future<List<Map<String, dynamic>>> listAnnouncements() => get(
    '/announcements',
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<void> ackAnnouncement(String id) async {
    await post('/announcements/$id/ack');
  }

  Future<Map<String, dynamic>> createAnnouncement({
    required String title,
    required String body,
    String scope = 'GLOBAL',
    String priority = 'INFO',
    String? channelId,
    bool notify = true,
    bool pinned = true,
  }) =>
      post(
        '/announcements',
        body: {
          'title': title,
          'body': body,
          'scope': scope,
          'priority': priority,
          if (channelId != null && channelId.isNotEmpty) 'channelId': channelId,
          'notify': notify,
          'pinned': pinned,
        },
      );

  // ---- search ----
  Future<Map<String, dynamic>> search(
    String q, {
    int perEntity = 6,
    String? kinds,
  }) => get(
    '/search',
    query: {'q': q, 'perEntity': perEntity, if (kinds != null) 'kinds': kinds},
  );

  // ---- saved items ----
  Future<List<Map<String, dynamic>>> listSaved({String? kind}) => get(
    '/saved',
    query: {if (kind != null) 'kind': kind},
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<void> saveItem({
    required String kind,
    required String refId,
    String? note,
  }) async {
    await post(
      '/saved',
      body: {'kind': kind, 'refId': refId, if (note != null) 'note': note},
    );
  }

  // ---- feature flags ----
  Future<Map<String, dynamic>> myFlags() => get('/flags/mine');

  // ---- telecaller ----
  Future<List<Map<String, dynamic>>> listLeads({
    String? q,
    String? status,
    String? assignedDate,
  }) =>
      get(
        '/telecaller/leads',
        query: {
          if (q != null) 'q': q,
          if (status != null) 'status': status,
          if (assignedDate != null) 'assignedDate': assignedDate,
        },
      ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<Map<String, dynamic>> createLead(Map<String, dynamic> data) =>
      post('/telecaller/leads', body: data);
  Future<Map<String, dynamic>> updateLeadStatus(String leadId, String status) async {
    final r = await dio.patch('/telecaller/leads/$leadId', data: {'status': status});
    return r.data as Map<String, dynamic>;
  }
  Future<Map<String, dynamic>> callLead(String leadId, {String mode = 'EXOTEL'}) =>
      post('/telecaller/leads/$leadId/call', body: {'mode': mode});
  Future<Map<String, dynamic>> updateTelecallerCallOutcome(
    String callId, {
    required String outcome,
    String? notes,
  }) async {
    final r = await dio.patch(
      '/telecaller/calls/$callId/outcome',
      data: {'outcome': outcome, if (notes != null) 'notes': notes},
    );
    return r.data as Map<String, dynamic>;
  }
  Future<Map<String, dynamic>> attachTelecallerCallRecording(
    String callId, {
    String? fileId,
    String? url,
  }) =>
      post(
        '/telecaller/calls/$callId/recording',
        body: {
          if (fileId != null) 'fileId': fileId,
          if (url != null) 'url': url,
        },
      );
  Future<Map<String, dynamic>> bulkDistributeLeads(
    Map<String, dynamic> data,
  ) =>
      post('/telecaller/leads/bulk-distribute', body: data);
  Future<Map<String, dynamic>> bulkDistributeLeadsFile({
    required List<int> bytes,
    required String filename,
    required List<String> telecallerIds,
    required String startDate,
    required String endDate,
    int recordsPerTelecallerPerDay = 100,
    String? source,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'telecallerIds': telecallerIds.join(','),
      'startDate': startDate,
      'endDate': endDate,
      'recordsPerTelecallerPerDay': recordsPerTelecallerPerDay.toString(),
      if (source != null) 'source': source,
    });
    final r = await dio.post('/telecaller/leads/bulk-distribute-file', data: form);
    return r.data as Map<String, dynamic>;
  }

  // ---- employees + clients (admin) ----
  Future<List<Map<String, dynamic>>> listEmployees({
    String? q,
    String? role,
    int? pageSize,
    bool? forChat,
  }) => get(
    '/employees',
    query: {
      if (q != null) 'q': q,
      if (role != null) 'role': role,
      if (pageSize != null) 'pageSize': pageSize,
      if (forChat == true) 'forChat': 'true',
    },
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> data) =>
      post('/employees', body: data);
  Future<Map<String, dynamic>> updateEmployee(
    String id,
    Map<String, dynamic> data,
  ) async {
    final r = await dio.patch('/employees/$id', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<void> deleteEmployee(String id) async {
    await dio.delete('/employees/$id');
  }

  Future<Map<String, dynamic>> listRecordings({
    int page = 1,
    int pageSize = 50,
    String scope = 'org',
  }) => get(
    '/recordings',
    query: {'page': page, 'pageSize': pageSize, 'scope': scope},
  );

  // ---- platform organisations (SUPER_ADMIN) ----
  Future<List<Map<String, dynamic>>> listTenants() => get(
    '/tenants',
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));

  Future<Map<String, dynamic>> createTenant(Map<String, dynamic> data) =>
      post('/tenants', body: data);

  Future<Map<String, dynamic>> registerOrganization(Map<String, dynamic> data) =>
      post('/tenants/register', body: data);

  Future<Map<String, dynamic>> updateTenant(
    String id,
    Map<String, dynamic> data,
  ) async {
    final r = await dio.patch('/tenants/$id', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<void> deleteRecording(String source, String id) async {
    await dio.delete('/recordings/${source.toUpperCase()}/$id');
  }

  Future<Map<String, dynamic>> updateMyProfile(Map<String, dynamic> data) async {
    final r = await dio.patch('/auth/me', data: data);
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<Map<String, dynamic>> updateMyAvatar(String avatarUrl) =>
      updateMyProfile({'avatarUrl': avatarUrl});

  Future<Map<String, dynamic>> clearMyAvatar() =>
      updateMyProfile({'avatarUrl': ''});

  /// Resolves a downloadable URL for a file asset (signed URL for R2, direct for Cloudinary).
  Future<String> getFileDownloadUrl(String fileId) async {
    final r = await get('/files/$fileId/signed-url');
    final url = r['url']?.toString() ?? '';
    if (url.isEmpty) throw 'File has no download URL';
    return url;
  }

  Future<List<Map<String, dynamic>>> listClients({String? q}) => get(
    '/clients',
    query: {if (q != null) 'q': q},
  ).then((r) => List<Map<String, dynamic>>.from(r['items'] ?? const []));
  Future<Map<String, dynamic>> createClient(Map<String, dynamic> data) =>
      post('/clients', body: data);

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

  /// React to a message with an emoji. Idempotent — re-acting with the same
  /// emoji is a no-op. The reaction broadcasts to the channel room.
  Future<Map<String, dynamic>> reactMessage(String id, String emoji) =>
      post('/chat/messages/$id/react', body: {'emoji': emoji});

  /// Remove your previous reaction with the same emoji.
  Future<void> unreactMessage(String id, String emoji) async {
    await post('/chat/messages/$id/unreact', body: {'emoji': emoji});
  }

  Future<Map<String, dynamic>> pinMessage(String id) =>
      post('/chat/messages/$id/pin');
  Future<Map<String, dynamic>> unpinMessage(String id) =>
      post('/chat/messages/$id/unpin');

  // ---- channel admin (members + policy) ----
  /// Add one or more members to an existing channel. Server enforces
  /// per-channel invite policy.
  Future<Map<String, dynamic>> addChannelMembers(
    String channelId,
    List<String> memberIds,
  ) => post('/channels/$channelId/members', body: {'memberIds': memberIds});

  /// Remove a single member. Admin / channel-owner only.
  Future<void> removeChannelMember(String channelId, String memberId) async {
    await dio.delete('/channels/$channelId/members/$memberId');
  }

  Future<Map<String, dynamic>> pinChannel(String id) =>
      post('/channels/$id/pin');
  Future<Map<String, dynamic>> unpinChannel(String id) =>
      post('/channels/$id/unpin');
  Future<Map<String, dynamic>> archiveChannel(String id) =>
      post('/channels/$id/archive');
  Future<Map<String, dynamic>> unarchiveChannel(String id) =>
      post('/channels/$id/unarchive');

  // ---- task lifecycle (update / delete / comments / subtasks) ----
  /// Update any field on a task — title, description, status, priority,
  /// due date, or assignees. Server returns the refreshed row.
  Future<Map<String, dynamic>> updateTask(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final r = await dio.patch('/tasks/$id', data: patch);
    return r.data as Map<String, dynamic>;
  }

  Future<void> deleteTask(String id) async {
    await dio.delete('/tasks/$id');
  }

  Future<Map<String, dynamic>> addTaskComment(String taskId, String body) =>
      post('/tasks/$taskId/comments', body: {'body': body});

  Future<Map<String, dynamic>> addSubtask(String taskId, String title) =>
      post('/tasks/$taskId/subtasks', body: {'title': title});

  Future<Map<String, dynamic>> toggleSubtask(
    String subtaskId,
    bool done,
  ) async {
    final r = await dio.patch(
      '/tasks/subtasks/$subtaskId',
      data: {'done': done},
    );
    return r.data as Map<String, dynamic>;
  }

  // ---- calendar event CRUD ----
  Future<Map<String, dynamic>> createCalendarEvent({
    required String title,
    String? description,
    required DateTime startsAt,
    DateTime? endsAt,
    String kind = 'event',
    List<String>? attendeeIds,
  }) => post(
    '/calendar',
    body: {
      'title': title,
      if (description != null) 'description': description,
      'startsAt': startsAt.toUtc().toIso8601String(),
      if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
      'kind': kind,
      if (attendeeIds != null) 'attendeeIds': attendeeIds,
    },
  );

  Future<Map<String, dynamic>> updateCalendarEvent(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final r = await dio.patch('/calendar/$id', data: patch);
    return r.data as Map<String, dynamic>;
  }

  Future<void> deleteCalendarEvent(String id) async {
    await dio.delete('/calendar/$id');
  }

  /// RSVP to an event you've been invited to.
  Future<Map<String, dynamic>> rsvpCalendarEvent(String id, String status) =>
      post('/calendar/$id/rsvp', body: {'status': status});

  /// Unregister an FCM token (call this on logout so the device stops
  /// receiving pushes meant for the previous user).
  Future<void> unregisterDevice(String token) async {
    await dio.delete('/notifications/devices/$token');
  }

  Future<Map<String, dynamic>> notificationPreferences() =>
      get('/notifications/preferences');

  Future<Map<String, dynamic>> updateNotificationPreferences(
    Map<String, dynamic> patch,
  ) async {
    final r = await dio.put('/notifications/preferences', data: patch);
    return r.data as Map<String, dynamic>;
  }

  // ---- saved items: unsave + list one kind ----
  Future<void> unsaveItem({required String kind, required String refId}) async {
    await dio.delete('/saved', data: {'kind': kind, 'refId': refId});
  }

  // ---- audit log ----
  /// Recent activity feed — admin scope by default, scoped to the user
  /// otherwise. Query: actor, entity, kind, cursor, limit.
  Future<Map<String, dynamic>> auditLog({Map<String, dynamic>? query}) =>
      get('/audit', query: query);

  // ---- analytics ----
  /// Analytics is partitioned into named slices on the backend:
  /// `productivity`, `tasks`, `telecaller`, `workspace`, `client-engagement`,
  /// `calls`, `attendance`. Pass the slice name and any query knobs (most
  /// take `from`, `to`, sometimes `userId`).
  Future<Map<String, dynamic>> analytics(
    String slice, {
    Map<String, dynamic>? query,
  }) => get('/analytics/$slice', query: query);

  // ---- permissions + workspace + settings ----
  /// "What can I do?" — list of permission keys the current user holds.
  Future<Map<String, dynamic>> myPermissions() => get('/permissions/mine');

  Future<Map<String, dynamic>> workspaceThemes() => get('/workspace/themes');
  Future<Map<String, dynamic>> workspaceWidgets() => get('/workspace/widgets');

  /// Replace the user's dashboard widget set in one call.
  Future<Map<String, dynamic>> setWorkspaceWidgets(
    List<Map<String, dynamic>> widgets,
  ) async {
    final r = await dio.put('/workspace/widgets', data: {'widgets': widgets});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> settingsScope({String? scope}) =>
      get('/settings', query: {if (scope != null) 'scope': scope});

  Future<Map<String, dynamic>> setSetting({
    required String scope,
    required String key,
    required Object value,
  }) async {
    final r = await dio.put('/settings/$scope/$key', data: {'value': value});
    return r.data as Map<String, dynamic>;
  }

  // ---- files: signed-url + download + delete + access control ----
  Future<Map<String, dynamic>> requestSignedUrl({
    required String filename,
    required String mimeType,
    int? sizeBytes,
  }) => post(
    '/files/signed-url',
    body: {
      'filename': filename,
      'mimeType': mimeType,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
    },
  );

  Future<void> deleteFile(String id) async {
    await dio.delete('/files/$id');
  }

  Future<Map<String, dynamic>> setFileAccessControl(
    String id, {
    required bool allowDownload,
  }) =>
      post('/files/$id/access-control', body: {'allowDownload': allowDownload});

  // ---- meetings: lobby + guest approval ----
  Future<void> endCall(String callId) async {
    await post('/calls/$callId/leave');
  }

  /// Approve a pending guest request (host or admin only).
  Future<Map<String, dynamic>> approveMeetingGuest(
    String slug,
    String requestId,
  ) => post('/meetings/$slug/guest-requests/$requestId/approve');

  Future<Map<String, dynamic>> rejectMeetingGuest(
    String slug,
    String requestId,
  ) => post('/meetings/$slug/guest-requests/$requestId/reject');

  // ---- attendance (workday log: check-in / lunch / check-out) ----
  /// Today's workday log row + computed lunch state. The response also
  /// carries the server config (minRequiredWords, lunch window, etc.) so
  /// a single round trip is enough to render the whole screen.
  Future<Map<String, dynamic>> attendanceToday({String? timezone}) => get(
    '/attendance/today',
    query: {if (timezone != null) 'timezone': timezone},
  );

  /// Submit the morning plan (≥ 10 words) and clock in.
  Future<Map<String, dynamic>> attendanceCheckIn({
    required String plan,
    String? timezone,
  }) => post(
    '/attendance/check-in',
    body: {'plan': plan, if (timezone != null) 'timezone': timezone},
  );

  /// Toggle lunch — first call starts the break, second ends it.
  Future<Map<String, dynamic>> attendanceLunch({
    String? note,
    String? timezone,
  }) => post(
    '/attendance/lunch',
    body: {
      if (note != null) 'note': note,
      if (timezone != null) 'timezone': timezone,
    },
  );

  /// Submit the evening report (≥ 10 words) and clock out.
  Future<Map<String, dynamic>> attendanceCheckOut({
    required String report,
    String? timezone,
  }) => post(
    '/attendance/check-out',
    body: {'report': report, if (timezone != null) 'timezone': timezone},
  );

  /// Toggle a short break — first call starts it, second ends it. The
  /// backend auto-notifies the user's supervisor on each transition.
  Future<Map<String, dynamic>> attendanceBreak({String? timezone}) => post(
    '/attendance/break',
    body: {if (timezone != null) 'timezone': timezone},
  );

  /// Range of workday entries between two ISO dates, used by the streak
  /// counter to walk back from today and count consecutive check-ins.
  Future<Map<String, dynamic>> attendanceRange({
    required DateTime from,
    required DateTime to,
    String? timezone,
  }) => get(
    '/attendance/range',
    query: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
      if (timezone != null) 'timezone': timezone,
    },
  );

  // ---- desktop work activity ----
  Future<Map<String, dynamic>> workActivityState() =>
      get('/work-activity/me/state');

  Future<Map<String, dynamic>> createWorkActivityClip({
    String? fileId,
    String? clipUrl,
    String? note,
    String status = 'WORKING',
    required String platform,
    String? deviceLabel,
    int durationSeconds = 5,
    DateTime? captureStartedAt,
    DateTime? captureEndedAt,
    DateTime? promptShownAt,
    DateTime? promptRespondedAt,
  }) => post(
    '/work-activity/clips',
    body: {
      if (fileId != null) 'fileId': fileId,
      if (clipUrl != null) 'clipUrl': clipUrl,
      if (note != null) 'note': note,
      'status': status,
      'platform': platform,
      if (deviceLabel != null) 'deviceLabel': deviceLabel,
      'durationSeconds': durationSeconds,
      if (captureStartedAt != null)
        'captureStartedAt': captureStartedAt.toUtc().toIso8601String(),
      if (captureEndedAt != null)
        'captureEndedAt': captureEndedAt.toUtc().toIso8601String(),
      if (promptShownAt != null)
        'promptShownAt': promptShownAt.toUtc().toIso8601String(),
      if (promptRespondedAt != null)
        'promptRespondedAt': promptRespondedAt.toUtc().toIso8601String(),
    },
  );

  Future<Map<String, dynamic>> workActivitySummary({
    String? date,
    String? timezone,
  }) => get(
    '/work-activity/summary',
    query: {
      if (date != null) 'date': date,
      if (timezone != null) 'timezone': timezone,
    },
  );

  Future<Map<String, dynamic>> workActivityClips({
    required String userId,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) => get(
    '/work-activity/users/$userId/clips',
    query: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      'page': page,
      'pageSize': pageSize,
    },
  );

  // ---- call participant management ----
  /// Adds one or more existing users to an in-flight call.
  /// Mirrors `POST /calls/:id/participants` on the backend.
  Future<Map<String, dynamic>> addCallParticipants(
    String callId,
    List<String> userIds, {
    String? mode,
  }) => post(
    '/calls/$callId/participants',
    body: {'userIds': userIds, if (mode != null) 'mode': mode},
  );

  // ---- file upload (multipart) ----
  /// Uploads [bytes] to `POST /files/upload` and returns the created file
  /// asset (`{ id, url, mimeType, size, ... }`). The chat composer then sends
  /// the message with `attachmentIds: [asset.id]`.
  Future<Map<String, dynamic>> uploadFile({
    required List<int> bytes,
    required String filename,
    String? mimeType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: mimeType != null ? DioMediaType.parse(mimeType) : null,
      ),
    });
    final r = await dio.post(
      '/files/upload',
      data: form,
      onSendProgress: onProgress,
    );
    return Map<String, dynamic>.from(r.data as Map);
  }
}

// BestieApi already exposes `get(path, query:)` and `post(path, body:)`
// directly on the class; the extension above calls into them.
