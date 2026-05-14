import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/barrier_event.dart';
import 'api_client.dart';

class BarrierService {
  BarrierService._();
  static final BarrierService instance = BarrierService._();

  final _unknownController = StreamController<List<BarrierEvent>>.broadcast();

  /// Поток неизвестных ТС ожидающих решения.
  /// Эмиттится после каждого [getUnknownVehicles] и после [refreshFromPush].
  /// Вкладка "Неизвестные ТС" подписывается, чтобы перерисовываться
  /// автоматически при получении FCM с kind=unknown_vehicle.
  Stream<List<BarrierEvent>> get unknownEventsStream =>
      _unknownController.stream;

  /// POST /api/v1/barrier/scan-qr
  Future<Map<String, dynamic>> scanQR(String qrCode) async {
    final res = await ApiClient.instance.post('/barrier/scan-qr', data: {
      'qr_code': qrCode,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// GET /api/v1/barrier/events — resident: own events
  Future<List<BarrierEvent>> getMyEvents() async {
    final res = await ApiClient.instance.get('/barrier/events');
    return _parseEvents(res.data);
  }

  /// GET /api/v1/admin/barrier/events — admin: full history
  Future<List<BarrierEvent>> getAllEvents() async {
    final res = await ApiClient.instance.get('/admin/barrier/events');
    return _parseEvents(res.data);
  }

  /// GET /api/v1/admin/barrier/unknown — admin: pending unknown vehicles.
  /// Результат дополнительно пушится в [unknownEventsStream].
  Future<List<BarrierEvent>> getUnknownVehicles() async {
    final res = await ApiClient.instance.get('/admin/barrier/unknown');
    final list = _parseEvents(res.data);
    _unknownController.add(list);
    return list;
  }

  /// POST /api/v1/admin/barrier/unknown/:id/approve
  Future<void> approveUnknown(String eventId) async {
    await ApiClient.instance.post('/admin/barrier/unknown/$eventId/approve');
  }

  /// POST /api/v1/admin/barrier/unknown/:id/reject
  Future<void> rejectUnknown(String eventId) async {
    await ApiClient.instance.post('/admin/barrier/unknown/$eventId/reject');
  }

  /// POST /api/v1/barrier/open-manual
  Future<void> openManual({required String direction}) async {
    await ApiClient.instance.post('/barrier/open-manual', data: {
      'direction': direction,
    });
  }

  /// Вызывается из NotificationsService при получении FCM с kind=unknown_vehicle.
  /// Делает тихий повторный запрос неизвестных ТС — UI обновится через
  /// подписку на [unknownEventsStream]. Не падает на ошибках: best-effort.
  Future<void> refreshFromPush(Map<String, String> data) async {
    try {
      await getUnknownVehicles();
    } catch (e) {
      debugPrint('[BarrierService] refreshFromPush failed: $e');
    }
  }

  List<BarrierEvent> _parseEvents(dynamic data) => (data as List)
      .map((e) => BarrierEvent.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  void dispose() {
    _unknownController.close();
  }
}
