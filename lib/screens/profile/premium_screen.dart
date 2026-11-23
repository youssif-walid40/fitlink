import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../providers/session_provider.dart';
import '../../services/api_service.dart';

/// Premium subscription with simulated payment. The upgrade itself is done by
/// the backend (/premium/activate) – the app can never set isPremium directly.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  String _plan = 'yearly';
  bool _busy = false;

  Future<void> _buy() async {
    final plan = AppConfig.premiumPlans[_plan]!;
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FakeCheckout(label: plan.label, price: plan.price),
    );
    if (paid != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiService>().activatePremium(_plan);
      if (!mounted) return;
      showSnack(context, 'Welcome to FitLink Premium! 🎉');
      goBack(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user!;
    return Scaffold(
      appBar: AppBar(title: const Text('FitLink Premium')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const DarkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.workspace_premium, color: AppColors.lime, size: 36),
            SizedBox(height: 10),
            Text('Understand every scan', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Free accounts include 2 InBody analyses and 1 progress report.',
                style: TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 16),
        for (final f in const [
          'Unlimited AI InBody explanations',
          'Unlimited progress-over-time analysis',
          'History charts for every metric',
          'Share any scan with your coach',
        ])
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_circle, color: AppColors.success), title: Text(f)),
        const SizedBox(height: 8),
        if (user.isPremium)
          const AppCard(child: Text('You already have Premium. Thank you for supporting FitLink!'))
        else ...[
          for (final e in AppConfig.premiumPlans.entries) ...[
            AppCard(
              highlighted: _plan == e.key,
              onTap: () => setState(() => _plan = e.key),
              child: Row(children: [
                Icon(_plan == e.key ? Icons.radio_button_checked : Icons.radio_button_off),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.value.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (e.key == 'yearly') const Text('Save 24% vs monthly', style: TextStyle(fontSize: 12)),
                  ]),
                ),
                Text('${egp(e.value.price)}/${e.value.period}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          BusyButton(label: 'Continue', busy: _busy, onPressed: _buy),
          const SizedBox(height: 8),
          Text('Payment is simulated in this prototype. Cancel anytime.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ]),
    );
  }
}

class _FakeCheckout extends StatefulWidget {
  const _FakeCheckout({required this.label, required this.price});
  final String label;
  final int price;

  @override
  State<_FakeCheckout> createState() => _FakeCheckoutState();
}

class _FakeCheckoutState extends State<_FakeCheckout> {
  final _form = GlobalKey<FormState>();
  bool _processing = false;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Pay ${egp(widget.price)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${widget.label} plan · simulated checkout'),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: '4242 4242 4242 4242',
              decoration: const InputDecoration(labelText: 'Card number (test)'),
              keyboardType: TextInputType.number,
              validator: (v) => (v ?? '').replaceAll(' ', '').length == 16 ? null : 'Enter 16 digits',
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: '12/30',
                  decoration: const InputDecoration(labelText: 'MM/YY'),
                  validator: (v) => RegExp(r'^\d{2}/\d{2}$').hasMatch(v ?? '') ? null : 'MM/YY',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: '123',
                  decoration: const InputDecoration(labelText: 'CVC'),
                  validator: (v) => RegExp(r'^\d{3}$').hasMatch(v ?? '') ? null : '3 digits',
                ),
              ),
            ]),
            const SizedBox(height: 16),
            BusyButton(
              label: 'Pay now',
              busy: _processing,
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                setState(() => _processing = true);
                await Future.delayed(const Duration(milliseconds: 1200));
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
          ]),
        ),
      );
}
