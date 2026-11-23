import 'dart:math' as math;

import '../models/scan.dart';

/// One scan reduced to the numbers progress analysis needs.
class ScanPoint {
  final String id;
  final DateTime date;
  final Map<String, double> values;
  const ScanPoint({required this.id, required this.date, required this.values});

  factory ScanPoint.fromScan(Scan s) => ScanPoint(id: s.id, date: s.scanDate, values: s.values);
}

enum Trend { up, down, flat }

enum Assessment { improved, worsened, stable }

class MetricTrend {
  final String key;
  final double first;
  final double last;
  final double change;
  final double? percentChange;
  final double perWeek;
  final Trend trend;
  final Assessment assessment;

  const MetricTrend({
    required this.key,
    required this.first,
    required this.last,
    required this.change,
    required this.percentChange,
    required this.perWeek,
    required this.trend,
    required this.assessment,
  });

  Map<String, dynamic> toJson() => {
        'metric': key,
        'label': metricByKey(key).label,
        'unit': metricByKey(key).unit,
        'first': _r(first),
        'last': _r(last),
        'change': _r(change),
        'percentChange': percentChange == null ? null : _r(percentChange!),
        'perWeek': _r(perWeek),
        'trend': trend.name,
        'assessment': assessment.name,
      };
}

class ProgressResult {
  final String fromScanId;
  final String toScanId;
  final DateTime from;
  final DateTime to;
  final double weeks;
  final int scanCount;
  final String goal;
  final List<MetricTrend> trends;

  const ProgressResult({
    required this.fromScanId,
    required this.toScanId,
    required this.from,
    required this.to,
    required this.weeks,
    required this.scanCount,
    required this.goal,
    required this.trends,
  });

  Iterable<MetricTrend> get improved => trends.where((t) => t.assessment == Assessment.improved);
  Iterable<MetricTrend> get worsened => trends.where((t) => t.assessment == Assessment.worsened);

  /// Only computed numbers are sent to the LLM – never the raw scan images.
  Map<String, dynamic> toJson() => {
        'goal': goal,
        'from': from.toIso8601String().substring(0, 10),
        'to': to.toIso8601String().substring(0, 10),
        'weeks': _r(weeks),
        'scanCount': scanCount,
        'metrics': trends.map((t) => t.toJson()).toList(),
      };
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// Deterministic progress maths (unit-tested in test/progress_calculator_test.dart).
class ProgressCalculator {
  ProgressCalculator._();

  /// Changes smaller than this (absolute, in the metric's unit) count as "flat".
  static const flatThreshold = <String, double>{
    'weight': 0.3,
    'skeletalMuscleMass': 0.2,
    'bodyFatMass': 0.3,
    'percentBodyFat': 0.3,
    'bmi': 0.1,
    'basalMetabolicRate': 10,
    'visceralFatLevel': 0.5,
    'totalBodyWater': 0.2,
  };

  static ProgressResult compute(List<ScanPoint> scans, String goal) {
    if (scans.length < 2) {
      throw ArgumentError('Progress analysis needs at least two scans');
    }
    final sorted = [...scans]..sort((a, b) => a.date.compareTo(b.date));
    final first = sorted.first;
    final last = sorted.last;
    final days = last.date.difference(first.date).inHours / 24.0;
    final weeks = math.max(days / 7.0, 0.0);

    final trends = <MetricTrend>[];
    for (final m in kMetrics) {
      final a = first.values[m.key];
      final b = last.values[m.key];
      if (a == null || b == null) continue;
      final change = b - a;
      final threshold = flatThreshold[m.key] ?? 0;
      final trend = change.abs() < threshold ? Trend.flat : (change > 0 ? Trend.up : Trend.down);
      trends.add(MetricTrend(
        key: m.key,
        first: a,
        last: b,
        change: change,
        percentChange: a == 0 ? null : change / a * 100,
        perWeek: weeks >= 1 / 7 ? change / weeks : 0,
        trend: trend,
        assessment: assess(trend, m.preferredFor(goal)),
      ));
    }
    return ProgressResult(
      fromScanId: first.id,
      toScanId: last.id,
      from: first.date,
      to: last.date,
      weeks: weeks,
      scanCount: sorted.length,
      goal: goal,
      trends: trends,
    );
  }

  static Assessment assess(Trend trend, int preferred) {
    if (preferred == 0) return trend == Trend.flat ? Assessment.stable : Assessment.worsened;
    if (trend == Trend.flat) return Assessment.stable;
    final up = trend == Trend.up;
    return (up && preferred > 0) || (!up && preferred < 0) ? Assessment.improved : Assessment.worsened;
  }
}
