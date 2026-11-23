import 'package:fitlink/core/validators.dart';
import 'package:fitlink/services/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email('sara@fitlink.app'), isNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email(''), isNotNull);
    });

    test('password needs 8+ chars and a number', () {
      expect(Validators.password('Passw0rd!'), isNull);
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('longbutnonumber'), isNotNull);
    });

    test('number range and optional', () {
      expect(Validators.number('24.6', min: 2, max: 70), isNull);
      expect(Validators.number('240', min: 2, max: 70), isNotNull);
      expect(Validators.number('abc'), isNotNull);
      expect(Validators.number('', optional: true), isNull);
      expect(Validators.number(''), isNotNull);
    });

    test('phone is optional but must be valid when given', () {
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('+201001234567'), isNull);
      expect(Validators.phone('12ab'), isNotNull);
    });
  });

  group('OcrService.evaluate (on-device pre-check)', () {
    test('accepts text that looks like an InBody sheet', () {
      const text = 'InBody 570 Body Composition Analysis Weight 82.4 Skeletal Muscle Mass 31.2 '
          'Body Fat Mass 20.3 BMI 26.1 Percent Body Fat 24.6 Visceral Fat Level 9';
      final r = OcrService.evaluate(text);
      expect(r.ok, isTrue);
      expect(r.keywordHits, greaterThanOrEqualTo(2));
    });

    test('rejects blurry images with almost no text', () {
      expect(OcrService.evaluate('a b').ok, isFalse);
    });

    test('rejects unrelated documents', () {
      const receipt = 'SUPERMARKET RECEIPT Bread 15.00 Milk 32.50 Eggs 60.00 TOTAL 107.50 Thank you for shopping';
      expect(OcrService.evaluate(receipt).ok, isFalse);
    });
  });
}
