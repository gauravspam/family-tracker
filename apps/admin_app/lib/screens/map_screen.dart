import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:tracker_core/tracker_core.dart';

import '../map/motion_estimator.dart';
import '../appearance/avatar_widget.dart';
import '../models/device_view.dart';
import '../state/devices_controller.dart';
import '../state/hidden_devices_controller.dart';
import 'device_detail_sheet.dart';

class MapScreen extends StatefulWidget {
  final int remountSignal;
  const MapScreen({super.key, this.remountSignal = 0});

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

  /// History playback: index into the trail for the followed device.
  int? _playbackIndex;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

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
    if (_playbackIndex != null) {
      final trail = context.read<DevicesController>().trailFor(id);
      if (_playbackIndex! < trail.length) {
        final p = trail[_playbackIndex!];
        _programmaticMove = true;
        _mapController.move(LatLng(p.latitude, p.longitude), _mapController.camera.zoom);
        _programmaticMove = false;
      }
      return;
    }
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
                  markers: _buildMarkersWithOffset(context, devicesWithPos, now),
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


  List<Marker> _buildMarkersWithOffset(
    BuildContext context,
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
        _buildMarker(context, v, now, pixelOffset: offsets[v.device.id]),
    ];
  }

  Marker _buildMarker(BuildContext context, DeviceView v, DateTime now, {Offset? pixelOffset}) {
    final est = _estimators[v.device.id];
    final shown = est?.predictAt(now) ??
        LatLng(v.position!.latitude, v.position!.longitude);

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
            if (v.isLive) _PulsingRing(color: Colors.green),
            DeviceAvatar(
              avatarId: v.device.avatarId,
              colorHex: v.device.colorHex,
              size: 40,
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
      child: Material(
        color: isDark
            ? Colors.grey.shade900.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        elevation: 6,
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
