import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'state.dart';

class ReporterStorage {
  static const _storage = FlutterSecureStorage();

  static const _keyApproval = 'approval';
  static const _keyMode = 'mode';
  static const _keyIngestToken = 'ingestToken';
  static const _keyIngestUrl = 'ingestUrl';
  static const _keyLiveExpiresAt = 'liveExpiresAt';
  static const _keyAndroidId = 'androidId';
  static const _keyFcmToken = 'fcmToken';

  static Future<ReporterState> load() async {
    final approval = await _storage.read(key: _keyApproval);
    final mode = await _storage.read(key: _keyMode);
    final token = await _storage.read(key: _keyIngestToken);
    final url = await _storage.read(key: _keyIngestUrl);
    final expiry = await _storage.read(key: _keyLiveExpiresAt);

    return ReporterState(
      approval: _parseApproval(approval),
      mode: mode == 'live' ? TrackingMode.live : TrackingMode.idle,
      ingestToken: token,
      ingestUrl: url,
      liveExpiresAt: expiry != null ? DateTime.tryParse(expiry) : null,
    );
  }

  static Future<void> save(ReporterState state) async {
    await _storage.write(key: _keyApproval, value: state.approval.name);
    await _storage.write(key: _keyMode, value: state.mode.name);
    if (state.ingestToken != null) {
      await _storage.write(key: _keyIngestToken, value: state.ingestToken);
    }
    if (state.ingestUrl != null) {
      await _storage.write(key: _keyIngestUrl, value: state.ingestUrl);
    }
    if (state.liveExpiresAt != null) {
      await _storage.write(
        key: _keyLiveExpiresAt,
        value: state.liveExpiresAt!.toIso8601String(),
      );
    } else {
      await _storage.delete(key: _keyLiveExpiresAt);
    }
  }

  static Future<void> saveAndroidId(String id) async {
    await _storage.write(key: _keyAndroidId, value: id);
  }

  static Future<String?> getAndroidId() async {
    return _storage.read(key: _keyAndroidId);
  }

  static Future<void> saveFcmToken(String token) async {
    await _storage.write(key: _keyFcmToken, value: token);
  }

  static Future<String?> getFcmToken() async {
    return _storage.read(key: _keyFcmToken);
  }

  static ApprovalStatus _parseApproval(String? value) {
    switch (value) {
      case 'approved':
        return ApprovalStatus.approved;
      case 'removed':
        return ApprovalStatus.removed;
      default:
        return ApprovalStatus.pending;
    }
  }
}
