import 'package:flutter/foundation.dart';

import 'session_storage.dart';
import 'traccar_auth.dart';

enum AuthPhase { checking, loggedOut, loggedIn }

class AuthController extends ChangeNotifier {
  final SessionStorage _storage;
  final TraccarAuth _traccar;

  AuthPhase _phase = AuthPhase.checking;
  String? _lastError;

  AuthController({
    required SessionStorage storage,
    required TraccarAuth traccar,
  })  : _storage = storage,
        _traccar = traccar {
    _restore();
  }

  AuthPhase get phase => _phase;
  String? get lastError => _lastError;

  Future<void> _restore() async {
    final hasSession = await _storage.hasSession();
    _phase = hasSession ? AuthPhase.loggedIn : AuthPhase.loggedOut;
    notifyListeners();
  }

  Future<bool> login({
    required String email,
    required String password,
    required String relayAdminToken,
  }) async {
    _lastError = null;
    notifyListeners();

    try {
      final result = await _traccar.login(email, password);

      await _storage.saveJSessionId(result.jSessionId);
      await _storage.saveTraccarEmail(result.email);
      await _storage.saveTraccarUserId(result.userId);
      await _storage.saveRelayAdminToken(relayAdminToken);

      _phase = AuthPhase.loggedIn;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.clear();
    _phase = AuthPhase.loggedOut;
    notifyListeners();
  }
}
