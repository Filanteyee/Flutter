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

  /// Когда последний раз пришло MQTT-сообщение (включая heartbeat).
  /// На UI «когда датчик жил последний раз» — это поле.
  final DateTime? lastSeenAt;

  const Sensor({
    required this.id,
    required this.type,
    required this.entranceNum,
    required this.floor,
    required this.status,
    required this.lastUpdated,
    this.lastSeenAt,
  });

  Sensor copyWith({
    SensorStatus? status,
    DateTime? lastUpdated,
    DateTime? lastSeenAt,
  }) {
    return Sensor(
      id: id,
      type: type,
      entranceNum: entranceNum,
      floor: floor,
      status: status ?? this.status,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  factory Sensor.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(dynamic raw) {
      if (raw == null) return null;
      final s = raw.toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return Sensor(
      id: json['id'].toString(),
      type: _parseType(json['type'].toString()),
      entranceNum: (json['entrance_num'] as num).toInt(),
      floor: (json['floor'] as num).toInt(),
      status: _parseStatus(json['status'].toString()),
      lastUpdated: DateTime.parse(json['last_updated'].toString()),
      lastSeenAt: parseOpt(json['last_seen_at']),
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
  final DateTime? checkingAt;
  final DateTime? confirmedAt;
  final DateTime? falseAlarmedAt;
  final String? confirmedBy;

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
    this.checkingAt,
    this.confirmedAt,
    this.falseAlarmedAt,
    this.confirmedBy,
  });

  SensorEvent copyWith({
    EventStatus? status,
    ThreatType? threatType,
    String? adminComment,
    DateTime? checkingAt,
    DateTime? confirmedAt,
    DateTime? falseAlarmedAt,
    String? confirmedBy,
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
      checkingAt: checkingAt ?? this.checkingAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      falseAlarmedAt: falseAlarmedAt ?? this.falseAlarmedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
    );
  }

  factory SensorEvent.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(dynamic raw) {
      if (raw == null) return null;
      final s = raw.toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

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
      checkingAt: parseOpt(json['checking_at']),
      confirmedAt: parseOpt(json['confirmed_at']),
      falseAlarmedAt: parseOpt(json['false_alarmed_at']),
      confirmedBy: json['confirmed_by']?.toString(),
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

/// Шаг таймлайна события: DETECTED → CHECKING → CONFIRMED/FALSE_ALARM.
/// Бэк гарантирует упорядоченность по времени, DETECTED всегда первым.
class TimelineStep {
  final EventStatus status;
  final DateTime at;
  final String? by;
  final ThreatType? threatType;
  final String? comment;

  const TimelineStep({
    required this.status,
    required this.at,
    this.by,
    this.threatType,
    this.comment,
  });

  factory TimelineStep.fromJson(Map<String, dynamic> json) {
    return TimelineStep(
      status: SensorEvent._parseEventStatus(json['status'].toString()),
      at: DateTime.parse(json['at'].toString()),
      by: json['by']?.toString(),
      threatType: json['threat_type'] != null
          ? SensorEvent._parseThreatType(json['threat_type'].toString())
          : null,
      comment: json['comment']?.toString(),
    );
  }
}

/// Ответ `GET /sensors/events/:id`: событие + датчик + таймлайн переходов.
class SensorEventDetail {
  final SensorEvent event;
  final Sensor sensor;
  final List<TimelineStep> timeline;

  const SensorEventDetail({
    required this.event,
    required this.sensor,
    required this.timeline,
  });

  factory SensorEventDetail.fromJson(Map<String, dynamic> json) {
    final rawTimeline = (json['timeline'] as List?) ?? const [];
    return SensorEventDetail(
      event: SensorEvent.fromJson(Map<String, dynamic>.from(json['event'] as Map)),
      sensor: Sensor.fromJson(Map<String, dynamic>.from(json['sensor'] as Map)),
      timeline: rawTimeline
          .map((e) => TimelineStep.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
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

/// Строка «топ этажей» из ответа `/admin/sensors/stats`.
class FloorCount {
  final int floor;
  final int entrance;
  final int count;

  const FloorCount({
    required this.floor,
    required this.entrance,
    required this.count,
  });

  factory FloorCount.fromJson(Map<String, dynamic> json) => FloorCount(
        floor: (json['floor'] as num).toInt(),
        entrance: (json['entrance_num'] as num).toInt(),
        count: (json['count'] as num).toInt(),
      );
}

/// Ответ `GET /admin/sensors/stats?period=today|week`.
class SensorStats {
  final int totalEvents;
  final Map<EventStatus, int> byStatus;
  final Map<ThreatType, int> byThreat;
  final double avgResponseSeconds;
  final double falseAlarmRate;
  final List<FloorCount> topFloors;
  final int offlineSensors;
  final int totalSensors;

  const SensorStats({
    required this.totalEvents,
    required this.byStatus,
    required this.byThreat,
    required this.avgResponseSeconds,
    required this.falseAlarmRate,
    required this.topFloors,
    required this.offlineSensors,
    required this.totalSensors,
  });

  factory SensorStats.fromJson(Map<String, dynamic> json) {
    Map<EventStatus, int> parseByStatus(dynamic raw) {
      if (raw == null) return {};
      final m = Map<String, dynamic>.from(raw as Map);
      return {
        for (final e in m.entries)
          SensorEvent._parseEventStatus(e.key): (e.value as num).toInt(),
      };
    }

    Map<ThreatType, int> parseByThreat(dynamic raw) {
      if (raw == null) return {};
      final m = Map<String, dynamic>.from(raw as Map);
      return {
        for (final e in m.entries)
          SensorEvent._parseThreatType(e.key): (e.value as num).toInt(),
      };
    }

    final rawFloors = (json['top_floors'] as List?) ?? const [];
    return SensorStats(
      totalEvents: (json['total_events'] as num?)?.toInt() ?? 0,
      byStatus: parseByStatus(json['by_status']),
      byThreat: parseByThreat(json['by_threat']),
      avgResponseSeconds:
          (json['avg_response_seconds'] as num?)?.toDouble() ?? 0,
      falseAlarmRate: (json['false_alarm_rate'] as num?)?.toDouble() ?? 0,
      topFloors: rawFloors
          .map((e) =>
              FloorCount.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      offlineSensors: (json['offline_sensors'] as num?)?.toInt() ?? 0,
      totalSensors: (json['total_sensors'] as num?)?.toInt() ?? 0,
    );
  }
}
