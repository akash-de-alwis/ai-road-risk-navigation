class TelemetryEvent {
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double headingDegrees;
  final String vehicleType;
  final String timestamp;

  TelemetryEvent({
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    this.headingDegrees = 0,
    this.vehicleType = 'car',
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'speed_kmh': speedKmh,
        'heading_degrees': headingDegrees,
        'vehicle_type': vehicleType,
        'timestamp': timestamp,
      };
}
