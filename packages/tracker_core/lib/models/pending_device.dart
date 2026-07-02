class PendingDevice {
  final int id;
  final String androidId;
  final String deviceModel;
  final String? appVersion;
  final String? osVersion;
  final DateTime createdAt;

  const PendingDevice({
    required this.id,
    required this.androidId,
    required this.deviceModel,
    required this.appVersion,
    required this.osVersion,
    required this.createdAt,
  });

  factory PendingDevice.fromJson(Map<String, dynamic> json) {
    return PendingDevice(
      id: json['id'] as int,
      androidId: json['androidId'] as String,
      deviceModel: json['deviceModel'] as String,
      appVersion: json['appVersion'] as String?,
      osVersion: json['osVersion'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
