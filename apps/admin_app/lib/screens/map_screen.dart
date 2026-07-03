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

  /// The Traccar device id currently being followed, or null.
  int? _followingId;

  /// Set when we programmatically move the map so the manual-pan
  /// stop-follow detection can distinguish user gestures.
  bool _programmaticMove = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  /// External entry point used by the device detail sheet.
  void followDevice(int traccarId) {
    setState(() => _followingId = traccarId);
  }

  void _stopFollow() {
    if (_followingId != null) {
      setState(() => _followingId = null);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    _maybeFollow();
    setState(() {});
  }

  void _maybeFollow() {
    final id = _followingId;
    if (id == null) return;
    final est = _estimators[id];
    if (est == null || !est.hasAnchor) return;
    final target = est.predictAt(DateTime.now());
    _programmaticMove = true;
    _mapController.move(target, _mapController.camera.zoom < 15 ? 17 : _mapController.camera.zoom);
    _programmaticMove = false;
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
              options: MapOptions(
                initialCenter: const LatLng(20.0, 77.0),
                initialZoom: 5,
                minZoom: 2,
                maxZoom: 19,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && !_programmaticMove) {
                    _stopFollow();
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.familytracker.admin_app',
                  maxZoom: 19,
                ),
                if (_followingId != null)
                  _buildTrailLayer(context, controller, _followingId!),
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
            if (_followingId != null)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: _FollowingChip(
                  label: devicesWithPos
                          .firstWhere(
                            (d) => d.device.id == _followingId,
                            orElse: () => devicesWithPos.first,
                          )
                          .displayName,
                  onStop: _stopFollow,
                  onClearTrail: () {
                    controller.clearTrail(_followingId!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Trail cleared'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'recenter',
                onPressed: () {
                  _stopFollow();
                  _fitToDevices(devicesWithPos);
                },
                tooltip: 'Recenter',
                child: const Icon(Icons.center_focus_strong),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrailLayer(
    BuildContext context,
    DevicesController controller,
    int traccarId,
  ) {
    final points = controller.trailFor(traccarId);
    if (points.length < 2) return const SizedBox.shrink();

    // Break the trail into segments when the time gap between consecutive
    // fixes exceeds [gapThreshold]. Prevents drawing a single long line
    // across a period where we lost signal.
    const gapThreshold = Duration(seconds: 60);

    final segments = <List<LatLng>>[[]];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (i > 0) {
        final gap = p.fixTime.difference(points[i - 1].fixTime);
        if (gap > gapThreshold) {
          segments.add(<LatLng>[]);
        }
      }
      segments.last.add(LatLng(p.latitude, p.longitude));
    }

    final polylines = segments
        .where((s) => s.length >= 2)
        .map((s) => Polyline(
              points: s,
              strokeWidth: 4,
              color: Colors.blue.shade400.withValues(alpha: 0.75),
            ))
        .toList();

    if (polylines.isEmpty) return const SizedBox.shrink();

    return PolylineLayer(polylines: polylines);
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
        onTap: () => showDeviceDetailSheet(
          context,
          v,
          onFollow: followDevice,
        ),
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

class _FollowingChip extends StatelessWidget {
  final String label;
  final VoidCallback onStop;
  final VoidCallback onClearTrail;

  const _FollowingChip({
    required this.label,
    required this.onStop,
    required this.onClearTrail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: Material(
            color: Colors.blue.shade700,
            elevation: 3,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onStop,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gps_fixed, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Following $label',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.close, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.blue.shade700,
          elevation: 3,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onClearTrail,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Tooltip(
                message: 'Clear trail',
                child: Icon(Icons.timeline, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
