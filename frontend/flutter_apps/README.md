# Bestie — Flutter apps

Four targets share one design system + core package:

```
flutter_apps/
├── shared_design_system/   tokens, theme, widgets (Avatar, Sidebar, UserName, …)
├── shared_core/            API client, auth store, socket client, models
├── mobile_app/             Android + iOS
├── windows_app/            Windows desktop
└── macos_app/              macOS desktop
```

## Why this layout

- `shared_design_system` mirrors `frontend/react_web/src/styles/tokens.css`. Both sides reference the same color/spacing/typography contract, so a button drawn in Flutter and one drawn in React look identical.
- `shared_core` is the same API surface (login, refresh, socket auth, models) wherever it runs.
- Each app target is a thin shell — its job is platform shape (mobile bottom-nav, desktop sidebar) and to compose the shared widgets.

## Build

```bash
# bootstrap each target
cd mobile_app && flutter create --org com.bestie --platforms=android,ios . && flutter pub get
cd windows_app && flutter create --org com.bestie --platforms=windows .  && flutter pub get
cd macos_app   && flutter create --org com.bestie --platforms=macos .    && flutter pub get
```

`flutter create` writes the platform-specific scaffolding (Android Gradle, iOS Xcode, etc.) without touching the existing Dart sources. After that, run from any app dir:

```bash
flutter run --dart-define=API_URL=https://api.example.com --dart-define=SOCKET_URL=https://api.example.com
```

## Desktop targets

`windows_app/` and `macos_app/` start as copies of `mobile_app/lib/` with a sidebar-driven layout instead of a bottom navigation bar — drop in `BestieSidebar` from `shared_design_system` and reuse the same screens.

## Clients are red, everywhere

`BestieUserName` and `BestieAvatar` render any user whose `isClient = true` in `BestieTokens.cClient` (the same `--c-client` red as the web). Do not override this color — it is a contract.
