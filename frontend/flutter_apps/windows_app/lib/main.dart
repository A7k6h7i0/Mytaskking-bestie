import 'dart:async';
import 'dart:io' show Directory, File, Platform, exit;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core show ThemeMode;
import 'package:mytaskking_mobile/router.dart' as mobile_router;
import 'package:mytaskking_mobile/screens.dart'
    hide ThemeMode, WorkActivityScreen;
import 'package:mytaskking_mobile/screens/connectivity_banner.dart';
import 'package:mytaskking_mobile/screens/incoming_call_overlay.dart';
import 'package:mytaskking_mobile/screens/ongoing_call_bar.dart';
import 'package:mytaskking_mobile/windows_workspace.dart';
import 'package:mytaskking_mobile/branding.dart';
import 'package:mytaskking_mobile/mobile_appearance_providers.dart';
import 'package:mytaskking_mobile/mobile_local_settings.dart';
import 'package:mytaskking_mobile/mobile_theme_palettes.dart';
import 'package:mytaskking_mobile/screens/organizations_screen.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_local_settings.dart';
import 'desktop_profile_screen.dart';
import 'desktop_runtime.dart';
import 'desktop_work_activity_agent.dart';
import 'desktop_calendar_screen.dart';
import 'desktop_chat_screen.dart';
import 'desktop_calls_screen.dart';
import 'desktop_task_detail_screen.dart';
import 'desktop_notifications_screen.dart';
import 'work_activity_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await DesktopLocalSettings.load();
  await MobileLocalSettings.load();
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

class BestieWindowsApp extends ConsumerStatefulWidget {
  const BestieWindowsApp({super.key});

  @override
  ConsumerState<BestieWindowsApp> createState() => _BestieWindowsAppState();
}

class _BestieWindowsAppState extends ConsumerState<BestieWindowsApp> {
  @override
  void initState() {
    super.initState();
    ref.read(themeModeProvider.notifier).state =
        MobileLocalSettings.themeMode.value;
    ref.read(mobileColorThemeProvider.notifier).state =
        MobileLocalSettings.colorTheme.value;
  }

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
          redirect: (_, __) =>
              kWindowsWorkspaceNoCalls ? '/calls' : null,
          builder: (_, s) => CallScreen(
            callId: s.pathParameters['id'],
            mode: s.uri.queryParameters['mode'] ?? 'video',
          ),
        ),
        GoRoute(
          path: '/meeting/:slug',
          redirect: (_, __) =>
              kWindowsWorkspaceNoCalls ? '/meetings' : null,
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
          builder: (_, s) =>
              DesktopTaskDetailScreen(taskId: s.pathParameters['id']!),
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
            GoRoute(path: '/calls', builder: (_, __) => const DesktopCallsScreen()),
            GoRoute(
                path: '/calendar',
                builder: (_, __) => const DesktopCalendarScreen()),
            GoRoute(
                path: '/telecaller',
                builder: (_, __) =>
                    const TelecallerScreen(embeddedInShell: true),
            ),
            GoRoute(
                path: '/ai-review',
                builder: (_, __) => const AiReviewScreen(),
            ),
            GoRoute(
                path: '/announcements',
                builder: (_, __) => const AnnouncementsScreen()),
            GoRoute(path: '/saved', builder: (_, __) => const SavedScreen()),
            GoRoute(
                path: '/sessions', builder: (_, __) => const SessionsScreen()),
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
                path: '/login-activity',
                builder: (_, __) => const LoginActivityScreen()),
            GoRoute(
                path: '/notifications',
                builder: (_, __) => const DesktopNotificationsScreen()),
            GoRoute(
              path: '/profile',
              builder: (_, __) => const DesktopProfileScreen(),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider);
    final auth = ref.watch(authStoreProvider);
    ref.watch(themeModeProvider);
    ref.watch(mobileColorThemeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final router = _router(auth);
    return ValueListenableBuilder<int>(
      valueListenable: MobileLocalSettings.themeEpoch,
      builder: (context, themeEpoch, _) {
        return ValueListenableBuilder<MobileThemeId>(
          valueListenable: MobileLocalSettings.colorTheme,
          builder: (context, paletteId, __) {
            return ValueListenableBuilder<
                Map<MobileThemeId, Map<String, int>>>(
              valueListenable: MobileLocalSettings.themeColorOverrides,
              builder: (context, overridesMap, ___) {
                return ValueListenableBuilder<int?>(
                  valueListenable: MobileLocalSettings.adminPrimaryColor,
                  builder: (context, adminPrimary, ____) {
                    return ValueListenableBuilder<core.ThemeMode>(
                      valueListenable: MobileLocalSettings.themeMode,
                      builder: (context, mode, _____) {
                        final overrides = <String, int>{
                          ...?overridesMap[paletteId],
                        };
                        if (adminPrimary != null &&
                            paletteId == MobileThemeId.mytaskkingBlue) {
                          overrides['brand'] = adminPrimary;
                          overrides['brandStrong'] = adminPrimary;
                          overrides['accent'] = adminPrimary;
                          overrides['logoGradientStart'] = adminPrimary;
                          overrides['logoGradientEnd'] = adminPrimary;
                          overrides['sidebarActiveStart'] = adminPrimary;
                          overrides['sidebarActiveEnd'] = adminPrimary;
                          overrides['backdropDot'] = adminPrimary;
                        }
                        final palette = MobileThemePalettes.paletteFor(
                          paletteId,
                          overrides:
                              overrides.isEmpty ? null : overrides,
                        );
                        final light = _desktopTheme(
                          MobileThemePalettes.applyTo(
                            BestieTheme.light(),
                            palette,
                          ),
                        );
                        final dark = _desktopTheme(
                          MobileThemePalettes.applyTo(
                            BestieTheme.dark(),
                            palette,
                          ),
                        );
                        ref.watch(orgBrandingProvider);
                        return MaterialApp.router(
                          key: ValueKey(
                            'theme-$themeEpoch-${mode.name}-${paletteId.storageKey}-$adminPrimary',
                          ),
                          title: 'MyTaskKing · Windows',
                          debugShowCheckedModeBanner: false,
                          theme: light,
                          darkTheme: dark,
                          themeMode: switch (mode) {
                            core.ThemeMode.light => ThemeMode.light,
                            core.ThemeMode.dark => ThemeMode.dark,
                            core.ThemeMode.system => ThemeMode.system,
                          },
                          routerConfig: router,
                          builder: (ctx, child) {
                            return MediaQuery(
                              data: MediaQuery.of(ctx).copyWith(
                                textScaler: TextScaler.linear(fontScale),
                              ),
                              child: DesktopLifecycleHost(
                                child: KeyedSubtree(
                                  key: ValueKey(
                                    '$themeEpoch-${paletteId.storageKey}-${mode.name}-$adminPrimary',
                                  ),
                                  child: ProviderScope(
                                    overrides: [
                                      mobile_router.routerProvider
                                          .overrideWithValue(router),
                                    ],
                                    child: kWindowsWorkspaceNoCalls
                                        ? ConnectivityBanner(
                                            child: child ??
                                                const SizedBox.shrink(),
                                          )
                                        : IncomingCallOverlay(
                                            child: OngoingCallBar(
                                              child: ConnectivityBanner(
                                                child: child ??
                                                    const SizedBox.shrink(),
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
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

class DesktopLifecycleHost extends ConsumerStatefulWidget {
  const DesktopLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopLifecycleHost> createState() =>
      _DesktopLifecycleHostState();
}

class _DesktopLifecycleHostState extends ConsumerState<DesktopLifecycleHost>
    with WindowListener, TrayListener {
  final _activityAgent = DesktopWorkActivityAgent();
  StreamSubscription? _authSub;
  Timer? _autoLogoutTimer;
  bool _trayReady = false;
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    DesktopLocalSettings.autoLogout.addListener(_onAutoLogoutSettingsChanged);
    _authSub = ref.read(authStoreProvider).changes.listen(
          (_) => unawaited(_syncDesktopSession()),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeDesktopLifecycle());
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    DesktopLocalSettings.autoLogout
        .removeListener(_onAutoLogoutSettingsChanged);
    _authSub?.cancel();
    _autoLogoutTimer?.cancel();
    if (!_trayShouldRemainVisible()) {
      unawaited(_disposeTray());
    }
    _activityAgent.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (!DesktopRuntime.interceptClose) return;
    unawaited(DesktopRuntime.hideWindowToBackground());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_restoreFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open_window':
        unawaited(_restoreFromTray());
        break;
      case 'sign_out':
        unawaited(_signOutFromDesktop(exitAfter: false));
        break;
      case 'quit_app':
        unawaited(_closeDesktopCompletely());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider);
    return widget.child;
  }

  Future<void> _initializeDesktopLifecycle() async {
    await _syncDesktopSession();
    if (mounted &&
        DesktopRuntime.shouldRunActivityAgent &&
        ref.read(authStoreProvider).accessToken != null) {
      _activityAgent.start(context, ref);
    }
  }

  Future<void> _syncDesktopSession() async {
    final loggedIn = ref.read(authStoreProvider).accessToken != null;
    await DesktopRuntime.setSessionActive(loggedIn);
    if (!mounted) return;
    if (loggedIn) {
      await _ensureTray();
      if (!mounted) return;
      _startAutoLogoutMonitor();
      if (DesktopRuntime.shouldRunActivityAgent) {
        _activityAgent.start(context, ref);
      }
    } else {
      _activityAgent.dispose();
      _autoLogoutTimer?.cancel();
      _autoLogoutTimer = null;
      await _disposeTray();
    }
  }

  void _onAutoLogoutSettingsChanged() {
    if (!mounted) return;
    if (ref.read(authStoreProvider).accessToken == null) return;
    if (_isAutoLogoutExempt()) return;
    _startAutoLogoutMonitor();
  }

  /// Org admins and platform super admins stay signed in — no 6 PM cutoff.
  bool _isAutoLogoutExempt() {
    final user = ref.read(authStoreProvider).user;
    if (user == null) return false;
    return user.role == 'ADMIN' ||
        user.role == 'SUPER_ADMIN' ||
        user.isPlatformSuperAdmin;
  }

  void _startAutoLogoutMonitor() {
    _autoLogoutTimer?.cancel();
    if (_isAutoLogoutExempt()) return;
    _autoLogoutTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_checkAutoLogout()),
    );
    unawaited(_checkAutoLogout());
  }

  Future<void> _checkAutoLogout() async {
    if (!mounted || _quitting) return;
    if (ref.read(authStoreProvider).accessToken == null) return;
    if (_isAutoLogoutExempt()) return;
    final settings = DesktopLocalSettings.autoLogout.value;
    if (!settings.enabled) return;
    final now = DateTime.now();
    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
      settings.hour,
      settings.minute,
    );
    if (now.isBefore(cutoff)) return;
    await DesktopRuntime.revealAgentWindow();
    if (!mounted || _quitting) return;
    await _signOutFromDesktop(exitAfter: true);
  }

  Future<void> _ensureTray() async {
    if (_trayReady || !(Platform.isWindows || Platform.isLinux)) return;
    final menu = Menu(
      items: [
        MenuItem(key: 'open_window', label: 'Open MyTaskKing'),
        MenuItem.separator(),
        MenuItem(key: 'sign_out', label: 'Sign out'),
        MenuItem(key: 'quit_app', label: 'Quit'),
      ],
    );
    await trayManager.setIcon(_trayIconPath);
    if (Platform.isWindows) {
      await trayManager.setToolTip('MyTaskKing');
    }
    await trayManager.setContextMenu(menu);
    _trayReady = true;
  }

  Future<void> _disposeTray() async {
    if (!_trayReady) return;
    try {
      await trayManager.destroy();
    } catch (_) {}
    _trayReady = false;
  }

  bool _trayShouldRemainVisible() {
    if (_quitting) return false;
    return ref.read(authStoreProvider).accessToken != null;
  }

  Future<void> _restoreFromTray() async {
    await DesktopRuntime.revealAgentWindow();
  }

  Future<void> _signOutFromDesktop({required bool exitAfter}) async {
    if (_quitting) return;
    try {
      await ref.read(apiProvider).logout();
    } catch (_) {
      await ref.read(authStoreProvider).clear();
    }
    await DesktopRuntime.setSessionActive(false);
    _activityAgent.dispose();
    _autoLogoutTimer?.cancel();
    _autoLogoutTimer = null;
    await _disposeTray();
    if (exitAfter) {
      await _closeDesktopCompletely(skipTrayDestroy: true);
      return;
    }
    if (mounted) {
      final router = GoRouter.of(context);
      if (router.state.matchedLocation != '/login') {
        router.go('/login');
      }
    }
  }

  Future<void> _closeDesktopCompletely({bool skipTrayDestroy = false}) async {
    if (_quitting) return;
    _quitting = true;
    _activityAgent.dispose();
    _autoLogoutTimer?.cancel();
    _autoLogoutTimer = null;
    if (!skipTrayDestroy) {
      await _disposeTray();
    }
    await DesktopRuntime.setSessionActive(false);
    await DesktopRuntime.release();
    exit(0);
  }

  String get _trayIconPath {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\data\\flutter_assets\\assets\\logo.png',
      '$exeDir\\data\\flutter_assets\\packages\\mytaskking_mobile\\assets\\icon.png',
      '$exeDir\\data\\flutter_assets\\assets\\icon.png',
      '${Directory.current.path}\\windows\\runner\\resources\\app_icon.ico',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return candidates.first;
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

class _DesktopShellState extends ConsumerState<DesktopShell> {
  List<BestieSidebarItem> _itemsFor(BestieUser? user) {
    final isAdmin = user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN';
    final isManager = isAdmin || user?.role == 'MANAGER';
    final isTelecallerOnly = user?.role == 'TELECALLER';
    final isTelecaller = isTelecallerOnly || isAdmin || user?.role == 'SUPER_ADMIN';
    final isPlatformSuperAdmin = user?.isPlatformSuperAdmin == true;

    if (isTelecallerOnly) {
      return const [
        BestieSidebarItem(
            icon: Icons.chat_bubble_outline, label: 'Chats', route: '/chat'),
        BestieSidebarItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            route: '/dashboard'),
        BestieSidebarItem(
            icon: Icons.headset_mic_outlined,
            label: 'Telecaller Leads',
            route: '/telecaller'),
        BestieSidebarItem(
            icon: Icons.person_outline, label: 'Profile', route: '/profile'),
        BestieSidebarItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            route: '/settings'),
      ];
    }

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
            icon: Icons.login_rounded,
            label: 'Login activity',
            route: '/login-activity'),
      if (isPlatformSuperAdmin)
        const BestieSidebarItem(
            icon: Icons.apartment_rounded,
            label: 'Organisations',
            route: '/organizations'),
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
            label: 'Telecaller Leads',
            route: '/telecaller'),
      if (isAdmin)
        const BestieSidebarItem(
            icon: Icons.psychology_outlined,
            label: 'AI Review',
            route: '/ai-review'),
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

  String _activeRoute(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/chat')) return '/chat';
    if (path.startsWith('/tasks')) return '/tasks';
    if (path.startsWith('/meetings')) return '/meetings';
    if (path.startsWith('/work-activity')) return '/work-activity';
    if (path.startsWith('/login-activity')) return '/login-activity';
    if (path.startsWith('/organizations')) return '/organizations';
    if (path.startsWith('/employees')) return '/employees';
    if (path.startsWith('/clients')) return '/clients';
    if (path.startsWith('/telecaller')) return '/telecaller';
    if (path.startsWith('/ai-review')) return '/ai-review';
    if (path.startsWith('/calls')) return '/calls';
    if (path.startsWith('/calendar')) return '/calendar';
    if (path.startsWith('/reports')) return '/reports';
    if (path.startsWith('/recordings')) return '/recordings';
    if (path.startsWith('/notifications')) return '/notifications';
    if (path.startsWith('/settings')) return '/settings';
    if (path.startsWith('/profile')) return '/profile';
    return '/dashboard';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStoreProvider).user;
    final items = _itemsFor(user);
    final activeRoute = _activeRoute(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: _DesktopBackdrop()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                BestieSidebar(
                  items: items,
                  activeRoute: activeRoute,
                  onSelect: context.go,
                  header: Padding(
                    padding: const EdgeInsets.all(BestieTokens.s3),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF08307A), Color(0xFF0C4FBF)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF08307A)
                                    .withValues(alpha: 0.22),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MyTaskKing',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'WORKSPACE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: BestieTokens.cTextMuted,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  footer: user == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            BestieAvatar(
                                name: user.name,
                                imageUrl: user.avatarUrl,
                                isClient: user.isClient,
                                size: 34),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BestieUserName(
                                      name: user.name,
                                      isClient: user.isClient,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                    user.isClient
                                        ? (user.clientCompany ?? 'Client')
                                        : user.role.replaceAll('_', ' '),
                                    style: const TextStyle(
                                        color: BestieTokens.cTextMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF27426F)
                            : const Color(0xFFDCE6F5),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: Theme.of(context).brightness == Brightness.dark
                            ? [
                                const Color(0xCC0D1A33),
                                const Color(0xCC112242),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.88),
                                const Color(0xFFF5F9FF).withValues(alpha: 0.86),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF082C6C).withValues(alpha: 0.14),
                          blurRadius: 48,
                          offset: const Offset(0, 22),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(34),
                      child: AnimatedSwitcher(
                        duration: BestieMotion.base,
                        child: KeyedSubtree(
                          key: ValueKey(activeRoute),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

ThemeData _desktopTheme(ThemeData base) {
  final isDark = base.brightness == Brightness.dark;
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontSize: (text.headlineMedium?.fontSize ?? 28) + 2,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: (text.titleLarge?.fontSize ?? 18) + 1,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: (text.titleMedium?.fontSize ?? 16) + 1,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      bodyMedium: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: isDark
          ? const Color(0xCC0D1A33)
          : Colors.white.withValues(alpha: 0.78),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

class _DesktopBackdrop extends StatelessWidget {
  const _DesktopBackdrop();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF040B17),
                  Color(0xFF0A1730),
                  Color(0xFF0E2345),
                ]
              : const [
                  Color(0xFFF8FBFF),
                  Color(0xFFF2F7FF),
                  Color(0xFFEEF4FF),
                ],
        ),
      ),
      child: CustomPaint(
        painter: _BackdropPainter(isDark: isDark),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFF0A4AA6))
          .withValues(alpha: isDark ? 0.06 : 0.07)
      ..style = PaintingStyle.fill;
    const gap = 12.0;
    for (double x = 20; x < size.width; x += gap) {
      for (double y = 20; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 0.9, dotPaint);
      }
    }

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.11 : 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    _drawSwirl(
      canvas,
      Offset(size.width * 0.34, size.height * 0.12),
      size.width * 0.26,
      linePaint,
    );
    _drawSwirl(
      canvas,
      Offset(size.width * 0.12, size.height * 0.78),
      size.width * 0.18,
      linePaint,
    );
    _drawSwirl(
      canvas,
      Offset(size.width * 0.92, size.height * 0.28),
      size.width * 0.22,
      linePaint,
    );
  }

  void _drawSwirl(
      Canvas canvas, Offset center, double baseRadius, Paint paint) {
    for (int i = 0; i < 10; i++) {
      final radius = baseRadius + (i * 10);
      final rect = Rect.fromCircle(center: center, radius: radius);
      final start = -math.pi * 0.1 + (i * 0.03);
      const sweep = math.pi * 1.18;
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
