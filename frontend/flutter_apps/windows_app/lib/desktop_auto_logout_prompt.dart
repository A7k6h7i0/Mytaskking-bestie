import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

/// Shown when the scheduled auto-logout time is reached.
/// Returns `true` if the user chose **Still working** (+1 hour),
/// `false` if **Work over** (sign out).
Future<bool?> showDesktopAutoLogoutPrompt(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DesktopAutoLogoutPromptDialog(),
  );
}

class _DesktopAutoLogoutPromptDialog extends StatelessWidget {
  const _DesktopAutoLogoutPromptDialog();

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.schedule_rounded, color: c.brandStrong, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'End of work day',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your scheduled sign-out time has arrived.',
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap Work over to sign out and close the app, or Still working '
              'to stay signed in for one more hour.',
              style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.more_time_rounded, size: 18),
          label: const Text('Still working'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          style: FilledButton.styleFrom(backgroundColor: c.brandStrong),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Work over'),
        ),
      ],
    );
  }
}
