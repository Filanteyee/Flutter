class Vehicle {
  final String id;
  final String userId;
  final String plateNumber;
  final String brand;
  final String color;
  final bool isActive;
  final DateTime createdAt;

  const Vehicle({
    required this.id,
    required this.userId,
    required this.plateNumber,
    required this.brand,
    required this.color,
    required this.isActive,
    required this.createdAt,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'].toString(),
        userId: json['user_id'].toString(),
        plateNumber: json['plate_number'].toString(),
        brand: (json['brand'] ?? '').toString(),
        color: (json['color'] ?? '').toString(),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'].toString()),
      );
}
