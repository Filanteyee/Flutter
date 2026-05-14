enum BarrierEventType { autoRecognized, qrScan, manual, unknown }

enum BarrierDirection { inn, out }

enum BarrierEventStatus { opened, rejected, pending }

class BarrierEvent {
  final String id;
  final BarrierEventType eventType;
  final BarrierDirection? direction;
  final String? plateNumber;
  final String status;
  final DateTime createdAt;
  // Admin-enriched fields (nullable — absent for resident view)
  final String? ownerName;
  final String? brand;
  final String? color;

  const BarrierEvent({
    required this.id,
    required this.eventType,
    required this.direction,
    required this.plateNumber,
    required this.status,
    required this.createdAt,
    this.ownerName,
    this.brand,
    this.color,
  });

  factory BarrierEvent.fromJson(Map<String, dynamic> json) => BarrierEvent(
        id: json['id'].toString(),
        eventType: _parseType(json['event_type']?.toString()),
        direction: _parseDirection(json['direction']?.toString()),
        plateNumber: json['plate_number']?.toString(),
        status: (json['status'] ?? 'OPENED').toString(),
        createdAt: DateTime.parse(json['created_at'].toString()),
        ownerName: json['owner_name']?.toString(),
        brand: json['brand']?.toString(),
        color: json['color']?.toString(),
      );

  static BarrierEventType _parseType(String? v) {
    switch (v?.toUpperCase()) {
      case 'AUTO_RECOGNIZED':
        return BarrierEventType.autoRecognized;
      case 'QR_SCAN':
        return BarrierEventType.qrScan;
      case 'MANUAL':
        return BarrierEventType.manual;
      default:
        return BarrierEventType.unknown;
    }
  }

  static BarrierDirection? _parseDirection(String? v) {
    switch (v?.toUpperCase()) {
      case 'IN':
        return BarrierDirection.inn;
      case 'OUT':
        return BarrierDirection.out;
      default:
        return null;
    }
  }
}

extension BarrierEventTypeX on BarrierEventType {
  String get typeLabel {
    switch (this) {
      case BarrierEventType.autoRecognized:
        return 'Распознан номер';
      case BarrierEventType.qrScan:
        return 'QR-пропуск';
      case BarrierEventType.manual:
        return 'Ручное открытие';
      case BarrierEventType.unknown:
        return 'Неизвестный';
    }
  }
}

extension BarrierDirectionX on BarrierDirection {
  String get label => this == BarrierDirection.inn ? 'Въезд' : 'Выезд';
  String get apiValue => this == BarrierDirection.inn ? 'IN' : 'OUT';
}
