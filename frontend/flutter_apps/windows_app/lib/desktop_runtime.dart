import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

class DesktopRuntime {
  DesktopRuntime._();

  static const startupFlag = '--background-agent';
  static const _startupValueName = 'MyTaskKingBackgroundAgent';
  static const _lockFilename = 'mytaskking-background-agent.lock';
  static const _foregroundSignalFilename =
      'mytaskking-foreground-request.signal';

  static bool _backgroundRequested = false;
  static bool _primaryAgent = true;
  static bool _backgroundSessionActive = false;
  static RandomAccessFile? _lockHandle;
  static Timer? _foregroundSignalTimer;
  static DateTime? _lastForegroundSignalAt;

  static bool get backgroundRequested => _backgroundRequested;
  static bool get primaryAgent => _primaryAgent;
  static bool get interceptClose =>
      Platform.isWindows && _primaryAgent && _backgroundSessionActive;
  static bool get hideOnClose => interceptClose && _backgroundRequested;
  static bool get shouldRunActivityAgent =>
      !Platform.isWindows || _primaryAgent;

  static Future<bool> initialize(List<String> args) async {
    _backgroundRequested = args.contains(startupFlag);
    _primaryAgent = true;
    if (Platform.isWindows) {
      _primaryAgent = await _tryAcquireAgentLock();
      await _ensureStartupRegistration();
      if (!_primaryAgent && !_backgroundRequested) {
        await _requestForeground();
        return false;
      }
      if (_backgroundRequested && !_primaryAgent) {
        return false;
      }
    }
    return true;
  }

  static Future<bool> configureWindowForSession(
      {required bool hasAuthSession}) async {
    if (!Platform.isWindows) return true;
    _backgroundSessionActive = hasAuthSession;
    if (_backgroundRequested && !_backgroundSessionActive) {
      return false;
    }
    await _configureWindow();
    if (_primaryAgent) {
      _startForegroundListener();
    }
    return true;
  }

  static Future<void> release() async {
    _foregroundSignalTimer?.cancel();
    _foregroundSignalTimer = null;
    try {
      await _lockHandle?.unlock();
    } catch (_) {}
    try {
      await _lockHandle?.close();
    } catch (_) {}
    _lockHandle = null;
  }

  static Future<void> hideWindowToBackground() async {
    if (!Platform.isWindows) return;
    try {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    } catch (_) {}
  }

  static Future<void> handoffToBackgroundAgent() async {
    if (!Platform.isWindows || !_primaryAgent || !_backgroundSessionActive) {
      return;
    }
    final executable = Platform.executable;
    if (executable.isEmpty) return;
    await release();
    try {
      await Process.start(
        executable,
        [startupFlag],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
  }

  static Future<void> revealAgentWindow() async {
    if (!Platform.isWindows) return;
    try {
      await _bringWindowToFront();
    } catch (_) {}
  }

  static Future<void> _configureWindow() async {
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(1280, 720),
        center: true,
        title: 'MyTaskKing',
        skipTaskbar: hideOnClose,
      ),
      () async {
        await windowManager.setPreventClose(interceptClose);
        if (hideOnClose) {
          await windowManager.setPreventClose(true);
          await windowManager.hide();
        } else {
          await _bringWindowToFront();
        }
      },
    );
  }

  static Future<void> _bringWindowToFront() async {
    await windowManager.setSkipTaskbar(false);
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();

    // Windows can keep the window behind another app even after show/focus.
    // Toggling always-on-top briefly makes the first launch visibly come forward.
    await windowManager.setAlwaysOnTop(true);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await windowManager.setAlwaysOnTop(false);
    await windowManager.focus();
  }

  static Future<bool> _tryAcquireAgentLock() async {
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}$_lockFilename';
    final file = File(path);
    try {
      _lockHandle = await file.open(mode: FileMode.write);
      await _lockHandle!.lock(FileLock.blockingExclusive);
      await _lockHandle!.setPosition(0);
      await _lockHandle!.truncate(0);
      await _lockHandle!
          .writeString('$pid:${DateTime.now().toIso8601String()}');
      return true;
    } catch (_) {
      try {
        await _lockHandle?.close();
      } catch (_) {}
      _lockHandle = null;
      return false;
    }
  }

  static void _startForegroundListener() {
    if (!Platform.isWindows) return;
    _foregroundSignalTimer?.cancel();
    _foregroundSignalTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) async {
        final signalFile = File(_foregroundSignalPath);
        if (!await signalFile.exists()) return;
        try {
          final modifiedAt = await signalFile.lastModified();
          if (_lastForegroundSignalAt != null &&
              !modifiedAt.isAfter(_lastForegroundSignalAt!)) {
            return;
          }
          _lastForegroundSignalAt = modifiedAt;
          await revealAgentWindow();
        } catch (_) {}
      },
    );
  }

  static Future<void> _requestForeground() async {
    if (!Platform.isWindows) return;
    final signalFile = File(_foregroundSignalPath);
    try {
      await signalFile.writeAsString(DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static String get _foregroundSignalPath =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}$_foregroundSignalFilename';

  static Future<void> _ensureStartupRegistration() async {
    final executable = Platform.executable;
    if (executable.isEmpty) return;
    final commandValue = '"$executable" $startupFlag';
    final script = r'''
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
New-Item -Path $runKey -Force | Out-Null
Set-ItemProperty -Path $runKey -Name ''' +
        _ps(_startupValueName) +
        r''' -Value ''' +
        _ps(commandValue) +
        r'''
''';
    await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ],
    );
  }

  static String _ps(String value) => "'${value.replaceAll("'", "''")}'";
}
