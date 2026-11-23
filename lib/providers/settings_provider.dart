import 'package:flutter/material.dart';

import '../services/cache_service.dart';

/// Theme setting, persisted with SharedPreferences.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._cache) : _themeMode = _cache.themeMode;
  final CacheService _cache;
  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _cache.setThemeMode(mode);
  }
}
