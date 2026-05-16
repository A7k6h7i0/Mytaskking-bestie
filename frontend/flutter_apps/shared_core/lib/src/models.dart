class BestieUser {
  final String id;
  final String userId;
  final String name;
  final String role;
  final bool isClient;
  final String? avatarUrl;
  final String? clientCompany;
  final DateTime? accessEndsAt;
  final String status;

  BestieUser({
    required this.id,
    required this.userId,
    required this.name,
    required this.role,
    required this.isClient,
    this.avatarUrl,
    this.clientCompany,
    this.accessEndsAt,
    required this.status,
  });

  factory BestieUser.fromJson(Map<String, dynamic> j) => BestieUser(
        id: j['id'] as String,
        userId: j['userId'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        isClient: (j['isClient'] as bool?) ?? false,
        avatarUrl: j['avatarUrl'] as String?,
        clientCompany: j['clientCompany'] as String?,
        accessEndsAt: j['accessEndsAt'] != null ? DateTime.parse(j['accessEndsAt']) : null,
        status: (j['status'] as String?) ?? 'ACTIVE',
      );
}

class BestieMessage {
  final String id;
  final String channelId;
  final String? body;
  final String authorName;
  final bool authorIsClient;
  final DateTime createdAt;

  BestieMessage({
    required this.id,
    required this.channelId,
    required this.body,
    required this.authorName,
    required this.authorIsClient,
    required this.createdAt,
  });

  factory BestieMessage.fromJson(Map<String, dynamic> j) => BestieMessage(
        id: j['id'],
        channelId: j['channelId'],
        body: j['body'],
        authorName: j['author']?['name'] ?? '?',
        authorIsClient: (j['author']?['isClient'] as bool?) ?? false,
        createdAt: DateTime.parse(j['createdAt']),
      );
}
