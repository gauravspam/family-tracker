import 'package:dio/dio.dart';

import '../models/join_request.dart';

class RelayClient {
  final Dio _dio;

  RelayClient(this._dio);

  Future<void> submitJoinRequest(JoinRequest request) async {
    await _dio.post('/join', data: request.toJson());
  }

  Future<Map<String, dynamic>> getDeviceStatus(String androidId) async {
    final response = await _dio.get(
      '/api/device/status',
      queryParameters: {'androidId': androidId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> getPendingDevices() async {
    final response = await _dio.get('/admin/pending');
    return (response.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> approveDevice(int pendingId) async {
    await _dio.post('/admin/approve/$pendingId');
  }

  Future<void> removeDevice(int id) async {
    await _dio.post('/admin/remove/$id');
  }

  Future<void> triggerLiveMode(int deviceId, String expiresAtIsoUtc) async {
    await _dio.post(
      '/admin/live/$deviceId',
      data: {'expiresAt': expiresAtIsoUtc},
    );
  }

  Future<void> registerAdminFcmToken(String fcmToken) async {
    await _dio.post(
      '/admin/fcm-token',
      data: {'fcmToken': fcmToken},
    );
  }
}
