import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sensor.dart';
import 'api_client.dart';
import 'sse_service.dart';

/// Сервис общедомовых датчиков. Все запросы — через [ApiClient] (JWT-интерсептор
/// уже подставлен). Бэкенд: `http://10.0.2.2:8080/api/v1` для Android-эмулятора.
///
/// FCM-пуш с `kind=sensor_alert` дёргает [refreshFromPush]: сервис тихо
/// перезапрашивает свежий список событий и пушит в [eventsStream], на который
/// подписаны экраны.
///
/// Если подключен [SseService.connect], сервис принимает live-обновления
/// статусов датчиков и событий, и сам перепушивает изменения в стримы —
/// UI перерисовывается без свайпа.
class SensorService {
  SensorService._internal();
  static final SensorService instance = SensorService._internal();

  final _eventsController =
      StreamController<List<SensorEvent>>.broadcast();
  final _sensorsController = StreamController<List<Sensor>>.broadcast();

  /// Локальный кеш сенсоров — обновляется SSE и `getAllSensors`.
  List<Sensor> _sensors = const [];
  List<SensorEvent> _events = const [];
  StreamSubscription<SseEvent>? _sseSub;

  /// Поток последних загруженных событий. Эмиттится после каждого `getEvents`
  /// и после `refreshFromPush`. UI подписывается, чтобы перерисовываться без
  /// ручного `setState` по таймеру.
  Stream<List<SensorEvent>> get eventsStream => _eventsController.stream;

  /// Поток актуального состояния датчиков. Обновляется SSE-фреймами
  /// `sensor_update` / `sensor_offline` и REST-методами get*.
  Stream<List<Sensor>> get sensorsStream => _sensorsController.stream;

  List<Sensor> get sensorsSnapshot => _sensors;
  List<SensorEvent> get eventsSnapshot => _events;

  /// Привязывает SSE-стрим к сервису: бэк присылает обновления, мы патчим
  /// локальный кеш и перепушиваем в `sensorsStream` / `eventsStream`.
  void attachSse(SseService sse) {
    _sseSub?.cancel();
    _sseSub = sse.events.listen(_onSseEvent);
  }

  void detachSse() {
    _sseSub?.cancel();
    _sseSub = null;
  }

  void _onSseEvent(SseEvent e) {
    if (e is SsePatchSensor) {
      _patchSensorStatus(e.id, e.status);
    } else if (e is SseSensorOffline) {
      _patchSensorStatus(e.id, SensorStatus.offline);
    } else if (e is SseNewEvent) {
      _events = [e.event, ..._events.where((x) => x.id != e.event.id)]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _eventsController.add(_events);
    } else if (e is SseEventStatusUpdate) {
      _events = _events
          .map((x) => x.id == e.event.id ? e.event : x)
          .toList();
      _eventsController.add(_events);
    }
  }

  void _patchSensorStatus(String id, SensorStatus status) {
    var changed = false;
    _sensors = _sensors.map((s) {
      if (s.id != id) return s;
      if (s.status == status) return s;
      changed = true;
      return s.copyWith(status: status, lastUpdated: DateTime.now());
    }).toList();
    if (changed) _sensorsController.add(_sensors);
  }

  /// GET /api/v1/sensors?entrance={entrance}
  Future<List<Sensor>> getSensors({required int entrance}) async {
    final res = await ApiClient.instance.get(
      '/sensors',
      params: {'entrance': entrance},
    );
    final list = (res.data as List)
        .map((e) => Sensor.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _mergeSensors(list);
    return list;
  }

  /// GET /api/v1/admin/sensors
  Future<List<Sensor>> getAllSensors() async {
    final res = await ApiClient.instance.get('/admin/sensors');
    final list = (res.data as List)
        .map((e) => Sensor.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _sensors = list;
    _sensorsController.add(_sensors);
    return list;
  }

  /// Подмешивает свежие сенсоры из REST в локальный кеш, не выбрасывая
  /// данные о датчиках из других подъездов (полезно для резидента, который
  /// видит только свой entrance).
  void _mergeSensors(List<Sensor> fresh) {
    final byId = {for (final s in _sensors) s.id: s};
    for (final s in fresh) {
      byId[s.id] = s;
    }
    _sensors = byId.values.toList();
    _sensorsController.add(_sensors);
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
    _events = list;
    _eventsController.add(list);
    return list;
  }

  /// GET /api/v1/sensors/events/{id} — событие + датчик + таймлайн переходов.
  /// Резидент получает 403 если event.entrance_num не совпадает с его подъездом.
  Future<SensorEventDetail> getEventDetail(String eventId) async {
    final res = await ApiClient.instance.get('/sensors/events/$eventId');
    return SensorEventDetail.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

  /// POST /api/v1/admin/sensors/{id}/reset — публикует NORMAL в MQTT-топик
  /// датчика. После echo через subscriber придёт SSE sensor_update.
  Future<void> resetSensor(String sensorId) async {
    await ApiClient.instance.post('/admin/sensors/$sensorId/reset');
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

  /// GET /api/v1/admin/sensors/stats?period=today|week
  Future<SensorStats> getStats({String period = 'today'}) async {
    final res = await ApiClient.instance.get(
      '/admin/sensors/stats',
      params: {'period': period},
    );
    return SensorStats.fromJson(
      Map<String, dynamic>.from(res.data as Map),
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
    _sseSub?.cancel();
    _eventsController.close();
    _sensorsController.close();
  }
}
