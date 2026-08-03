# MyTaskKing macOS desktop app

macOS desktop workspace — same chat/calls/meetings shell as Linux, including work activity and a background agent.

## What works on macOS

- Login, split-pane chat, profile, search
- Voice/video calls and meetings (same as Linux — not chat-only like Windows)
- Emergency buzzer in chat ⋮ menu (DM + group)
- Org TTS caller prompts
- Menu bar tray (open / sign out / quit)
- Auto-logout at configured time (optional)
- **Work activity** — idle detection, screen capture, and native “Are you working?” prompts
- **Background agent** — keeps running when the window is closed; registers a LaunchAgent for autostart on login

## Work activity setup

On first capture, macOS may ask for **Screen Recording** permission:

**System Settings → Privacy & Security → Screen Recording → MyTaskKing**

Without this permission, captures fall back to screenshot-only or fail gracefully.

Logs (if needed for support): `~/Library/Caches/MyTaskKing/work_activity_agent.log`

## Background agent

- On login, a LaunchAgent starts the app with `--background-agent` (hidden, tray-only when signed in).
- Closing the window while signed in hides or minimizes instead of quitting, so tracking continues.
- Opening the app again while the agent is running brings the existing window forward.

LaunchAgent file: `~/Library/LaunchAgents/com.mytaskking.background-agent.plist`

## Build requirements

- **Physical Mac or Mac cloud VM** (cannot build from Windows)
- macOS 11+
- [Flutter SDK](https://docs.flutter.dev/get-started/install/macos) with `flutter config --enable-macos-desktop`
- **Xcode** from the App Store
- **CocoaPods**: `sudo gem install cocoapods`

## Build

```bash
cd frontend/flutter_apps/macos_app
chmod +x build_macos.sh
./build_macos.sh
```

Output:

- `build/macos/Build/Products/Release/mytaskking_macos.app`
- `dist/mytaskking-macos.zip`

Run:

```bash
open build/macos/Build/Products/Release/mytaskking_macos.app
```

## Distribution

For users outside your machine:

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/)
2. Code-sign the `.app`
3. Notarize with Apple
4. Ship the zip or a signed `.dmg`

## API URL

Same as Windows/Linux — set via `--dart-define=API_URL=...` and `SOCKET_URL=...` at build time, or use defaults from `shared_core`.

## Folder layout

Cloned from `linux_app`:

- `lib/` — desktop shell + split chat (shared with Linux)
- `desktop_stubs/` — mobile-only plugins stubbed for desktop
- `macos/Runner/MytaskkingDesktopPlugin.swift` — idle time, screen capture, work prompts
- `macos/` — Xcode project (entitlements, Info.plist)
