import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/gym.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db.collection('users').doc(uid);

  /// Live profile of the signed-in user. Emits null until the doc exists
  /// (right after registration).
  Stream<AppUser?> watchUser(String uid) =>
      _doc(uid).snapshots().map((d) => d.exists ? AppUser.fromDoc(d) : null);

  /// Only these keys may be changed by the client (enforced in firestore.rules).
  Future<void> updateProfile(String uid,
      {String? name, String? photoUrl, String? phone, String? goal}) async {
    final data = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (phone != null) 'phone': phone.trim(),
      if (goal != null) 'goal': goal,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _doc(uid).update(data);
  }

  /// Keeps the public PT profile's name/photo in sync with the user profile.
  Future<void> syncPtIdentity(String uid, {String? name, String? photoUrl}) => _db.collection('pts').doc(uid).update({
        if (name != null) 'name': name.trim(),
        if (photoUrl != null) 'photoUrl': photoUrl,
      });

  Future<void> addFcmToken(String uid, String token) =>
      _doc(uid).update({'fcmTokens': FieldValue.arrayUnion([token])});

  Future<void> removeFcmToken(String uid, String token) =>
      _doc(uid).update({'fcmTokens': FieldValue.arrayRemove([token])});

  /// Member joins a gym tier. Payment is simulated; the gym owner sees the
  /// member in gyms/{gymId}/members.
  Future<void> joinGym(AppUser user, Gym gym, GymTier tier) async {
    final batch = _db.batch();
    if (user.gymId != null && user.gymId != gym.id) {
      batch.delete(_db.collection('gyms').doc(user.gymId).collection('members').doc(user.uid));
    }
    batch.update(_doc(user.uid), {
      'gymId': gym.id,
      'gymName': gym.name,
      'gymTier': tier.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('gyms').doc(gym.id).collection('members').doc(user.uid), {
      'name': user.name,
      'photoUrl': user.photoUrl,
      'tier': tier.name,
      'price': tier.price,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> leaveGym(AppUser user) async {
    if (user.gymId == null) return;
    final batch = _db.batch();
    batch.delete(_db.collection('gyms').doc(user.gymId).collection('members').doc(user.uid));
    batch.update(_doc(user.uid), {
      'gymId': FieldValue.delete(),
      'gymName': FieldValue.delete(),
      'gymTier': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
