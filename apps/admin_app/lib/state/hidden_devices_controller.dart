import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class HiddenDevicesController extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _passcodeKey = 'hidden_passcode';
  static const _hiddenIdsKey = 'hidden_device_ids';

  String? _passcode;
  Set<int> _hiddenIds = {};
  bool _isShowingHidden = false;

  String? get passcode => _passcode;
  Set<int> get hiddenIds => Set.unmodifiable(_hiddenIds);
  bool get isShowingHidden => _isShowingHidden;
  bool get hasPasscode => _passcode != null && _passcode!.isNotEmpty;

  HiddenDevicesController() {
    _load();
  }

  Future<void> _load() async {
    _passcode = await _storage.read(key: _passcodeKey);
    final raw = await _storage.read(key: _hiddenIdsKey);
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List;
      _hiddenIds = list.map((e) => e as int).toSet();
    }
    notifyListeners();
  }

  Future<void> setPasscode(String code) async {
    _passcode = code;
    await _storage.write(key: _passcodeKey, value: code);
    notifyListeners();
  }

  bool verifyPasscode(String code) => _passcode == code;

  void showHidden() {
    _isShowingHidden = true;
    notifyListeners();
  }

  void hideHidden() {
    _isShowingHidden = false;
    notifyListeners();
  }

  bool isHidden(int traccarId) => _hiddenIds.contains(traccarId);

  Future<void> toggleHidden(int traccarId) async {
    if (_hiddenIds.contains(traccarId)) {
      _hiddenIds.remove(traccarId);
    } else {
      _hiddenIds.add(traccarId);
    }
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    await _storage.write(
      key: _hiddenIdsKey,
      value: jsonEncode(_hiddenIds.toList()),
    );
  }
}
