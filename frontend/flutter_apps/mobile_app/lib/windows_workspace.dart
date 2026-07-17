import 'dart:io' show Platform;

/// MyTaskKing Windows desktop: chat + history workspace only (no live calls/meetings).
bool get kWindowsWorkspaceNoCalls => Platform.isWindows;
