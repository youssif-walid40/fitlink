import 'package:cloud_firestore/cloud_firestore.dart';

import 'parse.dart';

class GymTier {
  final String name;
  final int price; // EGP
  final String period; // month | 3 months | year
  final List<String> perks;

  const GymTier({required this.name, required this.price, this.period = 'month', this.perks = const []});

  factory GymTier.fromMap(Map<String, dynamic> m) => GymTier(
        name: m['name'] ?? 'Tier',
        price: asInt(m['price']),
        period: m['period'] ?? 'month',
        perks: asStringList(m['perks']),
      );

  Map<String, dynamic> toMap() => {'name': name, 'price': price, 'period': period, 'perks': perks};
}

class Gym {
  final String id;
  final String ownerId;
  final String name;
  final String description;
  final String area;
  final String address;
  final double lat;
  final double lng;
  final List<GymTier> tiers;
  final List<String> photos;
  final List<String> policies;
  final List<String> facilities;
  final String openHours;
  final bool sponsored;
  final bool verified;
  final DateTime? sponsoredUntil;

  const Gym({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description = '',
    this.area = '',
    this.address = '',
    required this.lat,
    required this.lng,
    this.tiers = const [],
    this.photos = const [],
    this.policies = const [],
    this.facilities = const [],
    this.openHours = '',
    this.sponsored = false,
    this.verified = false,
    this.sponsoredUntil,
  });

  int? get minPrice =>
      tiers.isEmpty ? null : tiers.map((t) => t.price).reduce((a, b) => a < b ? a : b);

  bool get isSponsoredNow =>
      sponsored && (sponsoredUntil == null || sponsoredUntil!.isAfter(DateTime.now()));

  factory Gym.fromMap(String id, Map<String, dynamic> d) => Gym(
        id: id,
        ownerId: d['ownerId'] ?? '',
        name: d['name'] ?? 'Gym',
        description: d['description'] ?? '',
        area: d['area'] ?? '',
        address: d['address'] ?? '',
        lat: asDouble(d['lat']) ?? 0,
        lng: asDouble(d['lng']) ?? 0,
        tiers: (d['tiers'] as List? ?? []).map((t) => GymTier.fromMap(asMap(t))).toList(),
        photos: asStringList(d['photos']),
        policies: asStringList(d['policies']),
        facilities: asStringList(d['facilities']),
        openHours: d['openHours'] ?? '',
        sponsored: d['sponsored'] == true,
        verified: d['verified'] == true,
        sponsoredUntil: asDate(d['sponsoredUntil']),
      );

  factory Gym.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => Gym.fromMap(doc.id, doc.data() ?? {});

  /// Fields the gym owner is allowed to write (see firestore.rules).
  Map<String, dynamic> toEditableMap() => {
        'ownerId': ownerId,
        'name': name,
        'description': description,
        'area': area,
        'address': address,
        'lat': lat,
        'lng': lng,
        'tiers': tiers.map((t) => t.toMap()).toList(),
        'photos': photos,
        'policies': policies,
        'facilities': facilities,
        'openHours': openHours,
      };

  /// JSON-safe map for the Hive cache.
  Map<String, dynamic> toCache() => {
        ...toEditableMap(),
        'id': id,
        'sponsored': sponsored,
        'verified': verified,
        'sponsoredUntil': sponsoredUntil?.millisecondsSinceEpoch,
      };

  factory Gym.fromCache(Map<String, dynamic> m) => Gym.fromMap(m['id'] ?? '', m);
}
