import 'package:geolocator/geolocator.dart';

import '../core/constants.dart';
import 'cache_service.dart';

typedef LatLng2 = ({double lat, double lng, bool live});

/// GPS access with graceful fallbacks: live position → last cached position → Cairo.
class LocationService {
  LocationService(this._cache);
  final CacheService _cache;

  LatLng2 get fallback {
    final last = _cache.lastLocation;
    return last == null
        ? (lat: AppConfig.defaultLat, lng: AppConfig.defaultLng, live: false)
        : (lat: last.lat, lng: last.lng, live: false);
  }

  /// Returns the position plus a human message when GPS was not used.
  Future<(LatLng2, String?)> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (fallback, 'Location services are off – showing distances from your last known area.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return (fallback, 'Location permission denied – distances are approximate.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await _cache.saveLastLocation(pos.latitude, pos.longitude);
      return ((lat: pos.latitude, lng: pos.longitude, live: true), null);
    } catch (_) {
      return (fallback, 'Could not get your location – distances are approximate.');
    }
  }

  static double distanceKm(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000.0;
}
