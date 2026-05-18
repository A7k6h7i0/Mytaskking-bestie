import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bestie_design/bestie_design.dart';

/// Mobile shell with bottom navigation. Each tab routes through go_router so
/// deep-links (`/chat/abc`) still land in the right place inside the shell.
class ShellScreen extends ConsumerWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  static const _tabs = [
    _Tab('/dashboard',     Icons.dashboard_outlined,    'Home'),
    _Tab('/chat',          Icons.chat_bubble_outline,   'Chat'),
    _Tab('/tasks',         Icons.view_kanban_outlined,  'Tasks'),
    _Tab('/meetings',      Icons.videocam_outlined,     'Meet'),
    _Tab('/profile',       Icons.person_outline,        'Me'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    int index = _tabs.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: _tabs.map((t) => NavigationDestination(
          icon: Icon(t.icon),
          label: t.label,
        )).toList(),
      ),
    );
  }
}

class _Tab {
  final String path;
  final IconData icon;
  final String label;
  const _Tab(this.path, this.icon, this.label);
}
