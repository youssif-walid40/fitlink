import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/scan.dart';

/// Private health data: users/{uid}/scans and users/{uid}/progressReports.
/// A PT can only read a scan whose sharedWith array contains their uid.
class ScanRepository {
  ScanRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _scans(String uid) =>
      _db.collection('users').doc(uid).collection('scans');
  CollectionReference<Map<String, dynamic>> _reports(String uid) =>
      _db.collection('users').doc(uid).collection('progressReports');

  String newScanId(String uid) => _scans(uid).doc().id;

  Future<List<Scan>> fetchScans(String uid) async {
    final s = await _scans(uid).orderBy('scanDate', descending: true).get();
    return s.docs.map(Scan.fromDoc).toList();
  }

  Stream<Scan?> watchScan(String memberId, String scanId) =>
      _scans(memberId).doc(scanId).snapshots().map((d) => d.exists ? Scan.fromDoc(d) : null);

  Stream<List<Scan>> watchSharedWith(String memberId, String ptId) => _scans(memberId)
      .where('sharedWith', arrayContains: ptId)
      .snapshots()
      .map((s) => s.docs.map(Scan.fromDoc).toList()..sort((a, b) => b.scanDate.compareTo(a.scanDate)));

  Future<Scan> saveScan({
    required String uid,
    required String scanId,
    required String? imageUrl,
    required Map<String, double> values,
    required DateTime scanDate,
    required String goal,
    required String summary,
    required List<String> nextSteps,
  }) async {
    final ref = _scans(uid).doc(scanId);
    await ref.set({
      'memberId': uid,
      'imageUrl': imageUrl,
      'values': values,
      'scanDate': Timestamp.fromDate(scanDate),
      'goal': goal,
      'summary': summary,
      'nextSteps': nextSteps,
      'sharedWith': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return Scan(
      id: scanId,
      memberId: uid,
      imageUrl: imageUrl,
      values: values,
      scanDate: scanDate,
      goal: goal,
      summary: summary,
      nextSteps: nextSteps,
      createdAt: DateTime.now(),
    );
  }

  Future<void> shareWith(String uid, String scanId, String ptId) =>
      _scans(uid).doc(scanId).update({'sharedWith': FieldValue.arrayUnion([ptId])});

  Future<void> saveReport(String uid,
      {required String narrative,
      required List<String> focus,
      required String fromScanId,
      required String toScanId,
      required Map<String, dynamic> numbers}) =>
      _reports(uid).add({
        'narrative': narrative,
        'focus': focus,
        'fromScanId': fromScanId,
        'toScanId': toScanId,
        'numbers': numbers,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Stream<ProgressReport?> watchLatestReport(String uid) => _reports(uid)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : ProgressReport.fromDoc(s.docs.first));
}
