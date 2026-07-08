import 'dart:math' as math;

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

  /// Ring buffer of recent positions per Traccar device id.
  /// Used to draw movement trails on the map.
  final Map<int, List<TraccarPosition>> _trails = {};

  /// Max positions to keep per device (~50 covers a few minutes of live mode).
  static const int _trailMaxLength = 50;

  /// Max age of trail positions. Older points are discarded on new arrival.
  static const Duration _trailMaxAge = Duration(minutes: 30);
  String? _lastError;

  DevicesController(this._traccar, this._relay);

  DevicesPhase get phase => _phase;
  String? get lastError => _lastError;

  /// Last N positions for [traccarDeviceId], oldest first. Empty if none.
  List<TraccarPosition> trailFor(int traccarDeviceId) =>
      List.unmodifiable(_trails[traccarDeviceId] ?? const []);

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
        _appendToTrail(p);
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
      _lastError = friendlyNetworkError(e);
      // Keep any previously loaded devices on screen when refresh fails so
      // the user still sees the last-known state during transient network
      // hiccups.
      _phase = _devicesById.isEmpty ? DevicesPhase.error : DevicesPhase.ready;
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
        _appendToTrail(p);
      } catch (_) {
        // skip malformed
      }
    }
    if (changed) notifyListeners();
  }

  /// Impossible-jump filter: a GPS point that appears >200m from the last
  /// known point in <5 seconds is almost always a glitch or test-data reset.
  static const double _maxRealisticSpeedMs = 200 / 5; // 40 m/s ≈ 144 km/h

  void _appendToTrail(TraccarPosition p) {
    final list = _trails.putIfAbsent(p.deviceId, () => []);

    // De-dupe by id (WebSocket + poll can both deliver the same point)
    if (list.isNotEmpty && list.last.id == p.id) return;

    // Reject impossible jumps that suggest a GPS glitch or a test-data reset.
    if (list.isNotEmpty) {
      final prev = list.last;
      final dt = p.fixTime.difference(prev.fixTime).inMilliseconds / 1000.0;
      if (dt > 0) {
        final meters = _haversine(
          prev.latitude, prev.longitude,
          p.latitude, p.longitude,
        );
        final impliedSpeed = meters / dt;
        if (impliedSpeed > _maxRealisticSpeedMs) {
          // Silently drop the impossible point from the trail.
          // The latest-position map is unaffected — the marker still moves,
          // it's just the trail line that omits this outlier.
          return;
        }
      }
    }

    list.add(p);

    // Trim by age
    final cutoff = DateTime.now().subtract(_trailMaxAge);
    while (list.isNotEmpty && list.first.fixTime.isBefore(cutoff)) {
      list.removeAt(0);
    }
    // Trim by length
    while (list.length > _trailMaxLength) {
      list.removeAt(0);
    }
  }

  /// Fetches historical positions for [traccarDeviceId] from Traccar and
  /// prepends them to the in-memory trail. Call this when the user starts
  /// following a device so older trail data is available immediately.
  Future<void> fetchTrail(int traccarDeviceId, {Duration lookback = const Duration(hours: 2)}) async {
    final now = DateTime.now();
    final from = now.subtract(lookback);
    try {
      final raw = await _traccar.listDevicePositions(
        traccarDeviceId,
        from: from,
        to: now,
      );
      final list = _trails.putIfAbsent(traccarDeviceId, () => []);
      for (final rp in raw) {
        final p = TraccarPosition.fromJson(rp);
        // Skip points already in trail (by id)
        if (list.any((e) => e.id == p.id)) continue;
        list.add(p);
      }
      list.sort((a, b) => a.fixTime.compareTo(b.fixTime));
      // Re-apply trim rules
      final cutoff = DateTime.now().subtract(_trailMaxAge);
      while (list.isNotEmpty && list.first.fixTime.isBefore(cutoff)) {
        list.removeAt(0);
      }
      while (list.length > _trailMaxLength) {
        list.removeAt(0);
      }
      notifyListeners();
    } catch (_) {
      // Silently fail — live trail data will still arrive via WebSocket.
    }
  }


  /// or all devices when [traccarDeviceId] is null.
  void clearTrail([int? traccarDeviceId]) {
    if (traccarDeviceId == null) {
      _trails.clear();
    } else {
      _trails.remove(traccarDeviceId);
    }
    notifyListeners();
  }

  /// Haversine distance in metres between two lat/lon pairs.
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.asin(math.min(1.0, math.sqrt(a)));
    return r * c;
  }

  double _rad(double deg) => deg * math.pi / 180.0;
}
