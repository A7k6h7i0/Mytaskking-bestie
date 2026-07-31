/// Server and client agree: chat / file uploads are capped at 50 MB.
const int kMaxUploadBytes = 50 * 1024 * 1024;
const String kMaxUploadLabel = '50 MB';

String formatUploadBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// User-facing message when [bytes] exceeds [kMaxUploadBytes].
String? uploadSizeLimitMessage(int bytes) {
  if (bytes <= kMaxUploadBytes) return null;
  return "You can't upload more than $kMaxUploadLabel. "
      'This file is ${formatUploadBytes(bytes)}.';
}

bool isApkFilename(String name) =>
    name.toLowerCase().trim().endsWith('.apk');

bool isApkMime(String mime) {
  final m = mime.toLowerCase();
  return m.contains('android.package-archive') ||
      m == 'application/apk' ||
      m == 'application/x-apk';
}

bool isApkAttachment({required String name, required String mime}) =>
    isApkFilename(name) || isApkMime(mime);
