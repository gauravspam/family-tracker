import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:tracker_core/tracker_core.dart';

import '../map/motion_estimator.dart';
import '../appearance/avatar_widget.dart';
import '../appearance/colors.dart';
import '../models/device_view.dart';
import '../services/geocode_service.dart';
import '../state/devices_controller.dart';
import '../state/geofences_controller.dart';
import '../state/hidden_devices_controller.dart';
import 'device_detail_sheet.dart';

class MapScreen extends StatefulWidget {
  final int remountSignal;

  /// When set, the map enters placement mode to position a new geofence.
  final ({String name, double radius})? pendingGeofence;

  /// Called after pendingGeofence is consumed and placement mode starts.
  final VoidCallback? onPlacementStarted;

  /// Called when a pin card / placement overlay visibility changes.
  final ValueChanged<bool>? onOverlayVisibilityChanged;

  const MapScreen({super.key, this.remountSignal = 0, this.pendingGeofence, this.onPlacementStarted, this.onOverlayVisibilityChanged});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  final Map<int, MotionEstimator> _estimators = {};
  Ticker? _ticker;
  bool _hasFittedOnce = false;

  int? _followingId;
  int? _playbackIndex;

  // ── Geofence placement mode ──────────────────────────────────────
  bool _placing = false;
  String _placeName = '';
  double _placeRadius = 100;
  double _placeLat = 19.0760;
  double _placeLng = 72.8777;

  // ── Pin-drop result ──────────────────────────────────────────────
  ({double lat, double lng})? _pin;
  String? _pinAddress;
  bool _pinLoading = false;
  bool _useSatellite = false;

  void _updateOverlayVisibility() {
    widget.onOverlayVisibilityChanged
        ?.call(_pin != null || _placing);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _checkPendingGeofence();
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pendingGeofence != null &&
        widget.pendingGeofence != oldWidget.pendingGeofence) {
      _enterPlacement(widget.pendingGeofence!);
    }
  }

  void _checkPendingGeofence() {
    final pg = widget.pendingGeofence;
    if (pg != null) {
      // Use a post-frame callback so the map is laid out first.
      WidgetsBinding.instance.addPostFrameCallback((_) => _enterPlacement(pg));
    }
  }

  void _enterPlacement(({String name, double radius}) pg) {
    setState(() {
      _placing = true;
      _placeName = pg.name;
      _placeRadius = pg.radius;
      _placeLat = _mapController.camera.center.latitude;
      _placeLng = _mapController.camera.center.longitude;
      _pin = null;
      _pinAddress = null;
    });
    _updateOverlayVisibility();
    widget.onPlacementStarted?.call();
  }

  void _exitPlacement() {
    setState(() {
      _placing = false;
      _placeName = '';
      _placeRadius = 100;
      _pin = null;
      _pinAddress = null;
    });
    _updateOverlayVisibility();
  }

  Future<void> _savePlacement() async {
    try {
      await context.read<GeofencesController>().create(
        _placeName, _placeLat, _placeLng, _placeRadius,
      );
      if (!mounted) return;
      _exitPlacement();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Geofence "$_placeName" created')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red.shade700),
    );
  }
}

  void _dropPin(double lat, double lng) {
    setState(() {
      _placeLat = lat;
      _placeLng = lng;
      _pin = (lat: lat, lng: lng);
      _pinAddress = null;
      _pinLoading = true;
    });
    _updateOverlayVisibility();
    _lookupPinAddress(lat, lng);
  }

  void _clearPin() {
    setState(() {
      _pin = null;
      _pinAddress = null;
      _pinLoading = false;
    });
    _updateOverlayVisibility();
  }

  Future<void> _lookupPinAddress(double lat, double lng) async {
    final addr = await GeocodeService.instance.reverse(lat, lng);
    if (!mounted) return;
    setState(() {
      _pinAddress = addr;
      _pinLoading = false;
    });
  }

  void followDevice(int traccarId) {
    setState(() => _followingId = traccarId);
    context.read<DevicesController>().fetchTrail(traccarId);
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
    if (_followingId == null) return;
    _maybeFollow();
    setState(() {});
  }

  void _maybeFollow() {
    final id = _followingId;
    if (id == null) return;
    if (_playbackIndex != null) {
      final trail = context.read<DevicesController>().trailFor(id);
      if (_playbackIndex! < trail.length) {
        final p = trail[_playbackIndex!];
        _mapController.move(LatLng(p.latitude, p.longitude), _mapController.camera.zoom);
      }
      return;
    }
    // Follow latest trail point — only center the map, keep user's zoom
    final trail = context.read<DevicesController>().trailFor(id);
    if (trail.length >= 2) {
      final last = trail.last;
      _mapController.move(LatLng(last.latitude, last.longitude), _mapController.camera.zoom);
    }
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
        final hidden = context.read<HiddenDevicesController>();
        final visibleDevices = hidden.isShowingHidden
            ? controller.devices
            : controller.devices.where((d) => !hidden.isHidden(d.device.id)).toList();
        final devicesWithPos =
            visibleDevices.where((d) => d.hasPosition).toList();

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
              key: ValueKey('map_${widget.remountSignal}'),
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(20.0, 77.0),
                initialZoom: 5,
                minZoom: 2,
                maxZoom: 19,
                onPositionChanged: (position, hasGesture) {
                  // handled via onMapEvent below
                },
                onMapEvent: (event) {
                  // Only stop follow on drag (pan), not on pinch-zoom, double-tap, etc.
                  if (event.source == MapEventSource.dragStart && _followingId != null) {
                    _stopFollow();
                  }
                },
                onTap: (tapPos, latlng) {
                  if (_placing) {
                    _dropPin(latlng.latitude, latlng.longitude);
                  }
                },
                onLongPress: (tapPos, latlng) {
                  if (!_placing) {
                    _dropPin(latlng.latitude, latlng.longitude);
                  }
                },
              ),
              children: [
                _buildTileLayer(),
                _buildGeofenceOverlay(),
                if (_followingId != null)
                  _buildTrailLayer(context, controller, _followingId!),
                MarkerLayer(
                  markers: [
                    ..._buildMarkersWithOffset(devicesWithPos, now),
                    if (_placing)
                      Marker(
                        point: LatLng(_placeLat, _placeLng),
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on, color: Colors.blue.shade700, size: 36),
                      ),
                    if (!_placing && _pin != null)
                      Marker(
                        point: LatLng(_pin!.lat, _pin!.lng),
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on, color: Colors.red, size: 36),
                      ),
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
              bottom: 156,
              child: FloatingActionButton.small(
                heroTag: 'satellite',
                onPressed: () => setState(() => _useSatellite = !_useSatellite),
                tooltip: _useSatellite ? 'Street map' : 'Satellite',
                child: Icon(
                  _useSatellite ? Icons.map : Icons.satellite_alt_outlined,
                  size: 20,
                ),
              ),
            ),

            Positioned(
              right: 16,
              bottom: 100,
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

            // ── Pin info card (normal mode long-press) ─────────────
            if (!_placing && _pin != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewPadding.bottom + 16,
                child: _PinInfoCard(
                  lat: _pin!.lat,
                  lng: _pin!.lng,
                  address: _pinAddress,
                  loading: _pinLoading,
                  onDismiss: _clearPin,
                ),
              ),

            // ── Placement mode bottom bar ──────────────────────────
            if (_placing)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewPadding.bottom + 16,
                child: _PlacementBar(
                  name: _placeName,
                  radius: _placeRadius,
                  onRadiusChanged: (v) => setState(() => _placeRadius = v),
                  onCancel: _exitPlacement,
                  onSave: _savePlacement,
                ),
              ),

            // ── Follow peek sheet ──────────────────────────────────────
            if (_followingId != null)
              _FollowPeekSheet(
                device: devicesWithPos.firstWhere(
                  (d) => d.device.id == _followingId,
                  orElse: () => devicesWithPos.first,
                ),
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
                trail: controller.trailFor(_followingId!),
                playbackIndex: _playbackIndex,
                onPlaybackChanged: (i) => setState(() => _playbackIndex = i),
                bottomPadding: MediaQuery.of(context).viewPadding.bottom + 88,
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

    // Find the device view for color info
    final deviceView = controller.devices.where((d) => d.device.id == traccarId);
    final colorHex = deviceView.isNotEmpty ? deviceView.first.device.colorHex : null;
    final color = DeviceColorPalette.parse(colorHex);

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
              color: color.withValues(alpha: 0.8),
            ))
        .toList();

    return PolylineLayer(polylines: polylines);
  }

  double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2 * math.pi / 180);
    final x = math.cos(lat1 * math.pi / 180) * math.sin(lat2 * math.pi / 180) -
        math.sin(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Widget _buildTileLayer() {
    if (_useSatellite) {
      return TileLayer(
        urlTemplate:
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: 'com.familytracker.admin_app',
        maxZoom: 19,
      );
    }
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.familytracker.admin_app',
      maxZoom: 19,
    );
  }


  List<Marker> _buildMarkersWithOffset(
    List<DeviceView> devices,
    DateTime now,
  ) {
    const thresholdDeg = 0.0002;
    final offsets = <int, Offset>{};

    for (var i = 0; i < devices.length; i++) {
      final a = devices[i];
      if (!a.hasPosition) continue;

      int overlapIndex = 0;
      for (var j = 0; j < i; j++) {
        final b = devices[j];
        if (!b.hasPosition) continue;
        final dLat = (a.position!.latitude - b.position!.latitude).abs();
        final dLon = (a.position!.longitude - b.position!.longitude).abs();
        if (dLat < thresholdDeg && dLon < thresholdDeg) {
          overlapIndex++;
        }
      }

      if (overlapIndex > 0) {
        final dx = 18.0 * (overlapIndex % 2 == 0 ? 1 : -1);
        final dy = -14.0 * overlapIndex;
        offsets[a.device.id] = Offset(dx, dy);
      }
    }

    return [
      for (final v in devices)
        _buildMarker(v, now, pixelOffset: offsets[v.device.id]),
      if (_followingId != null) _buildTrailArrow(devices, now),
    ];
  }

  Marker _buildTrailArrow(List<DeviceView> devices, DateTime now) {
    final id = _followingId;
    final v = devices.where((d) => d.device.id == id).firstOrNull;
    if (v == null) return const Marker(point: LatLng(0, 0), child: SizedBox.shrink());
    final color = DeviceColorPalette.parse(v.device.colorHex);
    final trail = context.read<DevicesController>().trailFor(id!);

    if (trail.length < 2) return const Marker(point: LatLng(0, 0), child: SizedBox.shrink());

    LatLng pt;
    double? bearing;

    if (_playbackIndex != null) {
      final idx = _playbackIndex!.clamp(0, trail.length - 1);
      final p = trail[idx];
      pt = LatLng(p.latitude, p.longitude);
      if (idx > 0) {
        final prev = trail[idx - 1];
        bearing = _bearing(prev.latitude, prev.longitude, p.latitude, p.longitude);
      }
    } else {
      final last = trail.last;
      final prev = trail[trail.length - 2];
      pt = LatLng(last.latitude, last.longitude);
      bearing = _bearing(prev.latitude, prev.longitude, last.latitude, last.longitude);
    }

    return Marker(
      point: pt,
      width: 56,
      height: 56,
      alignment: Alignment.center,
      child: bearing != null
          ? Transform.rotate(
              angle: bearing * math.pi / 180,
              alignment: Alignment.center,
              child: CustomPaint(
                size: const Size(56, 56),
                painter: _ArrowPainter(color),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Marker _buildMarker(DeviceView v, DateTime now, {Offset? pixelOffset}) {
    final est = _estimators[v.device.id];
    final shown = est?.predictAt(now) ??
        LatLng(v.position!.latitude, v.position!.longitude);

    final colorHex = v.device.colorHex;
    final color = DeviceColorPalette.parse(colorHex);

    return Marker(
      point: shown,
      width: 56,
      height: 56,
      alignment: pixelOffset != null
          ? Alignment(pixelOffset.dx / 28, pixelOffset.dy / 28)
          : Alignment.center,
      child: GestureDetector(
        onTap: () => showDeviceDetailSheet(
          context,
          v,
          onFollow: followDevice,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (v.isLive) _PulsingRing(color: color),
            DeviceAvatar(
              avatarId: v.device.avatarId,
              colorHex: colorHex,
              size: 40,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeofenceOverlay() {
    try {
      final geofences = context.read<GeofencesController>();
      final polys = <Polygon>[];

      for (final g in geofences.list) {
        final pts = _parseCircleArea(g.area);
        if (pts != null && pts.length >= 3) {
          polys.add(Polygon(
            points: pts,
            color: Colors.blue.withValues(alpha: 0.08),
            borderColor: Colors.blue.withValues(alpha: 0.35),
            borderStrokeWidth: 2,
          ));
        }
      }

      if (_placing) {
        final pts = _circlePoints(_placeLat, _placeLng, _placeRadius);
        if (pts.length >= 3) {
          polys.add(Polygon(
            points: pts,
            color: Colors.blue.withValues(alpha: 0.15),
            borderColor: Colors.blue.withValues(alpha: 0.6),
            borderStrokeWidth: 2.5,
          ));
        }
      }

      if (polys.isEmpty) return const SizedBox.shrink();
      return PolygonLayer(polygons: polys);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  /// Parse "CIRCLE (lat lng, radius)" into polygon points.
  List<LatLng>? _parseCircleArea(String area) {
    try {
      if (!area.toUpperCase().startsWith('CIRCLE')) return null;
      final cleaned = area
          .replaceAll(RegExp(r'[A-Za-z]'), '')
          .replaceAll('(', '')
          .replaceAll(')', '')
          .trim();
      final parts = cleaned.split(',');
      if (parts.length < 2) return null;
      final coords = parts[0].trim().split(RegExp(r'\s+'));
      if (coords.length < 2) return null;
      final lat = double.tryParse(coords[0]);
      final lng = double.tryParse(coords[1]);
      final radius = double.tryParse(parts[1].trim());
      if (lat == null || lng == null || radius == null || radius <= 0) return null;
      return _circlePoints(lat, lng, radius);
    } catch (_) {
      return null;
    }
  }

  List<LatLng> _circlePoints(double lat, double lng, double radiusMeters) {
    final segments = 36;
    return List.generate(segments, (i) {
      final angle = (2 * 3.14159265 * i) / segments;
      final dLat = (radiusMeters / 111320) * math.cos(angle);
      final dLng = (radiusMeters / (111320 * math.cos(lat * 3.14159265 / 180))) * math.sin(angle);
      return LatLng(lat + dLat, lng + dLng);
    });
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

class _FollowPeekSheet extends StatelessWidget {
  final DeviceView device;
  final VoidCallback onStop;
  final VoidCallback onClearTrail;
  final List<TraccarPosition> trail;
  final int? playbackIndex;
  final ValueChanged<int?> onPlaybackChanged;
  final double bottomPadding;

  const _FollowPeekSheet({
    required this.device,
    required this.onStop,
    required this.onClearTrail,
    required this.trail,
    required this.playbackIndex,
    required this.onPlaybackChanged,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = device.position;
    final batt = p?.batteryPercent;

    return Positioned(
      left: 12,
      right: 12,
      bottom: bottomPadding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey.shade900.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.04),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle hint
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Main row: avatar + info + actions
              Row(
                children: [
                  DeviceAvatar(
                    avatarId: device.device.avatarId,
                    colorHex: device.device.colorHex,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                device.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (device.isLive) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (p != null) ...[
                              Text(
                                _relative(p.fixTime),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              if (batt != null) ...[
                                Text(
                                  ' · ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Icon(
                                  batt < 20
                                      ? Icons.battery_alert
                                      : Icons.battery_std,
                                  size: 12,
                                  color: batt < 20
                                      ? Colors.red
                                      : scheme.onSurfaceVariant,
                                ),
                                Text(
                                  ' $batt%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: batt < 20
                                        ? Colors.red
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (p.speed > 1) ...[
                                Text(
                                  ' · ${(p.speed * 3.6).toStringAsFixed(0)} km/h',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                            if (p == null)
                              Text(
                                'No position',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Actions
                  IconButton(
                    icon: const Icon(Icons.timeline_rounded, size: 20),
                    tooltip: 'Clear trail',
                    onPressed: onClearTrail,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Stop following',
                    onPressed: onStop,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              // ── History playback slider ──────────────────────────
              if (trail.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            playbackIndex != null
                                ? 'History ${playbackIndex! + 1}/${trail.length}'
                                : 'Playback (${trail.length} pts)',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (playbackIndex != null)
                            GestureDetector(
                              onTap: () => onPlaybackChanged(null),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.close_rounded,
                                    size: 14, color: scheme.primary),
                              ),
                            ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14),
                        ),
                        child: Slider(
                          value: (playbackIndex ?? 0).toDouble(),
                          min: 0,
                          max: (trail.length - 1).toDouble(),
                          divisions: trail.length - 1,
                          label: playbackIndex != null
                              ? _relative(trail[playbackIndex!].fixTime)
                              : null,
                          onChanged: (v) =>
                              onPlaybackChanged(v.round()),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat.Hm().format(t.toLocal());
  }
}

// ── Pin info bottom card (long-press result) ─────────────────────────

class _PinInfoCard extends StatelessWidget {
  final double lat;
  final double lng;
  final String? address;
  final bool loading;
  final VoidCallback onDismiss;
  const _PinInfoCard({
    required this.lat,
    required this.lng,
    this.address,
    required this.loading,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? Colors.grey.shade900.withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                _CopyButton(
                  value: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                  tooltip: 'Copy coordinates',
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (loading)
              Row(
                children: [
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Looking up address…',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              )
            else if (address != null)
              Row(
                children: [
                  Expanded(
                    child: Text(address!,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  ),
                  _CopyButton(value: address!, tooltip: 'Copy address'),
                ],
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onDismiss,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  final String value;
  final String tooltip;
  const _CopyButton({required this.value, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(Icons.copy_outlined, size: 16, color: scheme.primary),
      tooltip: tooltip,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$tooltip copied'), duration: Duration(seconds: 1)),
        );
      },
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Placement mode bottom bar ─────────────────────────────────────────

class _PlacementBar extends StatelessWidget {
  final String name;
  final double radius;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  const _PlacementBar({
    required this.name,
    required this.radius,
    required this.onRadiusChanged,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? Colors.grey.shade900.withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.circle_outlined, color: Colors.blue.shade600, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${radius.toInt()} m',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: radius,
                min: 25,
                max: 2000,
                divisions: 79,
                label: '${radius.toInt()} m',
                onChanged: onRadiusChanged,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Tap on map to position · long-press in normal mode to pinpoint',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  _ArrowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = ui.Path()
      ..moveTo(w / 2, 4)
      ..lineTo(w - 5, h - 11)
      ..lineTo(w / 2, h - 20)
      ..lineTo(5, h - 11)
      ..close();

    canvas.drawShadow(path, Colors.black26, 4, false);

    final fill = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}
