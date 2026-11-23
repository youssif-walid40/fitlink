import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> authChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Creates the Firebase Auth account and the matching users/{uid} profile.
  /// Admin accounts cannot be self-registered (blocked by security rules).
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    if (role == UserRole.admin) throw Exception('Admin accounts cannot be created from the app.');
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final uid = cred.user!.uid;
    await cred.user!.updateDisplayName(name.trim());

    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid), {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'role': role.name,
      'goal': 'fat_loss',
      'photoUrl': null,
      'isPremium': false,
      'aiUsage': {'scans': 0, 'progress': 0},
      'fcmTokens': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (role == UserRole.pt) {
      batch.set(_db.collection('pts').doc(uid), {
        'name': name.trim(),
        'photoUrl': null,
        'bio': '',
        'specialties': <String>[],
        'monthlyPrice': 0,
        'mode': 'both',
        'yearsExperience': 0,
        'rating': 0,
        'reviewCount': 0,
        'transformations': <Map<String, dynamic>>[],
        'verified': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> login(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> logout() => _auth.signOut();
}
