import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bestie_design/bestie_design.dart';

import '../state.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  static const _tabs = ['Workspace', 'Chat', 'Tasks', 'Calls'];
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.chat_bubble_outline,
    Icons.view_kanban_outlined,
    Icons.call_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStoreProvider).user;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BestieTokens.cSurface,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [BestieTokens.cAccent, BestieTokens.cBrand],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(_tabs[_index],
                style: const TextStyle(color: BestieTokens.cText, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: BestieTokens.cTextSoft),
            onPressed: () async {
              await ref.read(apiProvider).logout();
              if (mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BestieTokens.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user != null) ...[
                Row(
                  children: [
                    BestieAvatar(
                      name: user.name,
                      imageUrl: user.avatarUrl,
                      isClient: user.isClient,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BestieUserName(name: user.name, isClient: user.isClient, showChip: true),
                        Text(
                          user.isClient ? (user.clientCompany ?? 'Client') : user.role.replaceAll('_', ' '),
                          style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: BestieTokens.s4),
              ],
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: BestieTokens.cSurface,
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    border: Border.all(color: BestieTokens.cBorder),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_icons[_index], size: 48, color: BestieTokens.cTextFaint),
                      const SizedBox(height: 8),
                      Text('${_tabs[_index]} screen',
                          style: const TextStyle(
                              color: BestieTokens.cTextMuted,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: List.generate(_tabs.length, (i) {
          return NavigationDestination(icon: Icon(_icons[i]), label: _tabs[i]);
        }),
      ),
    );
  }
}
