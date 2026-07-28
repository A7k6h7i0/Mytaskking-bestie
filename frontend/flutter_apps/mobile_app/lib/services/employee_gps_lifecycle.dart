import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import 'employee_gps_tracker.dart';

/// Starts org-wide employee GPS tracking when logged in.
class EmployeeGpsLifecycle extends ConsumerStatefulWidget {
  const EmployeeGpsLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EmployeeGpsLifecycle> createState() =>
      _EmployeeGpsLifecycleState();
}

class _EmployeeGpsLifecycleState extends ConsumerState<EmployeeGpsLifecycle> {
  StreamSubscription<dynamic>? _authSub;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authStoreProvider);
    _authSub = auth.changes.listen((_) => _sync());
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _sync() async {
    final auth = ref.read(authStoreProvider);
    if (auth.user == null) {
      EmployeeGpsTracker.instance.stop();
      return;
    }
    if (auth.user!.isClient) return;
    await EmployeeGpsTracker.instance.sync(ref.read(apiProvider));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
