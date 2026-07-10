import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class ConnectivityMonitor extends ChangeNotifier {
  bool _isOnline = true;
  DateTime? _lastOnlineAt;
  DateTime? _lastCheckAt;
  Timer? _pingTimer;
  final Uri _pingTarget;

  ConnectivityMonitor(String relayBaseUrl)
      : _pingTarget = Uri.parse('$relayBaseUrl/healthz');

  bool get isOnline => _isOnline;
  DateTime? get lastOnlineAt => _lastOnlineAt;
  DateTime? get lastCheckAt => _lastCheckAt;
  Duration get offlineSince {
    if (_isOnline || _lastOnlineAt == null) return Duration.zero;
    return DateTime.now().difference(_lastOnlineAt!);
  }

  void start() {
    _pingTimer?.cancel();
    _ping();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _ping());
  }

  void stop() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> _ping() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(_pingTarget);
      final response = await request.close();
      client.close();
      if (response.statusCode == 200) {
        _setOnline(true);
      } else {
        _setOnline(false);
      }
    } catch (_) {
      _setOnline(false);
    }
  }

  void reportSuccess() => _setOnline(true);
  void reportFailure() => _setOnline(false);

  void _setOnline(bool v) {
    _lastCheckAt = DateTime.now();
    if (v == _isOnline) return;
    _isOnline = v;
    if (v) _lastOnlineAt = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
