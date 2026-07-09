import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'call_app.dart';
import 'router.dart';
import 'screens/call_screen.dart';
import 'screens/connectivity_banner.dart';
import 'screens/incoming_call_overlay.dart';
import 'screens/ongoing_call_bar.dart';
import 'state.dart' hide ThemeMode;
import 'telecaller_recording_setup.dart';

const _foregroundNotificationsChannelId = 'foreground_notifications_silent';
const _notificationReplyActionId = 'bestie.reply';
const _notificationMarkReadActionId = 'bestie.mark_read';
const _notificationSnoozeActionId = 'bestie.snooze_1h';
final _localNotifications = FlutterLocalNotificationsPlugin();
final _pushNavigationEvents =
    StreamController<Map<String, dynamic>>.broadcast();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await _initializeFirebase();
  } catch (_) {}
  // Chat / mention pushes are sent data-only so we can attach reply actions.
  // Android does NOT auto-display data-only messages, so without this the
  // notification never reaches the tray while the app is backgrounded — and
  // there's nothing for the user to tap to open the conversation. Render it
  // ourselves here, carrying the payload so a tap deep-links correctly.
  // Skip messages that already carry a `notification` block (the system tray
  // shows those automatically — rendering again would double-notify) and
  // calls, which have their own native incoming-call path.
  try {
    if (message.notification != null) return;
    if (_isIncomingCallPush(message.data)) return;
    await _initializeLocalNotifications();
    await _showForegroundNotification(message);
  } catch (_) {/* best-effort */}
}

@pragma('vm:entry-point')
void _notificationTapBackground(NotificationResponse response) {
  unawaited(_handleLocalNotificationResponse(response, navigateInApp: false));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = core.BestieAuthStore();
  await auth.load();
  await TelecallerRecordingSetup.load();

  assert(() {
    debugPrint('[MyTaskKing] API  → $kApiBaseUrl');
    debugPrint('[MyTaskKing] Socket → $kSocketUrl');
    return true;
  }());

  final api = core.BestieApi(
    baseUrl: kApiBaseUrl,
    auth: auth,
    userAgent:
        'MyTaskKing-Mobile/${Platform.operatingSystem}/${Platform.operatingSystemVersion}',
  );
  final socket = core.BestieSocket(
    url: kSocketUrl,
    auth: auth,
    clientApp: 'mytaskking',
  );

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
    final type = message.data['type']?.toString();
    if (type == 'call.ended') {
      showIncomingCallFromPush(Map<String, dynamic>.from(message.data));
      return;
    }
    if (_isIncomingCallPush(message.data)) {
      showIncomingCallFromPush(message.data);
      return;
    }
    // Realtime already shows the in-app banner while foregrounded. Rendering
    // the same FCM payload locally here produced two alerts for one message.
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
  const android = AndroidInitializationSettings('@drawable/ic_stat_mytaskking');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await _localNotifications.initialize(
    const InitializationSettings(android: android, iOS: ios),
    onDidReceiveNotificationResponse: (response) {
      unawaited(_handleLocalNotificationResponse(response));
    },
    onDidReceiveBackgroundNotificationResponse: _notificationTapBackground,
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
  final androidActions = _isActionableChatPush(data)
      ? const <AndroidNotificationAction>[
          AndroidNotificationAction(
            _notificationReplyActionId,
            'Reply',
            showsUserInterface: false,
            allowGeneratedReplies: true,
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(label: 'Reply'),
            ],
          ),
          AndroidNotificationAction(
            _notificationMarkReadActionId,
            'Mark read',
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            _notificationSnoozeActionId,
            'Snooze 1h',
            showsUserInterface: false,
          ),
        ]
      : null;
  await _localNotifications.show(
    id,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _foregroundNotificationsChannelId,
        'Foreground notifications',
        channelDescription:
            'Silent in-app banners for chat, task, mention, and system alerts',
        icon: '@drawable/ic_stat_mytaskking',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
        enableVibration: false,
        actions: androidActions,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      ),
    ),
    payload: jsonEncode(data),
  );
}

Future<void> _handleLocalNotificationResponse(
  NotificationResponse response, {
  bool navigateInApp = true,
}) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  try {
    final raw = jsonDecode(payload);
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    if (response.actionId == _notificationReplyActionId) {
      await _sendNotificationReply(data, response.input);
      return;
    }
    if (response.actionId == _notificationMarkReadActionId) {
      await _markNotificationChannelRead(data);
      return;
    }
    if (response.actionId == _notificationSnoozeActionId) {
      await _snoozeNotificationChannel(data);
      return;
    }
    if (navigateInApp) _pushNavigationEvents.add(data);
  } catch (_) {}
}

/// Marks the source channel of a chat-notification read. Hits the
/// existing `/chat/channels/:id/read` endpoint with cached auth so the
/// action works even when the app isn't on screen.
Future<void> _markNotificationChannelRead(Map<String, dynamic> data) async {
  final channelId = data['channelId']?.toString();
  if (channelId == null || channelId.isEmpty) return;
  final auth = core.BestieAuthStore();
  await auth.load();
  if (auth.user == null) return;
  try {
    await core.BestieApi(baseUrl: kApiBaseUrl, auth: auth)
        .post('/chat/channels/$channelId/read');
  } catch (_) {/* best-effort */}
}

/// Local-only 1-hour mute on the source channel. Writes into the same
/// SharedPreferences key the chat list reads so the mute applies
/// uniformly to the in-app toast + the next time the user opens chat.
Future<void> _snoozeNotificationChannel(Map<String, dynamic> data) async {
  final channelId = data['channelId']?.toString();
  if (channelId == null || channelId.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat.muted_until_v2');
    final cur = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        cur.addAll(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    cur[channelId] =
        DateTime.now().add(const Duration(hours: 1)).toIso8601String();
    await prefs.setString('chat.muted_until_v2', jsonEncode(cur));
  } catch (_) {/* best-effort */}
}

Future<void> _sendNotificationReply(
  Map<String, dynamic> data,
  String? input,
) async {
  final body = input?.trim();
  if (body == null || body.isEmpty) return;
  final actionToken = data['actionToken']?.toString();
  final apiBaseUrl = data['apiBaseUrl']?.toString();
  if (actionToken != null &&
      actionToken.isNotEmpty &&
      apiBaseUrl != null &&
      apiBaseUrl.isNotEmpty) {
    await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    )).post(
      '${apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/notifications/actions/chat-reply',
      data: {'token': actionToken, 'body': body},
    );
    return;
  }

  final channelId = data['channelId']?.toString();
  if (channelId == null || channelId.isEmpty) return;
  final auth = core.BestieAuthStore();
  await auth.load();
  if (auth.user == null) return;
  await core.BestieApi(baseUrl: kApiBaseUrl, auth: auth).post(
    '/chat/channels/$channelId/messages',
    body: {'body': body, 'kind': 'TEXT'},
  );
}

bool _isIncomingCallPush(Map<String, dynamic> data) {
  return isIncomingCallPushForThisApp(data);
}

bool _isActionableChatPush(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  final kind = data['kind']?.toString();
  final channelId = data['channelId']?.toString();
  return (type == 'chat.message' || kind == 'CHAT' || kind == 'MENTION') &&
      channelId != null &&
      channelId.isNotEmpty;
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _requestStartupPermissions());
  }

  /// Ask for the permissions the app needs up front, once, on first launch —
  /// notifications, microphone and camera (calls/meetings), plus media access
  /// for sharing photos/files. Runs after the first frame so the OS dialogs
  /// appear over the app, and only once (tracked in SharedPreferences) so we
  /// don't nag on every cold start. The call screen still re-requests mic/cam
  /// at join time as a fallback if the user declined here.
  Future<void> _requestStartupPermissions() async {
    try {
      // Notifications FIRST and on its own. Batching POST_NOTIFICATIONS with
      // mic/camera/photos made some OEMs silently skip its dialog, and the
      // old one-time flag then meant we never asked again — so the device got
      // no push notifications or call rings at all. Ask every launch until the
      // user explicitly grants or permanently denies it.
      final notif = await Permission.notification.status;
      if (!notif.isGranted && !notif.isPermanentlyDenied) {
        await Permission.notification.request();
      }

      // The remaining permissions are a once-only onboarding batch.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('perms.onboarded_v1') != true) {
        final toRequest = <Permission>[
          Permission.microphone,
          Permission.camera,
        ];
        // Android 13+ uses granular media perms; older versions use storage.
        // Bluetooth (Android 12+) lets calls route to a paired headset.
        if (Platform.isAndroid) {
          toRequest.add(Permission.photos);
          toRequest.add(Permission.bluetoothConnect);
        }
        await toRequest.request();
        await prefs.setBool('perms.onboarded_v1', true);
      }
    } catch (_) {/* best-effort — features re-prompt on first use */}
  }

  @override
  void dispose() {
    _pushTapSub?.cancel();
    _localPushTapSub?.cancel();
    super.dispose();
  }

  Future<void> _wirePushDeepLinks() async {
    _launchIntentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchPayload' && call.arguments is Map) {
        if (!mounted) return null;
        _navigateFromLaunchPayload(
            Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
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
          _navigateFromLaunchPayload(Map<String, dynamic>.from(raw));
        });
      }
    } catch (_) {/* Android native call notification bridge is optional */}
  }

  void _navigateFromLaunchPayload(Map<String, dynamic> raw) {
    final type = raw['type']?.toString();
    final accepted = raw['acceptCall']?.toString() == 'true';
    final callId = raw['callId']?.toString();
    final mode =
        raw['mode']?.toString().toLowerCase() == 'voice' ? 'voice' : 'video';

    // Ongoing-call notification must return to the live session, not open a
    // fresh incoming-call ringer.
    if (type == 'call.active') {
      if (callId != null && callId.isNotEmpty) {
        ref.read(routerProvider).go('/call/$callId?mode=$mode');
      } else {
        final slug = raw['meetingSlug']?.toString();
        if (slug != null && slug.isNotEmpty) {
          ref.read(routerProvider).go('/meeting/$slug?mode=$mode');
        }
      }
      return;
    }

    if (!accepted &&
        type == 'call.incoming' &&
        CallSession.isActive &&
        callId != null &&
        callId == CallSession.activeCallId) {
      ref.read(routerProvider).go('/call/$callId?mode=$mode');
      return;
    }

    if (!accepted && (type == 'call.incoming' || type == 'meeting.invited')) {
      showIncomingCallFromPush(raw);
      return;
    }
    if (accepted && callId != null && callId.isNotEmpty) {
      unawaited(_openAcceptedCall(callId, mode));
      return;
    }
    final route = _routeForPush(raw);
    if (route != null) ref.read(routerProvider).go(route);
  }

  void _openPushTarget(RemoteMessage message) {
    final route = _routeForPush(message.data);
    if (route == null) return;
    ref.read(routerProvider).go(route);
  }

  String? _routeForPush(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type == 'call.ended') return null;
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

  Future<void> _openAcceptedCall(String callId, String mode) async {
    try {
      await ref.read(apiProvider).get('/calls/$callId/token');
    } catch (_) {
      if (!mounted) return;
      ref.read(routerProvider).go('/chat');
      return;
    }
    if (!mounted) return;
    ref.read(routerProvider).go('/call/$callId?mode=$mode');
  }

  @override
  Widget build(BuildContext context) {
    final fontScale = ref.watch(fontScaleProvider);
    return MaterialApp.router(
      title: 'MyTaskKing',
      debugShowCheckedModeBanner: false,
      theme: BestieTheme.light(),
      darkTheme: BestieTheme.dark(),
      // App screens always use light theme. Call screen has its own UI theme toggle.
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
      // The overlay listens for incoming-call socket events globally and
      // covers whatever screen you're on with an Accept/Decline ringer.
      // OngoingCallBar sits above it and surfaces a "tap to return"
      // pill when the user has minimized a live call. The MediaQuery
      // wrap applies the user-set font-scale preference app-wide.
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: IncomingCallOverlay(
          child: OngoingCallBar(
            child: ConnectivityBanner(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
