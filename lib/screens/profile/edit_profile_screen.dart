import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/validators.dart';
import '../../core/widgets/common.dart';
import '../../providers/session_provider.dart';
import '../../repositories/user_repository.dart';
import '../../services/storage_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _user = context.read<SessionProvider>().user!;
  late final _name = TextEditingController(text: _user.name);
  late final _phone = TextEditingController(text: _user.phone ?? '');
  late String _goal = _user.goal;
  File? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final storage = context.read<StorageService>();
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take photo'), onTap: () => Navigator.pop(c, true)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(c, false)),
        ]),
      ),
    );
    if (camera == null) return;
    final f = await storage.pickImage(fromCamera: camera, maxWidth: 800);
    if (f != null && mounted) setState(() => _photo = f);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final users = context.read<UserRepository>();
    final storage = context.read<StorageService>();
    setState(() => _busy = true);
    try {
      String? url;
      if (_photo != null) url = await storage.uploadImage('users/${_user.uid}/avatar.jpg', _photo!);
      await users.updateProfile(_user.uid, name: _name.text, phone: _phone.text, goal: _goal, photoUrl: url);
      if (_user.isPt) await users.syncPtIdentity(_user.uid, name: _name.text, photoUrl: url);
      if (!mounted) return;
      showSnack(context, 'Profile updated');
      goBack(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(children: [
                _photo != null
                    ? CircleAvatar(radius: 52, backgroundImage: FileImage(_photo!))
                    : UserAvatar(initials: _user.initials, url: _user.photoUrl, radius: 52),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(Icons.camera_alt, size: 18, color: Theme.of(context).colorScheme.onPrimary),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: Validators.name,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)', hintText: '+201xxxxxxxxx'),
            validator: Validators.phone,
          ),
          if (_user.isMember) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _goal,
              decoration: const InputDecoration(labelText: 'Fitness goal'),
              items: [for (final e in AppConfig.goals.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _goal = v ?? _goal),
            ),
          ],
          const SizedBox(height: 24),
          BusyButton(label: 'Save changes', busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}
