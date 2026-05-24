import 'package:flutter/material.dart';
import '../colors.dart';
import '../tokens.dart';

/// Skeleton row placeholder with a shimmer sweep. Use [BestieSkeletonList]
/// for a full-screen loading state in place of a centered spinner —
/// communicates "content shape" to the user while the network roundtrip
/// completes, which feels noticeably more premium than an empty spinner.
class BestieSkeletonList extends StatefulWidget {
  final int itemCount;
  final BestieSkeletonShape shape;
  final EdgeInsets padding;
  const BestieSkeletonList({
    super.key,
    this.itemCount = 8,
    this.shape = BestieSkeletonShape.listTile,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  State<BestieSkeletonList> createState() => _BestieSkeletonListState();
}

class _BestieSkeletonListState extends State<BestieSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return ListView.builder(
      padding: widget.padding,
      itemCount: widget.itemCount,
      itemBuilder: (_, __) => AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) => _row(c, _ctrl.value),
      ),
    );
  }

  Widget _row(BestieColors c, double t) {
    switch (widget.shape) {
      case BestieSkeletonShape.listTile:
        return _listTileRow(c, t);
      case BestieSkeletonShape.card:
        return _cardRow(c, t);
    }
  }

  Widget _listTileRow(BestieColors c, double t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        _Box(width: 42, height: 42, radius: 999, t: t, colors: c),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Box(width: 180, height: 13, radius: 4, t: t, colors: c),
            const SizedBox(height: 8),
            _Box(width: 120, height: 11, radius: 4, t: t, colors: c),
          ]),
        ),
      ]),
    );
  }

  Widget _cardRow(BestieColors c, double t) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Box(width: 30, height: 4, radius: 2, t: t, colors: c),
          const SizedBox(width: 10),
          _Box(width: 70, height: 12, radius: 4, t: t, colors: c),
        ]),
        const SizedBox(height: 10),
        _Box(width: double.infinity, height: 14, radius: 4, t: t, colors: c),
        const SizedBox(height: 6),
        _Box(width: 220, height: 12, radius: 4, t: t, colors: c),
        const SizedBox(height: 10),
        Row(children: [
          _Box(width: 24, height: 24, radius: 999, t: t, colors: c),
          const SizedBox(width: 4),
          _Box(width: 24, height: 24, radius: 999, t: t, colors: c),
          const Spacer(),
          _Box(width: 80, height: 22, radius: 999, t: t, colors: c),
        ]),
      ]),
    );
  }
}

enum BestieSkeletonShape { listTile, card }

class _Box extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final double t;
  final BestieColors colors;
  const _Box({
    required this.width, required this.height, required this.radius,
    required this.t, required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Diagonal shimmer sweep — base color lightens at the moving stop.
    final dark = colors.isDark;
    final base = dark ? colors.surface2 : colors.surface2;
    final highlight = dark ? colors.surface3 : colors.surface;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + t * 2, -0.3),
          end: Alignment(1.0 + t * 2, 0.3),
          colors: [base, highlight, base],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
