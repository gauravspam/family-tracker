class ApprovedDevice {
  final int pendingId;
  final int traccarDeviceId;
  final String androidId;
  final String deviceModel;
  final String mode;
  final DateTime? liveExpiresAt;

  const ApprovedDevice({
    required this.pendingId,
    required this.traccarDeviceId,
    required this.androidId,
    required this.deviceModel,
    required this.mode,
    this.liveExpiresAt,
  });

  factory ApprovedDevice.fromJson(Map<String, dynamic> json) {
    final expStr = json['liveExpiresAt'] as String?;
    return ApprovedDevice(
      pendingId: json['pendingId'] as int,
      traccarDeviceId: json['traccarDeviceId'] as int,
      androidId: json['androidId'] as String,
      deviceModel: json['deviceModel'] as String,
      mode: json['mode'] as String,
      liveExpiresAt: expStr == null ? null : DateTime.parse(expStr),
    );
  }

  bool get isLive => mode == 'live';

  /// Time until live expiry, or null if not live / no expiry.
  /// Negative durations indicate expired.
  Duration? get remainingLive {
    if (!isLive || liveExpiresAt == null) return null;
    return liveExpiresAt!.difference(DateTime.now());
  }
}
