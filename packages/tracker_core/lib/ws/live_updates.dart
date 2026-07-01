class TraccarSocketMessage {
  final List<Map<String, dynamic>> positions;
  final List<Map<String, dynamic>> events;

  const TraccarSocketMessage({
    required this.positions,
    required this.events,
  });

  bool get isKeepalive => positions.isEmpty && events.isEmpty;

  factory TraccarSocketMessage.fromJson(Map<String, dynamic> json) {
    final positions = (json['positions'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];

    final events = (json['events'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];

    return TraccarSocketMessage(
      positions: positions,
      events: events,
    );
  }
}
