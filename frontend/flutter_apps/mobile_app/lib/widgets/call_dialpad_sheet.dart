import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef CallDialpadDigitHandler = void Function(String digit);

/// WhatsApp-style in-call DTMF dial pad (0–9, *, #).
Future<void> showCallDialpadSheet(
  BuildContext context, {
  required CallDialpadDigitHandler onDigit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1A),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _CallDialpadSheet(onDigit: onDigit),
  );
}

class _CallDialpadSheet extends StatefulWidget {
  final CallDialpadDigitHandler onDigit;

  const _CallDialpadSheet({required this.onDigit});

  @override
  State<_CallDialpadSheet> createState() => _CallDialpadSheetState();
}

class _CallDialpadSheetState extends State<_CallDialpadSheet> {
  final _entered = StringBuffer();

  void _tap(String digit) {
    HapticFeedback.selectionClick();
    _entered.write(digit);
    widget.onDigit(digit);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Keypad',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_hide_rounded,
                      color: Colors.white70),
                  tooltip: 'Hide keypad',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: Center(
                child: Text(
                  _entered.isEmpty ? ' ' : _entered.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 4,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['*', '0', '#'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (final digit in row) ...[
                      Expanded(child: _DialKey(label: digit, onTap: () => _tap(digit))),
                      if (digit != row.last) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DialKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 56,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
