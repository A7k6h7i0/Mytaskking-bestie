import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Pick, crop, upload, or remove the signed-in user's profile photo.
class ProfileAvatarEditor {
  ProfileAvatarEditor._();

  static String _croppedFilename(String original) {
    final base = original.contains('.')
        ? original.substring(0, original.lastIndexOf('.'))
        : original;
    return '$base-cropped.jpg';
  }

  static Future<void> pickAndUpload(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        imageQuality: 92,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!context.mounted) return;
      final cropped = await showAvatarCropSheet(
        context,
        imageBytes: bytes,
      );
      if (cropped == null || !context.mounted) return;

      final asset = await ref.read(apiProvider).uploadFile(
            bytes: cropped,
            filename: _croppedFilename(picked.name),
            mimeType: 'image/jpeg',
          );
      final url = asset['url']?.toString();
      if (url == null || url.isEmpty) throw 'Upload returned no image URL';
      final response = await ref.read(apiProvider).updateMyAvatar(url);
      await ref.read(authStoreProvider).updateUser(
            Map<String, dynamic>.from(response['user'] as Map),
          );
      if (context.mounted) {
        bestieToast(context, 'Profile photo updated',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        bestieToast(context, 'Could not update profile photo',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  static Future<void> remove(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStoreProvider).user;
    if (user?.avatarUrl == null || user!.avatarUrl!.isEmpty) return;

    final ok = await bestieConfirm(
      context,
      title: 'Remove profile photo?',
      description: 'Your account will use the default avatar again.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;

    try {
      final response = await ref.read(apiProvider).clearMyAvatar();
      await ref.read(authStoreProvider).updateUser(
            Map<String, dynamic>.from(response['user'] as Map),
          );
      if (context.mounted) {
        bestieToast(context, 'Profile photo removed',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        bestieToast(context, 'Could not remove profile photo',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  static Future<void> showOptions(
    BuildContext context,
    WidgetRef ref, {
    required bool hasAvatar,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: BestieColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_a_photo_outlined),
              title: const Text('Change profile photo'),
              subtitle: const Text('Choose an image and crop before upload'),
              onTap: () => Navigator.pop(ctx, 'change'),
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: BestieTokens.cDanger),
                title: const Text('Remove profile photo',
                    style: TextStyle(color: BestieTokens.cDanger)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ListTile(
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;
    if (action == 'change') {
      await pickAndUpload(context, ref);
    } else if (action == 'remove') {
      await remove(context, ref);
    }
  }
}

/// Avatar with a camera badge — tap to open photo options.
class EditableProfileAvatar extends ConsumerWidget {
  const EditableProfileAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.isClient = false,
    this.size = 56,
  });

  final String name;
  final String? imageUrl;
  final bool isClient;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final hasAvatar = imageUrl != null && imageUrl!.isNotEmpty;
    final badgeSize = size * 0.34;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ProfileAvatarEditor.showOptions(
          context,
          ref,
          hasAvatar: hasAvatar,
        ),
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            BestieAvatar(
              name: name,
              imageUrl: imageUrl,
              isClient: isClient,
              size: size,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: colors.brand,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: badgeSize * 0.55,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
