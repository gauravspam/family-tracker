import 'package:tracker_core/tracker_core.dart';

/// A [TraccarDevice] joined with its latest known [TraccarPosition] (if any).
class DeviceView {
  final TraccarDevice device;
  final TraccarPosition? position;

  const DeviceView({required this.device, this.position});

  bool get hasPosition => position != null;
  bool get isOnline => device.status == 'online';

  String get displayName => device.name;
}
