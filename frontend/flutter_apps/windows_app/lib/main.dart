import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core show ThemeMode;
import 'package:mytaskking_mobile/screens.dart' hide ThemeMode;

import 'desktop_work_activity_agent.dart';
import 'work_activity_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = BestieAuthStore();
  await auth.load();
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStoreProvider).user;
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'MyTaskKing · Windows',
      debugShowCheckedModeBanner: false,
      theme: BestieTheme.light(),
      darkTheme: BestieTheme.dark(),
      themeMode: switch (mode) {
        core.ThemeMode.light => ThemeMode.light,
        core.ThemeMode.dark => ThemeMode.dark,
        core.ThemeMode.system => ThemeMode.system,
      },
      home: user == null ? const LoginScreen() : const DesktopShell(),
    );
  }
}

/// Desktop shell: persistent sidebar + content area. Routes are tracked in
/// local state — deep-linking on desktop isn't a strong requirement yet.
/// All feature screens are reused from `package:mytaskking_mobile/screens.dart`.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});
  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  String _route = '/dashboard';
  final _activityAgent = DesktopWorkActivityAgent();

  List<BestieSidebarItem> _itemsFor(BestieUser? user) {
    final isAdmin = user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN';
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
      const BestieSidebarItem(
          icon: Icons.notifications_outlined,
          label: 'Notifications',
          route: '/notifications'),
      const BestieSidebarItem(
          icon: Icons.person_outline, label: 'Profile', route: '/profile'),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activityAgent.start(context, ref);
    });
  }

  @override
  void dispose() {
    _activityAgent.dispose();
    super.dispose();
  }

  Widget _content() {
    switch (_route) {
      case '/dashboard':
        return const DashboardScreen();
      case '/chat':
        return const ChatListScreen();
      case '/tasks':
        return const TasksScreen();
      case '/meetings':
        return const MeetingsScreen();
      case '/work-activity':
        return const WorkActivityScreen();
      case '/notifications':
        return const NotificationsScreen();
      case '/profile':
        return const ProfileScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStoreProvider).user;
    final items = _itemsFor(user);
    return Scaffold(
      body: Row(children: [
        BestieSidebar(
          items: items,
          activeRoute: _route,
          onSelect: (r) => setState(() => _route = r),
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
              child: KeyedSubtree(key: ValueKey(_route), child: _content()),
            ),
          ),
        ),
      ]),
    );
  }
}
