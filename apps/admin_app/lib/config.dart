class AppConfig {
  // Same LAN IP as reporter for now; will switch to domain in prod
  static const String relayBaseUrl = 'http://192.168.1.35:8080';
  static const String traccarBaseUrl = 'http://192.168.1.35:8082';
  static const String traccarWsUrl = 'ws://192.168.1.35:8082/api/socket';
}
