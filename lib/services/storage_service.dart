import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

/// Image picking (camera / gallery) and uploads.
///
/// Uploads go to the FitLink backend (POST /files/upload) instead of Firebase
/// Storage, so the project runs on Firebase's free Spark plan. The backend
/// applies the same access rules Storage rules would:
///   users/{uid}/avatar.jpg, users/{uid}/scans/{scanId}.jpg  – owner only
///   pts/{uid}/…  – that trainer · gyms/{gymId}/…  – gym owner · chats/{chatId}/…  – participants
class StorageService {
  StorageService(this._api);
  final ApiService _api;
  final _picker = ImagePicker();

  /// Returns a relative URL ("/files/…"); display it with AppConfig.mediaUrl().
  Future<String> uploadImage(String path, File file) async => _api.uploadImage(path, await file.readAsBytes());

  /// Opens the camera or gallery. Images are downscaled to keep uploads small.
  Future<File?> pickImage({required bool fromCamera, double maxWidth = 1600}) async {
    final x = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxWidth,
      imageQuality: 85,
    );
    return x == null ? null : File(x.path);
  }

  static String uniqueName() => '${DateTime.now().millisecondsSinceEpoch}.jpg';
}
