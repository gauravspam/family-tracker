import 'package:dio/dio.dart';

import '../models/device.dart';
import '../models/position.dart';

class TraccarClient {
  final Dio _dio;

  TraccarClient(this._dio);

  Future<Map<String, dynamic>> createSession({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '/api/session',
      data: 'email=$email&password=$password',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<TraccarDevice>> getDevices() async {
    final response = await _dio.get('/api/devices');
    return (response.data as List)
        .map((e) => TraccarDevice.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<TraccarPosition>> getPositions() async {
    final response = await _dio.get('/api/positions');
    return (response.data as List)
        .map((e) => TraccarPosition.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
