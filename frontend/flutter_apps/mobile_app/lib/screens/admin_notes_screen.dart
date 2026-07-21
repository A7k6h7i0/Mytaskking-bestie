import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

class AdminNotesScreen extends ConsumerStatefulWidget {
  const AdminNotesScreen({super.key});

  @override
  ConsumerState<AdminNotesScreen> createState() => _AdminNotesScreenState();
}

class _AdminNotesScreenState extends ConsumerState<AdminNotesScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(apiProvider).listAdminNotes();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _createNote() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final c = BestieColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New admin note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: bodyCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Note to super admin'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: c.brand),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiProvider).createAdminNote(
            title: titleCtrl.text.trim(),
            body: bodyCtrl.text.trim(),
          );
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not send note',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      titleCtrl.dispose();
      bodyCtrl.dispose();
    }
  }

  Future<void> _review(String id, String status) async {
    try {
      await ref.read(apiProvider).reviewAdminNote(id, status: status);
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Review failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStoreProvider).user;
    final isSuper = user?.isPlatformSuperAdmin ?? false;
    final isSales = user?.isSalesHead ?? false;
    final c = BestieColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin notes'),
        actions: [
          if (isSales)
            IconButton(onPressed: _createNote, icon: const Icon(Icons.add)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: BestieSpinner())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: c.danger)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final n = _items[i];
                    final status = (n['status'] ?? 'PENDING').toString();
                    return Card(
                      child: ListTile(
                        title: Text(n['title']?.toString() ?? 'Note'),
                        subtitle: Text(n['body']?.toString() ?? ''),
                        trailing: BestieBadge(
                          tone: status == 'APPROVED'
                              ? BestieTone.success
                              : status == 'REJECTED'
                                  ? BestieTone.danger
                                  : BestieTone.warning,
                          child: Text(status),
                        ),
                        onTap: isSuper && status == 'PENDING'
                            ? () => showModalBottomSheet<void>(
                                  context: context,
                                  builder: (ctx) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.check),
                                          title: const Text('Approve note'),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            _review(n['id'].toString(), 'APPROVED');
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.close),
                                          title: const Text('Reject note'),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            _review(n['id'].toString(), 'REJECTED');
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}
