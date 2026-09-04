import 'dart:async';
import 'location_service_stub.dart'
    if (dart.library.html) 'location_service_web.dart'
    if (dart.library.io) 'location_service_mobile.dart';

abstract class LocationService {
  static LocationService get instance => getLocationServiceInstance();

  bool get isTracking;
  Stream<LocationData> get onLocationChanged;

  Future<void> init();
  Future<String?> requestPermission();
  Future<LocationData?> getCurrentLocation();
  void startTracking();
  void stopTracking();
}

class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final DateTime timestamp;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.timestamp,
  });
}
