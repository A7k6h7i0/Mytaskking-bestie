import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

/// Full-screen KYC / document image viewer with pinch-to-zoom.
class DocumentImageViewer extends StatelessWidget {
  const DocumentImageViewer({
    super.key,
    required this.title,
    required this.imageUrl,
  });

  final String title;
  final String imageUrl;

  static void show(
    BuildContext context, {
    required String title,
    required String imageUrl,
  }) {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DocumentImageViewer(
          title: title,
          imageUrl: imageUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transform = TransformationController();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: GestureDetector(
        onDoubleTap: () {
          transform.value = transform.value.isIdentity()
              ? (Matrix4.identity()..scale(2.0))
              : Matrix4.identity();
        },
        child: InteractiveViewer(
          transformationController: transform,
          minScale: 1.0,
          maxScale: 4.0,
          child: Center(
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 2,
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load document image',
                  style: TextStyle(color: BestieColors.of(context).danger),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
