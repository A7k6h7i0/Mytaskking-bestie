# MyTaskKing — Flutter apps

Four targets, one shared codebase. Mobile (Android + iOS) is the source of
truth for the screen widgets; the desktop apps consume the same screens
through a sidebar shell instead of a bottom-nav.

```
flutter_apps/
├── shared_design_system/   tokens, theme, motion, Logo, Avatar, Sidebar,
│                           UserName, PrimaryButton, TextField, RiveAnimation,
│                           plus primitives (Badge, StatusBadge, Spinner,
│                           ProgressRing, SuccessCheck, EmptyState,
│                           SegmentedControl, ConfirmDialog, Toast, BottomSheet)
├── shared_core/            API client (Dio + token refresh), typed API
│                           extension covering every backend endpoint,
│                           AuthStore (secure storage), Socket.IO client,
│                           MyTaskKingRealtime event hub, Riverpod providers
│                           (auth, dashboard, channels, chat, tasks, meetings,
│                           calendar, notifications, presence, search, saved,
│                           sessions, flags, theme)
├── mobile_app/             Android + iOS — entry point, go_router config,
│                           bottom-nav shell, feature screens. Exposes every
│                           screen via `screens.dart` so desktop apps reuse.
├── windows_app/            Windows desktop — sidebar shell consuming
│                           `package:bestie_mobile/screens.dart`.
└── macos_app/              macOS desktop — same shape as windows_app.
```

## What's built (mobile)

| Screen | Path | What it does |
|---|---|---|
| Login | `/login` | Gradient backdrop, animated brand logo, success-check celebration, shake-on-error |
| Dashboard | `/dashboard` | Role-aware stat grid (admin / employee / client), realtime activity feed for admins, AnimatedCounter for every numeric stat |
| Chat list | `/chat` | Channel directory with unread badges and search bottom sheet |
| Chat detail | `/chat/:channelId` | Bubble layout, composer, realtime invalidation on new messages |
| Tasks | `/tasks` | Kanban (drag between columns) + list view via segmented control, new-task bottom sheet |
| Meetings | `/meetings` | Create + join + end Agora rooms (voice / video / webinar / livestream) |
| Notifications | `/notifications` | Realtime grouped by category, mark-all-read, live indicator |
| Profile | `/profile` | Presence picker, theme switcher, active sessions, sign-out-everywhere, logout |

## What's built (desktop)

Both desktop apps wrap the same screens in a sidebar shell. Routes are
selected via the sidebar; the body uses `AnimatedSwitcher` to cross-fade
between feature screens. The shared auth store, API, Riverpod providers,
and realtime hub are all the same singletons as on mobile — login state,
unread counts, and presence travel with the user across windows.

Desktop-only admin tabs (Activity, Analytics, Employees, Clients) are the
next layer; the React web has them today, and the screens drop straight in
the same way once you copy the patterns from the mobile screens.

## Why the screens live in `mobile_app`

It keeps the codebase honest — there's no "shared screens" abstraction that
diverges from any real app. The screens are written against `package:bestie_design`
+ `package:bestie_core`, both of which the desktop targets also depend on.
The desktop apps add `bestie_mobile` as a path dependency and import from
`bestie_mobile/screens.dart`, which exports each screen plus the state
helpers. Re-skinning a screen for desktop is a wrap, not a rewrite.

## Build

```bash
# 1. bootstrap each target's platform scaffolding
cd mobile_app && flutter create --org com.mytaskking --platforms=android,ios . && flutter pub get
cd windows_app && flutter create --org com.mytaskking --platforms=windows . && flutter pub get
cd macos_app   && flutter create --org com.mytaskking --platforms=macos   . && flutter pub get

# 2. run any target
flutter run --dart-define=API_URL=http://localhost:4000 --dart-define=SOCKET_URL=http://localhost:4000
```

`flutter create` writes Android Gradle, iOS Xcode, Windows CMake, macOS
Xcode shells without touching any Dart sources.

## State + realtime

Every screen reads state through Riverpod providers in `bestie_core`:

- `apiProvider` — the Dio-backed MyTaskKing API singleton, with the typed
  extension methods (`dashboardOverview()`, `listChannels()`, `createTask()`,
  `meetingToken()`, etc.)
- `realtimeProvider` — opens the socket on first watch, exposes
  `on(topic, handler)` and `emit(topic, data)`. Providers like
  `messagesProvider(channelId)` re-invalidate themselves on
  `chat.message.created`; `notificationsProvider` is a `StreamProvider`
  that re-fetches on `activity.recorded` and `announcement.published`.
- `themeModeProvider`, `presenceStatusProvider`, `searchQueryProvider`
  — plain `StateProvider`s the UI toggles directly.

## Clients are red, everywhere

`BestieUserName` and `BestieAvatar` render any user whose `isClient = true`
in `BestieTokens.cClient` — the same brand-mandated red as the React web.
This is a contract, not a styling choice.
