import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'notifications_service.dart';
import 'sensor_service.dart';
import 'sse_service.dart';

class AppUser {
  final String id;
  final String email;

  const AppUser({required this.id, required this.email});
}

class ResidentAddress {
  final int entrance;
  final int floor;
  final int apartment;

  const ResidentAddress({
    required this.entrance,
    required this.floor,
    required this.apartment,
  });
}

class AuthService {
  final ApiClient _api = ApiClient.instance;
  final _controller = StreamController<AppUser?>.broadcast();

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  Stream<AppUser?> get authStateChanges => _controller.stream;

  AuthService() {
    _init();
  }

  /// Обновляет JWT, подтягивая актуальную роль из БД.
  /// Вызывать при возврате приложения на экран.
  Future<void> refreshToken() async {
    if (!_api.isLoggedIn) return;
    try {
      final res = await _api.post('/auth/refresh');
      final newToken = res.data['token'] as String;
      final newRole = (res.data['role'] as String?) ?? 'resident';
      await _api.saveSession(
        token: newToken,
        userId: _api.userId!,
        role: newRole,
      );
    } catch (_) {}
  }

  Future<void> _init() async {
    if (!_api.isLoggedIn) {
      _controller.add(null);
      return;
    }

    try {
      final profile = await getCurrentUserProfile();
      if (profile != null) {
        // Обновляем JWT чтобы подтянуть актуальную роль из БД
        try {
          final refreshRes = await _api.post('/auth/refresh');
          final newToken = refreshRes.data['token'] as String;
          final newRole = (refreshRes.data['role'] as String?) ?? 'resident';
          await _api.saveSession(
            token: newToken,
            userId: _api.userId!,
            role: newRole,
          );
        } catch (_) {
          // Если refresh не удался — продолжаем с текущим токеном
        }

        _currentUser = AppUser(
          id: _api.userId!,
          email: (profile['email'] ?? '').toString(),
        );
        _controller.add(_currentUser);
        return;
      }
    } catch (_) {}

    // Токен невалиден — выходим
    await _api.clearSession();
    _controller.add(null);
  }

  Future<String?> registerResident({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required String iin,
    required String personType,
    required String city,
    required String street,
    required String propertyType,
    required String propertyNumber,
    required String fullAddress,
  }) async {
    try {
      final res = await _api.post('/auth/register', data: {
        'email': email.trim(),
        'password': password.trim(),
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'iin': iin.trim(),
        'person_type': personType,
        'city': city,
        'street': street,
        'property_type': propertyType,
        'property_number': propertyNumber,
        'full_address': fullAddress.trim(),
      });

      final token = res.data['token'] as String;
      final userId = res.data['user_id'] as String;
      await _api.saveSession(token: token, userId: userId, role: 'resident');

      _currentUser = AppUser(id: userId, email: email.trim());
      _controller.add(_currentUser);
      // Регистрируем FCM-токен на новом аккаунте, чтобы бэк начал слать пуши.
      unawaited(NotificationsService.instance.syncTokenWithBackend());
      return null;
    } on DioException catch (e) {
      final msg = e.response?.data?['error']?.toString() ?? '';
      if (msg.contains('already registered') || e.response?.statusCode == 409) {
        return 'Этот email уже используется';
      }
      return msg.isNotEmpty ? msg : 'Ошибка регистрации';
    } catch (e) {
      return 'Неизвестная ошибка: $e';
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _api.post('/auth/login', data: {
        'email': email.trim(),
        'password': password.trim(),
      });

      final token = res.data['token'] as String;
      final userId = res.data['user_id'] as String;
      final role = res.data['role'] as String? ?? 'resident';
      await _api.saveSession(token: token, userId: userId, role: role);

      _currentUser = AppUser(id: userId, email: email.trim());
      _controller.add(_currentUser);
      unawaited(NotificationsService.instance.syncTokenWithBackend());
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return 'Неверный email или пароль';
      }
      return e.response?.data?['error']?.toString() ?? 'Ошибка входа';
    } catch (e) {
      return 'Неизвестная ошибка: $e';
    }
  }

  Future<void> signOut() async {
    // Сначала снимаем FCM-токен с этого аккаунта на бэке, пока JWT ещё
    // валиден — иначе бэк продолжит слать пуши на старый токен.
    await NotificationsService.instance.deleteTokenOnBackend();
    // Закрываем admin SSE-стрим, чтобы не таскал старый токен по фоновому
    // backoff'у уже после logout.
    SseService.instance.disconnect();
    SensorService.instance.detachSse();
    await _api.clearSession();
    _currentUser = null;
    _controller.add(null);
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      final res = await _api.get('/auth/me');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (_) {
      return null;
    }
  }

  /// Возвращает адрес жильца внутри ЖК (подъезд/этаж/квартира).
  ///
  /// Источник — `GET /auth/me`. Бэк после approve верификации копирует
  /// `entrance/floor/apartment` из `verification_requests` в `profiles`,
  /// и отсюда они приходят в `/auth/me`. Поля парсятся устойчиво — `int`,
  /// `String` или `null` все обрабатываются.
  Future<ResidentAddress?> getResidentAddress() async {
    try {
      final res = await _api.get('/auth/me');
      final data = res.data as Map;
      final entrance = _parseInt(data['entrance']);
      final floor = _parseInt(data['floor']);
      final apartment = _parseInt(data['apartment']);
      debugPrint(
          '[Auth] /auth/me address: entrance=${data['entrance']} '
          'floor=${data['floor']} apartment=${data['apartment']}');
      if (entrance != null && floor != null) {
        return ResidentAddress(
          entrance: entrance,
          floor: floor,
          apartment: apartment ?? 0,
        );
      }
    } catch (e) {
      debugPrint('[Auth] /auth/me failed: $e');
    }
    return null;
  }

  static int? _parseInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return int.tryParse(trimmed);
    }
    return null;
  }

  Future<String?> submitVerificationRequest({
    required String requestedRole,
    required List<PlatformFile> documents,
    required int entrance,
    required int floor,
    required int apartment,
    String? comment,
  }) async {
    if (documents.isEmpty) return 'Прикрепите хотя бы один документ';

    try {
      final res = await _api.post('/verification/requests', data: {
        'requested_role': requestedRole,
        'comment': comment?.trim() ?? '',
        'entrance': entrance,
        'floor': floor,
        'apartment': apartment,
      });

      final verId = res.data['id'] as String;

      final formData = FormData();
      for (final doc in documents) {
        if (doc.path == null) continue;
        formData.files.add(MapEntry(
          'documents',
          await MultipartFile.fromFile(doc.path!, filename: doc.name),
        ));
      }

      await _api.postForm('/verification/requests/$verId/documents', formData);

      return null;
    } on DioException catch (e) {
      return e.response?.data?['error']?.toString() ?? 'Ошибка отправки документов';
    } catch (e) {
      return 'Ошибка отправки документов: $e';
    }
  }

  void dispose() {
    _controller.close();
  }
}
