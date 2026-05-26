import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;

import 'firebase_options.dart';
import 'router.dart';
import 'screens/incoming_call_overlay.dart';
import 'screens/ongoing_call_bar.dart';
import 'state.dart' hide ThemeMode;

const _foregroundNotificationsChannelId = 'foreground_notifications_silent';
final _localNotifications = FlutterLocalNotificationsPlugin();
final _pushNavigationEvents =
    StreamController<Map<String, dynamic>>.broadcast();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await _initializeFirebase();
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = core.BestieAuthStore();
  await auth.load();

  final api = core.BestieApi(baseUrl: kApiBaseUrl, auth: auth);
  final socket = core.BestieSocket(url: kSocketUrl, auth: auth);

  // Best-effort Firebase init. If the platform config files aren't bundled
  // yet (e.g. someone building locally without google-services.json) we
  // log + carry on rather than crash the app at boot.
  if (await _initializeFirebase()) {
    try {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      unawaited(_wirePushNotifications(api, auth));
    } catch (_) {/* push will silently no-op */}
  }

  runApp(ProviderScope(
    overrides: [
      authStoreProvider.overrideWithValue(auth),
      apiProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(socket),
    ],
    child: const BestieApp(),
  ));
}

Future<bool> _initializeFirebase() async {
  if (Firebase.apps.isNotEmpty) return true;
  try {
    final options = MobileFirebaseOptions.currentPlatform;
    if (options != null) {
      await Firebase.initializeApp(options: options);
    } else {
      await Firebase.initializeApp();
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Asks for push permission, fetches the FCM device token, and registers
/// it with the backend so the server can wake the device for incoming
/// calls / mentions when the app is backgrounded or killed. Re-runs on
/// every auth change so a new login binds the device to the new user.
Future<void> _wirePushNotifications(
  core.BestieApi api,
  core.BestieAuthStore auth,
) async {
  final messaging = FirebaseMessaging.instance;
  await _initializeLocalNotifications();
  // iOS requires explicit permission; Android grants by default below 13.
  try {
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: false,
    );
  } catch (_) {
    /* keep going — silent permission denial still allows data msgs */
  }

  Future<void> registerToken(String token) async {
    if (auth.user == null) return;
    final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
    try {
      await api.registerDevice(token: token, platform: platform);
    } catch (_) {}
  }

  Future<void> registerCurrent() async {
    if (auth.user == null) return;
    final token = await _currentFcmToken(messaging);
    if (token == null) return;
    await registerToken(token);
  }

  // Initial register + refresh on token rotation.
  await registerCurrent();
  messaging.onTokenRefresh.listen(registerToken);
  // Re-register whenever the auth store flips (login / logout / refresh).
  auth.changes.listen((user) {
    if (user != null) unawaited(registerCurrent());
  });

  // Foreground messages — the socket already covers most of these but
  // listening lets us reconnect the socket if a push lands while we're
  // in the foreground with a dropped connection.
  FirebaseMessaging.onMessage.listen((message) {
    if (_isIncomingCallPush(message.data)) {
      showIncomingCallFromPush(message.data);
      return;
    }
    unawaited(_showForegroundNotification(message));
  });
}

Future<String?> _currentFcmToken(FirebaseMessaging messaging) async {
  if (Platform.isIOS) {
    for (var i = 0; i < 5; i++) {
      final apns = await messaging.getAPNSToken().catchError((_) => null);
      if (apns != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }
  return messaging.getToken().catchError((_) => null);
}

Future<void> _initializeLocalNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await _localNotifications.initialize(
    const InitializationSettings(android: android, iOS: ios),
    onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      try {
        final raw = jsonDecode(payload);
        if (raw is Map) {
          _pushNavigationEvents.add(Map<String, dynamic>.from(raw));
        }
      } catch (_) {}
    },
  );

  const channel = AndroidNotificationChannel(
    _foregroundNotificationsChannelId,
    'Foreground notifications',
    description:
        'Silent in-app banners for chat, task, mention, and system alerts',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> _showForegroundNotification(RemoteMessage message) async {
  final data = message.data;
  if (_isIncomingCallPush(data)) {
    showIncomingCallFromPush(data);
    return;
  }
  final title = message.notification?.title ??
      data['title']?.toString() ??
      _titleForKind(data['kind']?.toString());
  final body = message.notification?.body ?? data['body']?.toString() ?? '';
  if (title == null || title.isEmpty) return;

  final id = (message.messageId ?? DateTime.now().microsecondsSinceEpoch)
      .hashCode
      .abs();
  await _localNotifications.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _foregroundNotificationsChannelId,
        'Foreground notifications',
        channelDescription:
            'Silent in-app banners for chat, task, mention, and system alerts',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
        enableVibration: false,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      ),
    ),
    payload: jsonEncode(data),
  );
}

bool _isIncomingCallPush(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  return type == 'call.incoming' || type == 'meeting.invited';
}

String? _titleForKind(String? kind) {
  return switch (kind) {
    'CHAT' => 'New message',
    'MENTION' => 'New mention',
    'TASK' => 'Task update',
    'CALL' => 'Call update',
    'LEAD_FOLLOWUP' => 'Lead follow-up',
    _ => 'New notification',
  };
}

class BestieApp extends ConsumerStatefulWidget {
  const BestieApp({super.key});

  @override
  ConsumerState<BestieApp> createState() => _BestieAppState();
}

class _BestieAppState extends ConsumerState<BestieApp> {
  static const _launchIntentChannel = MethodChannel('mytaskking/launch_intent');
  StreamSubscription<RemoteMessage>? _pushTapSub;
  StreamSubscription<Map<String, dynamic>>? _localPushTapSub;

  @override
  void initState() {
    super.initState();
    _wirePushDeepLinks();
  }

  @override
  void dispose() {
    _pushTapSub?.cancel();
    _localPushTapSub?.cancel();
    super.dispose();
  }

  Future<void> _wirePushDeepLinks() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _openPushTarget(initial));
      }
      _pushTapSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_openPushTarget);
    } catch (_) {/* Firebase is optional in local builds */}
    _localPushTapSub = _pushNavigationEvents.stream.listen((data) {
      final route = _routeForPush(data);
      if (route != null) ref.read(routerProvider).go(route);
    });
    try {
      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      final payload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        final raw = jsonDecode(payload);
        if (raw is Map) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final route = _routeForPush(Map<String, dynamic>.from(raw));
            if (route != null) ref.read(routerProvider).go(route);
          });
        }
      }
    } catch (_) {/* Local notification launch payload is optional */}
    try {
      final raw = await _launchIntentChannel.invokeMapMethod<String, dynamic>(
        'getInitialPayload',
      );
      if (raw != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final route = _routeForPush(raw);
          if (route != null) ref.read(routerProvider).go(route);
        });
      }
    } catch (_) {/* Android native call notification bridge is optional */}
  }

  void _openPushTarget(RemoteMessage message) {
    final route = _routeForPush(message.data);
    if (route == null) return;
    ref.read(routerProvider).go(route);
  }

  String? _routeForPush(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type == 'call.incoming') {
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
    if (channelId != null && channelId.isNotEmpty) {
      return '/chat/$channelId';
    }
    final taskId = data['taskId']?.toString();
    if (taskId != null && taskId.isNotEmpty) {
      return '/tasks/$taskId';
    }
    final kind = data['kind']?.toString();
    if (kind == 'LEAD_FOLLOWUP') return '/telecaller';
    if (kind != null && kind.isNotEmpty) return '/notifications';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'MyTaskKing',
      debugShowCheckedModeBanner: false,
      theme: BestieTheme.light(),
      darkTheme: BestieTheme.dark(),
      themeMode: switch (mode) {
        core.ThemeMode.light => ThemeMode.light,
        core.ThemeMode.dark => ThemeMode.dark,
        // Mobile defaults to light when no explicit preference is chosen.
        core.ThemeMode.system => ThemeMode.light,
      },
      routerConfig: ref.watch(routerProvider),
      // The overlay listens for incoming-call socket events globally and
      // covers whatever screen you're on with an Accept/Decline ringer.
      // OngoingCallBar sits above it and surfaces a "tap to return"
      // pill when the user has minimized a live call.
      builder: (ctx, child) => IncomingCallOverlay(
        child: OngoingCallBar(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
