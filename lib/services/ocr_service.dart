import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrCheck {
  final bool ok;
  final String? reason;
  final int keywordHits;
  const OcrCheck(this.ok, this.reason, this.keywordHits);
}

/// Step 2 of the InBody pipeline: on-device ML Kit text recognition checks the
/// photo is readable and looks like an InBody sheet BEFORE any paid API call.
class OcrService {
  static const keywords = [
    'inbody',
    'body composition',
    'skeletal muscle',
    'body fat',
    'percent body fat',
    'pbf',
    'bmi',
    'visceral',
    'total body water',
    'basal metabolic',
    'smm',
    'segmental',
    'fat free mass',
    'muscle-fat',
  ];

  Future<OcrCheck> check(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return evaluate(result.text);
    } finally {
      await recognizer.close();
    }
  }

  /// Pure function so it can be unit-tested without a device.
  static OcrCheck evaluate(String recognizedText) {
    final text = recognizedText.toLowerCase();
    if (text.replaceAll(RegExp(r'\s+'), '').length < 30) {
      return const OcrCheck(false,
          'The photo is too blurry or dark to read. Lay the sheet flat in good light and try again.', 0);
    }
    final hits = keywords.where(text.contains).length;
    if (hits < 2) {
      return OcrCheck(false,
          'This does not look like an InBody result sheet. Make sure the whole printout is in the frame.', hits);
    }
    return OcrCheck(true, null, hits);
  }
}
