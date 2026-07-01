import 'dart:io' show Platform, exit;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core show ThemeMode;
import 'package:mytaskking_mobile/router.dart' as mobile_router;
import 'package:mytaskking_mobile/screens.dart' hide ThemeMode;
import 'package:mytaskking_mobile/screens/connectivity_banner.dart';
import 'package:mytaskking_mobile/screens/incoming_call_overlay.dart';
import 'package:mytaskking_mobile/screens/ongoing_call_bar.dart';
import 'package:mytaskking_mobile/screens/organizations_screen.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_runtime.dart';
import 'desktop_work_activity_agent.dart';
import 'desktop_calendar_screen.dart';
import 'desktop_chat_screen.dart';
import 'work_activity_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final shouldContinue = await DesktopRuntime.initialize(args);
  if (!shouldContinue) {
    await DesktopRuntime.release();
    exit(0);
  }
  final auth = BestieAuthStore();
  await auth.load();
  final readyForWindow = await DesktopRuntime.configureWindowForSession(
    hasAuthSession: auth.accessToken != null,
  );
  if (!readyForWindow) {
    await DesktopRuntime.release();
    exit(0);
  }
  final api = BestieApi(
    baseUrl: kApiBaseUrl,
    auth: auth,
    userAgent:
        'MyTaskKing-Desktop/${Platform.operatingSystem}/${Platform.operatingSystemVersion}',
  );
  final socket =
      BestieSocket(url: kSocketUrl, auth: auth, clientApp: 'mytaskking');

  runApp(ProviderScope(
    overrides: [
      authStoreProvider.overrideWithValue(auth),
      apiProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(socket),
    ],
    child: const BestieWindowsApp(),
  ));
}

class BestieWindowsApp extends ConsumerWidget {
  const BestieWindowsApp({super.key});

  GoRouter _router(BestieAuthStore auth) {
    final logged = auth.accessToken != null;
    return GoRouter(
      initialLocation: logged ? '/dashboard' : '/login',
      refreshListenable: _AuthListenable(auth),
      redirect: (_, state) {
        final isLoggedIn = auth.accessToken != null;
        final loginPath = state.matchedLocation == '/login';
        if (!isLoggedIn && !loginPath) return '/login';
        if (isLoggedIn && loginPath) return '/dashboard';
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          redirect: (_, __) =>
              auth.accessToken != null ? '/dashboard' : '/login',
        ),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/search',
          builder: (_, s) => SearchScreen(
            initialQuery: s.uri.queryParameters['q'],
            initialKind: s.uri.queryParameters['k'],
          ),
        ),
        GoRoute(
          path: '/call/:id',
          builder: (_, s) => CallScreen(
            callId: s.pathParameters['id'],
            mode: s.uri.queryParameters['mode'] ?? 'video',
          ),
        ),
        GoRoute(
          path: '/meeting/:slug',
          builder: (_, s) => CallScreen(
            meetingSlug: s.pathParameters['slug'],
            mode: s.uri.queryParameters['mode'] ?? 'video',
          ),
        ),
        GoRoute(
          path: '/chat/:channelId',
          builder: (_, s) =>
              ChatDetailScreen(channelId: s.pathParameters['channelId']!),
        ),
        GoRoute(
          path: '/tasks/:id',
          builder: (_, s) => TaskDetailScreen(taskId: s.pathParameters['id']!),
        ),
        ShellRoute(
          builder: (_, __, child) => DesktopShell(child: child),
          routes: [
            GoRoute(
                path: '/dashboard',
                builder: (_, __) => const DashboardScreen()),
            GoRoute(
                path: '/chat', builder: (_, __) => const DesktopChatScreen()),
            GoRoute(
                path: '/employees',
                builder: (_, __) => const EmployeesScreen()),
            GoRoute(
                path: '/clients', builder: (_, __) => const ClientsScreen()),
            GoRoute(path: '/calls', builder: (_, __) => const CallsScreen()),
            GoRoute(
                path: '/calendar',
                builder: (_, __) => const DesktopCalendarScreen()),
            GoRoute(
                path: '/announcements',
                builder: (_, __) => const AnnouncementsScreen()),
            GoRoute(path: '/saved', builder: (_, __) => const SavedScreen()),
            GoRoute(
                path: '/sessions', builder: (_, __) => const SessionsScreen()),
            GoRoute(
                path: '/telecaller',
                builder: (_, __) => const TelecallerScreen()),
            GoRoute(
                path: '/settings', builder: (_, __) => const SettingsScreen()),
            GoRoute(
                path: '/reports', builder: (_, __) => const ReportsScreen()),
            GoRoute(
                path: '/recordings',
                builder: (_, __) => const RecordingsScreen()),
            GoRoute(
                path: '/organizations',
                builder: (_, __) => const OrganizationsScreen()),
            GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen()),
            GoRoute(
                path: '/attendance',
                builder: (_, __) => const AttendanceScreen()),
            GoRoute(path: '/attendence', redirect: (_, __) => '/attendance'),
            GoRoute(
                path: '/meetings', builder: (_, __) => const MeetingsScreen()),
            GoRoute(
                path: '/work-activity',
                builder: (_, __) => const WorkActivityScreen()),
            GoRoute(
                path: '/notifications',
                builder: (_, __) => const NotificationsScreen()),
            GoRoute(
                path: '/profile', builder: (_, __) => const ProfileScreen()),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentUserProvider);
    final auth = ref.watch(authStoreProvider);
    final mode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final router = _router(auth);
    return MaterialApp.router(
      title: 'MyTaskKing · Windows',
      debugShowCheckedModeBanner: false,
      theme: BestieTheme.light(),
      darkTheme: BestieTheme.dark(),
      themeMode: switch (mode) {
        core.ThemeMode.light => ThemeMode.light,
        core.ThemeMode.dark => ThemeMode.dark,
        core.ThemeMode.system => ThemeMode.system,
      },
      routerConfig: router,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: ProviderScope(
          overrides: [mobile_router.routerProvider.overrideWithValue(router)],
          child: IncomingCallOverlay(
            child: OngoingCallBar(
              child:
                  ConnectivityBanner(child: child ?? const SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._auth) {
    _sub = _auth.changes.listen((_) => notifyListeners());
  }

  final BestieAuthStore _auth;
  late final dynamic _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Desktop shell: persistent sidebar + content area. Routes are tracked in
/// local state — deep-linking on desktop isn't a strong requirement yet.
/// All feature screens are reused from `package:mytaskking_mobile/screens.dart`.
class DesktopShell extends ConsumerStatefulWidget {
  final Widget child;
  const DesktopShell({super.key, required this.child});
  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell>
    with WindowListener {
  final _activityAgent = DesktopWorkActivityAgent();

  List<BestieSidebarItem> _itemsFor(BestieUser? user) {
    final isAdmin = user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN';
    final isManager = isAdmin || user?.role == 'MANAGER';
    final isTelecaller = user?.role == 'TELECALLER' ||
        user?.role == 'ADMIN' ||
        user?.role == 'SUPER_ADMIN';
    return [
      const BestieSidebarItem(
          icon: Icons.dashboard_outlined,
          label: 'Dashboard',
          route: '/dashboard'),
      const BestieSidebarItem(
          icon: Icons.chat_bubble_outline, label: 'Chat', route: '/chat'),
      const BestieSidebarItem(
          icon: Icons.view_kanban_outlined, label: 'Tasks', route: '/tasks'),
      const BestieSidebarItem(
          icon: Icons.videocam_outlined, label: 'Meetings', route: '/meetings'),
      if (isAdmin)
        const BestieSidebarItem(
            icon: Icons.monitor_heart_outlined,
            label: 'Work Activity',
            route: '/work-activity'),
      if (isAdmin)
        const BestieSidebarItem(
            icon: Icons.people_outline_rounded,
            label: 'Employees',
            route: '/employees'),
      if (isManager)
        const BestieSidebarItem(
            icon: Icons.business_center_outlined,
            label: 'Clients',
            route: '/clients'),
      if (isTelecaller)
        const BestieSidebarItem(
            icon: Icons.headset_mic_outlined,
            label: 'Telecaller',
            route: '/telecaller'),
      const BestieSidebarItem(
          icon: Icons.history_rounded, label: 'Calls', route: '/calls'),
      const BestieSidebarItem(
          icon: Icons.event_outlined, label: 'Calendar', route: '/calendar'),
      if (isAdmin)
        const BestieSidebarItem(
            icon: Icons.description_outlined,
            label: 'Reports',
            route: '/reports'),
      if (isAdmin)
        const BestieSidebarItem(
            icon: Icons.download_for_offline_outlined,
            label: 'Recordings',
            route: '/recordings'),
      const BestieSidebarItem(
          icon: Icons.notifications_outlined,
          label: 'Notifications',
          route: '/notifications'),
      const BestieSidebarItem(
          icon: Icons.settings_outlined, label: 'Settings', route: '/settings'),
      const BestieSidebarItem(
          icon: Icons.person_outline, label: 'Profile', route: '/profile'),
    ];
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && DesktopRuntime.shouldRunActivityAgent) {
        _activityAgent.start(context, ref);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _activityAgent.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (!DesktopRuntime.interceptClose) return;
    DesktopRuntime.hideWindowToBackground();
  }

  String _activeRoute(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/chat')) return '/chat';
    if (path.startsWith('/tasks')) return '/tasks';
    if (path.startsWith('/meetings')) return '/meetings';
    if (path.startsWith('/work-activity')) return '/work-activity';
    if (path.startsWith('/employees')) return '/employees';
    if (path.startsWith('/clients')) return '/clients';
    if (path.startsWith('/telecaller')) return '/telecaller';
    if (path.startsWith('/calls')) return '/calls';
    if (path.startsWith('/calendar')) return '/calendar';
    if (path.startsWith('/reports')) return '/reports';
    if (path.startsWith('/recordings')) return '/recordings';
    if (path.startsWith('/organizations')) return '/settings';
    if (path.startsWith('/notifications')) return '/notifications';
    if (path.startsWith('/settings')) return '/settings';
    if (path.startsWith('/profile')) return '/profile';
    return '/dashboard';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider);
    final user = ref.watch(authStoreProvider).user;
    final items = _itemsFor(user);
    final activeRoute = _activeRoute(context);
    return Scaffold(
      body: Row(children: [
        BestieSidebar(
          items: items,
          activeRoute: activeRoute,
          onSelect: context.go,
          header: Padding(
            padding: const EdgeInsets.all(BestieTokens.s3),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'MyTaskKing',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          footer: user == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    BestieAvatar(
                        name: user.name,
                        imageUrl: user.avatarUrl,
                        isClient: user.isClient,
                        size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BestieUserName(
                              name: user.name,
                              isClient: user.isClient,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            user.isClient
                                ? (user.clientCompany ?? 'Client')
                                : user.role.replaceAll('_', ' '),
                            style: const TextStyle(
                                color: BestieTokens.cTextMuted, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
        ),
        Expanded(
          child: Container(
            color: BestieTokens.cBg,
            child: AnimatedSwitcher(
              duration: BestieMotion.base,
              child:
                  KeyedSubtree(key: ValueKey(activeRoute), child: widget.child),
            ),
          ),
        ),
      ]),
    );
  }
}
