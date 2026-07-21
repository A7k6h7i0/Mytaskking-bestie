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
import 'screens/search_screen.dart';
import 'screens/call_screen.dart';
import 'screens/employees_screen.dart';
import 'screens/clients_screen.dart';
import 'screens/calls_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/announcements_screen.dart';
import 'screens/saved_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/telecaller_screen.dart';
import 'screens/telecaller_onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/attendance_screen.dart';
import 'screens/task_detail_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/recordings_screen.dart';
import 'screens/login_activity_screen.dart';
import 'screens/work_activity_screen.dart';
import 'screens/ai_review_screen.dart';
import 'screens/organizations_screen.dart';
import 'screens/admin_notes_screen.dart';
import 'screens/payments_screen.dart';
import 'screens/deleted_chats_screen.dart';
import 'state.dart' hide ThemeMode;
import 'telecaller_recording_setup.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStoreProvider);

  return GoRouter(
    initialLocation: auth.accessToken == null ? '/login' : '/chat',
    refreshListenable: _AuthListenable(auth),
    redirect: (ctx, state) {
      final logged = auth.accessToken != null;
      final loc = state.matchedLocation;
      final loginPath = loc == '/login';
      final setupPath = loc == '/telecaller/setup';

      if (!logged && !loginPath) return '/login';
      if (logged && loginPath) {
        final role = auth.user?.role;
        if (role == 'TELECALLER' &&
            TelecallerRecordingSetup.isLoaded &&
            !TelecallerRecordingSetup.isComplete) {
          return '/telecaller/setup';
        }
        if (role == 'TELECALLER') return '/telecaller';
        if (role == 'SALES_HEAD') return '/dashboard';
        return '/chat';
      }
      if (logged &&
          auth.user?.role == 'TELECALLER' &&
          TelecallerRecordingSetup.isLoaded &&
          !TelecallerRecordingSetup.isComplete &&
          !setupPath &&
          loc != '/profile') {
        return '/telecaller/setup';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

      // Dynamic search — full-screen, outside the shell so it can take the
      // whole viewport (no bottom nav while typing). `?q=` and `?k=` set
      // initial state for deep links / scope-to-person flows.
      GoRoute(
        path: '/search',
        builder: (_, s) => SearchScreen(
          initialQuery: s.uri.queryParameters['q'],
          initialKind: s.uri.queryParameters['k'],
        ),
      ),

      // Live call (from chat-detail "call back" / "video call")
      GoRoute(
        path: '/call/:id',
        builder: (_, s) => CallScreen(
          callId: s.pathParameters['id'],
          mode: s.uri.queryParameters['mode'] ?? 'video',
        ),
      ),

      // Live meeting room (from meetings list "join")
      GoRoute(
        path: '/meeting/:slug',
        builder: (_, s) => CallScreen(
          meetingSlug: s.pathParameters['slug'],
          mode: s.uri.queryParameters['mode'] ?? 'video',
        ),
      ),

      // ----- screens outside the bottom-nav shell -----
      GoRoute(path: '/employees', builder: (_, __) => const EmployeesScreen()),
      GoRoute(path: '/clients', builder: (_, __) => const ClientsScreen()),
      GoRoute(
          path: '/announcements',
          builder: (_, __) => const AnnouncementsScreen()),
      GoRoute(path: '/saved', builder: (_, __) => const SavedScreen()),
      GoRoute(path: '/sessions', builder: (_, __) => const SessionsScreen()),
      GoRoute(
          path: '/telecaller/setup',
          builder: (_, __) => const TelecallerOnboardingScreen()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(
          path: '/recordings', builder: (_, __) => const RecordingsScreen()),
      GoRoute(
          path: '/login-activity',
          builder: (_, __) => const LoginActivityScreen()),
      GoRoute(
          path: '/work-activity',
          builder: (_, __) => const WorkActivityScreen()),
      GoRoute(
          path: '/ai-review',
          builder: (_, __) => const AiReviewScreen()),
      GoRoute(
          path: '/deleted-chats', builder: (_, __) => const DeletedChatsScreen()),

      // Chat detail lives OUTSIDE the shell
      // composer + keyboard space. Back arrow returns to the chat list.
      GoRoute(
        path: '/chat/:channelId',
        builder: (_, s) =>
            ChatDetailScreen(channelId: s.pathParameters['channelId']!),
      ),

      // Task detail full-screen — out of the shell so the user can focus on
      // the task without bottom-nav distraction. Reachable via context.push.
      GoRoute(
        path: '/tasks/:id',
        builder: (_, s) => TaskDetailScreen(taskId: s.pathParameters['id']!),
      ),

      // Shell with bottom navigation; nested routes swap the body, sidebar
      // tabs stay rendered.
      ShellRoute(
        builder: (ctx, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
              path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/chat', builder: (_, __) => const ChatListScreen()),
          GoRoute(
              path: '/telecaller', builder: (_, __) => const TelecallerScreen()),
          GoRoute(path: '/calls', builder: (_, __) => const CallsScreen()),
          GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen()),
          GoRoute(
              path: '/attendance',
              builder: (_, __) => const AttendanceScreen()),
          GoRoute(
              path: '/meetings', builder: (_, __) => const MeetingsScreen()),
          GoRoute(
              path: '/notifications',
              builder: (_, __) => const NotificationsScreen()),
          GoRoute(
              path: '/calendar', builder: (_, __) => const CalendarScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(
              path: '/organizations',
              builder: (_, __) => const OrganizationsScreen()),
          GoRoute(
              path: '/admin-notes',
              builder: (_, __) => const AdminNotesScreen()),
          GoRoute(
              path: '/payments',
              builder: (_, __) => const PaymentsScreen()),
          GoRoute(
              path: '/settings', builder: (_, __) => const SettingsScreen()),
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
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
