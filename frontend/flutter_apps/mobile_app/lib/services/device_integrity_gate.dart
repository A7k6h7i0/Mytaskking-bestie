import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'device_integrity_service.dart';

/// Blocks the app on Android when mock GPS, root, or emulator is detected.
/// Re-checks on resume and every 20 seconds while open.
class DeviceIntegrityGate extends StatefulWidget {
  const DeviceIntegrityGate({super.key, required this.child});

  final Widget child;

  @override
  State<DeviceIntegrityGate> createState() => _DeviceIntegrityGateState();
}

class _DeviceIntegrityGateState extends State<DeviceIntegrityGate>
    with WidgetsBindingObserver {
  static const _periodicInterval = Duration(seconds: 20);

  bool _checking = true;
  bool _retrying = false;
  DeviceIntegrityResult _result = const DeviceIntegrityResult.ok();
  Timer? _periodicTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runCheck();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) => _runCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runCheck();
    }
  }

  Future<void> _runCheck({bool showRetrySpinner = false}) async {
    if (showRetrySpinner) {
      setState(() => _retrying = true);
    }
    final result = await DeviceIntegrityService.check();
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const _IntegrityCheckSplash();
    }
    if (!_result.passed) {
      return _SecurityBlockScreen(
        reasons: _result.reasons,
        retrying: _retrying,
        onRetry: () => _runCheck(showRetrySpinner: true),
      );
    }
    return widget.child;
  }
}

class _IntegrityCheckSplash extends StatelessWidget {
  const _IntegrityCheckSplash();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: BestieTheme.light().scaffoldBackgroundColor,
        body: const Center(child: BestieSpinner()),
      ),
    );
  }
}

class _SecurityBlockScreen extends StatelessWidget {
  const _SecurityBlockScreen({
    required this.reasons,
    required this.onRetry,
    this.retrying = false,
  });

  final List<String> reasons;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.resolve(isDark: false);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: c.surface,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gpp_bad_rounded, size: 64, color: c.danger),
                    const SizedBox(height: 16),
                    Text(
                      'Security check failed',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Field visits require a trusted device and real GPS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.surface1,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: reasons
                            .map(
                              (r) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_outline, size: 16, color: c.danger),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(r, style: TextStyle(color: c.text))),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: retrying ? null : onRetry,
                        style: FilledButton.styleFrom(backgroundColor: c.brand),
                        child: retrying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Try again'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Turn off any fake-location app, disable root access, or use a physical device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
