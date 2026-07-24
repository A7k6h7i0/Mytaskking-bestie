import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import '../../state.dart';
import 'field_offline_queue.dart';

/// Navigate back through the stack, or fall back to [fallbackRoute].
void fieldGoBack(BuildContext context, {String fallbackRoute = '/field'}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackRoute);
  }
}

/// Resolves active visit from server or offline queue.
Future<Map<String, dynamic>?> resolveActiveFieldVisit(BestieApi api) async {
  final server = await api.getActiveFieldVisit();
  if (server != null) return server;
  final pending = await FieldOfflineQueue.snapshot();
  final visits = (pending['visits'] as List?) ?? const [];
  for (final raw in visits.reversed) {
    final v = Map<String, dynamic>.from(raw as Map);
    if (v['check_out_at'] != null) continue;
    if (v['status']?.toString() != 'in_progress') continue;
    final offlineId = v['offlineId']?.toString() ?? v['offline_id']?.toString();
    return {
      'id': offlineId,
      'outletId': v['outletId'] ?? v['outlet_id'],
      'offline': true,
      'checkInAt': v['check_in_at'],
    };
  }
  return null;
}

Future<Map<String, dynamic>?> pickMarketingOutlet(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Select outlet',
}) async {
  final resp = await ref.read(apiProvider).listMarketingOutlets(pageSize: 100);
  final items = ((resp['items'] as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  if (!context.mounted || items.isEmpty) return null;
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (_, scroll) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final o = items[i];
                  return ListTile(
                    title: Text(o['name']?.toString() ?? 'Outlet'),
                    subtitle: Text(o['address']?.toString() ?? ''),
                    onTap: () => Navigator.pop(ctx, o),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<List<Map<String, dynamic>>> pickMarketingOutletsMulti(
  BuildContext context,
  WidgetRef ref, {
  List<String> initialIds = const [],
}) async {
  final resp = await ref.read(apiProvider).listMarketingOutlets(pageSize: 200);
  final items = ((resp['items'] as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  if (!context.mounted || items.isEmpty) return const [];
  final selected = {...initialIds};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: const Text('Select outlets'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final o = items[i];
              final id = o['id'].toString();
              return CheckboxListTile(
                value: selected.contains(id),
                title: Text(o['name']?.toString() ?? 'Outlet'),
                onChanged: (v) => setDialog(() {
                  if (v == true) {
                    selected.add(id);
                  } else {
                    selected.remove(id);
                  }
                }),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Done')),
        ],
      ),
    ),
  );
  if (ok != true) return const [];
  return items.where((o) => selected.contains(o['id'].toString())).toList();
}

Future<Map<String, dynamic>?> pickExecutive(
  BuildContext context,
  WidgetRef ref,
) async {
  final list = await ref.read(apiProvider).listEmployees(role: 'EXECUTIVE', pageSize: 100);
  if (!context.mounted || list.isEmpty) return null;
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        children: [
          const ListTile(title: Text('Assign executive')),
          for (final e in list)
            ListTile(
              title: Text(e['name']?.toString() ?? 'Executive'),
              subtitle: Text(e['userId']?.toString() ?? ''),
              onTap: () => Navigator.pop(ctx, e),
            ),
        ],
      ),
    ),
  );
}
