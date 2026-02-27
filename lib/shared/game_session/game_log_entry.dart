/// A single entry in the session audit log.
class GameLogEntry {
  final String eventType;
  final String description;
  final int timestamp; // millisecondsSinceEpoch

  const GameLogEntry({
    required this.eventType,
    required this.description,
    required this.timestamp,
  });

  factory GameLogEntry.fromJson(Map<String, dynamic> json) => GameLogEntry(
        eventType: json['eventType'] as String,
        description: json['description'] as String,
        timestamp: json['timestamp'] as int,
      );

  Map<String, dynamic> toJson() => {
        'eventType': eventType,
        'description': description,
        'timestamp': timestamp,
      };
}
