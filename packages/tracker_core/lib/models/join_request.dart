class JoinRequest {
  final String androidId;
  final String deviceModel;
  final String fcmToken;
  final String? appVersion;
  final String? osVersion;

  const JoinRequest({
    required this.androidId,
    required this.deviceModel,
    required this.fcmToken,
    this.appVersion,
    this.osVersion,
  });

  Map<String, dynamic> toJson() => {
        'androidId': androidId,
        'deviceModel': deviceModel,
        'fcmToken': fcmToken,
        'appVersion': appVersion,
        'osVersion': osVersion,
      };
}
