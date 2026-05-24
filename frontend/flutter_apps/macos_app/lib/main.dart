import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bestie_design/bestie_design.dart';
import 'package:bestie_core/bestie_core.dart' as core show ThemeMode;
import 'package:bestie_mobile/screens.dart' hide ThemeMode;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = BestieAuthStore();
  await auth.load();
  final api = BestieApi(baseUrl: kApiBaseUrl, auth: auth);
  final socket = BestieSocket(url: kSocketUrl, auth: auth);

  runApp(ProviderScope(
    overrides: [
      authStoreProvider.overrideWithValue(auth),
      apiProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(socket),
    ],
    child: const BestieMacApp(),
  ));
}

class BestieMacApp extends ConsumerWidget {
  const BestieMacApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStoreProvider).user;
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'MyTaskKing · macOS',
      debugShowCheckedModeBanner: false,
      theme: BestieTheme.light(),
      darkTheme: BestieTheme.dark(),
      themeMode: switch (mode) {
        core.ThemeMode.light  => ThemeMode.light,
        core.ThemeMode.dark   => ThemeMode.dark,
        core.ThemeMode.system => ThemeMode.system,
      },
      home: user == null ? const LoginScreen() : const DesktopShell(),
    );
  }
}

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});
  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  String _route = '/dashboard';

  static const _items = [
    BestieSidebarItem(icon: Icons.dashboard_outlined,     label: 'Dashboard',     route: '/dashboard'),
    BestieSidebarItem(icon: Icons.chat_bubble_outline,    label: 'Chat',          route: '/chat'),
    BestieSidebarItem(icon: Icons.view_kanban_outlined,   label: 'Tasks',         route: '/tasks'),
    BestieSidebarItem(icon: Icons.videocam_outlined,      label: 'Meetings',      route: '/meetings'),
    BestieSidebarItem(icon: Icons.notifications_outlined, label: 'Notifications', route: '/notifications'),
    BestieSidebarItem(icon: Icons.person_outline,         label: 'Profile',       route: '/profile'),
  ];

  Widget _content() {
    switch (_route) {
      case '/dashboard':     return const DashboardScreen();
      case '/chat':          return const ChatListScreen();
      case '/tasks':         return const TasksScreen();
      case '/meetings':      return const MeetingsScreen();
      case '/notifications': return const NotificationsScreen();
      case '/profile':       return const ProfileScreen();
      default:               return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStoreProvider).user;
    return Scaffold(
      body: Row(children: [
        BestieSidebar(
          items: _items,
          activeRoute: _route,
          onSelect: (r) => setState(() => _route = r),
          footer: user == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    BestieAvatar(name: user.name, imageUrl: user.avatarUrl, isClient: user.isClient, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BestieUserName(name: user.name, isClient: user.isClient,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            user.isClient ? (user.clientCompany ?? 'Client') : user.role.replaceAll('_', ' '),
                            style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 11),
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
