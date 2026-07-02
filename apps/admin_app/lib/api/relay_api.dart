import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:tracker_core/tracker_core.dart';

import '../auth/session_storage.dart';

class RelayUnauthorized implements Exception {
  @override
  String toString() => 'RelayUnauthorized';
}

class RelayApi {
  final Dio _dio;

  RelayApi({
    required String baseUrl,
    required SessionStorage storage,
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 600,
          responseType: ResponseType.plain,
        )) {
    _dio.interceptors.add(_AdminTokenInterceptor(storage));
  }

  Future<List<PendingDevice>> listPending() async {
    final r = await _dio.get('/admin/pending');
    final list = _parseList(r);
    return list.map(PendingDevice.fromJson).toList();
  }

  Future<List<ApprovedDevice>> listApprovedDevices() async {
    final r = await _dio.get('/admin/devices');
    final list = _parseList(r);
    return list.map(ApprovedDevice.fromJson).toList();
  }

  Future<void> approve(int pendingId, {String? name}) async {
    final body = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) {
      body['name'] = name.trim();
    }
    final r = await _dio.post(
      '/admin/approve/$pendingId',
      data: body.isEmpty ? null : jsonEncode(body),
      options: body.isEmpty
          ? null
          : Options(contentType: Headers.jsonContentType),
    );
    _checkStatus(r);
  }

  Future<void> reject(int pendingId) async {
    final r = await _dio.post('/admin/reject/$pendingId');
    _checkStatus(r);
  }

  Future<void> removeByTraccarId(int traccarId) async {
    final r = await _dio.delete('/admin/device-by-traccar/$traccarId');
    _checkStatus(r);
  }

  Future<void> renameByTraccarId(int traccarId, String newName) async {
    final r = await _dio.put(
      '/admin/rename/$traccarId',
      data: jsonEncode({'name': newName.trim()}),
      options: Options(contentType: Headers.jsonContentType),
    );
    _checkStatus(r);
  }

  Future<void> triggerLive({
    required int traccarDeviceId,
    required DateTime expiresAtUtc,
  }) async {
    final r = await _dio.post(
      '/admin/live/$traccarDeviceId',
      data: jsonEncode({'expiresAt': expiresAtUtc.toIso8601String()}),
      options: Options(contentType: Headers.jsonContentType),
    );
    _checkStatus(r);
  }

  // ── helpers ──

  List<Map<String, dynamic>> _parseList(Response r) {
    _checkStatus(r);
    final raw = r.data;
    final text = raw is String ? raw.trim() : '';
    if (text.isEmpty || text == 'null') return const [];
    if (!text.startsWith('[')) {
      throw Exception('Relay returned non-JSON list: $text');
    }
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      throw Exception('Expected JSON array from relay');
    }
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _checkStatus(Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw RelayUnauthorized();
    }
    if (r.statusCode! >= 400) {
      final body = r.data is String ? r.data : '';
      throw Exception('Relay HTTP ${r.statusCode}: $body');
    }
  }
}

class _AdminTokenInterceptor extends Interceptor {
  final SessionStorage _storage;

  _AdminTokenInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final t = await _storage.getRelayAdminToken();
    if (t != null) {
      options.headers['Authorization'] = 'Bearer $t';
    }
    handler.next(options);
  }
}
