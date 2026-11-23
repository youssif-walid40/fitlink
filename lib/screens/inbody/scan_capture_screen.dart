import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/scan.dart';
import '../../services/api_service.dart';
import '../../services/ocr_service.dart';
import '../../services/storage_service.dart';
import 'share_scan.dart';

/// InBody pipeline steps 1–3:
///  1. photograph / pick the sheet
///  2. on-device ML Kit OCR rejects blurry or non-InBody images (no API cost)
///  3. backend + multimodal LLM extracts the values as strict JSON
class ScanCaptureScreen extends StatefulWidget {
  const ScanCaptureScreen({super.key});

  @override
  State<ScanCaptureScreen> createState() => _ScanCaptureScreenState();
}

class _ScanCaptureScreenState extends State<ScanCaptureScreen> {
  File? _image;
  OcrCheck? _check;
  bool _checking = false;
  bool _extracting = false;
  String? _error;

  Future<void> _pick(bool camera) async {
    setState(() => _error = null);
    final storage = context.read<StorageService>();
    final ocr = context.read<OcrService>();
    try {
      final file = await storage.pickImage(fromCamera: camera, maxWidth: 2000);
      if (file == null || !mounted) return;
      setState(() {
        _image = file;
        _check = null;
        _checking = true;
      });
      final result = await ocr.check(file.path);
      if (mounted) setState(() => _check = result);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read the image: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _extract() async {
    if (_image == null) return;
    setState(() {
      _extracting = true;
      _error = null;
    });
    try {
      final bytes = await _image!.readAsBytes();
      if (!mounted) return;
      final r = await context.read<ApiService>().extractInBody(bytes);
      if (!mounted) return;
      if (r.values.values.every((v) => v == null)) {
        setState(() => _error = 'The AI could not find any values on this sheet. Try a clearer photo.');
        return;
      }
      context.push('/inbody/confirm', extra: ScanDraft(imagePath: _image!.path, values: r.values, scanDate: r.scanDate));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.needsPremium) {
        showPremiumPrompt(context, e.message, () => context.push('/premium'));
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = _check?.ok ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan InBody sheet')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_image == null)
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('Tips for a good scan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              SizedBox(height: 10),
              _Tip(Icons.crop_free, 'Fit the whole printout inside the frame'),
              _Tip(Icons.light_mode_outlined, 'Use good, even light – avoid glare and shadows'),
              _Tip(Icons.straighten, 'Lay the sheet flat and hold the phone parallel'),
              _Tip(Icons.lock_outline, 'Your scans are private unless you share them'),
            ]),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(_image!, height: 340, fit: BoxFit.contain),
          ),
        const SizedBox(height: 14),
        if (_checking)
          const AppCard(
            child: Row(children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Checking the image on your device…'),
            ]),
          ),
        if (_check != null)
          AppCard(
            color: ok ? AppColors.limeSoft : AppColors.danger.withValues(alpha: 0.08),
            child: Row(children: [
              Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? AppColors.ink : AppColors.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ok ? 'Looks like an InBody sheet. Ready to read the values.' : _check!.reason!,
                  style: TextStyle(color: ok ? AppColors.ink : null),
                ),
              ),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _extracting ? null : () => _pick(false),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: (_image == null || !ok)
                ? FilledButton.icon(
                    onPressed: _extracting ? null : () => _pick(true),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(_image == null ? 'Camera' : 'Retake'),
                  )
                : OutlinedButton.icon(
                    onPressed: _extracting ? null : () => _pick(true),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Retake'),
                  ),
          ),
        ]),
        if (ok) ...[
          const SizedBox(height: 12),
          BusyButton(label: 'Read values with AI', icon: Icons.auto_awesome, busy: _extracting, onPressed: _extract),
          if (_extracting)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Reading your sheet – this can take up to 20 seconds.', textAlign: TextAlign.center),
            ),
        ],
      ]),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 10), Expanded(child: Text(text))]),
      );
}
