class TraccarDevice {
  final int id;
  final String name;
  final String uniqueId;
  final String status;
  final int positionId;
  final bool disabled;

  const TraccarDevice({
    required this.id,
    required this.name,
    required this.uniqueId,
    required this.status,
    required this.positionId,
    required this.disabled,
  });

  factory TraccarDevice.fromJson(Map<String, dynamic> json) {
    return TraccarDevice(
      id: json['id'] as int,
      name: json['name'] as String,
      uniqueId: json['uniqueId'] as String,
      status: json['status'] as String? ?? 'unknown',
      positionId: json['positionId'] as int? ?? 0,
      disabled: json['disabled'] as bool? ?? false,
    );
  }
}
