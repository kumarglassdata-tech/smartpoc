// Telemetry JSON sent alongside each JPEG frame.
class GpsCoordinates {
  final double lat;
  final double lon;

  const GpsCoordinates({required this.lat, required this.lon});

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
}

class ContextEngineInput {
  final GpsCoordinates gpsCoordinates;
  final double temperatureC;
  final String facingMode;
  final dynamic userId;
  final String? sessionId;

  const ContextEngineInput({
    required this.gpsCoordinates,
    required this.temperatureC,
    this.facingMode = 'environment',
    this.userId,
    this.sessionId,
  });

  Map<String, dynamic> toJson() => {
    'gps_coordinates': gpsCoordinates.toJson(),
    'temperature_c': temperatureC,
    'facing_mode': facingMode,
    if (userId != null) 'user_id': userId,
    if (sessionId != null && sessionId!.isNotEmpty) 'session_id': sessionId,
  };
}
