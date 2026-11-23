import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/gym.dart';
import '../services/cache_service.dart';

class GymMember {
  final String uid;
  final String name;
  final String tier;
  final DateTime? joinedAt;
  const GymMember(this.uid, this.name, this.tier, this.joinedAt);
}

class GymRepository {
  GymRepository(this._cache, {FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final CacheService _cache;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('gyms');

  /// Verified gyms, live. Every emission refreshes the Hive cache.
  Stream<List<Gym>> watchGyms() => _col.where('verified', isEqualTo: true).snapshots().map((s) {
        final gyms = s.docs.map(Gym.fromDoc).toList();
        _cache.saveGyms(gyms);
        return gyms;
      });

  Stream<Gym?> watchGym(String id) => _col.doc(id).snapshots().map((d) => d.exists ? Gym.fromDoc(d) : null);

  Stream<Gym?> watchOwnerGym(String ownerId) => _col
      .where('ownerId', isEqualTo: ownerId)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : Gym.fromDoc(s.docs.first));

  String newGymId() => _col.doc().id;

  /// Creates (unverified, unsponsored) or updates the owner's gym listing.
  Future<void> saveGym(Gym gym, {required bool isNew}) async {
    if (isNew) {
      await _col.doc(gym.id).set({
        ...gym.toEditableMap(),
        'verified': false,
        'sponsored': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _col.doc(gym.id).update({...gym.toEditableMap(), 'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  Stream<List<GymMember>> watchMembers(String gymId) => _col
      .doc(gymId)
      .collection('members')
      .orderBy('joinedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) {
            final m = d.data();
            return GymMember(d.id, m['name'] ?? 'Member', m['tier'] ?? '',
                (m['joinedAt'] as Timestamp?)?.toDate());
          }).toList());
}
