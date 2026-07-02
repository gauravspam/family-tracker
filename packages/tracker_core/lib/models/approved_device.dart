class ApprovedDevice {
  final int pendingId;
  final int traccarDeviceId;
  final String androidId;
  final String deviceModel;
  final String mode;

  const ApprovedDevice({
    required this.pendingId,
    required this.traccarDeviceId,
    required this.androidId,
    required this.deviceModel,
    required this.mode,
  });

  factory ApprovedDevice.fromJson(Map<String, dynamic> json) {
    return ApprovedDevice(
      pendingId: json['pendingId'] as int,
      traccarDeviceId: json['traccarDeviceId'] as int,
      androidId: json['androidId'] as String,
      deviceModel: json['deviceModel'] as String,
      mode: json['mode'] as String,
    );
  }

  bool get isLive => mode == 'live';
}
