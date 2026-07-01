abstract class SessionStore {
  Future<void> saveJSessionId(String value);
  Future<String?> getJSessionId();
  Future<void> clear();
}
