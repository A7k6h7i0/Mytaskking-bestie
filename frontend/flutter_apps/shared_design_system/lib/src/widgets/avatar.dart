import 'package:flutter/material.dart';
import '../tokens.dart';

class BestieAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final bool isClient;

  const BestieAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 32,
    this.isClient = false,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2);
    return parts.map((s) => s[0].toUpperCase()).join();
  }

  Color get _bg {
    int h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) % 360;
    }
    return HSLColor.fromAHSL(1, h.toDouble(), 0.6, 0.88).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final ring = isClient
        ? Border.all(color: BestieTokens.cClient, width: 2)
        : null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: imageUrl != null ? null : _bg,
        image: imageUrl != null
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
            : null,
        border: ring,
      ),
      alignment: Alignment.center,
      child: imageUrl != null
          ? null
          : Text(
              _initials.isEmpty ? '?' : _initials,
              style: TextStyle(
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
                color: BestieTokens.cText.withOpacity(0.75),
              ),
            ),
    );
  }
}
