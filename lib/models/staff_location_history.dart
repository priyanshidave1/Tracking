class StaffLocationHistory {
  final String id;
  final String staffId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? shiftId;

  const StaffLocationHistory({
    required this.id,
    required this.staffId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.shiftId,
  });

  factory StaffLocationHistory.fromJson(Map<String, dynamic> json) {
    return StaffLocationHistory(
      id: json['id'] as String,
      staffId: json['staffId'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      shiftId: json['shiftId'] as String?,
    );
  }
}