import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

// Real device GPS + reverse-geocoded city/country. Used by the phone/
// video-upload source adapters and to replace the hardcoded test coordinates
// previously sent to the context engine.
class LocationService extends ChangeNotifier {
  bool _isRunning = false;
  double? _latitude;
  double? _longitude;
  String? _city;
  String? _country;
  StreamSubscription<Position>? _positionSubscription;

  bool get isRunning => _isRunning;
  double? get latitude => _latitude;
  double? get longitude => _longitude;
  String? get city => _city;
  String? get country => _country;

  Future<void> start() async {
    if (_isRunning) return;

    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint('[LocationService] Location services are disabled.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[LocationService] Permission denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint('[LocationService] Permission permanently denied.');
      return;
    }

    _isRunning = true;

    try {
      final position = await Geolocator.getCurrentPosition();
      _latitude = position.latitude;
      _longitude = position.longitude;
      await _updateCity();
      notifyListeners();
    } catch (error) {
      debugPrint('[LocationService] Failed to get initial position: $error');
    }

    final locationSettings = kIsWeb
        ? const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)
        : AndroidSettings(accuracy: LocationAccuracy.high, distanceFilter: 5, intervalDuration: const Duration(seconds: 5));

    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((position) async {
      _latitude = position.latitude;
      _longitude = position.longitude;
      await _updateCity();
      notifyListeners();
    });
  }

  Future<void> _updateCity() async {
    if (_latitude == null || _longitude == null) return;
    try {
      final placemarks = await placemarkFromCoordinates(_latitude!, _longitude!);
      if (placemarks.isNotEmpty) {
        _city = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Unknown City';
        _country = placemarks.first.country ?? 'Unknown Country';
      }
    } catch (_) {
      // Fallback to displaying the raw device location if reverse-geocoding is unavailable (e.g., on Web)
      _city = '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}';
      _country = 'GPS Coordinates';
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}
