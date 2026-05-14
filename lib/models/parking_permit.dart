class ParkingPermit {
  final String id;
  final String userId;
  final String fullName;
  final String vehicleId;
  final String plateNumber;
  final String? spotId;
  final String? spotNumber;
  final String status;
  final String? documentUrl;
  final String? adminComment;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const ParkingPermit({
    required this.id,
    required this.userId,
    this.fullName = '',
    required this.vehicleId,
    required this.plateNumber,
    this.spotId,
    this.spotNumber,
    required this.status,
    this.documentUrl,
    this.adminComment,
    required this.createdAt,
    this.reviewedAt,
  });

  String get fullNameOrEmpty => fullName;

  factory ParkingPermit.fromJson(Map<String, dynamic> json) => ParkingPermit(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String? ?? '',
        vehicleId: json['vehicle_id'] as String,
        plateNumber: json['plate_number'] as String? ?? '',
        spotId: json['spot_id'] as String?,
        spotNumber: json['spot_number'] as String?,
        status: json['status'] as String,
        documentUrl: json['document_url'] as String?,
        adminComment: json['admin_comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        reviewedAt: json['reviewed_at'] != null
            ? DateTime.parse(json['reviewed_at'] as String)
            : null,
      );

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  String get statusLabel => switch (status) {
        'pending' => 'На рассмотрении',
        'approved' => 'Одобрен',
        'rejected' => 'Отклонён',
        _ => status,
      };
}
