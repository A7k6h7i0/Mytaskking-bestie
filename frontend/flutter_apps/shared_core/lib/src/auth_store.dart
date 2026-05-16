import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

/// Persists tokens securely (keychain on iOS/macOS, Keystore on Android, DPAPI on Windows).
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
    if (raw != null) {
      // stored as the same JSON shape as `BestieUser.fromJson`.
      // Lazily parse via dart:convert in callers when needed; keep cached map here.
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
    await _storage.write(key: _kUser, value: userJson.toString());
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
