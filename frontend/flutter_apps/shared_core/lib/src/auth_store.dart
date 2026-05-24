import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

/// Persists tokens + user identity securely (keychain on iOS/macOS, Keystore
/// on Android, DPAPI on Windows).
///
/// On app boot we *must* restore the cached [BestieUser] in addition to the
/// access/refresh tokens — otherwise the chat detail renders every message
/// on the left side because `user?.id` is null and the "is this mine?" check
/// never matches.
class BestieAuthStore {
  static const _kAccess = 'bestie.access';
  static const _kRefresh = 'bestie.refresh';
  static const _kUser = 'bestie.user';

  final _storage = const FlutterSecureStorage();
  final _controller = StreamController<BestieUser?>.broadcast();

  String? _accessToken;
  String? _refreshToken;
  BestieUser? _user;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  BestieUser? get user => _user;
  Stream<BestieUser?> get changes => _controller.stream;

  Future<void> load() async {
    _accessToken = await _storage.read(key: _kAccess);
    _refreshToken = await _storage.read(key: _kRefresh);
    final raw = await _storage.read(key: _kUser);
    if (raw != null && raw.isNotEmpty) {
      try {
        // Stored via `jsonEncode` in setSession — round-trip with jsonDecode.
        // Older builds wrote the user via `.toString()` which produces a
        // Dart-map literal (not valid JSON). We catch that and discard the
        // junk so the user signs in fresh instead of hitting parse errors
        // forever.
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _user = BestieUser.fromJson(decoded);
        } else if (decoded is Map) {
          _user = BestieUser.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Corrupt cache from an older build — wipe so we don't loop on it.
        await _storage.delete(key: _kUser);
      }
    }
    _controller.add(_user);
  }

  Future<void> setSession({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> userJson,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _user = BestieUser.fromJson(userJson);
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
    // jsonEncode (not .toString()) so the round-trip in load() actually works.
    await _storage.write(key: _kUser, value: jsonEncode(userJson));
    _controller.add(_user);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    await _storage.deleteAll();
    _controller.add(null);
  }
}
