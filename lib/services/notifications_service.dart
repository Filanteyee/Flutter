import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api_client.dart';
import 'sensor_service.dart';

/// Ключ в SharedPreferences для payload-а, по которому пользователь
/// открыл локальный баннер пока main-изолят был не активен.
const _kPendingTapPrefsKey = 'pending_notification_event_id';

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
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // В фоне у нас новый изолят — нужно поднять Firebase заново.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[FCM-bg] got message: ${message.data}');
  // FlutterLocalNotificationsPlugin тоже надо проинициализировать в новом
  // изоляте — main-изолят сюда не дотягивается. Без этого `show()` тихо
  // ничего не делает, и пользователь не видит баннер.
  await NotificationsService._ensureLocalNotificationsInited();
  // Бэк шлёт data-only сообщения, поэтому Android системный баннер сам
  // не нарисует — рисуем руками через flutter_local_notifications.
  await NotificationsService._showFromData(message.data);
}

class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  static const _channelId = 'sensor_alerts';
  static const _channelName = 'Тревоги датчиков';
  static const _channelDescription =
      'Push-уведомления о срабатывании датчиков воды и дыма';

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  final _eventController = StreamController<Map<String, String>>.broadcast();

  /// Поток FCM-пэйлоадов, по которым UI должен перезапросить события.
  /// Каждый элемент — `data` из `RemoteMessage` (всё в строках).
  Stream<Map<String, String>> get sensorAlerts => _eventController.stream;

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
      ),
      onDidReceiveNotificationResponse: (response) {
        // Тап по локальной нотификации в foreground.
        // payload содержит event_id, чтобы UI мог подсветить событие.
        final payload = response.payload;
        debugPrint('[FCM] local tap (fg): event_id=$payload');
        if (payload != null && payload.isNotEmpty) {
          _pendingOpenedMessage = {
            'kind': 'sensor_alert',
            'event_id': payload,
          };
        }
      },
      onDidReceiveBackgroundNotificationResponse: _onLocalNotificationBgTap,
    );

    // Если пока main-изолят не был активен, фоновый колбэк успел положить
    // payload в SharedPreferences — подхватываем и кладём в pending.
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingTap = prefs.getString(_kPendingTapPrefsKey);
      if (pendingTap != null && pendingTap.isNotEmpty) {
        debugPrint('[FCM] resumed from bg local tap: event_id=$pendingTap');
        _pendingOpenedMessage = {
          'kind': 'sensor_alert',
          'event_id': pendingTap,
        };
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

    // 2) Permission на Android 13+ / iOS.
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      '[FCM] permission: ${settings.authorizationStatus}',
    );

    // 3) Background handler регистрируется один раз на процесс.
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // 4) Foreground listener.
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
      final data = _stringMap(msg.data);
      debugPrint('[FCM] onMessage: $data');
      await _showFromData(data);
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
  }

  static Future<void> _showFromData(Map<String, dynamic> raw) async {
    final data = _stringMap(raw);
    if (data['kind'] != 'sensor_alert') return;
    final title = data['title'] ?? 'Тревога';
    final body = data['body'] ?? '';
    final eventId = data['event_id'] ?? '';

    // ID нотификации — стабильный hash event_id. Если для одного события
    // придёт несколько обновлений, новая заменит старую.
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
        ),
      ),
      payload: eventId,
    );
  }

  void _emitIfSensorAlert(Map<String, String> data) {
    if (data['kind'] != 'sensor_alert') return;
    _eventController.add(data);
    SensorService.instance.refreshFromPush(data);
  }

  static Map<String, String> _stringMap(Map<String, dynamic> raw) {
    return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }
}
