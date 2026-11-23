import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gym.dart';
import '../models/pt_profile.dart';

/// Local persistence:
///  * Hive  – cached gym and trainer lists so the app shows data instantly on
///            startup and while offline.
///  * SharedPreferences – lightweight settings (theme), last known location
///            and text drafts for chat messages and plan proposals.
class CacheService {
  CacheService._(this._box, this._prefs);

  final Box<String> _box;
  final SharedPreferences _prefs;

  static Future<CacheService> init() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<String>('fitlink_cache');
    final prefs = await SharedPreferences.getInstance();
    return CacheService._(box, prefs);
  }

  // ---------- Hive: lists ----------
  List<Gym> get cachedGyms => _readList('gyms').map(Gym.fromCache).toList();
  Future<void> saveGyms(List<Gym> gyms) => _box.put('gyms', jsonEncode(gyms.map((g) => g.toCache()).toList()));

  List<PtProfile> get cachedPts => _readList('pts').map(PtProfile.fromCache).toList();
  Future<void> savePts(List<PtProfile> pts) => _box.put('pts', jsonEncode(pts.map((p) => p.toCache()).toList()));

  List<Map<String, dynamic>> _readList(String key) {
    final raw = _box.get(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // ---------- Settings ----------
  ThemeMode get themeMode => ThemeMode.values.firstWhere(
        (m) => m.name == _prefs.getString('themeMode'),
        orElse: () => ThemeMode.system,
      );
  Future<void> setThemeMode(ThemeMode m) => _prefs.setString('themeMode', m.name);

  // ---------- Location ----------
  ({double lat, double lng})? get lastLocation {
    final lat = _prefs.getDouble('lastLat');
    final lng = _prefs.getDouble('lastLng');
    return (lat == null || lng == null) ? null : (lat: lat, lng: lng);
  }

  Future<void> saveLastLocation(double lat, double lng) async {
    await _prefs.setDouble('lastLat', lat);
    await _prefs.setDouble('lastLng', lng);
  }

  // ---------- Drafts ----------
  String? chatDraft(String chatId) => _prefs.getString('draft_chat_$chatId');
  Future<void> saveChatDraft(String chatId, String text) => text.trim().isEmpty
      ? _prefs.remove('draft_chat_$chatId')
      : _prefs.setString('draft_chat_$chatId', text);

  Map<String, dynamic>? proposalDraft(String coachingId) {
    final raw = _prefs.getString('draft_proposal_$coachingId');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProposalDraft(String coachingId, Map<String, dynamic> draft) =>
      _prefs.setString('draft_proposal_$coachingId', jsonEncode(draft));
  Future<void> clearProposalDraft(String coachingId) => _prefs.remove('draft_proposal_$coachingId');

  // ---------- Onboarding ----------
  bool get seenScanTips => _prefs.getBool('seenScanTips') ?? false;
  Future<void> setSeenScanTips() => _prefs.setBool('seenScanTips', true);
}
