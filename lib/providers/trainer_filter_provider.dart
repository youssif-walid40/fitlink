import 'package:flutter/foundation.dart';

import '../models/pt_profile.dart';

enum TrainerScope { all, myGym, online }

class TrainerFilterProvider extends ChangeNotifier {
  TrainerScope scope = TrainerScope.all;
  String query = '';
  int? maxPrice;
  double minRating = 0;
  String? specialty;

  void setScope(TrainerScope s) {
    scope = s;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setMaxPrice(int? p) {
    maxPrice = p;
    notifyListeners();
  }

  void setMinRating(double r) {
    minRating = r;
    notifyListeners();
  }

  void setSpecialty(String? s) {
    specialty = s;
    notifyListeners();
  }

  /// [myGymPtIds] = trainers with an approved affiliation at the member's gym.
  List<PtProfile> apply(List<PtProfile> pts, Set<String> myGymPtIds) {
    final q = query.trim().toLowerCase();
    final list = pts.where((p) {
      if (scope == TrainerScope.myGym && !(myGymPtIds.contains(p.id) && p.offersInGym)) return false;
      if (scope == TrainerScope.online && !p.offersOnline) return false;
      if (maxPrice != null && p.monthlyPrice > maxPrice!) return false;
      if (p.rating < minRating) return false;
      if (specialty != null && !p.specialties.contains(specialty)) return false;
      if (q.isNotEmpty &&
          !p.name.toLowerCase().contains(q) &&
          !p.specialties.any((s) => s.toLowerCase().contains(q))) {
        return false;
      }
      return true;
    }).toList();
    list.sort((a, b) => b.rating.compareTo(a.rating));
    return list;
  }
}
