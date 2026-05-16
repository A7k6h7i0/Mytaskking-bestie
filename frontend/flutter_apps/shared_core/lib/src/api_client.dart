import 'package:dio/dio.dart';
import 'auth_store.dart';

class BestieApi {
  final Dio dio;
  final BestieAuthStore auth;

  BestieApi({required String baseUrl, required this.auth})
      : dio = Dio(BaseOptions(
          baseUrl: '$baseUrl/api/v1',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = auth.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401 && auth.refreshToken != null) {
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
    ));
  }

  Future<bool> _refresh() async {
    try {
      final r = await dio.post('/auth/refresh', data: {'refreshToken': auth.refreshToken});
      await auth.setSession(
        accessToken: r.data['accessToken'],
        refreshToken: r.data['refreshToken'],
        userJson: r.data['user'] as Map<String, dynamic>,
      );
      return true;
    } catch (_) {
      await auth.clear();
      return false;
    }
  }

  Future<Map<String, dynamic>> login({required String userId, required String password}) async {
    final r = await dio.post('/auth/login', data: {'userId': userId, 'password': password});
    await auth.setSession(
      accessToken: r.data['accessToken'],
      refreshToken: r.data['refreshToken'],
      userJson: r.data['user'] as Map<String, dynamic>,
    );
    return r.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await dio.post('/auth/logout', data: {'refreshToken': auth.refreshToken});
    } catch (_) {}
    await auth.clear();
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final r = await dio.get(path, queryParameters: query);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    final r = await dio.post(path, data: body);
    return r.data as Map<String, dynamic>;
  }
}
