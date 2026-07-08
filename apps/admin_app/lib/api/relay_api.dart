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

  Future<void> ringDevice(int traccarDeviceId, {int durationSec = 30}) async {
    final r = await _dio.post(
      '/admin/ring/$traccarDeviceId',
      data: jsonEncode({'durationSec': durationSec}),
      options: Options(contentType: Headers.jsonContentType),
    );
    _checkStatus(r);
  }

  Future<void> stopLive(int traccarDeviceId) async {
    final r = await _dio.post('/admin/idle/$traccarDeviceId');
    _checkStatus(r);
  }

  Future<void> registerFcmToken(String token) async {
    final r = await _dio.post(
      '/admin/fcm-token',
      data: jsonEncode({'fcmToken': token, 'userId': 1}),
      options: Options(contentType: Headers.jsonContentType),
    );
    _checkStatus(r);
  }

  Future<void> setAppearance({
    required int traccarDeviceId,
    String? colorHex,
    String? avatarId,
  }) async {
    final body = <String, dynamic>{};
    if (colorHex != null) body['color'] = colorHex;
    if (avatarId != null) body['avatarId'] = avatarId;
    if (body.isEmpty) return;
    final r = await _dio.put(
      '/admin/appearance/$traccarDeviceId',
      data: jsonEncode(body),
      options: Options(contentType: Headers.jsonContentType),
    );
    _checkStatus(r);
  }

  Future<void> locateDevice(int traccarDeviceId) async {
    final r = await _dio.post('/admin/locate/$traccarDeviceId');
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

/// Converts messy Dio / socket exceptions into a short human-readable line.
String friendlyNetworkError(Object e) {
  final s = e.toString();
  if (s.contains('Network is unreachable') ||
      s.contains('Unable to resolve host') ||
      s.contains('SocketException')) {
    return "Can't reach the server. Check your network connection.";
  }
  if (s.contains('Connection refused') || s.contains('ECONNREFUSED')) {
    return 'The server is not responding. Is the relay running?';
  }
  if (s.contains('timeout') || s.contains('Timeout')) {
    return 'The server took too long to respond. Try again.';
  }
  if (s.contains('Relay HTTP 401') || s.contains('Relay HTTP 403')) {
    return 'Your session has expired. Sign in again.';
  }
  return s;
}
