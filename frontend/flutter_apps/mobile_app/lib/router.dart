import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_detail_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/meetings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStoreProvider);

  return GoRouter(
    initialLocation: auth.accessToken == null ? '/login' : '/dashboard',
    refreshListenable: _AuthListenable(auth),
    redirect: (ctx, state) {
      final logged = auth.accessToken != null;
      final loginPath = state.matchedLocation == '/login';
      if (!logged && !loginPath) return '/login';
      if (logged && loginPath)   return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

      // Shell with bottom navigation; nested routes swap the body, sidebar
      // tabs stay rendered.
      ShellRoute(
        builder: (ctx, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/chat',      builder: (_, __) => const ChatListScreen()),
          GoRoute(
            path: '/chat/:channelId',
            builder: (_, s) => ChatDetailScreen(channelId: s.pathParameters['channelId']!),
          ),
          GoRoute(path: '/tasks',         builder: (_, __) => const TasksScreen()),
          GoRoute(path: '/meetings',      builder: (_, __) => const MeetingsScreen()),
          GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/profile',       builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

// Bridges the auth store's `changes` stream into a Listenable that GoRouter
// re-evaluates redirects against, so logout/login navigations happen
// automatically without an explicit `context.go(...)`.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._auth) {
    _sub = _auth.changes.listen((_) => notifyListeners());
  }
  final dynamic _auth;
  late final dynamic _sub;
  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}
