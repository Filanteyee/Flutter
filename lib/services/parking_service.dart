import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/parking_booking.dart';
import '../models/parking_event.dart';
import '../models/parking_permit.dart';
import '../models/parking_spot.dart';
import 'api_client.dart';

class ParkingService {
  ParkingService._();
  static final ParkingService instance = ParkingService._();

  final _spotsController = StreamController<List<ParkingSpot>>.broadcast();

  Stream<List<ParkingSpot>> get spotsStream => _spotsController.stream;

  /// GET /api/v1/parking/spots
  Future<List<ParkingSpot>> getSpots() async {
    final res = await ApiClient.instance.get('/parking/spots');
    final list = _parseSpots(res.data);
    _spotsController.add(list);
    return list;
  }

  /// GET /api/v1/parking/bookings/my
  Future<List<ParkingBooking>> getMyBookings() async {
    final res = await ApiClient.instance.get('/parking/bookings/my');
    return _parseBookings(res.data);
  }

  /// GET /api/v1/admin/parking/spots  (includes assigned_user_name)
  Future<List<ParkingSpot>> getAdminSpots() async {
    final res = await ApiClient.instance.get('/admin/parking/spots');
    final list = _parseSpots(res.data);
    _spotsController.add(list);
    return list;
  }

  /// POST /api/v1/parking/bookings
  Future<ParkingBooking> createBooking({
    required String spotId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final res = await ApiClient.instance.post('/parking/bookings', data: {
      'spot_id': spotId,
      'start_time': startTime.toUtc().toIso8601String(),
      'end_time': endTime.toUtc().toIso8601String(),
    });
    return ParkingBooking.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// PUT /api/v1/parking/bookings/:id/cancel
  Future<void> cancelBooking(String bookingId) async {
    await ApiClient.instance.put('/parking/bookings/$bookingId/cancel');
  }

  /// GET /api/v1/admin/parking/events
  Future<List<ParkingEvent>> getEvents() async {
    final res = await ApiClient.instance.get('/admin/parking/events');
    return _parseEvents(res.data);
  }

  /// GET /api/v1/admin/parking/bookings
  Future<List<ParkingBooking>> getAllBookings() async {
    final res = await ApiClient.instance.get('/admin/parking/bookings');
    return _parseBookings(res.data);
  }

  /// POST /api/v1/admin/parking/spots/:id/assign
  Future<void> assignPermanentSpot({
    required String spotId,
    required String userId,
  }) async {
    await ApiClient.instance.post('/admin/parking/spots/$spotId/assign', data: {
      'user_id': userId,
    });
  }

  // ─── Parking Permits ────────────────────────────────────────

  /// GET /parking/permit
  Future<List<ParkingPermit>> getMyPermits() async {
    final res = await ApiClient.instance.get('/parking/permit');
    return (res.data as List)
        .map((e) => ParkingPermit.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// POST /parking/permit
  Future<ParkingPermit> submitPermit(String vehicleId, {String? spotId}) async {
    final res = await ApiClient.instance.post('/parking/permit', data: {
      'vehicle_id': vehicleId,
      if (spotId != null) 'spot_id': spotId,
    });
    return ParkingPermit.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// POST /parking/permit/:id/document
  Future<String> uploadPermitDocument(String permitId, File file) async {
    final formData = FormData.fromMap({
      'document': await MultipartFile.fromFile(file.path,
          filename: file.path.split('/').last),
    });
    final res = await ApiClient.instance.post(
      '/parking/permit/$permitId/document',
      data: formData,
    );
    return (res.data as Map)['document_url'] as String;
  }

  /// GET /admin/parking/permits
  Future<List<ParkingPermit>> getAdminPermits({String? status}) async {
    final res = await ApiClient.instance.get(
      '/admin/parking/permits',
      params: status != null ? {'status': status} : null,
    );
    return (res.data as List)
        .map((e) => ParkingPermit.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// PUT /admin/parking/permits/:id/status
  Future<void> adminReviewPermit(
    String permitId,
    String status, {
    String? adminComment,
    String? spotId,
  }) async {
    await ApiClient.instance.put('/admin/parking/permits/$permitId/status', data: {
      'status': status,
      if (adminComment != null) 'admin_comment': adminComment,
      if (spotId != null) 'spot_id': spotId,
    });
  }

  // ─────────────────────────────────────────────────────────────

  /// Вызывается при получении FCM parking_alert / parking_spot_freed
  Future<void> refreshFromPush(Map<String, String> data) async {
    try {
      await getSpots();
    } catch (e) {
      debugPrint('[ParkingService] refreshFromPush failed: $e');
    }
  }

  List<ParkingSpot> _parseSpots(dynamic data) => (data as List)
      .map((e) => ParkingSpot.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  List<ParkingBooking> _parseBookings(dynamic data) => (data as List)
      .map((e) => ParkingBooking.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  List<ParkingEvent> _parseEvents(dynamic data) => (data as List)
      .map((e) => ParkingEvent.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  void dispose() {
    _spotsController.close();
  }
}
