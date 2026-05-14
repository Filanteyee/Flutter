# Smart Residency — контекст проекта для Claude Code

## Что это

Мобильное приложение для управления жилым комплексом. Два проекта работают вместе:

- **Flutter**: `D:/AndroidStudioProjects/MyApplication2/Smart_Residency_Flutter`
- **Go backend**: `D:/vsprojects/Smart_Residency_BackEnd`

Физическое устройство разработки: Samsung SM-G973F, device ID `RF8M2089Y0A`.

---

## Стек

**Flutter**
- Flutter/Dart, Material 3
- Dio (`ApiClient`) — HTTP с JWT Bearer interceptor
- Firebase Messaging (FCM) + `flutter_local_notifications`
- `shared_preferences` — хранение pending notification payload при tap из фона
- Singleton-сервисы: `Service._()` + `static final instance`
- `StreamController.broadcast()` для real-time обновлений UI из FCM

**Go Backend**
- Gin (HTTP роутер)
- pgx v5 (PostgreSQL)
- Firebase Admin SDK (отправка FCM)
- Paho MQTT (подключение к HiveMQ — IoT датчики и паркинг)
- JWT авторизация

**Android нативно**
- `SmartResidencyMessagingService.kt` — Kotlin FCM-сервис для foreground уведомлений

---

## Архитектура: FCM push-уведомления

### Каналы уведомлений (v2 — единые для Flutter и Kotlin)
| ID | Назначение |
|---|---|
| `sensor_alerts_v2` | Датчики воды/дыма |
| `barrier_events_v2` | Шлагбаум (неизвестные ТС, гости) |
| `parking_events_v2` | Паркинг (место занято/освобождено) |

### Типы FCM-сообщений (`kind` в data payload)
| kind | Получатель | Канал |
|---|---|---|
| `sensor_alert` | Жители подъезда | sensor_alerts_v2 |
| `unknown_vehicle` | Admins | barrier_events_v2 |
| `guest_arrived` | Конкретный резидент | barrier_events_v2 |
| `parking_alert` | Владелец постоянного места | parking_events_v2 |
| `parking_spot_freed` | Владелец постоянного места | parking_events_v2 |

### Foreground-разделение (Android)
Для `unknown_vehicle`, `parking_alert`, `parking_spot_freed` когда приложение **открыто**:
- Уведомление показывает **Kotlin** `SmartResidencyMessagingService`
- Flutter **пропускает** `_showFromData` для этих kind (метод `_isAndroidNativeForegroundKind`)

Для `sensor_alert`, `guest_arrived`:
- Уведомление показывает **Flutter** `flutter_local_notifications`

**Фоновый хендлер** (`firebaseBackgroundHandler`): если `message.notification != null` → `return` сразу (бэкенд шлёт `notification + data`, Android сам отображает системное уведомление, дубль не нужен).

### Бэкенд шлёт всегда: `notification + data + AndroidConfig (channelID) + APNS`
- `notificationText()` — берёт title/body из data, иначе генерирует fallback
- `channelIDFor(kind)` — маппинг kind → channel_id строкой
- Протухшие токены (`IsUnregistered`) удаляются автоматически из `fcm_tokens`

---

## Архитектура: паркинг

### Mqtt (client.go)
- Топик: `smartresidency/parking/spots/+`
- `event_type` нормализуется через `strings.ToLower`, допустимы только `occupied` / `freed`
- FCM шлётся только если: spot type=`permanent` AND `assigned_user_id` != nil AND `parkingNotifier` != nil
- Data включает `spot_id`, `spot_number`, готовые `title`/`body`

### Flutter parking
- Модели: `ParkingSpot`, `ParkingBooking`, `ParkingEvent` → `lib/models/`
- Сервис: `ParkingService` (singleton) → `lib/services/parking_service.dart`
- Страница: `ParkingPage` → `lib/pages/parking_page.dart`
  - Роль admin → `_AdminParkingPage` (3 вкладки: места, брони, IoT-события)
  - Роль resident → `_ResidentParkingPage` (карточка постоянного места + гостевая сетка + мои брони)
- Карточка на главном экране: `_ParkingStatusCard` в `dashboard_page.dart`
  - Пульсирует красным, если постоянное место жильца занято
  - Для admin: показывает X из Y свободно

### API эндпоинты (паркинг)
```
GET  /api/v1/parking/spots
GET  /api/v1/parking/bookings/my   (не /my-bookings!)
POST /api/v1/parking/bookings
PUT  /api/v1/parking/bookings/:id/cancel
GET  /api/v1/admin/parking/spots
POST /api/v1/admin/parking/spots/:id/assign
GET  /api/v1/admin/parking/bookings
GET  /api/v1/admin/parking/events
```

---

## Архитектура: шлагбаум

`ProcessScanPlate` в `barrier_v2.go` — три ветки:
1. Зарегистрированный автомобиль → `OPEN`, запись `AUTO_RECOGNIZED`
2. Гостевой пропуск по номеру авто → `OPEN`, статус пропуска `used`, FCM резиденту (`guest_arrived`)
3. Неизвестный → `REJECT/PENDING`, FCM всем adminам (`unknown_vehicle`) с логом `sent=%d`

Admin может одобрить/отклонить через `admin_barrier.go`.

MQTT топики:
- `smartresidency/barrier/camera/plate` — номер с камеры
- `smartresidency/barrier/motion` — датчик движения (пока только лог)
- `smartresidency/barrier/command` — команда открытия шлагбаума

---

## Структура Flutter (`lib/`)

```
main.dart               — точка входа, Firebase init, FCM init, AppStateScope
core/
  app_state.dart
  app_state_scope.dart
models/
  barrier_event.dart
  parking_booking.dart  parking_event.dart  parking_spot.dart
  sensor.dart           vehicle.dart
pages/
  dashboard_page.dart   — главная, BottomNav, роль-роутинг
  parking_page.dart     — полная реализация паркинга
  barrier_page.dart     — история шлагбаума (жилец: только история)
  guests_page.dart      — гостевые пропуска
  vehicles_page.dart    — мои автомобили
  sensors_page.dart     admin_sensors_page.dart
  announcements_page.dart  profile_page.dart  login_page.dart
  register_page.dart    register_flow_page.dart
  service_requests_page.dart  services_page.dart
  payments_page.dart    (есть, но вкладка заменена на Паркинг в BottomNav)
services/
  api_client.dart       — Dio singleton, JWT interceptor
  auth_service.dart
  notifications_service.dart  — FCM, local notifications, каналы v2
  parking_service.dart  barrier_service.dart  sensor_service.dart  vehicle_service.dart
utils/
  error_helper.dart     — friendlyError(e) — человекочитаемые ошибки вместо DioException
widgets/
  sensor_widgets.dart   — PulsingAlert и др.
  create_request_sheet.dart
theme/
  app_theme.dart
```

---

## Структура Backend (`internal/`)

```
cmd/server/main.go        — точка входа, роутер, инициализация всего
fcm/sender.go             — отправка FCM (notification+data, channel IDs, pruning токенов)
mqtt/client.go            — MQTT: датчики, шлагбаум, паркинг
handler/
  auth.go                 — register/login/me/refresh
  barrier_v2.go           — ProcessScanPlate, ScanQR, OpenManual, ListEvents
  admin_barrier.go        — ListAll, ListUnknown, ApproveUnknown, RejectUnknown
  parking.go              — паркинг CRUD
  parking_permit.go       — разрешения на паркинг (permit flow)
  vehicles.go             — CRUD автомобилей
  sensors.go              — датчики и события
  guests.go               — гостевые пропуска
  profiles.go  verification.go  service_requests.go  fcm.go  log.go  types.go
middleware/auth.go         — JWT проверка
parking/seed.go           — сид паркинговых мест
sensors/seed.go
migrations/
  001_init.sql  002_sensors.sql  003_verification_address.sql
  004_barrier_vehicles.sql  005_parking.sql  006_parking_permit.sql
```

---

## Роли пользователей

- `admin` — видит всё, управляет верификацией, шлагбаумом, паркингом
- `resident` (approved) — датчики своего подъезда, паркинг, гости, автомобили
- `resident` (не verified) — ограниченный доступ, видит заглушки
- Не залогинен — только публичные разделы

Роль определяется в `dashboard_page.dart` через `GET /auth/me` → поле `role`.

---

## Важные паттерны

**Ошибки (Flutter):** всегда `friendlyError(e)` из `utils/error_helper.dart` вместо сырого DioException.

**Диалоги (Flutter):** при `showDialog` внутри AlertDialog обязательно:
```dart
// Обернуть content в SizedBox(width: double.maxFinite) + SingleChildScrollView
// иначе RenderBox not laid out / RenderIntrinsicWidth ошибка
```

**Singleton сервисы:**
```dart
class MyService {
  MyService._();
  static final MyService instance = MyService._();
}
```

**StreamController:** всегда `.broadcast()` для сервисов, которые слушают несколько виджетов.

**ApiClient:** базовый URL `http://192.168.X.X:8080/api/v1` (локальный IP ПК в сети Wi-Fi).
Телефон и ПК должны быть в одной сети. Порт 8080 должен быть открыт в Windows Firewall.

---

## Нативный Android сервис

`android/app/src/main/kotlin/kz/smartresidency/app/SmartResidencyMessagingService.kt`

- Зарегистрирован в `AndroidManifest.xml` с `MESSAGING_EVENT` intent-filter
- Зависимость в `build.gradle.kts`: `firebase-bom:33.16.0` + `firebase-messaging`
- Срабатывает **только** для `unknown_vehicle`, `parking_alert`, `parking_spot_freed` когда приложение в foreground
- Проверяет `ActivityManager.getMyMemoryState()` для определения foreground

---

## Если нужно добавить новый тип уведомления (kind)

Нужно обновить **4 места**:
1. `internal/fcm/sender.go` → `channelIDFor()` и `notificationText()`
2. `lib/services/notifications_service.dart` → `_isAndroidNativeForegroundKind()`, `_showFromData()`, `_emitInApp()`, `_payloadToMessage()`
3. `SmartResidencyMessagingService.kt` → `isNativeForegroundKind()`, `channelIdFor()`, `fallbackTitle()`, `fallbackBody()`
4. Бэкенд-хендлер — добавить отправку FCM с нужным kind

---

## Firebase

- Project ID: `smart-residency-e3404`
- Package: `kz.smartresidency.app`
- Credentials (backend): путь из `FIREBASE_CREDENTIALS_PATH` env
- Отключены в AndroidManifest: Analytics, Performance, Crashlytics (чтобы не тормозил старт)

---

## Переменные окружения (backend .env)

```
DATABASE_URL=postgres://...
JWT_SECRET=...
FIREBASE_CREDENTIALS_PATH=./firebase-credentials.json
HIVEMQ_URL=ssl://...
HIVEMQ_USERNAME=...
HIVEMQ_PASSWORD=...
HIVEMQ_CLIENT_ID=smartresidency-backend
PORT=8080
```

---

## Что было сделано (хронология)

1. Настройка запуска на физическом Android-устройстве (SM-G973F)
2. Фикс `const ListView` в `barrier_page.dart`
3. Убрали QR-сканер из вида жильца в `barrier_page.dart`
4. Добавили "Мои автомобили" на главный экран
5. Фикс диалога гостевого пропуска (RenderBox / затемнение экрана)
6. `friendlyError()` — человекочитаемые ошибки вместо raw DioException
7. Фикс Windows Firewall (порт 8080)
8. Отключили Firebase Analytics/Performance/Crashlytics (ускорило запуск)
9. Реализован полный функционал **паркинга**: модели, сервис, страница, карточка на главном
10. FCM push-уведомления: разделение foreground Flutter/Kotlin, каналы v2, notification+data payload

---

## Что обсуждали, но НЕ реализовали

- Node-RED: планируемое переделывание flow (motion → camera → backend decides вместо готовых сценариев)
- Parking permit: архитектурная проблема связки `user + vehicle + spot + document` — нужно будет переработать в будущем
- Открытие/закрытие шлагбаума жильцом — решили пока не добавлять
