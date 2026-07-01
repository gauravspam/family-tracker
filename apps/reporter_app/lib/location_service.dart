import 'dart:async';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'state.dart';
import 'storage.dart';

class LocationService {
  static const _idleIntervalMs = 600000; // 10 minutes
  static const _liveIntervalMs = 5000;   // 5 seconds

  Timer? _timer;
  final Dio _dio = Dio();
  bool _posting = false;

  void start(ReporterState state) {
    stop();
    if (!state.isApproved) return;

    final interval = state.isLive ? _liveIntervalMs : _idleIntervalMs;
    _timer = Timer.periodic(
      Duration(milliseconds: interval),
      (_) => _tick(),
    );
    // Post immediately on start
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_posting) return;
    _posting = true;

    try {
      final state = await ReporterStorage.load();

      if (state.approval != ApprovalStatus.approved) {
        stop();
        return;
      }

      // Check LIVE expiry
      if (state.isLive &&
          state.liveExpiresAt != null &&
          DateTime.now().isAfter(state.liveExpiresAt!)) {
        final newState = state.copyWith(
          mode: TrackingMode.idle,
          clearExpiry: true,
        );
        await ReporterStorage.save(newState);
        start(newState); // restart with idle interval
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      await _postPosition(state, position);
    } catch (e) {
      // Silently ignore — next tick will retry
    } finally {
      _posting = false;
    }
  }

  Future<void> _postPosition(ReporterState state, Position position) async {
    if (state.ingestToken == null || state.ingestUrl == null) return;

    final uri = Uri.parse(state.ingestUrl!).replace(
      queryParameters: {
        'id': state.ingestToken!,
        'lat': position.latitude.toString(),
        'lon': position.longitude.toString(),
        'timestamp': (position.timestamp.millisecondsSinceEpoch ~/ 1000)
            .toString(),
        'hdop': position.accuracy.toString(),
        'altitude': position.altitude.toString(),
        'speed': position.speed.toString(),
      },
    );

    await _dio.getUri(uri);
  }
}
