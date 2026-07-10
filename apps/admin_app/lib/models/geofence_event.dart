class GeofenceEvent {
  final int id;
  final int traccarDeviceId;
  final int geofenceId;
  final String geofenceName;
  final String eventType;
  final String deviceName;
  final DateTime createdAt;

  const GeofenceEvent({
    required this.id,
    required this.traccarDeviceId,
    required this.geofenceId,
    required this.geofenceName,
    required this.eventType,
    required this.deviceName,
    required this.createdAt,
  });

  factory GeofenceEvent.fromJson(Map<String, dynamic> json) {
    return GeofenceEvent(
      id: json['id'] as int,
      traccarDeviceId: json['traccarDeviceId'] as int,
      geofenceId: json['geofenceId'] as int,
      geofenceName: json['geofenceName'] as String? ?? '',
      eventType: json['eventType'] as String,
      deviceName: json['deviceName'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  bool get isEnter => eventType == 'geofenceEnter';

  String get label => isEnter ? 'Entered' : 'Exited';
}
