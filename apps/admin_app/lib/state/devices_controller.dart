import 'package:flutter/foundation.dart';
import 'package:tracker_core/tracker_core.dart';

import '../api/relay_api.dart';
import '../api/traccar_api.dart';
import '../models/device_view.dart';

enum DevicesPhase { initial, loading, ready, error }

class DevicesController extends ChangeNotifier {
  final TraccarApi _traccar;
  final RelayApi _relay;

  DevicesPhase _phase = DevicesPhase.initial;
  final Map<int, TraccarDevice> _devicesById = {};
  final Map<int, TraccarPosition> _latestPosByDeviceId = {};
  final Map<int, ApprovedDevice> _approvedByTraccarId = {};
  String? _lastError;

  DevicesController(this._traccar, this._relay);

  DevicesPhase get phase => _phase;
  String? get lastError => _lastError;

  List<DeviceView> get devices {
    final list = _devicesById.values
        .map((d) => DeviceView(
              device: d,
              position: _latestPosByDeviceId[d.id],
              approved: _approvedByTraccarId[d.id],
            ))
        .toList();
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
      final rawDevices = await _traccar.listDevices();
      final rawPositions = await _traccar.listPositions();
      final approvedList = await _relay.listApprovedDevices();

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

      _approvedByTraccarId
        ..clear()
        ..addEntries(approvedList.map((a) => MapEntry(a.traccarDeviceId, a)));

      _phase = DevicesPhase.ready;
      notifyListeners();
    } on TraccarUnauthorized {
      rethrow;
    } on RelayUnauthorized {
      rethrow;
    } catch (e) {
      _lastError = e.toString();
      _phase = DevicesPhase.error;
      notifyListeners();
    }
  }

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
