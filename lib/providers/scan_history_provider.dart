import 'package:flutter/foundation.dart';

import '../core/live_data.dart';
import '../models/scan.dart';
import '../repositories/scan_repository.dart';

/// The member's InBody scan history, loaded once and kept in memory.
class ScanHistoryProvider extends ChangeNotifier {
  ScanHistoryProvider(this._repo, this.uid);

  final ScanRepository _repo;
  final String uid;

  List<Scan> scans = [];
  bool loading = false;
  bool loaded = false;
  String? error;

  Scan? get latest => scans.isEmpty ? null : scans.first;
  bool get canAnalyzeProgress => scans.length >= 2;

  Future<void> load({bool force = false}) async {
    if (loading || (loaded && !force)) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      scans = await _repo.fetchScans(uid);
      loaded = true;
    } catch (e) {
      error = friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void add(Scan s) {
    scans = [s, ...scans]..sort((a, b) => b.scanDate.compareTo(a.scanDate));
    notifyListeners();
  }

  void markShared(String scanId, String ptId) {
    scans = scans
        .map((s) => s.id != scanId
            ? s
            : Scan(
                id: s.id,
                memberId: s.memberId,
                imageUrl: s.imageUrl,
                values: s.values,
                scanDate: s.scanDate,
                goal: s.goal,
                summary: s.summary,
                nextSteps: s.nextSteps,
                sharedWith: {...s.sharedWith, ptId}.toList(),
                createdAt: s.createdAt,
              ))
        .toList();
    notifyListeners();
  }
}
