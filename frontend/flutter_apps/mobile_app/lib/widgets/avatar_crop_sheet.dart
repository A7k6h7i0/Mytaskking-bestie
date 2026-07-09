import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

/// Shows a bottom sheet to preview and square-crop a profile photo before upload.
Future<Uint8List?> showAvatarCropSheet(
  BuildContext context, {
  required Uint8List imageBytes,
}) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _AvatarCropSheet(imageBytes: imageBytes),
  );
}

class _AvatarCropSheet extends StatefulWidget {
  final Uint8List imageBytes;

  const _AvatarCropSheet({required this.imageBytes});

  @override
  State<_AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<_AvatarCropSheet> {
  bool _processing = false;

  Future<void> _confirm() async {
    setState(() => _processing = true);
    try {
      final cropped = await _centerSquareCrop(widget.imageBytes);
      if (!mounted) return;
      Navigator.pop(context, cropped);
    } catch (_) {
      if (mounted) {
        bestieToast(context, 'Could not process photo',
            kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<Uint8List> _centerSquareCrop(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final side = math.min(image.width, image.height);
    final offsetX = (image.width - side) ~/ 2;
    final offsetY = (image.height - side) ~/ 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        offsetX.toDouble(),
        offsetY.toDouble(),
        side.toDouble(),
        side.toDouble(),
      ),
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(side, side);
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Crop failed');
    return data.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Profile photo',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Center your face in the frame. The photo will be cropped to a square.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BestieTokens.rLg),
              child: ColoredBox(
                color: colors.bgSoft,
                child: Image.memory(
                  widget.imageBytes,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _processing ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _processing ? null : _confirm,
                  child: _processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Use photo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
