import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bestie_design/bestie_design.dart';
import 'package:bestie_core/bestie_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = BestieAuthStore();
  await auth.load();
  runApp(ProviderScope(child: BestieWindowsApp(auth: auth)));
}

class BestieWindowsApp extends StatelessWidget {
  final BestieAuthStore auth;
  const BestieWindowsApp({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bestie',
      theme: BestieTheme.light(),
      debugShowCheckedModeBanner: false,
      home: const _Shell(),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  String _route = '/dashboard';
  static const _items = [
    BestieSidebarItem(icon: Icons.dashboard_outlined, label: 'Dashboard', route: '/dashboard'),
    BestieSidebarItem(icon: Icons.chat_bubble_outline, label: 'Chat', route: '/chat'),
    BestieSidebarItem(icon: Icons.view_kanban_outlined, label: 'Tasks', route: '/tasks'),
    BestieSidebarItem(icon: Icons.call_outlined, label: 'Calls', route: '/calls'),
    BestieSidebarItem(icon: Icons.headset_mic_outlined, label: 'Telecaller', route: '/telecaller'),
    BestieSidebarItem(icon: Icons.people_outline, label: 'Employees', route: '/employees'),
    BestieSidebarItem(icon: Icons.manage_accounts_outlined, label: 'Clients', route: '/clients'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          BestieSidebar(
            items: _items,
            activeRoute: _route,
            onSelect: (r) => setState(() => _route = r),
          ),
          Expanded(
            child: Container(
              color: BestieTokens.cBg,
              padding: const EdgeInsets.all(BestieTokens.s5),
              child: Center(
                child: Text('Desktop · $_route',
                    style: const TextStyle(color: BestieTokens.cTextMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
