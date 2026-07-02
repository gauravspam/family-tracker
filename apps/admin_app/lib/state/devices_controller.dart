import 'package:flutter/foundation.dart';
import 'package:tracker_core/tracker_core.dart';

import '../api/traccar_api.dart';
import '../models/device_view.dart';

enum DevicesPhase { initial, loading, ready, error }

class DevicesController extends ChangeNotifier {
  final TraccarApi _api;

  DevicesPhase _phase = DevicesPhase.initial;
  final Map<int, TraccarDevice> _devicesById = {};
  final Map<int, TraccarPosition> _latestPosByDeviceId = {};
  String? _lastError;

  DevicesController(this._api);

  DevicesPhase get phase => _phase;
  String? get lastError => _lastError;

  List<DeviceView> get devices {
    final list = _devicesById.values
        .map((d) => DeviceView(
              device: d,
              position: _latestPosByDeviceId[d.id],
            ))
        .toList();
    // Stable order: online first, then by name
    list.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  Future<void> refresh() async {
    _phase = DevicesPhase.loading;
    _lastError = null;
    notifyListeners();

    try {
      final rawDevices = await _api.listDevices();
      final rawPositions = await _api.listPositions();

      _devicesById
        ..clear()
        ..addEntries(rawDevices
            .map(TraccarDevice.fromJson)
            .map((d) => MapEntry(d.id, d)));

      _latestPosByDeviceId.clear();
      for (final rp in rawPositions) {
        final p = TraccarPosition.fromJson(rp);
        final existing = _latestPosByDeviceId[p.deviceId];
        if (existing == null || p.fixTime.isAfter(existing.fixTime)) {
          _latestPosByDeviceId[p.deviceId] = p;
        }
      }

      _phase = DevicesPhase.ready;
      notifyListeners();
    } on TraccarUnauthorized {
      rethrow;
    } catch (e) {
      _lastError = e.toString();
      _phase = DevicesPhase.error;
      notifyListeners();
    }
  }

  /// Apply a batch of positions from the WebSocket.
  void applyLivePositions(List<Map<String, dynamic>> rawPositions) {
    var changed = false;
    for (final rp in rawPositions) {
      try {
        final p = TraccarPosition.fromJson(rp);
        final existing = _latestPosByDeviceId[p.deviceId];
        if (existing == null || p.fixTime.isAfter(existing.fixTime)) {
          _latestPosByDeviceId[p.deviceId] = p;
          changed = true;
        }
      } catch (_) {
        // skip malformed
      }
    }
    if (changed) notifyListeners();
  }
}
