# MyTaskKing Linux desktop app

Linux-only copy of the MyTaskKing desktop workspace. The Windows app lives in
`../windows_app` and is **not** modified by this folder.

## What works on Linux

- Login, chat, tasks, calls/meetings UI
- System tray
- Work Activity: native GTK prompt, idle detection (X11), screen capture
- Background agent + autostart (`~/.config/autostart/mytaskking-background-agent.desktop`)

## Build requirements (Ubuntu/Debian example)

```bash
sudo apt update
sudo apt install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev libx11-dev libxss-dev
```

Also install [Flutter](https://docs.flutter.dev/get-started/install/linux) with Linux desktop enabled:

```bash
flutter config --enable-linux-desktop
flutter doctor
```

## Build

```bash
cd frontend/flutter_apps/linux_app
chmod +x build_linux.sh
./build_linux.sh
```

Output: `dist/mytaskking-linux-x64.tar.gz`

Run:

```bash
tar -xzf dist/mytaskking-linux-x64.tar.gz -C ~/mytaskking
~/mytaskking/mytaskking_linux
```

## Notes

- **X11**: idle time and screenshots use X11/GDK. On pure **Wayland**, idle may read as `0` and capture may fail until a portal-based capture is added.
- This folder is meant to be handed to someone with a **Linux machine** to build — you cannot build the Linux binary from Windows.
- Backend/API URL is configured the same way as the Windows app (see app settings / env).
