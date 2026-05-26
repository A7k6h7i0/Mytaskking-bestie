import 'package:flutter/material.dart';
import '../colors.dart';
import '../tokens.dart';

/// Renders a user's name. Clients are always shown in the brand-mandated red.
class BestieUserName extends StatelessWidget {
  final String name;
  final bool isClient;
  final bool showChip;
  final TextStyle? style;

  const BestieUserName({
    super.key,
    required this.name,
    this.isClient = false,
    this.showChip = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    // Use theme-aware text color so the name stays readable in dark mode.
    // Clients keep the brand-mandated red regardless of theme.
    final c = BestieColors.of(context);
    final color = isClient ? c.client : (style?.color ?? c.text);
    final base = (style ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: isClient ? FontWeight.w700 : (style?.fontWeight ?? FontWeight.w600),
    );

    if (!showChip || !isClient) {
      return Text(name, style: base);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: base),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: BestieTokens.cClientSoft,
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
          ),
          child: const Text(
            'CLIENT',
            style: TextStyle(
              color: BestieTokens.cClient,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}
