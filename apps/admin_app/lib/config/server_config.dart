import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Runtime-configurable server endpoints. Values persist in secure storage
/// so users only enter them once (or when moving between LAN / cloud).
class ServerConfig {
  static const _storage = FlutterSecureStorage();

  static const _keyRelay = 'server_relay_url';
  static const _keyTraccarBase = 'server_traccar_base_url';

  Future<ServerUrls?> load() async {
    final relay = await _storage.read(key: _keyRelay);
    final base = await _storage.read(key: _keyTraccarBase);
    if (relay == null || base == null) return null;
    return ServerUrls(relayBaseUrl: relay, traccarBaseUrl: base);
  }

  Future<void> save(ServerUrls urls) async {
    await _storage.write(key: _keyRelay, value: urls.relayBaseUrl);
    await _storage.write(key: _keyTraccarBase, value: urls.traccarBaseUrl);
  }

  Future<bool> hasConfig() async {
    final relay = await _storage.read(key: _keyRelay);
    final base = await _storage.read(key: _keyTraccarBase);
    return relay != null && base != null;
  }
}

class ServerUrls {
  final String relayBaseUrl;
  final String traccarBaseUrl;

  const ServerUrls({
    required this.relayBaseUrl,
    required this.traccarBaseUrl,
  });

  /// Derives the WebSocket URL from the Traccar base URL.
  String get traccarWsUrl {
    if (traccarBaseUrl.startsWith('https://')) {
      return 'wss://${traccarBaseUrl.substring(8)}/api/socket';
    }
    if (traccarBaseUrl.startsWith('http://')) {
      return 'ws://${traccarBaseUrl.substring(7)}/api/socket';
    }
    return 'ws://$traccarBaseUrl/api/socket';
  }

  static String? validateUrl(String? v, {bool allowWs = false}) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Required';
    final ok = allowWs
        ? (s.startsWith('http://') ||
            s.startsWith('https://') ||
            s.startsWith('ws://') ||
            s.startsWith('wss://'))
        : (s.startsWith('http://') || s.startsWith('https://'));
    if (!ok) return 'Must start with http:// or https://';
    if (s.endsWith('/')) return 'Do not include a trailing slash';
    return null;
  }
}
