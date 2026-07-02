class TraccarPosition {
  final int id;
  final int deviceId;
  final String protocol;
  final DateTime serverTime;
  final DateTime deviceTime;
  final DateTime fixTime;
  final bool outdated;
  final bool valid;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double course;
  final double accuracy;
  final Map<String, dynamic> attributes;

  const TraccarPosition({
    required this.id,
    required this.deviceId,
    required this.protocol,
    required this.serverTime,
    required this.deviceTime,
    required this.fixTime,
    required this.outdated,
    required this.valid,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.course,
    required this.accuracy,
    required this.attributes,
  });

  factory TraccarPosition.fromJson(Map<String, dynamic> json) {
    return TraccarPosition(
      id: json['id'] as int,
      deviceId: json['deviceId'] as int,
      protocol: json['protocol'] as String,
      serverTime: DateTime.parse(json['serverTime'] as String),
      deviceTime: DateTime.parse(json['deviceTime'] as String),
      fixTime: DateTime.parse(json['fixTime'] as String),
      outdated: json['outdated'] as bool,
      valid: json['valid'] as bool,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      course: (json['course'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      attributes: (json['attributes'] as Map?)?.map(
            (k, v) => MapEntry(k as String, v),
          ) ??
          const {},
    );
  }

  /// Battery percent 0-100, or null if the reporter didn't send it.
  int? get batteryPercent {
    final v = attributes['batteryLevel'];
    if (v is num) return v.round().clamp(0, 100);
    return null;
  }

  /// True when [batteryPercent] is present and below 20%.
  bool get isLowBattery {
    final b = batteryPercent;
    return b != null && b < 20;
  }
}
