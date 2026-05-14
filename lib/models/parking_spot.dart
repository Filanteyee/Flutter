enum ParkingSpotType { permanent, guest }

enum ParkingSpotStatus { free, occupied, reserved }

class ParkingSpot {
  final String id;
  final String spotNumber;
  final ParkingSpotType type;
  final ParkingSpotStatus status;
  final String? assignedUserId;
  final String? assignedUserName;
  final String? currentBookingId;

  const ParkingSpot({
    required this.id,
    required this.spotNumber,
    required this.type,
    required this.status,
    this.assignedUserId,
    this.assignedUserName,
    this.currentBookingId,
  });

  factory ParkingSpot.fromJson(Map<String, dynamic> json) => ParkingSpot(
        id: json['id'].toString(),
        spotNumber: json['spot_number'].toString(),
        type: _parseType(json['type']?.toString()),
        status: _parseStatus(json['status']?.toString()),
        assignedUserId: json['assigned_user_id']?.toString(),
        assignedUserName: json['assigned_user_name']?.toString(),
        currentBookingId: json['current_booking_id']?.toString(),
      );

  static ParkingSpotType _parseType(String? v) {
    switch (v?.toUpperCase()) {
      case 'PERMANENT':
        return ParkingSpotType.permanent;
      default:
        return ParkingSpotType.guest;
    }
  }

  static ParkingSpotStatus _parseStatus(String? v) {
    switch (v?.toUpperCase()) {
      case 'OCCUPIED':
        return ParkingSpotStatus.occupied;
      case 'RESERVED':
        return ParkingSpotStatus.reserved;
      default:
        return ParkingSpotStatus.free;
    }
  }
}

extension ParkingSpotStatusX on ParkingSpotStatus {
  String get label {
    switch (this) {
      case ParkingSpotStatus.free:
        return 'Свободно';
      case ParkingSpotStatus.occupied:
        return 'Занято';
      case ParkingSpotStatus.reserved:
        return 'Забронировано';
    }
  }
}

extension ParkingSpotTypeX on ParkingSpotType {
  String get label =>
      this == ParkingSpotType.permanent ? 'Постоянное' : 'Гостевое';
}
