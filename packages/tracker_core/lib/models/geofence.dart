class TraccarGeofence {
  final int id;
  final String name;
  final String? description;
  final String area;

  const TraccarGeofence({
    required this.id,
    required this.name,
    required this.description,
    required this.area,
  });

  factory TraccarGeofence.fromJson(Map<String, dynamic> json) {
    return TraccarGeofence(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      area: json['area'] as String,
    );
  }
}
