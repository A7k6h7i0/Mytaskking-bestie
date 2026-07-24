import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

/// Compact +/- quantity control that avoids ListTile trailing overflow.
class FieldQtyStepper extends StatelessWidget {
  const FieldQtyStepper({
    super.key,
    required this.qty,
    required this.onChanged,
  });

  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 22,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: qty > 0 ? () => onChanged(qty - 1) : null,
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
          ),
        ),
        SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 22,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onChanged(qty + 1),
          ),
        ),
      ],
    );
  }
}
