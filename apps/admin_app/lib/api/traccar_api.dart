import 'dart:convert';

import 'package:dio/dio.dart';

import '../auth/session_storage.dart';

/// HTTP client for Traccar REST that always attaches JSESSIONID.
/// Throws [TraccarUnauthorized] on 401/403 so callers can trigger logout.
class TraccarApi {
  final Dio _dio;

  TraccarApi({
    required String baseUrl,
    required SessionStorage storage,
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 600,
          responseType: ResponseType.plain,
        )) {
    _dio.interceptors.add(_CookieInterceptor(storage));
  }

  Future<List<Map<String, dynamic>>> listDevices() async {
    final r = await _dio.get('/api/devices');
    return _parseList(r);
  }

  Future<List<Map<String, dynamic>>> listPositions() async {
    final r = await _dio.get('/api/positions');
    return _parseList(r);
  }

  List<Map<String, dynamic>> _parseList(Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw TraccarUnauthorized();
    }

    final raw = r.data;
    final text = raw is String ? raw.trim() : '';

    if (r.statusCode! >= 500 || text.isEmpty || !text.startsWith('[')) {
      throw Exception('Server returned unexpected response (Traccar may be restarting)');
    }

    if (r.statusCode! >= 400) {
      throw Exception('Traccar HTTP ${r.statusCode}');
    }

    final decoded = jsonDecode(text);
    if (decoded is! List) {
      throw Exception('Expected JSON array from Traccar');
    }
    return decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}

class TraccarUnauthorized implements Exception {
  @override
  String toString() => 'TraccarUnauthorized';
}

class _CookieInterceptor extends Interceptor {
  final SessionStorage _storage;

  _CookieInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final j = await _storage.getJSessionId();
    if (j != null) {
      options.headers['Cookie'] = 'JSESSIONID=$j';
    }
    handler.next(options);
  }
}
