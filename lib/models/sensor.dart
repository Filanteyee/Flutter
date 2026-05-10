/// Конфигурация общедомовой сети датчиков. Должна совпадать с seed'ом на бэке
/// (см. промпт IoT-инициативы: 3 × 9 × 2 = 54 датчика).
const int kEntrancesCount = 3;
const int kFloorsPerEntrance = 9;

enum SensorType { water, smoke }

enum SensorStatus { normal, alert, offline }

enum EventStatus { detected, checking, confirmed, falseAlarm }

enum ThreatType { waterLeak, fire }

class Sensor {
  final String id;
  final SensorType type;
  final int entranceNum;
  final int floor;
  final SensorStatus status;
  final DateTime lastUpdated;

  const Sensor({
    required this.id,
    required this.type,
    required this.entranceNum,
    required this.floor,
    required this.status,
    required this.lastUpdated,
  });

  Sensor copyWith({
    SensorStatus? status,
    DateTime? lastUpdated,
  }) {
    return Sensor(
      id: id,
      type: type,
      entranceNum: entranceNum,
      floor: floor,
      status: status ?? this.status,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  factory Sensor.fromJson(Map<String, dynamic> json) {
    return Sensor(
      id: json['id'].toString(),
      type: _parseType(json['type'].toString()),
      entranceNum: (json['entrance_num'] as num).toInt(),
      floor: (json['floor'] as num).toInt(),
      status: _parseStatus(json['status'].toString()),
      lastUpdated: DateTime.parse(json['last_updated'].toString()),
    );
  }

  static SensorType _parseType(String value) {
    switch (value.toUpperCase()) {
      case 'WATER':
        return SensorType.water;
      case 'SMOKE':
        return SensorType.smoke;
      default:
        return SensorType.water;
    }
  }

  static SensorStatus _parseStatus(String value) {
    switch (value.toUpperCase()) {
      case 'NORMAL':
        return SensorStatus.normal;
      case 'ALERT':
        return SensorStatus.alert;
      case 'OFFLINE':
        return SensorStatus.offline;
      default:
        return SensorStatus.offline;
    }
  }
}

class SensorEvent {
  final String id;
  final String sensorId;
  final SensorType type;
  final int entranceNum;
  final int floor;
  final EventStatus status;
  final ThreatType? threatType;
  final String? adminComment;
  final DateTime createdAt;
  final DateTime? confirmedAt;

  const SensorEvent({
    required this.id,
    required this.sensorId,
    required this.type,
    required this.entranceNum,
    required this.floor,
    required this.status,
    required this.createdAt,
    this.threatType,
    this.adminComment,
    this.confirmedAt,
  });

  SensorEvent copyWith({
    EventStatus? status,
    ThreatType? threatType,
    String? adminComment,
    DateTime? confirmedAt,
  }) {
    return SensorEvent(
      id: id,
      sensorId: sensorId,
      type: type,
      entranceNum: entranceNum,
      floor: floor,
      status: status ?? this.status,
      threatType: threatType ?? this.threatType,
      adminComment: adminComment ?? this.adminComment,
      createdAt: createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
    );
  }

  factory SensorEvent.fromJson(Map<String, dynamic> json) {
    return SensorEvent(
      id: json['id'].toString(),
      sensorId: json['sensor_id'].toString(),
      type: Sensor._parseType(json['type'].toString()),
      entranceNum: (json['entrance_num'] as num).toInt(),
      floor: (json['floor'] as num).toInt(),
      status: _parseEventStatus(json['status'].toString()),
      threatType: json['threat_type'] != null
          ? _parseThreatType(json['threat_type'].toString())
          : null,
      adminComment: json['admin_comment']?.toString(),
      createdAt: DateTime.parse(json['created_at'].toString()),
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.parse(json['confirmed_at'].toString())
          : null,
    );
  }

  static EventStatus _parseEventStatus(String value) {
    switch (value.toUpperCase()) {
      case 'DETECTED':
        return EventStatus.detected;
      case 'CHECKING':
        return EventStatus.checking;
      case 'CONFIRMED':
        return EventStatus.confirmed;
      case 'FALSE_ALARM':
        return EventStatus.falseAlarm;
      default:
        return EventStatus.detected;
    }
  }

  static ThreatType _parseThreatType(String value) {
    switch (value.toUpperCase()) {
      case 'WATER_LEAK':
        return ThreatType.waterLeak;
      case 'FIRE':
        return ThreatType.fire;
      default:
        return ThreatType.waterLeak;
    }
  }
}

extension SensorTypeX on SensorType {
  String get apiValue => this == SensorType.water ? 'WATER' : 'SMOKE';
  String get label => this == SensorType.water ? 'Датчик воды' : 'Датчик дыма';
  String get shortLabel => this == SensorType.water ? 'Вода' : 'Дым';
}

extension SensorStatusX on SensorStatus {
  String get apiValue {
    switch (this) {
      case SensorStatus.normal:
        return 'NORMAL';
      case SensorStatus.alert:
        return 'ALERT';
      case SensorStatus.offline:
        return 'OFFLINE';
    }
  }

  String get label {
    switch (this) {
      case SensorStatus.normal:
        return 'Норма';
      case SensorStatus.alert:
        return 'Тревога';
      case SensorStatus.offline:
        return 'Не на связи';
    }
  }
}

extension EventStatusX on EventStatus {
  String get apiValue {
    switch (this) {
      case EventStatus.detected:
        return 'DETECTED';
      case EventStatus.checking:
        return 'CHECKING';
      case EventStatus.confirmed:
        return 'CONFIRMED';
      case EventStatus.falseAlarm:
        return 'FALSE_ALARM';
    }
  }

  String get label {
    switch (this) {
      case EventStatus.detected:
        return 'Обнаружено';
      case EventStatus.checking:
        return 'Проверяется';
      case EventStatus.confirmed:
        return 'Подтверждено';
      case EventStatus.falseAlarm:
        return 'Ложная тревога';
    }
  }
}

extension ThreatTypeX on ThreatType {
  String get apiValue =>
      this == ThreatType.waterLeak ? 'WATER_LEAK' : 'FIRE';
  String get label =>
      this == ThreatType.waterLeak ? 'Затопление' : 'Пожар';
}
