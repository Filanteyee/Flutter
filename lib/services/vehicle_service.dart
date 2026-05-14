import '../models/vehicle.dart';
import 'api_client.dart';

class VehicleService {
  VehicleService._();
  static final VehicleService instance = VehicleService._();

  /// GET /api/v1/vehicles
  Future<List<Vehicle>> getMyVehicles() async {
    final res = await ApiClient.instance.get('/vehicles');
    return (res.data as List)
        .map((e) => Vehicle.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// POST /api/v1/vehicles
  Future<void> addVehicle({
    required String plateNumber,
    required String brand,
    required String color,
  }) async {
    await ApiClient.instance.post('/vehicles', data: {
      'plate_number': plateNumber.trim().toUpperCase(),
      'brand': brand.trim(),
      'color': color.trim(),
    });
  }

  /// DELETE /api/v1/vehicles/:id
  Future<void> deleteVehicle(String id) async {
    await ApiClient.instance.delete('/vehicles/$id');
  }
}
