import 'package:cloud_firestore/cloud_firestore.dart';

import 'parse.dart';

enum UserRole { member, pt, owner, admin }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.member => 'Member',
        UserRole.pt => 'Personal trainer',
        UserRole.owner => 'Gym owner',
        UserRole.admin => 'Admin',
      };

  static UserRole parse(String? s) =>
      UserRole.values.firstWhere((r) => r.name == s, orElse: () => UserRole.member);
}

/// The private profile stored at users/{uid}. Only the owner (and the backend)
/// can read or write it. Fields like role, isPremium and aiUsage are locked by
/// security rules and only changed by the backend.
class AppUser {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String? photoUrl;
  final String? phone;
  final String goal; // fat_loss | muscle_gain | maintenance
  final String? gymId;
  final String? gymName;
  final String? gymTier;
  final bool isPremium;
  final DateTime? premiumUntil;
  final int scansUsed;
  final int progressUsed;
  final DateTime? createdAt;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl,
    this.phone,
    this.goal = 'fat_loss',
    this.gymId,
    this.gymName,
    this.gymTier,
    this.isPremium = false,
    this.premiumUntil,
    this.scansUsed = 0,
    this.progressUsed = 0,
    this.createdAt,
  });

  bool get isMember => role == UserRole.member;
  bool get isPt => role == UserRole.pt;
  bool get isOwner => role == UserRole.owner;
  bool get isAdmin => role == UserRole.admin;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final usage = asMap(d['aiUsage']);
    return AppUser(
      uid: doc.id,
      name: d['name'] ?? '',
      email: d['email'] ?? '',
      role: UserRoleX.parse(d['role']),
      photoUrl: d['photoUrl'],
      phone: d['phone'],
      goal: d['goal'] ?? 'fat_loss',
      gymId: d['gymId'],
      gymName: d['gymName'],
      gymTier: d['gymTier'],
      isPremium: d['isPremium'] == true,
      premiumUntil: asDate(d['premiumUntil']),
      scansUsed: asInt(usage['scans']),
      progressUsed: asInt(usage['progress']),
      createdAt: asDate(d['createdAt']),
    );
  }
}
