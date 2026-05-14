enum ParkingEventType { occupied, freed }

class ParkingEvent {
  final String id;
  final String spotId;
  final String spotNumber;
  final ParkingEventType eventType;
  final DateTime createdAt;

  const ParkingEvent({
    required this.id,
    required this.spotId,
    required this.spotNumber,
    required this.eventType,
    required this.createdAt,
  });

  factory ParkingEvent.fromJson(Map<String, dynamic> json) => ParkingEvent(
        id: json['id'].toString(),
        spotId: json['spot_id'].toString(),
        spotNumber: json['spot_number'].toString(),
        eventType: _parseType(json['event_type']?.toString()),
        createdAt: DateTime.parse(json['created_at'].toString()),
      );

  static ParkingEventType _parseType(String? v) {
    switch (v?.toUpperCase()) {
      case 'FREED':
        return ParkingEventType.freed;
      default:
        return ParkingEventType.occupied;
    }
  }
}

extension ParkingEventTypeX on ParkingEventType {
  String get label => this == ParkingEventType.occupied ? 'Занято' : 'Освобождено';
}
