library gal;

/// No-op gallery saver on desktop — chat media uses Downloads instead.
class Gal {
  static Future<void> putImageBytes(
    List<int> bytes, {
    String? name,
  }) async {}

  static Future<void> putVideo(
    String path, {
    String? album,
  }) async {}
}
