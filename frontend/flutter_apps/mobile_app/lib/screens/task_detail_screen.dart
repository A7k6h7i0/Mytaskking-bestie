import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import 'task_actions_sheet.dart';

/// Full-screen detail for a single task. Wraps the existing
/// [TaskActionsSheet] body in a Scaffold so users get a real back button +
/// dedicated route (`/tasks/:id`) instead of a bottom sheet.
///
/// All accept / decline / complete actions inside the sheet pop the current
/// route on success — same behavior as the modal version had.
class TaskDetailScreen extends ConsumerWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          // Prefer the navigator stack pop so we land on whatever screen
          // pushed us (chat list, tasks, search results, notifications).
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/tasks');
            }
          },
        ),
        title: const Text('Task'),
      ),
      body: SafeArea(
        child: TaskActionsSheet(taskId: taskId, parentRef: ref),
      ),
    );
  }
}
