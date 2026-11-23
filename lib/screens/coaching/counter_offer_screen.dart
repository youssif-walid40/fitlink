import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/validators.dart';
import '../../core/widgets/common.dart';
import '../../models/coaching.dart';
import '../../providers/session_provider.dart';
import '../../repositories/coaching_repository.dart';
import '../../services/api_service.dart';
import 'coaching_widgets.dart';

/// Workflow step 4 (counter): the member proposes changes to the plan.
class CounterOfferScreen extends StatefulWidget {
  const CounterOfferScreen({super.key, required this.coachingId});
  final String coachingId;

  @override
  State<CounterOfferScreen> createState() => _CounterOfferScreenState();
}

class _CounterOfferScreenState extends State<CounterOfferScreen> {
  final _form = GlobalKey<FormState>();
  final _weeks = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _weeks.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(Coaching c) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<CoachingRepository>().counter(
            c.id,
            context.read<SessionProvider>().user!,
            CounterOffer(
              durationWeeks: int.tryParse(_weeks.text),
              price: int.tryParse(_price.text),
              notes: _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      context.read<ApiService>().notify(type: 'coaching', refId: c.id);
      showSnack(context, 'Counter offer sent');
      goBack(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context
        .watch<LiveData<List<Coaching>>>()
        .data
        ?.where((x) => x.id == widget.coachingId)
        .firstOrNull;
    if (c == null || c.proposal == null) {
      return Scaffold(appBar: AppBar(title: const Text('Counter offer')), body: const LoadingView());
    }
    if (c.status != CoachingStatus.proposed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Counter offer')),
        body: EmptyView(icon: Icons.info_outline, title: 'Not available', message: 'Status is now ${c.status.label}.'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Counter offer')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ProposalCard(proposal: c.proposal!, label: 'CURRENT PROPOSAL'),
          const SizedBox(height: 20),
          const Text('What would you like to change?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _weeks,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Weeks', hintText: '${c.proposal!.durationWeeks}'),
                validator: (v) => Validators.number(v, min: 1, max: 52, optional: true, field: 'Weeks'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Price (EGP)', hintText: '${c.proposal!.price}'),
                validator: (v) => Validators.number(v, min: 0, max: 200000, optional: true, field: 'Price'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Explain your changes',
              hintText: 'e.g. Can we do 3 sessions a week instead of 4? I work late on Thursdays.',
              alignLabelWithHint: true,
            ),
            validator: (v) => (v == null || v.trim().length < 5) ? 'Please describe the changes' : null,
          ),
          const SizedBox(height: 12),
          BusyButton(label: 'Send counter offer', busy: _busy, onPressed: () => _submit(c)),
        ]),
      ),
    );
  }
}
