class TraccarDevice {
  final int id;
  final String name;
  final String uniqueId;
  final String status;
  final int positionId;
  final bool disabled;
  final Map<String, dynamic> attributes;

  const TraccarDevice({
    required this.id,
    required this.name,
    required this.uniqueId,
    required this.status,
    required this.positionId,
    required this.disabled,
    required this.attributes,
  });

  factory TraccarDevice.fromJson(Map<String, dynamic> json) {
    return TraccarDevice(
      id: json['id'] as int,
      name: json['name'] as String,
      uniqueId: json['uniqueId'] as String,
      status: json['status'] as String? ?? 'unknown',
      positionId: json['positionId'] as int? ?? 0,
      disabled: json['disabled'] as bool? ?? false,
      attributes: (json['attributes'] as Map?)?.map(
            (k, v) => MapEntry(k as String, v),
          ) ??
          const {},
    );
  }

  /// Per-device avatar identifier stored in Traccar attributes.
  String? get avatarId => attributes['avatarId'] as String?;

  /// Per-device color as "#RRGGBB" stored in Traccar attributes.
  String? get colorHex => attributes['color'] as String?;
}
