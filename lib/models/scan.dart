import 'package:cloud_firestore/cloud_firestore.dart';

import 'parse.dart';

/// Definition of one InBody metric: display info, valid range for the
/// confirmation form, and which direction counts as progress for each goal.
class InBodyMetric {
  final String key;
  final String label;
  final String unit;
  final double min;
  final double max;

  /// Preferred direction per goal: 1 = up is good, -1 = down is good, 0 = stable is good.
  final Map<String, int> preferred;

  const InBodyMetric(this.key, this.label, this.unit, this.min, this.max, this.preferred);

  int preferredFor(String goal) => preferred[goal] ?? preferred['default'] ?? 0;
}

const kMetrics = <InBodyMetric>[
  InBodyMetric('weight', 'Weight', 'kg', 20, 300, {'fat_loss': -1, 'muscle_gain': 1, 'maintenance': 0}),
  InBodyMetric('skeletalMuscleMass', 'Skeletal muscle mass', 'kg', 5, 80, {'default': 1, 'maintenance': 0}),
  InBodyMetric('bodyFatMass', 'Body fat mass', 'kg', 1, 150, {'default': -1}),
  InBodyMetric('percentBodyFat', 'Body fat', '%', 2, 70, {'default': -1}),
  InBodyMetric('bmi', 'BMI', '', 10, 70, {'fat_loss': -1, 'muscle_gain': 0, 'maintenance': 0}),
  InBodyMetric('basalMetabolicRate', 'Basal metabolic rate', 'kcal', 500, 4000, {'default': 1, 'maintenance': 0}),
  InBodyMetric('visceralFatLevel', 'Visceral fat level', '', 1, 30, {'default': -1}),
  InBodyMetric('totalBodyWater', 'Total body water', 'L', 10, 80, {'default': 0}),
];

InBodyMetric metricByKey(String key) => kMetrics.firstWhere((m) => m.key == key);

/// A confirmed InBody scan at users/{uid}/scans/{id}.
class Scan {
  final String id;
  final String memberId;
  final String? imageUrl;
  final Map<String, double> values;
  final DateTime scanDate;
  final String goal;
  final String summary;
  final List<String> nextSteps;
  final List<String> sharedWith;
  final DateTime? createdAt;

  const Scan({
    required this.id,
    required this.memberId,
    this.imageUrl,
    required this.values,
    required this.scanDate,
    required this.goal,
    this.summary = '',
    this.nextSteps = const [],
    this.sharedWith = const [],
    this.createdAt,
  });

  double? operator [](String key) => values[key];

  factory Scan.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final raw = asMap(d['values']);
    final values = <String, double>{};
    raw.forEach((k, v) {
      final n = asDouble(v);
      if (n != null) values[k] = n;
    });
    return Scan(
      id: doc.id,
      memberId: d['memberId'] ?? '',
      imageUrl: d['imageUrl'],
      values: values,
      scanDate: asDate(d['scanDate']) ?? asDate(d['createdAt']) ?? DateTime.now(),
      goal: d['goal'] ?? 'fat_loss',
      summary: d['summary'] ?? '',
      nextSteps: asStringList(d['nextSteps']),
      sharedWith: asStringList(d['sharedWith']),
      createdAt: asDate(d['createdAt']),
    );
  }
}

/// Values extracted by the LLM, before the member confirms them.
class ScanDraft {
  final String imagePath;
  final Map<String, double?> values;
  final DateTime? scanDate;
  const ScanDraft({required this.imagePath, required this.values, this.scanDate});
}

class ProgressReport {
  final String id;
  final String narrative;
  final List<String> focus;
  final String fromScanId;
  final String toScanId;
  final DateTime? createdAt;

  const ProgressReport({
    required this.id,
    required this.narrative,
    this.focus = const [],
    required this.fromScanId,
    required this.toScanId,
    this.createdAt,
  });

  factory ProgressReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ProgressReport(
      id: doc.id,
      narrative: d['narrative'] ?? '',
      focus: asStringList(d['focus']),
      fromScanId: d['fromScanId'] ?? '',
      toScanId: d['toScanId'] ?? '',
      createdAt: asDate(d['createdAt']),
    );
  }
}
