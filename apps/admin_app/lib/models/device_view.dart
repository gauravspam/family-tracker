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
  bool get isOnline => device.status == 'online';
  bool get isLive => approved?.isLive ?? false;
  DateTime? get liveExpiresAt => approved?.liveExpiresAt;

  String get displayName => device.name;
}
