import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api_client.dart';
import 'barrier_service.dart';
import 'parking_service.dart';
import 'sensor_service.dart';

/// Ключ в SharedPreferences для payload-а, по которому пользователь
/// открыл локальный баннер пока main-изолят был не активен.
const _kPendingTapPrefsKey = 'pending_notification_event_id';

const _kHistoryPrefsKey = 'notifications_history';
const _kMaxHistory = 50;

/// Запись истории пуш-уведомлений. Хранится в SharedPreferences как JSON.
class NotificationHistoryItem {
  final String eventId;
  final String title;
  final String body;
  final String threatType;
  final DateTime receivedAt;

  const NotificationHistoryItem({
    required this.eventId,
    required this.title,
    required this.body,
    required this.threatType,
    required this.receivedAt,
  });

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'title': title,
        'body': body,
        'threat_type': threatType,
        'received_at': receivedAt.toIso8601String(),
      };

  factory NotificationHistoryItem.fromJson(Map<String, dynamic> json) =>
      NotificationHistoryItem(
        eventId: json['event_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        threatType: json['threat_type']?.toString() ?? '',
        receivedAt: DateTime.tryParse(
                json['received_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Top-level колбэк тапа по local-notification из фонового изолята.
/// Должен быть top-level + `@pragma('vm:entry-point')`, иначе AOT-компилятор
/// его выкинет и `flutter_local_notifications` не найдёт.
///
/// Тап по локальной нотификации, отрисованной из фонового изолята, не
/// перехватывается обычным `onDidReceiveNotificationResponse` (тот живёт
/// в main-изоляте). Поэтому payload сохраняем в SharedPreferences, а
/// `NotificationsService.init` при следующем старте main-изолята читает и
/// заполняет `_pendingOpenedMessage`.
@pragma('vm:entry-point')
void _onLocalNotificationBgTap(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingTapPrefsKey, payload);
    debugPrint('[FCM-bg-tap] saved pending event_id=$payload');
  } catch (e) {
    debugPrint('[FCM-bg-tap] failed to persist: $e');
  }
}

/// Топ-левел хендлер фоновых сообщений. Должен быть top-level и помечен
/// `@pragma('vm:entry-point')`, иначе AOT-компилятор его выкинет и Flutter
/// Engine не сможет вызвать его в отдельном изоляте.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  debugPrint('[FCM-bg] got message: ${message.data}');
  if (message.notification != null) {
    return;
  }
  await NotificationsService._ensureLocalNotificationsInited();
  await NotificationsService._showFromData(message.data);
}

class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  static const _channelId = 'sensor_alerts_v2';
  static const _channelName = 'Тревоги датчиков';
  static const _channelDescription =
      'Push-уведомления о срабатывании датчиков воды и дыма';

  static const _barrierChannelId = 'barrier_events_v2';
  static const _barrierChannelName = 'Шлагбаум';
  static const _barrierChannelDescription = 'Уведомления о въезде гостей и неизвестных ТС';

  static const _parkingChannelId = 'parking_events_v2';
  static const _parkingChannelName = 'Парковка';
  static const _parkingChannelDescription =
      'Уведомления о парковочных местах';

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  final _eventController = StreamController<Map<String, String>>.broadcast();
  final _inAppController = StreamController<({String title, String body})>.broadcast();

  /// Поток FCM-пэйлоадов, по которым UI должен перезапросить события.
  Stream<Map<String, String>> get sensorAlerts => _eventController.stream;

  /// Поток для показа уведомлений внутри открытого приложения.
  Stream<({String title, String body})> get inAppNotifications => _inAppController.stream;

  /// Тап по пушу — данные сообщения, по которому пользователь открыл приложение.
  /// Нужен для навигации в нужный экран после холодного запуска / из бэкграунда.
  Map<String, String>? _pendingOpenedMessage;
  Map<String, String>? consumePendingOpenedMessage() {
    final m = _pendingOpenedMessage;
    _pendingOpenedMessage = null;
    return m;
  }

  bool _initialized = false;
  String? _cachedToken;

  /// Инициализация. Безопасно вызывать повторно — повторные вызовы no-op.
  /// Вызывается из `main()` ДО `runApp` после `Firebase.initializeApp`.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1) Локальный канал нотификаций (Android 8+ требует канал).
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        debugPrint('[FCM] local tap (fg): payload=$payload');
        if (payload == null || payload.isEmpty) return;
        _pendingOpenedMessage = _payloadToMessage(payload);
      },
      onDidReceiveBackgroundNotificationResponse: _onLocalNotificationBgTap,
    );

    // Если пока main-изолят не был активен, фоновый колбэк успел положить
    // payload в SharedPreferences — подхватываем и кладём в pending.
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingTap = prefs.getString(_kPendingTapPrefsKey);
      if (pendingTap != null && pendingTap.isNotEmpty) {
        debugPrint('[FCM] resumed from bg local tap: payload=$pendingTap');
        _pendingOpenedMessage = _payloadToMessage(pendingTap);
        await prefs.remove(_kPendingTapPrefsKey);
      }
    } catch (e) {
      debugPrint('[FCM] read pending bg tap failed: $e');
    }

    final androidImpl = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _barrierChannelId,
        _barrierChannelName,
        description: _barrierChannelDescription,
        importance: Importance.high,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _parkingChannelId,
        _parkingChannelName,
        description: _parkingChannelDescription,
        importance: Importance.high,
      ),
    );

    // 2) Permission для flutter_local_notifications на Android 13+
    await androidImpl?.requestNotificationsPermission();

    // 3) Permission на Android 13+ / iOS.
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      '[FCM] permission: ${settings.authorizationStatus}',
    );

    // 3) Foreground listener.
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
      final data = _stringMap(msg.data);
      debugPrint('[FCM] onMessage: $data');
      if (!_isAndroidNativeForegroundKind(data['kind'])) {
        await _showFromData(data);
      }
      _emitIfSensorAlert(data);
    });

    // 5) Тап по пушу из бэкграунда.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      final data = _stringMap(msg.data);
      debugPrint('[FCM] onMessageOpenedApp: $data');
      _pendingOpenedMessage = data;
      _emitIfSensorAlert(data);
    });

    // 6) Холодный запуск через тап по пушу — сообщение, доставленное
    // пока приложение было полностью закрыто.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      final data = _stringMap(initial.data);
      debugPrint('[FCM] initialMessage: $data');
      _pendingOpenedMessage = data;
    }

    // 7) Получаем токен и пытаемся синхронизировать с бэком, если уже залогинены.
    try {
      _cachedToken = await messaging.getToken();
      debugPrint('[FCM] token: $_cachedToken');
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
    }

    // Авто-синхронизация при ротации токена.
    messaging.onTokenRefresh.listen((token) async {
      debugPrint('[FCM] onTokenRefresh: $token');
      _cachedToken = token;
      await syncTokenWithBackend();
    });

    // Если JWT уже есть на старте (повторный заход) — сразу синхронизируем.
    if (ApiClient.instance.isLoggedIn) {
      await syncTokenWithBackend();
    }
  }

  /// Отправляет текущий FCM-токен на бэк (`POST /users/me/fcm-token`).
  /// Вызывать после успешного логина и после регистрации.
  ///
  /// Возвращает `true` при HTTP 200/204 (бэк сохранил/обновил запись).
  Future<bool> syncTokenWithBackend() async {
    final token = _cachedToken ?? await FirebaseMessaging.instance.getToken();
    if (token == null) {
      debugPrint('[FCM] sync skipped: token is null');
      return false;
    }
    _cachedToken = token;
    if (!ApiClient.instance.isLoggedIn) {
      debugPrint('[FCM] sync skipped: not logged in');
      return false;
    }
    try {
      final res = await ApiClient.instance.post(
        '/users/me/fcm-token',
        data: {
          'token': token,
          'platform': _platformName(),
        },
      );
      debugPrint('[FCM] /users/me/fcm-token → ${res.statusCode}');
      return res.statusCode != null &&
          res.statusCode! >= 200 &&
          res.statusCode! < 300;
    } on DioException catch (e) {
      debugPrint('[FCM] sync failed: ${e.response?.statusCode} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[FCM] sync failed: $e');
      return false;
    }
  }

  /// На signOut вызывается ДО `clearSession()`, чтобы бэк не слал пуши на
  /// чужой аккаунт. Эндпоинт реализован и идемпотентен (200), поэтому
  /// здесь логируются только реальные сетевые ошибки.
  Future<void> deleteTokenOnBackend() async {
    final token = _cachedToken;
    if (token == null) return;
    if (!ApiClient.instance.isLoggedIn) return;
    try {
      final res = await ApiClient.instance.post(
        '/users/me/fcm-token/delete',
        data: {'token': token},
      );
      debugPrint('[FCM] /users/me/fcm-token/delete → ${res.statusCode}');
    } on DioException catch (e) {
      debugPrint(
          '[FCM] deleteToken network error: ${e.response?.statusCode} ${e.message}');
    }
  }

  // -------- private --------

  /// Идемпотентная инициализация локального плагина нотификаций для текущего
  /// изолята. Нужна и в фоновом изоляте (см. `_firebaseBackgroundHandler`).
  static bool _localInited = false;
  static Future<void> _ensureLocalNotificationsInited() async {
    if (_localInited) return;
    _localInited = true;
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    final androidImpl = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _barrierChannelId,
        _barrierChannelName,
        description: _barrierChannelDescription,
        importance: Importance.high,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _parkingChannelId,
        _parkingChannelName,
        description: _parkingChannelDescription,
        importance: Importance.high,
      ),
    );
  }

  static Future<void> _showFromData(Map<String, dynamic> raw) async {
    final data = _stringMap(raw);
    final kind = data['kind'] ?? '';

    if (kind == 'sensor_alert') {
      final title = data['title'] ?? 'Тревога';
      final body = data['body'] ?? '';
      final eventId = data['event_id'] ?? '';
      final notifId = eventId.hashCode & 0x7fffffff;
      await _local.show(
        notifId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
            ticker: 'Sensor alert',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: eventId,
      );

      await _saveToHistory(data);
      return;
    }

    if (kind == 'unknown_vehicle') {
      final plate = data['plate_number'] ?? '';
      final eventId = data['event_id'] ?? '';
      final title = data['title'] ?? 'Неизвестный автомобиль';
      final body = data['body'] ??
          (plate.isNotEmpty ? 'Номер: $plate — требуется решение' : 'Требуется решение');
      final notifId = eventId.hashCode & 0x7fffffff;
      await _local.show(
        notifId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _barrierChannelId,
            _barrierChannelName,
            channelDescription: _barrierChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
            ticker: 'Unknown vehicle',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'unknown_vehicle:$eventId',
      );
      return;
    }

    if (kind == 'guest_arrived') {
      final guestName = data['guest_name'] ?? 'Гость';
      final title = data['title'] ?? 'Гость въехал';
      final body = data['body'] ?? '$guestName прибыл на территорию ЖК';
      final notifId = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
      await _local.show(
        notifId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _barrierChannelId,
            _barrierChannelName,
            channelDescription: _barrierChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'guest_arrived:',
      );
      return;
    }

    if (kind == 'parking_alert') {
      final spotNumber = data['spot_number'] ?? '';
      final spotId = data['spot_id'] ?? '';
      final title = data['title'] ?? 'Тревога парковки';
      final body = data['body'] ??
          (spotNumber.isNotEmpty
              ? 'Место №$spotNumber занято'
              : 'Парковочное место занято');
      final notifId = spotId.isNotEmpty
          ? spotId.hashCode & 0x7fffffff
          : DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
      await _local.show(
        notifId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _parkingChannelId,
            _parkingChannelName,
            channelDescription: _parkingChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
            ticker: 'Parking alert',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'parking_alert:$spotId',
      );
      return;
    }

    if (kind == 'parking_spot_freed') {
      final spotNumber = data['spot_number'] ?? '';
      final spotId = data['spot_id'] ?? '';
      final title = data['title'] ?? 'Место освобождено';
      final body = data['body'] ??
          (spotNumber.isNotEmpty
              ? 'Парковочное место №$spotNumber свободно'
              : 'Парковочное место свободно');
      final notifId = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
      await _local.show(
        notifId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _parkingChannelId,
            _parkingChannelName,
            channelDescription: _parkingChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'parking_spot_freed:$spotId',
      );
      return;
    }

    if (kind == 'sensor_offline') {
      final title = data['title'] ?? 'Датчик не на связи';
      final body = data['body'] ?? 'Датчик не отвечает';
      final sensorId = data['sensor_id'] ?? '';
      final notifId = sensorId.isNotEmpty
          ? sensorId.hashCode & 0x7fffffff
          : DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
      await _local.show(
        notifId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'sensor_offline:$sensorId',
      );
      return;
    }

    if (kind == 'parking_no_permit') {
      final plate = data['plate_number'] ?? '';
      final eventId = data['event_id'] ?? '';
      final title = data['title'] ?? '🚫 Нет доступа в паркинг';
      final body = data['body'] ??
          (plate.isNotEmpty
              ? 'Автомобиль $plate не имеет пропуска на паркинг'
              : 'Нет пропуска на паркинг');
      final notifId = eventId.isNotEmpty
          ? eventId.hashCode & 0x7fffffff
          : DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
      await _local.show(
        notifId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _parkingChannelId,
            _parkingChannelName,
            channelDescription: _parkingChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'parking_no_permit:$eventId',
      );
      return;
    }
  }

  static Future<void> _saveToHistory(Map<String, String> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kHistoryPrefsKey) ?? [];
      final item = NotificationHistoryItem(
        eventId: data['event_id'] ?? '',
        title: data['title'] ?? 'Тревога',
        body: data['body'] ?? '',
        threatType: data['threat_type'] ?? '',
        receivedAt: DateTime.now(),
      );
      raw.insert(0, jsonEncode(item.toJson()));
      if (raw.length > _kMaxHistory) {
        raw.removeRange(_kMaxHistory, raw.length);
      }
      await prefs.setStringList(_kHistoryPrefsKey, raw);
    } catch (e) {
      debugPrint('[FCM] saveToHistory failed: $e');
    }
  }

  Future<List<NotificationHistoryItem>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kHistoryPrefsKey) ?? [];
      return raw
          .map((s) {
            try {
              return NotificationHistoryItem.fromJson(
                Map<String, dynamic>.from(jsonDecode(s) as Map),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<NotificationHistoryItem>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _emitIfSensorAlert(Map<String, String> data) {
    final kind = data['kind'] ?? '';
    if (kind == 'sensor_alert') {
      _eventController.add(data);
      SensorService.instance.refreshFromPush(data);
    } else if (kind == 'sensor_offline') {
      SensorService.instance.refreshFromPush(data);
    } else if (kind == 'unknown_vehicle') {
      BarrierService.instance.refreshFromPush(data);
    } else if (kind == 'parking_alert' || kind == 'parking_spot_freed') {
      ParkingService.instance.refreshFromPush(data);
    }
    // guest_arrived: only a local notification banner, no stream update needed
    _emitInApp(data);
  }

  void _emitInApp(Map<String, String> data) {
    final kind = data['kind'] ?? '';
    debugPrint('[FCM] _emitInApp called, kind=$kind');
    // sensor_alert / sensor_offline показываются через push (_showFromData),
    // нижний баннер для них не нужен.
    String title, body;
    switch (kind) {
      case 'unknown_vehicle':
        title = data['title'] ?? 'Неизвестный автомобиль';
        body = data['body'] ?? 'Номер: ${data['plate_number'] ?? '—'} — требует решения';
      case 'guest_arrived':
        title = data['title'] ?? 'Гость въехал';
        body = data['body'] ?? '${data['guest_name'] ?? 'Гость'} прибыл на территорию ЖК';
      case 'parking_alert':
        title = data['title'] ?? 'Тревога парковки';
        body = data['body'] ?? 'Место №${data['spot_number'] ?? ''} занято';
      case 'parking_spot_freed':
        title = data['title'] ?? 'Место освобождено';
        body = data['body'] ?? 'Парковочное место №${data['spot_number'] ?? ''} свободно';
      default:
        debugPrint('[FCM] _emitInApp: unknown kind=$kind, skipping');
        return;
    }
    debugPrint('[FCM] _emitInApp: emitting title=$title');
    _inAppController.add((title: title, body: body));
  }

  // Decodes a local notification payload string back to a data map.
  // Format: "<kind>:<extra>" e.g. "sensor_alert:evt-42", "unknown_vehicle:uuid", "guest_arrived:"
  static Map<String, String> _payloadToMessage(String payload) {
    final idx = payload.indexOf(':');
    if (idx == -1) return {'kind': 'sensor_alert', 'event_id': payload};
    final kind = payload.substring(0, idx);
    final extra = payload.substring(idx + 1);
    if (kind == 'unknown_vehicle') {
      return {'kind': 'unknown_vehicle', 'event_id': extra};
    }
    if (kind == 'guest_arrived') {
      return {'kind': 'guest_arrived'};
    }
    if (kind == 'parking_alert') {
      return {'kind': 'parking_alert', 'spot_id': extra};
    }
    if (kind == 'parking_spot_freed') {
      return {'kind': 'parking_spot_freed', 'spot_id': extra};
    }
    return {'kind': 'sensor_alert', 'event_id': payload};
  }

  static Map<String, String> _stringMap(Map<String, dynamic> raw) {
    return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  }

  static bool _isAndroidNativeForegroundKind(String? kind) {
    if (!Platform.isAndroid) return false;
    return kind == 'unknown_vehicle' ||
        kind == 'guest_arrived' ||
        kind == 'parking_alert' ||
        kind == 'parking_spot_freed';
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }
}
