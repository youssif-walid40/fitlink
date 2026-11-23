import 'package:fitlink/logic/progress_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

ScanPoint scan(String id, DateTime date, Map<String, double> values) => ScanPoint(id: id, date: date, values: values);

void main() {
  final jan1 = DateTime.utc(2026, 1, 1);
  final mar1 = DateTime.utc(2026, 2, 26); // exactly 8 weeks later

  group('ProgressCalculator', () {
    test('needs at least two scans', () {
      expect(() => ProgressCalculator.compute([scan('a', jan1, {'weight': 80})], 'fat_loss'), throwsArgumentError);
    });

    test('computes change, percent and per-week rate from first to last scan', () {
      final r = ProgressCalculator.compute([
        scan('b', mar1, {'weight': 76, 'percentBodyFat': 22}),
        scan('a', jan1, {'weight': 80, 'percentBodyFat': 25}), // unsorted on purpose
      ], 'fat_loss');

      expect(r.fromScanId, 'a');
      expect(r.toScanId, 'b');
      expect(r.weeks, closeTo(8, 0.001));
      final w = r.trends.firstWhere((t) => t.key == 'weight');
      expect(w.change, -4);
      expect(w.percentChange, closeTo(-5, 0.001));
      expect(w.perWeek, closeTo(-0.5, 0.001));
      expect(w.trend, Trend.down);
      expect(w.assessment, Assessment.improved);
    });

    test('assessment depends on the goal', () {
      final scans = [
        scan('a', jan1, {'weight': 70, 'skeletalMuscleMass': 30}),
        scan('b', mar1, {'weight': 72, 'skeletalMuscleMass': 31}),
      ];
      final gain = ProgressCalculator.compute(scans, 'muscle_gain');
      final loss = ProgressCalculator.compute(scans, 'fat_loss');
      expect(gain.trends.firstWhere((t) => t.key == 'weight').assessment, Assessment.improved);
      expect(loss.trends.firstWhere((t) => t.key == 'weight').assessment, Assessment.worsened);
      // More muscle is good for both goals.
      expect(loss.trends.firstWhere((t) => t.key == 'skeletalMuscleMass').assessment, Assessment.improved);
    });

    test('changes below the threshold count as flat / stable', () {
      final r = ProgressCalculator.compute([
        scan('a', jan1, {'weight': 80.0}),
        scan('b', mar1, {'weight': 80.2}),
      ], 'fat_loss');
      final w = r.trends.single;
      expect(w.trend, Trend.flat);
      expect(w.assessment, Assessment.stable);
    });

    test('skips metrics missing from either scan', () {
      final r = ProgressCalculator.compute([
        scan('a', jan1, {'weight': 80, 'bmi': 25}),
        scan('b', mar1, {'weight': 78}),
      ], 'fat_loss');
      expect(r.trends.map((t) => t.key), ['weight']);
    });

    test('same-day scans do not divide by zero', () {
      final r = ProgressCalculator.compute([
        scan('a', jan1, {'weight': 80}),
        scan('b', jan1, {'weight': 79}),
      ], 'fat_loss');
      expect(r.trends.single.perWeek, 0);
    });

    test('toJson only contains computed numbers', () {
      final json = ProgressCalculator.compute([
        scan('a', jan1, {'weight': 80}),
        scan('b', mar1, {'weight': 78}),
      ], 'fat_loss').toJson();
      expect(json.keys, containsAll(['goal', 'weeks', 'scanCount', 'metrics']));
      expect((json['metrics'] as List).first['change'], -2);
    });
  });
}
