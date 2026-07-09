import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../tokens.dart';

/// Square avatar crop — used after picking a profile photo on mobile & desktop.
Future<Uint8List?> showAvatarCropSheet(
  BuildContext context, {
  required Uint8List imageBytes,
}) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AvatarCropSheet(imageBytes: imageBytes),
  );
}

class _AvatarCropSheet extends StatefulWidget {
  const _AvatarCropSheet({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<_AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<_AvatarCropSheet> {
  final _cropController = CropController();
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: Colors.black,
          borderRadius: BorderRadius.circular(BestieTokens.rXl),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Crop profile photo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: BestieTokens.fwBold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            _cropping ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Crop(
                      controller: _cropController,
                      image: widget.imageBytes,
                      aspectRatio: 1,
                      withCircleUi: true,
                      baseColor: Colors.black,
                      maskColor: Colors.black.withValues(alpha: 0.55),
                      onCropped: (result) {
                        if (!mounted) return;
                        setState(() => _cropping = false);
                        switch (result) {
                          case CropSuccess(:final croppedImage):
                            Navigator.pop(context, croppedImage);
                          case CropFailure():
                            break;
                        }
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed:
                            _cropping ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _cropping
                            ? null
                            : () {
                                setState(() => _cropping = true);
                                _cropController.crop();
                              },
                        icon: _cropping
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(_cropping ? 'Cropping…' : 'Use photo'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
