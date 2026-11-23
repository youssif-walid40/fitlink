import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/gym.dart';
import '../models/pt_profile.dart';
import '../services/cache_service.dart';

class PtRepository {
  PtRepository(this._cache, {FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final CacheService _cache;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _pts => _db.collection('pts');
  CollectionReference<Map<String, dynamic>> get _aff => _db.collection('affiliations');

  Stream<List<PtProfile>> watchPts() => _pts.where('verified', isEqualTo: true).snapshots().map((s) {
        final list = s.docs.map(PtProfile.fromDoc).toList();
        _cache.savePts(list);
        return list;
      });

  Stream<PtProfile?> watchPt(String id) =>
      _pts.doc(id).snapshots().map((d) => d.exists ? PtProfile.fromDoc(d) : null);

  Future<void> savePt(PtProfile pt) =>
      _pts.doc(pt.id).update({...pt.toEditableMap(), 'updatedAt': FieldValue.serverTimestamp()});

  Stream<List<Review>> watchReviews(String ptId) => _pts
      .doc(ptId)
      .collection('reviews')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(Review.fromDoc).toList());

  // ---------- Gym affiliations ----------

  Stream<Set<String>> watchApprovedPtIds(String gymId) => _aff
      .where('gymId', isEqualTo: gymId)
      .where('status', isEqualTo: 'approved')
      .snapshots()
      .map((s) => s.docs.map((d) => '${d.data()['ptId']}').toSet());

  Stream<List<Affiliation>> watchGymAffiliations(String gymId) =>
      _aff.where('gymId', isEqualTo: gymId).snapshots().map((s) => s.docs.map(Affiliation.fromDoc).toList());

  Stream<List<Affiliation>> watchPtAffiliations(String ptId) =>
      _aff.where('ptId', isEqualTo: ptId).snapshots().map((s) => s.docs.map(Affiliation.fromDoc).toList());

  Future<void> requestAffiliation({required String ptId, required String ptName, required Gym gym}) =>
      _aff.doc('${ptId}_${gym.id}').set({
        'ptId': ptId,
        'ptName': ptName,
        'gymId': gym.id,
        'gymName': gym.name,
        'ownerId': gym.ownerId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> setAffiliationStatus(String id, String status) =>
      _aff.doc(id).update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});
}
