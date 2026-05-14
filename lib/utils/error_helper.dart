import 'package:dio/dio.dart';

String friendlyError(dynamic e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    if (status == 401) return 'Вы не вошли в аккаунт. Пожалуйста, войдите или зарегистрируйтесь.';
    if (status == 403) return 'Нет доступа к этому разделу.';
    if (status == 404) return 'Данные не найдены.';
    if (status != null && status >= 500) return 'Ошибка сервера. Попробуйте позже.';
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Нет подключения к серверу. Проверьте интернет или Wi-Fi.';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'Сервер не отвечает. Попробуйте позже.';
    }
  }
  return 'Что-то пошло не так. Попробуйте ещё раз.';
}
