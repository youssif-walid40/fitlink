import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/validators.dart';
import '../../core/widgets/common.dart';
import '../../models/scan.dart';
import '../../providers/scan_history_provider.dart';
import '../../providers/session_provider.dart';
import '../../repositories/scan_repository.dart';
import '../../repositories/user_repository.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import 'share_scan.dart';

/// InBody pipeline steps 4–6: the member corrects any misread values (range
/// validated), then the backend explains them and the scan is saved privately.
class ScanConfirmScreen extends StatefulWidget {
  const ScanConfirmScreen({super.key, required this.draft});
  final ScanDraft draft;

  @override
  State<ScanConfirmScreen> createState() => _ScanConfirmScreenState();
}

class _ScanConfirmScreenState extends State<ScanConfirmScreen> {
  static const _required = {'weight', 'percentBodyFat', 'skeletalMuscleMass'};
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _ctrls = {
    for (final m in kMetrics)
      m.key: TextEditingController(text: widget.draft.values[m.key] == null ? '' : fmtNum(widget.draft.values[m.key]!)),
  };
  late DateTime _date = widget.draft.scanDate ?? DateTime.now();
  String? _goal;
  String? _stage;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      showSnack(context, 'Please fix the highlighted values', error: true);
      return;
    }
    final user = context.read<SessionProvider>().user!;
    final api = context.read<ApiService>();
    final storage = context.read<StorageService>();
    final scans = context.read<ScanRepository>();
    final users = context.read<UserRepository>();
    final history = context.read<ScanHistoryProvider>();

    final values = <String, double>{
      for (final e in _ctrls.entries)
        if (double.tryParse(e.value.text.trim()) != null) e.key: double.parse(e.value.text.trim()),
    };
    final goal = _goal ?? user.goal;

    try {
      setState(() => _stage = 'Writing your explanation…');
      final ai = await api.explainInBody(values, goal);

      setState(() => _stage = 'Saving your scan…');
      final scanId = scans.newScanId(user.uid);
      String? imageUrl;
      try {
        imageUrl = await storage.uploadImage('users/${user.uid}/scans/$scanId.jpg', File(widget.draft.imagePath));
      } catch (_) {
        imageUrl = null; // The analysis is still useful without the photo.
      }
      final scan = await scans.saveScan(
        uid: user.uid,
        scanId: scanId,
        imageUrl: imageUrl,
        values: values,
        scanDate: _date,
        goal: goal,
        summary: ai.summary,
        nextSteps: ai.nextSteps,
      );
      if (goal != user.goal) await users.updateProfile(user.uid, goal: goal);
      history.add(scan);
      if (!mounted) return;
      final router = GoRouter.of(context);
      router.go('/home?tab=inbody');
      router.push('/scan/${user.uid}/$scanId');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _stage = null);
      if (e.needsPremium) {
        showPremiumPrompt(context, e.message, () => context.push('/premium'));
      } else {
        showSnack(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _stage = null);
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user!;
    _goal ??= user.goal;
    final busy = _stage != null;

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Confirm your values')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            AppCard(
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(widget.draft.imagePath), width: 56, height: 72, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Check each value against your sheet and fix anything the AI misread. '
                      'Fields marked * are required.'),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Scan date'),
              subtitle: Text(DateFormat.yMMMd().format(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: busy
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _date = d);
                    },
            ),
            DropdownButtonFormField<String>(
              initialValue: _goal,
              decoration: const InputDecoration(labelText: 'Your goal'),
              items: [for (final e in AppConfig.goals.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: busy ? null : (v) => setState(() => _goal = v),
            ),
            const SizedBox(height: 16),
            for (final m in kMetrics) ...[
              TextFormField(
                controller: _ctrls[m.key],
                enabled: !busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${m.label}${_required.contains(m.key) ? ' *' : ''}',
                  suffixText: m.unit,
                  helperText: widget.draft.values[m.key] == null ? 'Not found on the sheet – enter it if available' : null,
                ),
                validator: (v) => Validators.number(
                  v,
                  min: m.min,
                  max: m.max,
                  optional: !_required.contains(m.key),
                  field: m.label,
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Disclaimer(),
            BusyButton(label: busy ? _stage! : 'Confirm & analyze', icon: Icons.auto_awesome, busy: busy, onPressed: _submit),
            if (busy)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_stage!, textAlign: TextAlign.center),
              ),
          ]),
        ),
      ),
    );
  }
}
