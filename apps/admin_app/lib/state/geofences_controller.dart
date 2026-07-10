import 'package:flutter/foundation.dart';
import 'package:tracker_core/tracker_core.dart';

import '../api/traccar_api.dart';

enum GeofencesPhase { initial, loading, ready, error }

class GeofencesController extends ChangeNotifier {
  final TraccarApi _api;

  GeofencesPhase _phase = GeofencesPhase.initial;
  List<TraccarGeofence> _list = [];
  String? _lastError;

  GeofencesController(this._api);

  GeofencesPhase get phase => _phase;
  List<TraccarGeofence> get list => _list;
  String? get lastError => _lastError;
  DateTime? _lastFetchedAt;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  bool get isStale => _lastFetchedAt != null &&
      DateTime.now().difference(_lastFetchedAt!) > const Duration(minutes: 5);

  Future<void> refresh() async {
    _phase = GeofencesPhase.loading;
    _lastError = null;
    notifyListeners();

    try {
      final raw = await _api.listGeofences();
      _list = raw.map(TraccarGeofence.fromJson).toList();
      _phase = GeofencesPhase.ready;
      _lastFetchedAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      _phase = _list.isEmpty ? GeofencesPhase.error : GeofencesPhase.ready;
      notifyListeners();
    }
  }

  Future<void> create(String name, double lat, double lng, double radiusMeters) async {
    final area = 'CIRCLE ($lat $lng, ${radiusMeters.toInt()})';
    await _api.createGeofence({
      'name': name,
      'area': area,
      'description': '',
    });
    await refresh();
  }

  Future<void> update(int id, String name, double lat, double lng, double radiusMeters) async {
    final area = 'CIRCLE ($lat $lng, ${radiusMeters.toInt()})';
    await _api.updateGeofence(id, {
      'name': name,
      'area': area,
      'description': '',
    });
    await refresh();
  }

  Future<void> delete(int id) async {
    await _api.deleteGeofence(id);
    await refresh();
  }
}
