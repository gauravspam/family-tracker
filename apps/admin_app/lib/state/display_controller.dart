import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Global display switches. Currently just the glass-blur toggle so weak
/// GPUs can skip every BackdropFilter in the app from the ⋮ menu.
class DisplayController extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _keyGlass = 'glass_enabled';

  bool _glassEnabled = true;
  bool get glassEnabled => _glassEnabled;

  DisplayController() {
    _load();
  }

  Future<void> _load() async {
    final v = await _storage.read(key: _keyGlass);
    // Default ON; only an explicit 'false' disables.
    _glassEnabled = v != 'false';
    notifyListeners();
  }

  Future<void> setGlassEnabled(bool v) async {
    _glassEnabled = v;
    await _storage.write(key: _keyGlass, value: v ? 'true' : 'false');
    notifyListeners();
  }

  Future<void> toggleGlass() => setGlassEnabled(!_glassEnabled);
}
