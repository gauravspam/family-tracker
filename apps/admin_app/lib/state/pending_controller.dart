import 'package:flutter/foundation.dart';
import 'package:tracker_core/tracker_core.dart';

import '../api/relay_api.dart';

enum PendingPhase { initial, loading, ready, error }

class PendingController extends ChangeNotifier {
  final RelayApi _api;

  PendingPhase _phase = PendingPhase.initial;
  List<PendingDevice> _items = const [];
  String? _lastError;

  PendingController(this._api);

  PendingPhase get phase => _phase;
  List<PendingDevice> get items => _items;
  String? get lastError => _lastError;

  Future<void> refresh() async {
    _phase = PendingPhase.loading;
    _lastError = null;
    notifyListeners();

    try {
      _items = await _api.listPending();
      _phase = PendingPhase.ready;
      notifyListeners();
    } on RelayUnauthorized {
      rethrow;
    } catch (e) {
      _lastError = e.toString();
      _phase = PendingPhase.error;
      notifyListeners();
    }
  }

  Future<void> approve(int pendingId, {String? name}) async {
    await _api.approve(pendingId, name: name);
    await refresh();
  }

  Future<void> reject(int pendingId) async {
    await _api.reject(pendingId);
    await refresh();
  }
}
