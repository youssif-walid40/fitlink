import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  final String? code;
  const ApiException(this.status, this.message, [this.code]);

  /// 402 = the free AI quota is used up and premium is required.
  bool get needsPremium => status == 402;

  @override
  String toString() => message;
}

/// Client for the FitLink REST backend (backend/ folder).
/// Every request carries the user's Firebase ID token, which the backend
/// verifies before doing anything. The LLM key never touches the app.
class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.backendUrl;

  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw const ApiException(401, 'Please sign in again.');

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException(408, 'The server took too long to respond. Please try again.');
    } on SocketException {
      throw const ApiException(0, 'Could not reach the FitLink server. Check your connection.');
    } on http.ClientException {
      throw const ApiException(0, 'Could not reach the FitLink server. Check your connection.');
    }

    Map<String, dynamic> data = {};
    try {
      if (res.body.isNotEmpty) data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } on FormatException {
      data = {};
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw ApiException(
      res.statusCode,
      (data['error'] as String?) ?? 'Request failed (${res.statusCode}).',
      data['code'] as String?,
    );
  }

  // ---------- AI ----------

  /// Step 3 of the InBody pipeline: the multimodal LLM reads the sheet image
  /// and returns strict JSON values (validated against a schema server-side).
  Future<({Map<String, double?> values, DateTime? scanDate})> extractInBody(List<int> imageBytes) async {
    final data = await _post('/ai/inbody/extract', {
      'imageBase64': base64Encode(imageBytes),
      'mimeType': 'image/jpeg',
    }, timeout: const Duration(seconds: 90));
    final raw = Map<String, dynamic>.from(data['values'] as Map? ?? {});
    return (
      values: raw.map((k, v) => MapEntry(k, v is num ? v.toDouble() : null)),
      scanDate: DateTime.tryParse('${data['scanDate'] ?? ''}'),
    );
  }

  /// Step 5: confirmed values + goal -> plain-language explanation.
  Future<({String summary, List<String> nextSteps})> explainInBody(
      Map<String, double> values, String goal) async {
    final data = await _post('/ai/inbody/explain', {'values': values, 'goal': goal});
    return (
      summary: '${data['summary'] ?? ''}',
      nextSteps: (data['nextSteps'] as List? ?? []).map((e) => '$e').toList(),
    );
  }

  /// Progress narrative. Only computed deltas are sent, never raw scans.
  Future<({String narrative, List<String> focus})> analyzeProgress(Map<String, dynamic> progress) async {
    final data = await _post('/ai/inbody/progress', {'progress': progress});
    return (
      narrative: '${data['narrative'] ?? ''}',
      focus: (data['focus'] as List? ?? []).map((e) => '$e').toList(),
    );
  }

  // ---------- Notifications ----------

  /// Asks the backend to push a notification to the *other* participant of a
  /// coaching or chat. The backend checks the caller is a participant.
  Future<void> notify({required String type, required String refId, String? preview}) async {
    try {
      await _post('/notify', {'type': type, 'refId': refId, if (preview != null) 'preview': preview},
          timeout: const Duration(seconds: 15));
    } catch (_) {
      // Notifications are best-effort; never block the user flow on them.
    }
  }

  // ---------- Media ----------

  /// Uploads an image to the backend's media store and returns its relative URL.
  Future<String> uploadImage(String path, List<int> bytes) async {
    final data = await _post('/files/upload', {'path': path, 'imageBase64': base64Encode(bytes)},
        timeout: const Duration(seconds: 90));
    final url = data['url'];
    if (url is! String || url.isEmpty) throw const ApiException(500, 'Upload failed.');
    return url;
  }

  // ---------- Sensitive writes ----------

  Future<DateTime?> activatePremium(String plan) async {
    final data = await _post('/premium/activate', {'plan': plan});
    return DateTime.tryParse('${data['premiumUntil'] ?? ''}');
  }

  Future<void> sponsorGym(String gymId, int days) => _post('/gyms/sponsor', {'gymId': gymId, 'days': days});

  Future<void> submitReview({required String coachingId, required int rating, required String comment}) =>
      _post('/reviews', {'coachingId': coachingId, 'rating': rating, 'comment': comment});
}
