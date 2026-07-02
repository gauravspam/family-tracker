import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../map/motion_estimator.dart';
import '../models/device_view.dart';
import '../state/devices_controller.dart';
import 'device_detail_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  final Map<int, MotionEstimator> _estimators = {};
  Ticker? _ticker;
  bool _hasFittedOnce = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (mounted) setState(() {});
  }

  void _syncEstimators(List<DeviceView> devices) {
    for (final v in devices) {
      if (v.position == null) continue;
      final id = v.device.id;
      final est = _estimators.putIfAbsent(id, MotionEstimator.new);
      if (est.anchor == null || v.position!.fixTime.isAfter(est.anchor!.fixTime)) {
        est.submit(v.position!);
      }
    }
    final activeIds = devices.map((d) => d.device.id).toSet();
    _estimators.removeWhere((id, _) => !activeIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DevicesController>(
      builder: (context, controller, _) {
        final devicesWithPos =
            controller.devices.where((d) => d.hasPosition).toList();

        _syncEstimators(devicesWithPos);

        if (!_hasFittedOnce && devicesWithPos.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fitToDevices(devicesWithPos);
            _hasFittedOnce = true;
          });
        }

        final now = DateTime.now();

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(20.0, 77.0),
                initialZoom: 5,
                minZoom: 2,
                maxZoom: 19,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.familytracker.admin_app',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    for (final v in devicesWithPos)
                      _buildMarker(context, v, now),
                  ],
                ),
              ],
            ),
            if (devicesWithPos.isEmpty)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: _InfoBanner(
                  message: controller.devices.isEmpty
                      ? 'No devices yet'
                      : 'No positions yet',
                ),
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'recenter',
                onPressed: () => _fitToDevices(devicesWithPos),
                tooltip: 'Recenter',
                child: const Icon(Icons.center_focus_strong),
              ),
            ),
          ],
        );
      },
    );
  }

  Marker _buildMarker(BuildContext context, DeviceView v, DateTime now) {
    final est = _estimators[v.device.id];
    final shown = est?.predictAt(now) ??
        LatLng(v.position!.latitude, v.position!.longitude);

    return Marker(
      point: shown,
      width: 56,
      height: 56,
      child: GestureDetector(
        onTap: () => showDeviceDetailSheet(context, v),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (v.isLive) _PulsingRing(color: Colors.green),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: v.isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  void _fitToDevices(List<DeviceView> devices) {
    if (devices.isEmpty) return;

    if (devices.length == 1) {
      final p = devices.first.position!;
      _mapController.move(LatLng(p.latitude, p.longitude), 16);
      return;
    }

    final points = devices
        .map((d) => LatLng(d.position!.latitude, d.position!.longitude))
        .toList();

    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(64),
        maxZoom: 15,
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;
  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _PulsingRing extends StatefulWidget {
  final Color color;
  const _PulsingRing({required this.color});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        final size = 40 + (16 * t);
        final opacity = 1.0 - t;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: opacity),
              width: 3,
            ),
          ),
        );
      },
    );
  }
}
