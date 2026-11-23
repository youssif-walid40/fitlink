import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../logic/coaching_flow.dart';
import '../../models/coaching.dart';
import '../../providers/session_provider.dart';
import '../../services/api_service.dart';

/// Workflow step 8: verified review, only after completion. The review is
/// written by the backend, which checks the coaching really was completed.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.coachingId});
  final String coachingId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Tap the stars to rate your coach');
      return;
    }
    if (_comment.text.trim().length < 10) {
      setState(() => _error = 'Write at least a short sentence (10+ characters)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiService>().submitReview(
            coachingId: widget.coachingId,
            rating: _rating,
            comment: _comment.text.trim(),
          );
      if (!mounted) return;
      showSnack(context, 'Thanks for your review!');
      goBack(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<SessionProvider>().uid!;
    final c = context.watch<LiveData<List<Coaching>>>().data?.where((x) => x.id == widget.coachingId).firstOrNull;
    if (c == null) return Scaffold(appBar: AppBar(), body: const LoadingView());
    if (!CoachingFlow.canReview(c, uid)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const EmptyView(
          icon: Icons.rate_review_outlined,
          title: 'Review not available',
          message: 'You can review a coach once, after the coaching is completed.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Review ${c.ptName}')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('How was your coaching?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (i) => IconButton(
              iconSize: 42,
              onPressed: () => setState(() => _rating = i + 1),
              icon: Icon(i < _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.warning),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _comment,
          maxLines: 5,
          maxLength: 600,
          decoration: const InputDecoration(
            hintText: 'What results did you get? How was communication?',
            alignLabelWithHint: true,
          ),
        ),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        BusyButton(label: 'Submit review', busy: _busy, onPressed: _submit),
        const SizedBox(height: 8),
        Text('Your review is marked "Verified client" and cannot be edited by the coach.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}
