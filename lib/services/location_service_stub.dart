import 'location_service.dart';

LocationService? _instance;

LocationService getLocationServiceInstance() {
  _instance ??= StubLocationService();
  return _instance!;
}

class StubLocationService implements LocationService {
  @override
  bool get isTracking => false;

  @override
  Stream<LocationData> get onLocationChanged => const Stream.empty();

  @override
  Future<void> init() async {}

  @override
  Future<String?> requestPermission() async =>
      'Location features are not available on this platform.';

  @override
  Future<LocationData?> getCurrentLocation() async => null;

  @override
  void startTracking() {}

  @override
  void stopTracking() {}
}
