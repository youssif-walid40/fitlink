import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/validators.dart';
import '../../core/widgets/common.dart';
import '../../models/gym.dart';
import '../../providers/session_provider.dart';
import '../../repositories/gym_repository.dart';
import '../../services/cache_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';

class _TierDraft {
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController perks;
  String period;
  _TierDraft({String name = '', int? price, List<String> perks = const [], this.period = 'month'})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price == null ? '' : '$price'),
        perks = TextEditingController(text: perks.join(', '));

  GymTier toTier() => GymTier(
        name: name.text.trim(),
        price: int.tryParse(price.text.trim()) ?? 0,
        period: period,
        perks: perks.text.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList(),
      );
}

/// Create or edit the owner's gym listing.
class GymEditorScreen extends StatefulWidget {
  const GymEditorScreen({super.key});

  @override
  State<GymEditorScreen> createState() => _GymEditorScreenState();
}

class _GymEditorScreenState extends State<GymEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _address = TextEditingController();
  final _description = TextEditingController();
  final _hours = TextEditingController();
  final _policies = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final Set<String> _facilities = {};
  final List<_TierDraft> _tiers = [];
  final List<String> _photoUrls = [];
  final List<File> _newPhotos = [];
  Gym? _existing;
  bool _loading = true;
  bool _busy = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<SessionProvider>().uid!;
    try {
      _existing = await context.read<GymRepository>().watchOwnerGym(uid).first;
    } catch (_) {}
    final g = _existing;
    if (g != null) {
      _name.text = g.name;
      _area.text = g.area;
      _address.text = g.address;
      _description.text = g.description;
      _hours.text = g.openHours;
      _policies.text = g.policies.join('\n');
      _lat.text = '${g.lat}';
      _lng.text = '${g.lng}';
      _facilities.addAll(g.facilities);
      _photoUrls.addAll(g.photos);
      _tiers.addAll(g.tiers.map((t) => _TierDraft(name: t.name, price: t.price, perks: t.perks, period: t.period)));
    } else {
      _tiers.add(_TierDraft(name: 'Basic', perks: const ['Gym floor access']));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final (pos, note) = await LocationService(context.read<CacheService>()).current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _lat.text = pos.lat.toStringAsFixed(6);
      _lng.text = pos.lng.toStringAsFixed(6);
    });
    if (note != null) showSnack(context, note);
  }

  Future<void> _addPhoto() async {
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
    if (camera == null) return;
    final f = await storage.pickImage(fromCamera: camera, maxWidth: 1600);
    if (f != null && mounted) setState(() => _newPhotos.add(f));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_tiers.isEmpty) {
      showSnack(context, 'Add at least one membership tier', error: true);
      return;
    }
    final uid = context.read<SessionProvider>().uid!;
    final repo = context.read<GymRepository>();
    final storage = context.read<StorageService>();
    setState(() => _busy = true);
    try {
      final isNew = _existing == null;
      final id = _existing?.id ?? repo.newGymId();
      Gym build(List<String> photos) => Gym(
            id: id,
            ownerId: uid,
            name: _name.text.trim(),
            area: _area.text.trim(),
            address: _address.text.trim(),
            description: _description.text.trim(),
            openHours: _hours.text.trim(),
            lat: double.parse(_lat.text.trim()),
            lng: double.parse(_lng.text.trim()),
            tiers: _tiers.map((t) => t.toTier()).toList(),
            facilities: _facilities.toList(),
            policies: _policies.text.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList(),
            photos: photos,
          );

      // The gym doc must exist before Storage rules allow photo uploads for it.
      if (isNew) await repo.saveGym(build(_photoUrls), isNew: true);
      for (final f in List<File>.from(_newPhotos)) {
        _photoUrls.add(await storage.uploadImage('gyms/$id/${StorageService.uniqueName()}', f));
        _newPhotos.remove(f);
      }
      await repo.saveGym(build(_photoUrls), isNew: false);
      _existing = build(_photoUrls);
      if (!mounted) return;
      showSnack(context, isNew ? 'Listing created – pending verification' : 'Listing updated');
      goBack(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Gym listing')), body: const LoadingView());
    return Scaffold(
      appBar: AppBar(title: Text(_existing == null ? 'Create gym listing' : 'Edit gym listing')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Gym name'), validator: (v) => Validators.required(v, 'Name')),
          const SizedBox(height: 12),
          TextFormField(controller: _area, decoration: const InputDecoration(labelText: 'Area', hintText: 'e.g. New Cairo, Maadi'), validator: (v) => Validators.required(v, 'Area')),
          const SizedBox(height: 12),
          TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Street address')),
          const SizedBox(height: 12),
          TextFormField(controller: _hours, decoration: const InputDecoration(labelText: 'Opening hours', hintText: 'Daily 6am – 1am')),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 4,
            maxLength: 800,
            decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
          ),
          const SectionHeader('Location'),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
                validator: (v) => Validators.number(v, min: -90, max: 90, field: 'Latitude'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
                validator: (v) => Validators.number(v, min: -180, max: 180, field: 'Longitude'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: const Text('Use my current location (stand at the gym)'),
          ),
          SectionHeader('Membership tiers', action: TextButton.icon(onPressed: () => setState(() => _tiers.add(_TierDraft())), icon: const Icon(Icons.add), label: const Text('Add'))),
          for (var i = 0; i < _tiers.length; i++) ...[
            AppCard(
              key: ObjectKey(_tiers[i]),
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tiers[i].name,
                      decoration: const InputDecoration(labelText: 'Tier name'),
                      validator: (v) => Validators.required(v, 'Tier name'),
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => _tiers.removeAt(i)), icon: const Icon(Icons.delete_outline)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tiers[i].price,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Price', prefixText: 'EGP '),
                      validator: (v) => Validators.number(v, min: 50, max: 100000, field: 'Price'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _tiers[i].period,
                      decoration: const InputDecoration(labelText: 'Per'),
                      items: const [
                        DropdownMenuItem(value: 'month', child: Text('Month')),
                        DropdownMenuItem(value: '3 months', child: Text('3 months')),
                        DropdownMenuItem(value: 'year', child: Text('Year')),
                      ],
                      onChanged: (v) => _tiers[i].period = v ?? 'month',
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextFormField(controller: _tiers[i].perks, decoration: const InputDecoration(labelText: 'Perks (comma separated)')),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          const SectionHeader('Facilities'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in AppConfig.facilities)
              FilterChip(
                label: Text(f),
                selected: _facilities.contains(f),
                onSelected: (v) => setState(() => v ? _facilities.add(f) : _facilities.remove(f)),
              ),
          ]),
          const SectionHeader('Policies'),
          TextFormField(
            controller: _policies,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'One per line, e.g.\nFreeze up to 1 month per year\nTowel required', alignLabelWithHint: true),
          ),
          SectionHeader('Photos', action: TextButton.icon(onPressed: _addPhoto, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add'))),
          SizedBox(
            height: 100,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final url in _photoUrls) _thumb(NetImage(url: url, width: 100, height: 100), () => setState(() => _photoUrls.remove(url))),
              for (final f in _newPhotos)
                _thumb(ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(f, width: 100, height: 100, fit: BoxFit.cover)),
                    () => setState(() => _newPhotos.remove(f))),
              if (_photoUrls.isEmpty && _newPhotos.isEmpty) const Center(child: Text('No photos yet')),
            ]),
          ),
          const SizedBox(height: 24),
          BusyButton(label: _existing == null ? 'Create listing' : 'Save changes', busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }

  Widget _thumb(Widget child, VoidCallback onRemove) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(children: [
          child,
          Positioned(
            right: 2,
            top: 2,
            child: InkWell(
              onTap: onRemove,
              child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
            ),
          ),
        ]),
      );
}
