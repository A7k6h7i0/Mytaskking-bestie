// Re-exports the shared Riverpod providers + app-level constants so screens
// can `import 'state.dart'` and get everything in one shot.

export 'package:bestie_core/bestie_core.dart' show
    authStoreProvider, apiProvider, socketProvider, currentUserProvider,
    realtimeProvider, dashboardProvider, channelsProvider, messagesProvider,
    tasksKanbanProvider, meetingsProvider, calendarRangeProvider,
    notificationsProvider, savedProvider, announcementsProvider, flagsProvider,
    mySessionsProvider, presenceStatusProvider, searchQueryProvider,
    searchResultsProvider, themeModeProvider, ThemeMode, formatApiError;

const kApiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:4000',
);
const kSocketUrl = String.fromEnvironment(
  'SOCKET_URL',
  defaultValue: 'http://localhost:4000',
);
