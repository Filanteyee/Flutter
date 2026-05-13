import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';

import '../models/sensor.dart';
import 'api_client.dart';

/// SSE-события из `GET /admin/sensors/stream`. Бэк шлёт 4 типа фреймов:
/// `sensor_update`, `event_new`, `event_status`, `sensor_offline`.
abstract class SseEvent {
  const SseEvent();
}

/// Смена статуса датчика (NORMAL↔ALERT↔OFFLINE). Heartbeat-сообщения сюда
/// НЕ попадают — бэк фильтрует.
class SsePatchSensor extends SseEvent {
  final String id;
  final SensorStatus status;
  const SsePatchSensor(this.id, this.status);
}

/// Новое событие (NORMAL→ALERT). Поля минимальные — id, sensor_id, type,
/// entrance, floor, status. Подробности при необходимости — через GET.
class SseNewEvent extends SseEvent {
  final SensorEvent event;
  const SseNewEvent(this.event);
}

/// Изменился статус существующего события (через PATCH). Полный
/// SensorEvent со всеми audit-полями.
class SseEventStatusUpdate extends SseEvent {
  final SensorEvent event;
  const SseEventStatusUpdate(this.event);
}

/// Sweeper нашёл датчик без heartbeat > 60с.
class SseSensorOffline extends SseEvent {
  final String id;
  const SseSensorOffline(this.id);
}

/// Long-lived SSE-подключение к `/admin/sensors/stream`. Используется только
/// admin'ом — бэк проверяет роль из токена. Резидент пользуется FCM-пушами
/// и refresh-on-resume.
///
/// Токен передаётся через query, а не Bearer header (EventSource в Dart
/// не умеет custom headers). Бэк-middleware принимает оба варианта.
///
/// Реконнект — экспоненциальный backoff 2/5/10/30 сек, останавливается
/// при явном `disconnect()`.
class SseService {
  SseService._();
  static final SseService instance = SseService._();

  final _controller = StreamController<SseEvent>.broadcast();
  Stream<SseEvent> get events => _controller.stream;

  StreamSubscription<SSEModel>? _sub;
  Timer? _reconnectTimer;
  bool _wantConnected = false;
  int _reconnectAttempt = 0;

  bool get isConnected => _sub != null && _wantConnected;

  /// Подключается к admin-стриму. Идемпотентно — повторный вызов в активном
  /// состоянии ничего не делает.
  void connect() {
    if (_wantConnected) return;
    _wantConnected = true;
    _open();
  }

  /// Останавливает стрим и отменяет любые pending-реконнекты.
  void disconnect() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      SSEClient.unsubscribeFromSSE();
    } catch (_) {}
    debugPrint('[SSE] disconnected');
  }

  void _open() {
    final token = ApiClient.instance.token;
    if (token == null) {
      debugPrint('[SSE] no token, skip connect');
      _wantConnected = false;
      return;
    }
    final url =
        '${ApiClient.baseHost}/api/v1/admin/sensors/stream?token=$token';
    debugPrint('[SSE] connecting → $url');

    _sub?.cancel();
    _sub = SSEClient.subscribeToSSE(
      method: SSERequestType.GET,
      url: url,
      header: const {},
    ).listen(
      _onFrame,
      onError: (Object e, StackTrace st) {
        debugPrint('[SSE] error: $e');
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint('[SSE] stream done');
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
  }

  void _onFrame(SSEModel frame) {
    // :ping / :connected — keepalive без event/data.
    final eventName = frame.event;
    final raw = frame.data;
    if (eventName == null || raw == null || raw.isEmpty) {
      return;
    }
    // Удачно открыли — сбрасываем backoff.
    _reconnectAttempt = 0;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[SSE] bad json for $eventName: $e');
      return;
    }

    try {
      switch (eventName) {
        case 'sensor_update':
          _emit(SsePatchSensor(
            data['id'].toString(),
            _parseStatus(data['status']?.toString() ?? 'NORMAL'),
          ));
          break;
        case 'sensor_offline':
          _emit(SseSensorOffline(data['id'].toString()));
          break;
        case 'event_new':
          _emit(SseNewEvent(_eventFromPartial(data)));
          break;
        case 'event_status':
          _emit(SseEventStatusUpdate(SensorEvent.fromJson(data)));
          break;
        default:
          debugPrint('[SSE] unknown event: $eventName');
      }
    } catch (e) {
      debugPrint('[SSE] parse failed for $eventName: $e, raw=$raw');
    }
  }

  void _emit(SseEvent e) {
    debugPrint('[SSE] ${e.runtimeType}');
    _controller.add(e);
  }

  void _scheduleReconnect() {
    _sub?.cancel();
    _sub = null;
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    final delays = [2, 5, 10, 30];
    final delay = delays[_reconnectAttempt.clamp(0, delays.length - 1)];
    _reconnectAttempt++;
    debugPrint('[SSE] reconnect in ${delay}s (attempt $_reconnectAttempt)');
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (_wantConnected) _open();
    });
  }

  /// SSE event_new приходит без `created_at` — подставляем текущее время.
  SensorEvent _eventFromPartial(Map<String, dynamic> data) {
    return SensorEvent(
      id: data['id'].toString(),
      sensorId: data['sensor_id'].toString(),
      type: (data['type']?.toString().toUpperCase() ?? 'WATER') == 'SMOKE'
          ? SensorType.smoke
          : SensorType.water,
      entranceNum: (data['entrance_num'] as num?)?.toInt() ?? 0,
      floor: (data['floor'] as num?)?.toInt() ?? 0,
      status: _parseEventStatus(data['status']?.toString() ?? 'DETECTED'),
      createdAt: DateTime.now(),
    );
  }

  static SensorStatus _parseStatus(String s) {
    switch (s.toUpperCase()) {
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

  static EventStatus _parseEventStatus(String s) {
    switch (s.toUpperCase()) {
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
}
