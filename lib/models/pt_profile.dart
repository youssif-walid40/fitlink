import 'package:cloud_firestore/cloud_firestore.dart';

import 'parse.dart';

class Transformation {
  final String beforeUrl;
  final String afterUrl;
  final String caption;
  const Transformation({required this.beforeUrl, required this.afterUrl, this.caption = ''});

  factory Transformation.fromMap(Map<String, dynamic> m) =>
      Transformation(beforeUrl: m['before'] ?? '', afterUrl: m['after'] ?? '', caption: m['caption'] ?? '');
  Map<String, dynamic> toMap() => {'before': beforeUrl, 'after': afterUrl, 'caption': caption};
}

/// Public trainer profile at pts/{uid}. Rating fields are maintained by the
/// backend when a verified review is submitted.
class PtProfile {
  final String id;
  final String name;
  final String? photoUrl;
  final String bio;
  final List<String> specialties;
  final int monthlyPrice;
  final String mode; // online | inGym | both
  final int yearsExperience;
  final double rating;
  final int reviewCount;
  final List<Transformation> transformations;
  final bool verified;

  const PtProfile({
    required this.id,
    required this.name,
    this.photoUrl,
    this.bio = '',
    this.specialties = const [],
    this.monthlyPrice = 0,
    this.mode = 'both',
    this.yearsExperience = 0,
    this.rating = 0,
    this.reviewCount = 0,
    this.transformations = const [],
    this.verified = false,
  });

  bool get offersOnline => mode == 'online' || mode == 'both';
  bool get offersInGym => mode == 'inGym' || mode == 'both';

  String get modeLabel => switch (mode) {
        'online' => 'Online',
        'inGym' => 'In gym',
        _ => 'Online and local',
      };

  String get initials {
    final parts = name.replaceFirst('Coach ', '').trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return parts.length == 1 ? parts.first[0] : (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory PtProfile.fromMap(String id, Map<String, dynamic> d) => PtProfile(
        id: id,
        name: d['name'] ?? 'Trainer',
        photoUrl: d['photoUrl'],
        bio: d['bio'] ?? '',
        specialties: asStringList(d['specialties']),
        monthlyPrice: asInt(d['monthlyPrice']),
        mode: d['mode'] ?? 'both',
        yearsExperience: asInt(d['yearsExperience']),
        rating: asDouble(d['rating']) ?? 0,
        reviewCount: asInt(d['reviewCount']),
        transformations:
            (d['transformations'] as List? ?? []).map((t) => Transformation.fromMap(asMap(t))).toList(),
        verified: d['verified'] == true,
      );

  factory PtProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      PtProfile.fromMap(doc.id, doc.data() ?? {});

  Map<String, dynamic> toEditableMap() => {
        'name': name,
        'photoUrl': photoUrl,
        'bio': bio,
        'specialties': specialties,
        'monthlyPrice': monthlyPrice,
        'mode': mode,
        'yearsExperience': yearsExperience,
        'transformations': transformations.map((t) => t.toMap()).toList(),
      };

  Map<String, dynamic> toCache() => {
        ...toEditableMap(),
        'id': id,
        'rating': rating,
        'reviewCount': reviewCount,
        'verified': verified,
      };

  factory PtProfile.fromCache(Map<String, dynamic> m) => PtProfile.fromMap(m['id'] ?? '', m);
}

class Review {
  final String id;
  final String memberName;
  final int rating;
  final String comment;
  final DateTime? createdAt;

  const Review({required this.id, required this.memberName, required this.rating, this.comment = '', this.createdAt});

  factory Review.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Review(
      id: doc.id,
      memberName: d['memberName'] ?? 'Member',
      rating: asInt(d['rating']),
      comment: d['comment'] ?? '',
      createdAt: asDate(d['createdAt']),
    );
  }
}

/// A trainer's request to be listed as coaching inside a gym (affiliations/{ptId_gymId}).
class Affiliation {
  final String id;
  final String ptId;
  final String ptName;
  final String gymId;
  final String gymName;
  final String status; // pending | approved | rejected

  const Affiliation({
    required this.id,
    required this.ptId,
    required this.ptName,
    required this.gymId,
    required this.gymName,
    required this.status,
  });

  factory Affiliation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Affiliation(
      id: doc.id,
      ptId: d['ptId'] ?? '',
      ptName: d['ptName'] ?? '',
      gymId: d['gymId'] ?? '',
      gymName: d['gymName'] ?? '',
      status: d['status'] ?? 'pending',
    );
  }
}
