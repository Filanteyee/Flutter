import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sensor.dart';
import 'api_client.dart';

/// Сервис общедомовых датчиков. Все запросы — через [ApiClient] (JWT-интерсептор
/// уже подставлен). Бэкенд: `http://10.0.2.2:8080/api/v1` для Android-эмулятора.
///
/// FCM-пуш с `kind=sensor_alert` дёргает [refreshFromPush]: сервис тихо
/// перезапрашивает свежий список событий и пушит в [eventsStream], на который
/// подписаны экраны.
class SensorService {
  SensorService._internal();
  static final SensorService instance = SensorService._internal();

  final _eventsController =
      StreamController<List<SensorEvent>>.broadcast();

  /// Поток последних загруженных событий. Эмиттится после каждого `getEvents`
  /// и после `refreshFromPush`. UI подписывается, чтобы перерисовываться без
  /// ручного `setState` по таймеру.
  Stream<List<SensorEvent>> get eventsStream => _eventsController.stream;

  /// GET /api/v1/sensors?entrance={entrance}
  Future<List<Sensor>> getSensors({required int entrance}) async {
    final res = await ApiClient.instance.get(
      '/sensors',
      params: {'entrance': entrance},
    );
    return (res.data as List)
        .map((e) => Sensor.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// GET /api/v1/admin/sensors
  Future<List<Sensor>> getAllSensors() async {
    final res = await ApiClient.instance.get('/admin/sensors');
    return (res.data as List)
        .map((e) => Sensor.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// GET /api/v1/sensors/events?entrance={entrance}&status={status}
  Future<List<SensorEvent>> getEvents({
    int? entrance,
    EventStatus? status,
  }) async {
    final res = await ApiClient.instance.get(
      '/sensors/events',
      params: {
        if (entrance != null) 'entrance': entrance,
        if (status != null) 'status': status.apiValue,
      },
    );
    final list = (res.data as List)
        .map((e) => SensorEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _eventsController.add(list);
    return list;
  }

  /// PATCH /api/v1/admin/sensors/events/{id}/status
  ///
  /// При [EventStatus.confirmed] нужно обязательно передать [threatType]
  /// и желательно [adminComment]. Бэкенд после этого рассылает push
  /// всем жильцам подъезда (см. [notifyEntrance]).
  Future<SensorEvent> updateEventStatus({
    required String eventId,
    required EventStatus status,
    ThreatType? threatType,
    String? adminComment,
  }) async {
    final res = await ApiClient.instance.patch(
      '/admin/sensors/events/$eventId/status',
      data: {
        'status': status.apiValue,
        if (threatType != null) 'threat_type': threatType.apiValue,
        if (adminComment != null) 'admin_comment': adminComment,
      },
    );
    return SensorEvent.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// POST /api/v1/admin/sensors/events/{id}/notify
  ///
  /// Бэкенд рассылает push всем жильцам подъезда события.
  Future<void> notifyEntrance({required String eventId}) async {
    await ApiClient.instance.post(
      '/admin/sensors/events/$eventId/notify',
    );
  }

  /// Вызывается из NotificationsService при получении FCM с `kind=sensor_alert`.
  /// Делает тихий повторный запрос событий — UI обновится через подписку
  /// на [eventsStream].
  ///
  /// Не падает на ошибках: пуш — best-effort триггер.
  Future<void> refreshFromPush(Map<String, String> data) async {
    final entranceStr = data['entrance_num'];
    final entrance = entranceStr == null ? null : int.tryParse(entranceStr);
    try {
      await getEvents(entrance: entrance);
    } catch (e) {
      debugPrint('[SensorService] refreshFromPush failed: $e');
    }
  }

  void dispose() {
    _eventsController.close();
  }
}
