import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/gym.dart';
import '../models/pt_profile.dart';

class Report {
  final String id;
  final String targetType; // pt | gym
  final String targetId;
  final String targetName;
  final String reason;
  final String reporterId;
  final DateTime? createdAt;
  const Report(this.id, this.targetType, this.targetId, this.targetName, this.reason, this.reporterId, this.createdAt);
}

class AdminRepository {
  AdminRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<List<PtProfile>> watchUnverifiedPts() => _db
      .collection('pts')
      .where('verified', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.map(PtProfile.fromDoc).toList());

  Stream<List<Gym>> watchUnverifiedGyms() => _db
      .collection('gyms')
      .where('verified', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.map(Gym.fromDoc).toList());

  Future<void> setPtVerified(String id, bool v) => _db.collection('pts').doc(id).update({'verified': v});
  Future<void> setGymVerified(String id, bool v) => _db.collection('gyms').doc(id).update({'verified': v});

  Stream<List<Report>> watchReports() => _db
      .collection('reports')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) {
            final m = d.data();
            return Report(d.id, m['targetType'] ?? '', m['targetId'] ?? '', m['targetName'] ?? '',
                m['reason'] ?? '', m['reporterId'] ?? '', (m['createdAt'] as Timestamp?)?.toDate());
          }).toList());

  Future<void> dismissReport(String id) => _db.collection('reports').doc(id).delete();

  /// Any signed-in user can report a trainer or gym listing.
  Future<void> submitReport({
    required String reporterId,
    required String targetType,
    required String targetId,
    required String targetName,
    required String reason,
  }) =>
      _db.collection('reports').add({
        'reporterId': reporterId,
        'targetType': targetType,
        'targetId': targetId,
        'targetName': targetName,
        'reason': reason.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
}
