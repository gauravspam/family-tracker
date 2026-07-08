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

  // ── Geofences ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listGeofences() async {
    final r = await _dio.get('/api/geofences');
    return _parseList(r);
  }

  Future<Map<String, dynamic>> createGeofence(Map<String, dynamic> body) async {
    final r = await _dio.post('/api/geofences',
        data: jsonEncode(body),
        options: Options(contentType: Headers.jsonContentType));
    return _parseObject(r);
  }

  Future<Map<String, dynamic>> updateGeofence(int id, Map<String, dynamic> body) async {
    final r = await _dio.put('/api/geofences/$id',
        data: jsonEncode(body),
        options: Options(contentType: Headers.jsonContentType));
    return _parseObject(r);
  }

  Future<void> deleteGeofence(int id) async {
    final r = await _dio.delete('/api/geofences/$id');
    _checkStatus(r);
  }

  // ── Positions history ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listDevicePositions(
    int deviceId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, dynamic>{'deviceId': deviceId};
    if (from != null) params['from'] = from.toUtc().toIso8601String();
    if (to != null) params['to'] = to.toUtc().toIso8601String();
    final r = await _dio.get('/api/positions', queryParameters: params);
    return _parseList(r);
  }

  // ── Events ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listEvents({
    List<int>? deviceId,
    int? geofenceId,
    List<String>? type,
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, dynamic>{};
    if (deviceId != null && deviceId.isNotEmpty) params['deviceId'] = deviceId;
    if (geofenceId != null) params['geofenceId'] = geofenceId;
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (from != null) params['from'] = from.toUtc().toIso8601String();
    if (to != null) params['to'] = to.toUtc().toIso8601String();
    final r = await _dio.get(
      '/api/reports/events',
      queryParameters: params,
      options: Options(headers: {'Accept': 'application/json'}),
    );
    return _parseList(r);
  }

  List<Map<String, dynamic>> _parseList(Response r) {
    _checkStatus(r);
    final raw = r.data;
    final text = raw is String ? raw.trim() : '';
    if (text.isEmpty || !text.startsWith('[')) {
      throw Exception('Traccar list response unexpected: $text');
    }
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      throw Exception('Expected JSON array from Traccar');
    }
    return decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Map<String, dynamic> _parseObject(Response r) {
    _checkStatus(r);
    final raw = r.data;
    final text = raw is String ? raw.trim() : '';
    if (text.isEmpty) throw Exception('Traccar returned empty response');
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw Exception('Expected JSON object from Traccar');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _checkStatus(Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw TraccarUnauthorized();
    }
    if (r.statusCode! >= 400) {
      final body = r.data is String ? r.data : '';
      throw Exception('Traccar HTTP ${r.statusCode}: $body');
    }
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
