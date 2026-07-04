import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import '../auth/session_storage.dart';

enum SocketState { disconnected, connecting, connected, reconnecting }

/// Live subscription to Traccar /api/socket.
///
/// Emits [positions] and [events] streams from parsed messages.
/// [state] reflects connection status for UI banners.
/// Auto-reconnects with exponential backoff up to [maxBackoff].
class TraccarSocket extends ChangeNotifier {
  final String wsUrl;
  final SessionStorage _storage;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  final _positionsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _eventsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _unauthorizedController = StreamController<void>.broadcast();

  SocketState _state = SocketState.disconnected;
  DateTime? _lastMessageAt;

  TraccarSocket({required this.wsUrl, required SessionStorage storage})
      : _storage = storage;

  SocketState get state => _state;
  DateTime? get lastMessageAt => _lastMessageAt;

  Stream<List<Map<String, dynamic>>> get positions => _positionsController.stream;
  Stream<List<Map<String, dynamic>>> get events => _eventsController.stream;
  Stream<void> get unauthorized => _unauthorizedController.stream;

  static const Duration maxBackoff = Duration(seconds: 30);

  Future<void> connect() async {
    _reconnectTimer?.cancel();
    await _closeChannel();

    _setState(SocketState.connecting);

    final jSessionId = await _storage.getJSessionId();
    if (jSessionId == null) {
      _unauthorizedController.add(null);
      _setState(SocketState.disconnected);
      return;
    }

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {'Cookie': 'JSESSIONID=$jSessionId'},
      );

      _subscription = _channel!.stream.listen(
        _onMessage,
        onDone: _onDone,
        onError: _onError,
        cancelOnError: false,
      );

      _setState(SocketState.connected);
      _reconnectAttempt = 0;
    } catch (e) {
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _closeChannel();
    _setState(SocketState.disconnected);
  }

  void _onMessage(dynamic raw) {
    _lastMessageAt = DateTime.now();

    if (raw is! String) return;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '{}') return; // keepalive

    try {
      final data = json.decode(trimmed);
      if (data is! Map<String, dynamic>) return;

      final positions = data['positions'];
      if (positions is List) {
        _positionsController.add(
          positions.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
      }

      final events = data['events'];
      if (events is List) {
        _eventsController.add(
          events.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
      }
    } catch (_) {
      // ignore malformed message
    }
  }

  void _onDone() {
    // Server closed the socket. Could be normal shutdown or auth expiry.
    final code = _channel?.closeCode;
    if (code == 1008 || code == 4401 || code == 401) {
      _unauthorizedController.add(null);
      _setState(SocketState.disconnected);
      return;
    }
    _scheduleReconnect();
  }

  void _onError(Object error) {
    _scheduleReconnect();
  }

  Future<void> _closeChannel() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setState(SocketState.reconnecting);
    _reconnectAttempt++;

    final backoffMs = (1000 * (1 << (_reconnectAttempt - 1))).clamp(
      1000,
      maxBackoff.inMilliseconds,
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: backoffMs), connect);
  }

  void _setState(SocketState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _closeChannel();
    _positionsController.close();
    _eventsController.close();
    _unauthorizedController.close();
    super.dispose();
  }
}
