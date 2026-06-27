import 'dart:async';

import 'package:dio/dio.dart';
import 'auth_store.dart';

/// Accept either a bare origin (`https://mytaskking.com`) or a fully
/// versioned URL (`https://mytaskking.com/api/v1`) and always return the
/// versioned form — that way callers can't accidentally produce paths
/// like `/api/v1/api/v1/dashboard/overview` by appending `/api/v1` twice.
String _normalizeBaseUrl(String input) {
  final trimmed = input.endsWith('/')
      ? input.substring(0, input.length - 1)
      : input;
  if (trimmed.endsWith('/api/v1')) return trimmed;
  return '$trimmed/api/v1';
}

class BestieApi {
  final Dio dio;
  final BestieAuthStore auth;
  Future<bool>? _refreshInFlight;

  BestieApi({required String baseUrl, required this.auth, String? userAgent})
    : dio = Dio(
        BaseOptions(
          baseUrl: _normalizeBaseUrl(baseUrl),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: userAgent != null ? {'User-Agent': userAgent} : null,
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = auth.accessToken;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (e, handler) async {
          final isRefreshCall = e.requestOptions.path.endsWith('/auth/refresh');
          if (!isRefreshCall &&
              e.response?.statusCode == 401 &&
              auth.refreshToken != null) {
            final ok = await _refresh();
            if (ok) {
              final req = e.requestOptions;
              req.headers['Authorization'] = 'Bearer ${auth.accessToken}';
              try {
                final r = await dio.fetch(req);
                return handler.resolve(r);
              } catch (_) {}
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  Future<bool> _refresh() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final pending = _refreshOnce();
    _refreshInFlight = pending;
    try {
      return await pending;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<bool> _refreshOnce() async {
    try {
      final r = await dio.post(
        '/auth/refresh',
        data: {'refreshToken': auth.refreshToken},
      );
      await auth.setSession(
        accessToken: r.data['accessToken'],
        refreshToken: r.data['refreshToken'],
        userJson: r.data['user'] as Map<String, dynamic>,
      );
      return true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403 || code == 410) {
        await auth.clear();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> login({
    required String userId,
    required String password,
    String? tenantSlug,
    String? selfieBase64,
    String? selfieMimeType,
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final r = await dio.post(
      '/auth/login',
      data: {
        if (tenantSlug != null && tenantSlug.trim().isNotEmpty)
          'tenantSlug': tenantSlug.trim(),
        'userId': userId,
        'password': password,
        'loginSource': 'mobile',
        if (selfieBase64 != null) 'selfieBase64': selfieBase64,
        if (selfieMimeType != null) 'selfieMimeType': selfieMimeType,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (address != null) 'address': address,
      },
    );
    await auth.setSession(
      accessToken: r.data['accessToken'],
      refreshToken: r.data['refreshToken'],
      userJson: r.data['user'] as Map<String, dynamic>,
    );
    return r.data as Map<String, dynamic>;
  }

  Future<bool> loginRequiresSelfie(String userId, {String? tenantSlug}) async {
    final r = await dio.get(
      '/auth/login-requirements',
      queryParameters: {
        'userId': userId,
        if (tenantSlug != null && tenantSlug.trim().isNotEmpty)
          'tenantSlug': tenantSlug.trim(),
      },
    );
    return r.data['requiresSelfie'] == true;
  }

  Future<void> logout() async {
    try {
      await dio.post('/auth/logout', data: {'refreshToken': auth.refreshToken});
    } catch (_) {}
    await auth.clear();
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final r = await dio.get(path, queryParameters: query);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    final r = await dio.post(path, data: body);
    return r.data as Map<String, dynamic>;
  }
}
