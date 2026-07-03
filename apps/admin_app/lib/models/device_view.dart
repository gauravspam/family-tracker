import 'package:tracker_core/tracker_core.dart';

/// A [TraccarDevice] joined with its latest known [TraccarPosition]
/// and (if available) its relay [ApprovedDevice] metadata.
class DeviceView {
  final TraccarDevice device;
  final TraccarPosition? position;
  final ApprovedDevice? approved;

  const DeviceView({
    required this.device,
    this.position,
    this.approved,
  });

  bool get hasPosition => position != null;
  /// A device is considered online if we've received a position within
  /// [onlineThreshold]. This overrides Traccar's own status which is
  /// derived from its heartbeat logic and can lag.
  bool get isOnline {
    final p = position;
    if (p == null) return false;
    return DateTime.now().difference(p.fixTime.toLocal()) <= onlineThreshold;
  }

  static const Duration onlineThreshold = Duration(minutes: 2);
  bool get isLive => approved?.isLive ?? false;
  DateTime? get liveExpiresAt => approved?.liveExpiresAt;

  /// A device is an orphan when Traccar knows about it but the relay
  /// has no matching approved row. Usually the result of a partial
  /// approve failure or a device manually created in Traccar.
  bool get isOrphan => approved == null;

  String get displayName => device.name;
}
