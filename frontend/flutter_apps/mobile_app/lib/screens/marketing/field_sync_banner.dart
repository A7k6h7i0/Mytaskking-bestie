import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'field_offline_queue.dart';

/// Shows pending offline field actions count.
class FieldSyncBanner extends StatelessWidget {
  const FieldSyncBanner({super.key, this.onSync});

  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: FieldOfflineQueue.snapshot(),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final visits = (data['visits'] as List?)?.length ?? 0;
        final gps = (data['gps'] as List?)?.length ?? 0;
        final incidents = (data['incidents'] as List?)?.length ?? 0;
        final total = visits + gps + incidents;
        if (total == 0) return const SizedBox.shrink();
        final c = BestieColors.of(context);
        return Material(
          color: c.warningSoft,
          child: InkWell(
            onTap: onSync,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined, color: c.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$total item(s) waiting to sync — tap to retry',
                      style: TextStyle(color: c.text, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onSync != null)
                    Icon(Icons.sync_rounded, color: c.brand, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
