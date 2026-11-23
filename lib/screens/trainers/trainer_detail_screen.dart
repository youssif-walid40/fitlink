import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/widgets/common.dart';
import '../../models/coaching.dart';
import '../../models/pt_profile.dart';
import '../../providers/session_provider.dart';
import '../../repositories/admin_repository.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/pt_repository.dart';
import '../gyms/gym_detail_screen.dart' show promptText;

class TrainerDetailScreen extends StatelessWidget {
  const TrainerDetailScreen({super.key, required this.ptId});
  final String ptId;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        StreamProvider<LiveData<PtProfile?>>(
          initialData: const LiveData.loading(),
          create: (c) => c.read<PtRepository>().watchPt(ptId).asLive(),
        ),
        StreamProvider<LiveData<List<Review>>>(
          initialData: const LiveData.loading(),
          create: (c) => c.read<PtRepository>().watchReviews(ptId).asLive(),
        ),
      ],
      child: Consumer<LiveData<PtProfile?>>(builder: (context, live, _) {
        if (live.error != null) return Scaffold(appBar: AppBar(), body: ErrorView(error: live.error));
        if (live.loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
        if (live.data == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyView(icon: Icons.person_off_outlined, title: 'Trainer not found'));
        }
        return _TrainerView(pt: live.data!);
      }),
    );
  }
}

class _TrainerView extends StatefulWidget {
  const _TrainerView({required this.pt});
  final PtProfile pt;

  @override
  State<_TrainerView> createState() => _TrainerViewState();
}

class _TrainerViewState extends State<_TrainerView> {
  bool _opening = false;

  PtProfile get pt => widget.pt;

  Future<void> _message() async {
    final me = context.read<SessionProvider>().user!;
    setState(() => _opening = true);
    try {
      final id = await context.read<ChatRepository>().openThread(
            meId: me.uid,
            meName: me.name,
            mePhoto: me.photoUrl,
            otherId: pt.id,
            otherName: pt.name,
            otherPhoto: pt.photoUrl,
          );
      if (mounted) context.push('/chat/$id');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionProvider>().user!;
    final coachings = context.watch<LiveData<List<Coaching>>>().data ?? const <Coaching>[];
    final open = coachings.where((c) => c.ptId == pt.id && c.memberId == me.uid && c.status.isOpen).firstOrNull;
    final reviews = context.watch<LiveData<List<Review>>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final isSelf = me.uid == pt.id;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => goBack(context)),
        actions: [
          if (isSelf) IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/pt/edit')),
          if (!isSelf)
            PopupMenuButton<String>(
              onSelected: (_) async {
                final reason = await promptText(context, title: 'Report ${pt.name}', hint: 'Describe the problem');
                if (reason == null || !context.mounted) return;
                await context.read<AdminRepository>().submitReport(
                    reporterId: me.uid, targetType: 'pt', targetId: pt.id, targetName: pt.name, reason: reason);
                if (context.mounted) showSnack(context, 'Thanks – our team will review it.');
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report profile'))],
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          UserAvatar(initials: pt.initials, url: pt.photoUrl, radius: 34),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pt.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text([...pt.specialties.take(3), pt.modeLabel].join(' · '), style: TextStyle(color: muted)),
              Text(
                'Rating ${pt.rating.toStringAsFixed(1)} · ${pt.reviewCount} reviews'
                '${pt.yearsExperience > 0 ? ' · ${pt.yearsExperience} yrs' : ''}',
                style: TextStyle(color: muted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        AppCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Monthly plan', style: TextStyle(color: muted, fontSize: 13)),
                Text(egp(pt.monthlyPrice), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ]),
            ),
            Text('Negotiable\nin chat', textAlign: TextAlign.right, style: TextStyle(color: muted, fontSize: 13)),
          ]),
        ),
        if (pt.bio.isNotEmpty) ...[
          const SectionHeader('About'),
          Text(pt.bio, style: const TextStyle(height: 1.45)),
        ],
        if (pt.transformations.isNotEmpty) ...[
          const SectionHeader('Transformations'),
          for (final t in pt.transformations) ...[
            Row(children: [
              Expanded(child: AspectRatio(aspectRatio: 1, child: NetImage(url: t.beforeUrl, label: 'Before', icon: Icons.person_outline))),
              const SizedBox(width: 10),
              Expanded(child: AspectRatio(aspectRatio: 1, child: NetImage(url: t.afterUrl, label: 'After', icon: Icons.person))),
            ]),
            if (t.caption.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.caption, style: TextStyle(color: muted, fontSize: 13))),
            const SizedBox(height: 10),
          ],
        ],
        const SectionHeader('Reviews'),
        if (reviews.data == null && reviews.error == null) const LinearProgressIndicator(),
        if (reviews.error != null) Text(friendlyError(reviews.error)),
        if (reviews.data != null && reviews.data!.isEmpty)
          Text('No reviews yet. Reviews come only from verified clients after a completed plan.',
              style: TextStyle(color: muted)),
        for (final r in reviews.data ?? const <Review>[]) ...[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.memberName, style: const TextStyle(fontWeight: FontWeight.w700))),
                RatingStars(rating: r.rating.toDouble(), size: 14),
              ]),
              if (r.comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.comment)),
              if (r.createdAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Verified client · ${DateFormat.yMMMd().format(r.createdAt!)}',
                      style: TextStyle(fontSize: 12, color: muted)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ]),
      bottomNavigationBar: isSelf || !me.isMember
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(children: [
                  Expanded(child: BusyButton(label: 'Message', outlined: true, busy: _opening, onPressed: _message)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => open != null
                          ? context.push('/coaching/${open.id}')
                          : context.push('/trainers/${pt.id}/request'),
                      child: Text(open != null ? 'View request' : 'Book a plan'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}
