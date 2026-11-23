import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../core/widgets/common.dart';
import '../../models/pt_profile.dart';
import '../../providers/session_provider.dart';
import '../../repositories/pt_repository.dart';
import '../../services/storage_service.dart';

class _TransformationDraft {
  String? beforeUrl;
  String? afterUrl;
  File? beforeFile;
  File? afterFile;
  final TextEditingController caption;
  _TransformationDraft({this.beforeUrl, this.afterUrl, String caption = ''})
      : caption = TextEditingController(text: caption);
}

/// Trainer's own public profile: bio, prices, specialties, transformations,
/// plus the status of gym affiliation requests.
class PtProfileEditorScreen extends StatefulWidget {
  const PtProfileEditorScreen({super.key});

  @override
  State<PtProfileEditorScreen> createState() => _PtProfileEditorScreenState();
}

class _PtProfileEditorScreenState extends State<PtProfileEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _bio = TextEditingController();
  final _price = TextEditingController();
  final _years = TextEditingController();
  final Set<String> _specialties = {};
  String _mode = 'both';
  final List<_TransformationDraft> _transformations = [];
  PtProfile? _original;
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<SessionProvider>().uid!;
    try {
      final pt = await context.read<PtRepository>().watchPt(uid).first;
      if (pt != null) {
        _original = pt;
        _bio.text = pt.bio;
        _price.text = pt.monthlyPrice == 0 ? '' : '${pt.monthlyPrice}';
        _years.text = pt.yearsExperience == 0 ? '' : '${pt.yearsExperience}';
        _specialties.addAll(pt.specialties);
        _mode = pt.mode;
        _transformations.addAll(pt.transformations
            .map((t) => _TransformationDraft(beforeUrl: t.beforeUrl, afterUrl: t.afterUrl, caption: t.caption)));
      }
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _bio.dispose();
    _price.dispose();
    _years.dispose();
    for (final t in _transformations) {
      t.caption.dispose();
    }
    super.dispose();
  }

  Future<File?> _pick() async {
    final storage = context.read<StorageService>();
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Camera'), onTap: () => Navigator.pop(c, true)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Gallery'), onTap: () => Navigator.pop(c, false)),
        ]),
      ),
    );
    if (camera == null) return null;
    return storage.pickImage(fromCamera: camera, maxWidth: 1080);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_specialties.isEmpty) {
      showSnack(context, 'Pick at least one specialty', error: true);
      return;
    }
    final user = context.read<SessionProvider>().user!;
    final storage = context.read<StorageService>();
    final repo = context.read<PtRepository>();
    setState(() => _busy = true);
    try {
      final list = <Transformation>[];
      for (final t in _transformations) {
        if (t.beforeFile != null) {
          t.beforeUrl = await storage.uploadImage('pts/${user.uid}/${StorageService.uniqueName()}', t.beforeFile!);
          t.beforeFile = null;
        }
        if (t.afterFile != null) {
          t.afterUrl = await storage.uploadImage('pts/${user.uid}/${StorageService.uniqueName()}', t.afterFile!);
          t.afterFile = null;
        }
        if ((t.beforeUrl ?? '').isNotEmpty && (t.afterUrl ?? '').isNotEmpty) {
          list.add(Transformation(beforeUrl: t.beforeUrl!, afterUrl: t.afterUrl!, caption: t.caption.text.trim()));
        }
      }
      await repo.savePt(PtProfile(
        id: user.uid,
        name: user.name,
        photoUrl: user.photoUrl,
        bio: _bio.text.trim(),
        specialties: _specialties.toList(),
        monthlyPrice: int.parse(_price.text.trim()),
        mode: _mode,
        yearsExperience: int.tryParse(_years.text.trim()) ?? 0,
        transformations: list,
        rating: _original?.rating ?? 0,
        reviewCount: _original?.reviewCount ?? 0,
        verified: _original?.verified ?? false,
      ));
      if (!mounted) return;
      showSnack(context, 'Trainer profile saved');
      goBack(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Trainer profile')), body: const LoadingView());
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Trainer profile')), body: ErrorView(error: _error));
    final uid = context.read<SessionProvider>().uid!;

    return Scaffold(
      appBar: AppBar(title: const Text('Trainer profile')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_original != null && !_original!.verified)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: AppCard(
                color: AppColors.limeSoft,
                child: Text('Your profile is pending verification. Complete it so our team can approve it.',
                    style: TextStyle(color: AppColors.ink)),
              ),
            ),
          TextFormField(
            controller: _bio,
            maxLines: 5,
            maxLength: 600,
            decoration: const InputDecoration(
              labelText: 'About you',
              hintText: 'Certifications, experience, coaching style…',
              alignLabelWithHint: true,
            ),
            validator: (v) => (v == null || v.trim().length < 30) ? 'Write at least 30 characters' : null,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Monthly price', prefixText: 'EGP '),
                validator: (v) => Validators.number(v, min: 100, max: 100000, field: 'Price'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _years,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Years of experience'),
                validator: (v) => Validators.number(v, min: 0, max: 60, optional: true, field: 'Years'),
              ),
            ),
          ]),
          const SectionHeader('Coaching type'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'online', label: Text('Online')),
              ButtonSegment(value: 'inGym', label: Text('In gym')),
              ButtonSegment(value: 'both', label: Text('Both')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SectionHeader('Specialties'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in AppConfig.specialties)
              FilterChip(
                label: Text(s),
                selected: _specialties.contains(s),
                onSelected: (v) => setState(() => v ? _specialties.add(s) : _specialties.remove(s)),
              ),
          ]),
          SectionHeader(
            'Transformations',
            action: TextButton.icon(
              onPressed: () => setState(() => _transformations.add(_TransformationDraft())),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
          Text('Only upload photos you have the client\'s permission to share.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (var i = 0; i < _transformations.length; i++) ...[
            _TransformationEditor(
              key: ObjectKey(_transformations[i]),
              t: _transformations[i],
              onPickBefore: () async {
                final f = await _pick();
                if (f != null) setState(() => _transformations[i].beforeFile = f);
              },
              onPickAfter: () async {
                final f = await _pick();
                if (f != null) setState(() => _transformations[i].afterFile = f);
              },
              onRemove: () => setState(() => _transformations.removeAt(i)),
            ),
            const SizedBox(height: 10),
          ],
          _Affiliations(ptId: uid),
          const SizedBox(height: 20),
          BusyButton(label: 'Save profile', busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}

class _TransformationEditor extends StatelessWidget {
  const _TransformationEditor({super.key, required this.t, required this.onPickBefore, required this.onPickAfter, required this.onRemove});
  final _TransformationDraft t;
  final VoidCallback onPickBefore;
  final VoidCallback onPickAfter;
  final VoidCallback onRemove;

  Widget _slot(String label, File? file, String? url, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 1,
            child: file != null
                ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(file, fit: BoxFit.cover))
                : NetImage(url: url, label: label, icon: Icons.add_a_photo_outlined),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            _slot('Before', t.beforeFile, t.beforeUrl, onPickBefore),
            const SizedBox(width: 8),
            _slot('After', t.afterFile, t.afterUrl, onPickAfter),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: t.caption, decoration: const InputDecoration(hintText: 'Caption, e.g. −9 kg in 12 weeks'))),
            IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
          ]),
        ]),
      );
}

class _Affiliations extends StatelessWidget {
  const _Affiliations({required this.ptId});
  final String ptId;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Affiliation>>(
        stream: context.read<PtRepository>().watchPtAffiliations(ptId),
        builder: (context, snap) {
          final list = snap.data ?? const <Affiliation>[];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionHeader('Gym affiliations'),
            if (list.isEmpty)
              Text('Open a gym from the Gyms tab and tap "Request to coach at this gym".',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            for (final a in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_outlined),
                title: Text(a.gymName),
                trailing: Tag(a.status.toUpperCase(),
                    color: a.status == 'approved' ? AppColors.lime : null,
                    textColor: a.status == 'approved' ? AppColors.ink : null),
              ),
          ]);
        },
      );
}
