library firebase_messaging;

class RemoteNotification {
  final String? title;
  final String? body;

  const RemoteNotification({this.title, this.body});
}

class RemoteMessage {
  final String? messageId;
  final Map<String, dynamic> data;
  final RemoteNotification? notification;

  const RemoteMessage({
    this.messageId,
    this.data = const <String, dynamic>{},
    this.notification,
  });
}

class NotificationSettings {
  const NotificationSettings();
}

typedef BackgroundMessageHandler = Future<void> Function(RemoteMessage message);

class FirebaseMessaging {
  FirebaseMessaging._();

  static final FirebaseMessaging instance = FirebaseMessaging._();
  static const Stream<RemoteMessage> onMessage = Stream<RemoteMessage>.empty();
  static const Stream<RemoteMessage> onMessageOpenedApp =
      Stream<RemoteMessage>.empty();

  static void onBackgroundMessage(BackgroundMessageHandler handler) {}

  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  }) async {
    return const NotificationSettings();
  }

  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  }) async {}

  Future<String?> getToken() async => null;

  Future<String?> getAPNSToken() async => null;

  Future<RemoteMessage?> getInitialMessage() async => null;
}
