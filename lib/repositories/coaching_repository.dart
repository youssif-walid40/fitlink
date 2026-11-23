import 'package:cloud_firestore/cloud_firestore.dart';

import '../logic/coaching_flow.dart';
import '../models/app_user.dart';
import '../models/coaching.dart';
import '../models/pt_profile.dart';

/// Persists the member↔PT hiring and negotiation workflow.
/// Every status change runs in a transaction that re-reads the current status,
/// so two people acting at once cannot corrupt the flow.
class CoachingRepository {
  CoachingRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('coachings');

  Stream<List<Coaching>> watchForUser(String uid) => _col
      .where('participants', arrayContains: uid)
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Coaching.fromDoc).toList());

  Stream<Coaching?> watch(String id) =>
      _col.doc(id).snapshots().map((d) => d.exists ? Coaching.fromDoc(d) : null);

  Map<String, dynamic> _event(String status, String by, [String note = '']) =>
      {'status': status, 'by': by, 'note': note, 'at': Timestamp.now()};

  /// Step 1 – member sends a request.
  Future<String> request({
    required AppUser member,
    required PtProfile pt,
    required String goal,
    required String level,
    required String mode,
    required String message,
  }) async {
    final ref = _col.doc();
    await ref.set({
      'memberId': member.uid,
      'ptId': pt.id,
      'participants': [member.uid, pt.id],
      'memberName': member.name,
      'ptName': pt.name,
      'memberPhoto': member.photoUrl,
      'ptPhoto': pt.photoUrl,
      'goal': goal,
      'level': level,
      'mode': mode,
      'message': message.trim(),
      'status': CoachingStatus.requested.name,
      'sessionsDone': 0,
      'sharedScanIds': <String>[],
      'reviewed': false,
      'events': [_event('requested', member.uid, message.trim())],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> _transition(
    String id,
    CoachingStatus to,
    AppUser actor, {
    Map<String, dynamic> Function(Coaching current)? extra,
    String note = '',
  }) =>
      _db.runTransaction((tx) async {
        final snap = await tx.get(_col.doc(id));
        if (!snap.exists) throw Exception('This coaching no longer exists.');
        final current = Coaching.fromDoc(snap);
        if (!CoachingFlow.canTransition(current.status, to, actor.role)) {
          throw Exception('This action is no longer available (status is ${current.status.label}).');
        }
        tx.update(_col.doc(id), {
          'status': to.name,
          'updatedAt': FieldValue.serverTimestamp(),
          'events': FieldValue.arrayUnion([_event(to.name, actor.uid, note)]),
          ...?extra?.call(current),
        });
      });

  // Step 2
  Future<void> accept(String id, AppUser pt) => _transition(id, CoachingStatus.accepted, pt);
  Future<void> decline(String id, AppUser pt, String reason) =>
      _transition(id, CoachingStatus.declined, pt, note: reason);
  Future<void> cancel(String id, AppUser member) => _transition(id, CoachingStatus.cancelled, member);

  // Step 3 / 5 – PT sends or revises a proposal.
  Future<void> propose(String id, AppUser pt, PlanProposal p) => _transition(
        id,
        CoachingStatus.proposed,
        pt,
        note: p.title,
        extra: (c) => {
          'proposal': PlanProposal.fromMap(p.toMap()).copyWith(version: (c.proposal?.version ?? 0) + 1).toMap(),
          'counter': null,
        },
      );

  // Step 4 – member accepts or counters.
  Future<void> acceptProposal(String id, AppUser member) => _transition(
        id,
        CoachingStatus.active,
        member,
        extra: (_) => {'activatedAt': FieldValue.serverTimestamp(), 'sessionsDone': 0},
      );

  Future<void> counter(String id, AppUser member, CounterOffer offer) => _transition(
        id,
        CoachingStatus.countered,
        member,
        note: offer.notes,
        extra: (_) => {'counter': offer.toMap()},
      );

  // Step 5 – PT accepts the counter: the agreed terms are merged into the plan.
  Future<void> acceptCounter(String id, AppUser pt) => _transition(
        id,
        CoachingStatus.active,
        pt,
        extra: (c) {
          final p = c.proposal!;
          final o = c.counter;
          final merged = p.copyWith(
            durationWeeks: o?.durationWeeks ?? p.durationWeeks,
            price: o?.price ?? p.price,
            notes: [p.notes, if (o != null && o.notes.isNotEmpty) 'Agreed changes: ${o.notes}']
                .where((s) => s.isNotEmpty)
                .join('\n'),
            version: p.version + 1,
          );
          return {'proposal': merged.toMap(), 'activatedAt': FieldValue.serverTimestamp(), 'sessionsDone': 0};
        },
      );

  // Step 7
  Future<void> complete(String id, AppUser pt) => _transition(
        id,
        CoachingStatus.completed,
        pt,
        extra: (_) => {'completedAt': FieldValue.serverTimestamp()},
      );

  /// Step 6 – log a finished workout session (capped at the plan's total).
  Future<void> logSession(String id) => _db.runTransaction((tx) async {
        final snap = await tx.get(_col.doc(id));
        final c = Coaching.fromDoc(snap);
        if (c.status != CoachingStatus.active) throw Exception('The plan is not active.');
        final total = c.proposal?.totalSessions ?? 0;
        if (c.sessionsDone >= total) throw Exception('All sessions are already logged.');
        tx.update(_col.doc(id), {'sessionsDone': c.sessionsDone + 1, 'updatedAt': FieldValue.serverTimestamp()});
      });

  Future<void> addSharedScan(String id, String scanId) => _col.doc(id).update({
        'sharedScanIds': FieldValue.arrayUnion([scanId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
