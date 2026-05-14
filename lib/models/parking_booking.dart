enum BookingStatus { active, completed, cancelled }

class ParkingBooking {
  final String id;
  final String spotId;
  final String spotNumber;
  final String userId;
  final DateTime startTime;
  final DateTime endTime;
  final BookingStatus status;
  final DateTime createdAt;

  const ParkingBooking({
    required this.id,
    required this.spotId,
    required this.spotNumber,
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.createdAt,
  });

  factory ParkingBooking.fromJson(Map<String, dynamic> json) => ParkingBooking(
        id: json['id'].toString(),
        spotId: json['spot_id'].toString(),
        spotNumber: json['spot_number'].toString(),
        userId: json['user_id'].toString(),
        startTime: DateTime.parse(json['start_time'].toString()),
        endTime: DateTime.parse(json['end_time'].toString()),
        status: _parseStatus(json['status']?.toString()),
        createdAt: DateTime.parse(json['created_at'].toString()),
      );

  static BookingStatus _parseStatus(String? v) {
    switch (v?.toUpperCase()) {
      case 'COMPLETED':
        return BookingStatus.completed;
      case 'CANCELLED':
        return BookingStatus.cancelled;
      default:
        return BookingStatus.active;
    }
  }
}

extension BookingStatusX on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.active:
        return 'Активна';
      case BookingStatus.completed:
        return 'Завершена';
      case BookingStatus.cancelled:
        return 'Отменена';
    }
  }
}
