import 'package:flutter/foundation.dart';

import '../models/gym.dart';
import '../services/location_service.dart';

typedef GymWithDistance = ({Gym gym, double km});

enum GymSort { distance, price }

/// Search, filters, sorting and the user's GPS position for gym discovery.
class GymFilterProvider extends ChangeNotifier {
  GymFilterProvider(this._location) : position = _location.fallback;

  final LocationService _location;

  LatLng2 position;
  bool locating = false;
  String? locationNote;
  String query = '';
  double? maxDistanceKm;
  int? maxPrice;
  final Set<String> facilities = {};
  GymSort sort = GymSort.distance;
  bool showMap = false;

  bool get hasFilters => maxDistanceKm != null || maxPrice != null || facilities.isNotEmpty;

  Future<void> locate() async {
    locating = true;
    notifyListeners();
    final (pos, note) = await _location.current();
    position = pos;
    locationNote = note;
    locating = false;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setMaxDistance(double? km) {
    maxDistanceKm = km;
    notifyListeners();
  }

  void setMaxPrice(int? p) {
    maxPrice = p;
    notifyListeners();
  }

  void toggleFacility(String f) {
    facilities.contains(f) ? facilities.remove(f) : facilities.add(f);
    notifyListeners();
  }

  void setSort(GymSort s) {
    sort = s;
    notifyListeners();
  }

  void toggleMap(bool map) {
    showMap = map;
    notifyListeners();
  }

  void clear() {
    maxDistanceKm = null;
    maxPrice = null;
    facilities.clear();
    notifyListeners();
  }

  double distanceTo(Gym g) => LocationService.distanceKm(position.lat, position.lng, g.lat, g.lng);

  /// Sponsored listings first (always labelled), then by distance or price.
  List<GymWithDistance> apply(List<Gym> gyms) {
    final q = query.trim().toLowerCase();
    final list = gyms
        .map((g) => (gym: g, km: distanceTo(g)))
        .where((e) =>
            q.isEmpty ||
            e.gym.name.toLowerCase().contains(q) ||
            e.gym.area.toLowerCase().contains(q) ||
            e.gym.address.toLowerCase().contains(q))
        .where((e) => maxDistanceKm == null || e.km <= maxDistanceKm!)
        .where((e) => maxPrice == null || (e.gym.minPrice ?? 1 << 30) <= maxPrice!)
        .where((e) => facilities.every(e.gym.facilities.contains))
        .toList();

    int byKey(GymWithDistance a, GymWithDistance b) => sort == GymSort.price
        ? (a.gym.minPrice ?? 1 << 30).compareTo(b.gym.minPrice ?? 1 << 30)
        : a.km.compareTo(b.km);

    list.sort((a, b) {
      final sa = a.gym.isSponsoredNow ? 0 : 1;
      final sb = b.gym.isSponsoredNow ? 0 : 1;
      return sa != sb ? sa.compareTo(sb) : byKey(a, b);
    });
    return list;
  }
}
