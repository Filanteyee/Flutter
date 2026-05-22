import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const _host = String.fromEnvironment('SERVER_HOST', defaultValue: '192.168.1.64');

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8080/api/v1';
    return 'http://$_host:8080/api/v1';
  }

  /// Хост сервера без префикса `/api/v1` — нужен, например, для статики
  /// (`/uploads/...`), которую сервер раздаёт вне API-неймспейса.
  static String get baseHost {
    final url = baseUrl;
    final idx = url.indexOf('/api/');
    return idx == -1 ? url : url.substring(0, idx);
  }

  static ApiClient? _instance;
  static ApiClient get instance => _instance!;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _instance = ApiClient._(prefs);
  }

  final SharedPreferences _prefs;
  late final Dio _dio;

  ApiClient._(this._prefs) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _prefs.getString('token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  String? get token => _prefs.getString('token');
  String? get userId => _prefs.getString('user_id');
  String? get userRole => _prefs.getString('user_role');
  bool get isLoggedIn => token != null;

  Future<void> saveSession({
    required String token,
    required String userId,
    required String role,
  }) async {
    await _prefs.setString('token', token);
    await _prefs.setString('user_id', userId);
    await _prefs.setString('user_role', role);
  }

  Future<void> updateRole(String role) async {
    await _prefs.setString('user_role', role);
  }

  Future<void> clearSession() async {
    await _prefs.remove('token');
    await _prefs.remove('user_id');
    await _prefs.remove('user_role');
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);

  Future<Response> postForm(String path, FormData data) =>
      _dio.post(path, data: data);

  /// Скачивает файл по абсолютному URL, прокидывая Bearer-токен из интерсептора.
  /// Нужно для статики (`/uploads/...`) и других ручек вне `/api/v1`,
  /// которые тоже требуют авторизации.
  ///
  /// `validateStatus` разрешает все коды, чтобы вызывающий мог сам решать,
  /// что делать с 404/403 (например, перебрать запасные URL), а исключение
  /// летело только при сетевых ошибках.
  Future<Response<List<int>>> downloadBytes(String absoluteUrl) =>
      _dio.get<List<int>>(
        absoluteUrl,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
}
