import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

/// Fullscreen profile photo viewer — tap avatar in chat header or list.
class ProfileAvatarViewer extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isClient;

  const ProfileAvatarViewer({
    super.key,
    required this.name,
    this.imageUrl,
    this.isClient = false,
  });

  static void show(
    BuildContext context, {
    required String name,
    String? imageUrl,
    bool isClient = false,
  }) {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ProfileAvatarViewer(
          name: name,
          imageUrl: imageUrl,
          isClient: isClient,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final transform = TransformationController();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            GestureDetector(
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
                    imageUrl!,
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
                    errorBuilder: (_, __, ___) => BestieAvatar(
                      name: name,
                      size: 160,
                      isClient: isClient,
                    ),
                  ),
                ),
              ),
            )
          else
            Center(
              child: BestieAvatar(
                name: name,
                size: 160,
                isClient: isClient,
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: BestieTokens.fwBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
