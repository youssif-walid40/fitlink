import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/widgets/common.dart';
import '../../models/coaching.dart';
import '../../models/pt_profile.dart';
import '../../providers/session_provider.dart';
import '../../repositories/coaching_repository.dart';
import '../../services/api_service.dart';

/// Workflow step 1: the member sends a coaching request.
class RequestPtScreen extends StatefulWidget {
  const RequestPtScreen({super.key, required this.ptId});
  final String ptId;

  @override
  State<RequestPtScreen> createState() => _RequestPtScreenState();
}

class _RequestPtScreenState extends State<RequestPtScreen> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  String? _goal;
  String _level = AppConfig.levels.first;
  String? _mode;
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit(PtProfile pt) async {
    if (!_form.currentState!.validate()) return;
    final user = context.read<SessionProvider>().user!;
    final existing = (context.read<LiveData<List<Coaching>>>().data ?? const <Coaching>[])
        .where((c) => c.ptId == pt.id && c.status.isOpen)
        .firstOrNull;
    if (existing != null) {
      showSnack(context, 'You already have an open request with this trainer.');
      context.pushReplacement('/coaching/${existing.id}');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await context.read<CoachingRepository>().request(
            member: user,
            pt: pt,
            goal: _goal!,
            level: _level,
            mode: _mode!,
            message: _message.text,
          );
      if (!mounted) return;
      context.read<ApiService>().notify(type: 'coaching', refId: id);
      showSnack(context, 'Request sent to ${pt.name}');
      context.pushReplacement('/coaching/$id');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = context.watch<LiveData<List<PtProfile>>>().data ?? const <PtProfile>[];
    final pt = pts.where((p) => p.id == widget.ptId).firstOrNull;
    final user = context.watch<SessionProvider>().user!;
    _goal ??= user.goal;

    if (pt == null) {
      return Scaffold(appBar: AppBar(title: const Text('Request a trainer')), body: const LoadingView());
    }
    final modes = <String, String>{
      if (pt.offersOnline) 'online': 'Online coaching',
      if (pt.offersInGym) 'inGym': 'In-gym sessions',
    };
    if (_mode == null || !modes.containsKey(_mode)) _mode = modes.keys.first;

    return Scaffold(
      appBar: AppBar(title: Text('Request ${pt.name}')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Tell your coach about yourself so they can build the right plan.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _goal,
            decoration: const InputDecoration(labelText: 'Main goal'),
            items: [for (final e in AppConfig.goals.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _goal = v),
            validator: (v) => v == null ? 'Choose a goal' : null,
          ),
          const SizedBox(height: 18),
          const Text('Training level', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final l in AppConfig.levels) ButtonSegment(value: l, label: Text(l))],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          const SizedBox(height: 18),
          const Text('Coaching type', style: TextStyle(fontWeight: FontWeight.w600)),
          RadioGroup<String>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v),
            child: Column(children: [
              for (final e in modes.entries)
                RadioListTile<String>(value: e.key, title: Text(e.value), contentPadding: EdgeInsets.zero),
            ]),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _message,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Message (optional)',
              hintText: 'e.g. I want to lose fat and build muscle. I can train 4 days a week.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          BusyButton(label: 'Send request', icon: Icons.send, busy: _busy, onPressed: () => _submit(pt)),
        ]),
      ),
    );
  }
}
