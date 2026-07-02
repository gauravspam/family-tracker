import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorage {
  static const _storage = FlutterSecureStorage();

  static const _keyJSessionId = 'j_session_id';
  static const _keyRelayAdminToken = 'relay_admin_token';
  static const _keyTraccarEmail = 'traccar_email';
  static const _keyTraccarUserId = 'traccar_user_id';

  Future<void> saveJSessionId(String value) =>
      _storage.write(key: _keyJSessionId, value: value);

  Future<String?> getJSessionId() =>
      _storage.read(key: _keyJSessionId);

  Future<void> saveRelayAdminToken(String value) =>
      _storage.write(key: _keyRelayAdminToken, value: value);

  Future<String?> getRelayAdminToken() =>
      _storage.read(key: _keyRelayAdminToken);

  Future<void> saveTraccarEmail(String email) =>
      _storage.write(key: _keyTraccarEmail, value: email);

  Future<String?> getTraccarEmail() =>
      _storage.read(key: _keyTraccarEmail);

  Future<void> saveTraccarUserId(int id) =>
      _storage.write(key: _keyTraccarUserId, value: id.toString());

  Future<int?> getTraccarUserId() async {
    final s = await _storage.read(key: _keyTraccarUserId);
    return s == null ? null : int.tryParse(s);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyJSessionId);
    await _storage.delete(key: _keyRelayAdminToken);
    await _storage.delete(key: _keyTraccarEmail);
    await _storage.delete(key: _keyTraccarUserId);
  }

  Future<bool> hasSession() async {
    final j = await getJSessionId();
    final t = await getRelayAdminToken();
    return j != null && t != null;
  }
}
