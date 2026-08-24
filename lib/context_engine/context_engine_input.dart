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

  const ContextEngineInput({
    required this.gpsCoordinates,
    required this.temperatureC,
    this.facingMode = 'environment',
    this.userId,
  });

  // Without this, CE has no real identity to attribute a frame to and
  // stamps every response with a generic user_id (confirmed: every BE/AH
  // call downstream echoed back user_id 0 regardless of who was logged in) -
  // the real accumulated behaviour graph was building up under that generic
  // id instead of the authenticated account's.
  Map<String, dynamic> toJson() => {
    'gps_coordinates': gpsCoordinates.toJson(),
    'temperature_c': temperatureC,
    'facing_mode': facingMode,
    if (userId != null) 'user_id': userId,
  };
}
