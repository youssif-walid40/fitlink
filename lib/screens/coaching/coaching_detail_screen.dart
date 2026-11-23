import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../logic/coaching_flow.dart';
import '../../models/app_user.dart';
import '../../models/coaching.dart';
import '../../models/scan.dart';
import '../../providers/session_provider.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/coaching_repository.dart';
import '../../repositories/scan_repository.dart';
import '../../services/api_service.dart';
import '../gyms/gym_detail_screen.dart' show promptText;
import 'coaching_widgets.dart';

/// The shared screen for one member↔PT coaching. Both sides watch the same
/// Firestore document, so every action updates the other screen instantly.
class CoachingDetailScreen extends StatelessWidget {
  const CoachingDetailScreen({super.key, required this.coachingId});
  final String coachingId;

  @override
  Widget build(BuildContext context) {
    return StreamProvider<LiveData<Coaching?>>(
      initialData: const LiveData.loading(),
      create: (c) => c.read<CoachingRepository>().watch(coachingId).asLive(),
      child: Consumer<LiveData<Coaching?>>(builder: (context, live, _) {
        if (live.error != null) return Scaffold(appBar: AppBar(), body: ErrorView(error: live.error));
        if (live.loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
        if (live.data == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyView(icon: Icons.search_off, title: 'Coaching not found'));
        }
        return _CoachingView(c: live.data!);
      }),
    );
  }
}

class _CoachingView extends StatefulWidget {
  const _CoachingView({required this.c});
  final Coaching c;

  @override
  State<_CoachingView> createState() => _CoachingViewState();
}

class _CoachingViewState extends State<_CoachingView> {
  bool _busy = false;
  Coaching get c => widget.c;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      context.read<ApiService>().notify(type: 'coaching', refId: c.id);
      showSnack(context, success);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openChat(AppUser me) async {
    final otherId = c.otherId(me.uid);
    final id = await context.read<ChatRepository>().openThread(
          meId: me.uid,
          meName: me.name,
          mePhoto: me.photoUrl,
          otherId: otherId,
          otherName: c.otherName(me.uid),
          otherPhoto: c.otherPhoto(me.uid),
        );
    if (mounted) context.push('/chat/$id');
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionProvider>().user!;
    final isPt = me.uid == c.ptId;
    final repo = context.read<CoachingRepository>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => goBack(context)),
        title: Text(c.otherName(me.uid), style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(tooltip: 'Chat', icon: const Icon(Icons.chat_bubble_outline), onPressed: () => _openChat(me)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        AppCard(
          child: Row(children: [
            UserAvatar(initials: initialsOf(c.otherName(me.uid)), url: c.otherPhoto(me.uid), radius: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isPt ? 'Client' : 'Coach', style: TextStyle(color: muted, fontSize: 12)),
                Text(c.otherName(me.uid), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(
                  '${AppConfig.goals[c.goal] ?? c.goal} · ${c.level} · ${c.mode == 'online' ? 'Online' : 'In gym'}',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ]),
            ),
            StatusChip(c.status),
          ]),
        ),
        if (c.message.isNotEmpty) ...[
          const SectionHeader('Request message'),
          AppCard(child: Text(c.message)),
        ],
        if (c.status == CoachingStatus.active && c.proposal != null) _ProgressCard(c: c),
        if (c.proposal != null) ...[
          SectionHeader(c.status == CoachingStatus.active || c.status == CoachingStatus.completed ? 'Agreed plan' : 'Proposal'),
          ProposalCard(proposal: c.proposal!),
          const SizedBox(height: 8),
          _PlanDetails(p: c.proposal!),
        ],
        if (c.counter != null && c.status == CoachingStatus.countered) ...[
          const SectionHeader('Counter offer from client'),
          AppCard(
            color: AppColors.warning.withValues(alpha: 0.08),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (c.counter!.durationWeeks != null) Text('Duration: ${c.counter!.durationWeeks} weeks'),
              if (c.counter!.price != null) Text('Price: ${egp(c.counter!.price!)}'),
              if (c.counter!.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.counter!.notes)),
            ]),
          ),
        ],
        if (isPt && c.sharedScanIds.isNotEmpty) _SharedScans(c: c),
        const SectionHeader('Timeline'),
        for (final e in c.events.reversed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.radio_button_checked, size: 18),
            title: Text(
              '${CoachingStatusX.parse(e.status).label} by ${e.by == c.ptId ? c.ptName : c.memberName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text([
              if (e.at != null) DateFormat.MMMd().add_jm().format(e.at!),
              if (e.note.isNotEmpty) e.note,
            ].join(' · ')),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _busy ? const LinearProgressIndicator() : _actions(context, me, isPt, repo),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, AppUser me, bool isPt, CoachingRepository repo) {
    final buttons = <Widget>[];
    void add(Widget w) => buttons.add(Expanded(child: w));

    if (isPt) {
      switch (c.status) {
        case CoachingStatus.requested:
          add(OutlinedButton(
            onPressed: () async {
              final reason = await promptText(context, title: 'Decline request', hint: 'Optional reason', ok: 'Decline');
              if (reason != null) await _run(() => repo.decline(c.id, me, reason), 'Request declined');
            },
            child: const Text('Decline'),
          ));
          add(FilledButton(onPressed: () => _run(() => repo.accept(c.id, me), 'Request accepted'), child: const Text('Accept')));
        case CoachingStatus.accepted:
          add(FilledButton.icon(
            icon: const Icon(Icons.edit_note),
            onPressed: () => context.push('/coaching/${c.id}/propose'),
            label: const Text('Send plan proposal'),
          ));
        case CoachingStatus.proposed:
          add(OutlinedButton(onPressed: () => context.push('/coaching/${c.id}/propose'), child: const Text('Revise proposal')));
        case CoachingStatus.countered:
          add(OutlinedButton(onPressed: () => context.push('/coaching/${c.id}/propose'), child: const Text('Revise')));
          add(FilledButton(onPressed: () => _run(() => repo.acceptCounter(c.id, me), 'Counter accepted – plan is active'), child: const Text('Accept counter')));
        case CoachingStatus.active:
          add(FilledButton(
            onPressed: () async {
              if (await confirm(context, title: 'Complete coaching?', message: 'The client will be asked to leave a review.', ok: 'Complete')) {
                await _run(() => repo.complete(c.id, me), 'Coaching marked as completed');
              }
            },
            child: const Text('Mark as completed'),
          ));
        default:
          break;
      }
    } else {
      switch (c.status) {
        case CoachingStatus.requested:
        case CoachingStatus.accepted:
        case CoachingStatus.countered:
          add(OutlinedButton(
            onPressed: () async {
              if (await confirm(context, title: 'Cancel request?', message: 'Your coach will be notified.', danger: true, ok: 'Cancel request')) {
                await _run(() => repo.cancel(c.id, me), 'Request cancelled');
              }
            },
            child: const Text('Cancel request'),
          ));
        case CoachingStatus.proposed:
          add(OutlinedButton(onPressed: () => context.push('/coaching/${c.id}/counter'), child: const Text('Counter')));
          add(FilledButton(
            onPressed: () => _run(() => repo.acceptProposal(c.id, me), 'Plan accepted – let\'s go! 💪'),
            child: const Text('Accept'),
          ));
        case CoachingStatus.active:
          add(OutlinedButton.icon(
            icon: const Icon(Icons.monitor_weight_outlined),
            onPressed: () => context.go('/home?tab=inbody'),
            label: const Text('Share InBody'),
          ));
          add(FilledButton(onPressed: () => context.go('/home?tab=plans'), child: const Text('Open plan')));
        case CoachingStatus.completed:
          if (CoachingFlow.canReview(c, me.uid)) {
            add(FilledButton.icon(
              icon: const Icon(Icons.star_outline),
              onPressed: () => context.push('/coaching/${c.id}/review'),
              label: const Text('Leave a review'),
            ));
          }
        default:
          break;
      }
    }
    if (buttons.isEmpty) {
      return Text(
        switch (c.status) {
          CoachingStatus.proposed when isPt => 'Waiting for the client to respond…',
          CoachingStatus.completed => c.reviewed ? 'Completed and reviewed. Thank you!' : 'Completed.',
          CoachingStatus.declined => 'This request was declined.',
          CoachingStatus.cancelled => 'This request was cancelled.',
          _ => 'Waiting for your coach…',
        },
        textAlign: TextAlign.center,
      );
    }
    return Row(children: [
      for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: 10), buttons[i]],
    ]);
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.c});
  final Coaching c;

  @override
  Widget build(BuildContext context) {
    final total = c.proposal!.totalSessions;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DarkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PROGRESS', style: TextStyle(color: AppColors.lime, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total == 0 ? 0 : (c.sessionsDone / total).clamp(0, 1).toDouble(),
            minHeight: 8,
            color: AppColors.lime,
            backgroundColor: Colors.white24,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 8),
          Text('Week ${c.currentWeek} of ${c.proposal!.durationWeeks} · ${c.sessionsDone} of $total sessions done',
              style: const TextStyle(color: Colors.white70)),
        ]),
      ),
    );
  }
}

class _PlanDetails extends StatelessWidget {
  const _PlanDetails({required this.p});
  final PlanProposal p;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Plan details', style: TextStyle(fontWeight: FontWeight.w700)),
        children: [
          for (final d in p.workoutDays)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: AppColors.limeSoft, child: Text(d.day, style: const TextStyle(fontSize: 12, color: AppColors.ink))),
              title: Text('${d.title} · ${d.minutes} min'),
              subtitle: Text(d.exercises.join(', ')),
            ),
          if (p.nutrition != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restaurant_outlined),
              title: Text('${p.nutrition!.calories} kcal · ${p.nutrition!.proteinG} g protein · ${fmtNum(p.nutrition!.waterL)} L water'),
              subtitle: p.nutrition!.notes.isEmpty ? null : Text(p.nutrition!.notes),
            ),
          if (p.notes.isNotEmpty)
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.notes), title: Text(p.notes)),
        ],
      );
}

/// Scans the client explicitly shared with this PT (security rules enforce it).
class _SharedScans extends StatelessWidget {
  const _SharedScans({required this.c});
  final Coaching c;

  @override
  Widget build(BuildContext context) {
    final me = context.read<SessionProvider>().uid!;
    return StreamBuilder<List<Scan>>(
      stream: context.read<ScanRepository>().watchSharedWith(c.memberId, me),
      builder: (context, snap) {
        final scans = snap.data ?? const <Scan>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('Shared InBody scans'),
          if (snap.hasError) Text(friendlyError(snap.error)),
          if (!snap.hasData && !snap.hasError) const LinearProgressIndicator(),
          for (final s in scans)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => context.push('/scan/${c.memberId}/${s.id}'),
                child: Row(children: [
                  const Icon(Icons.monitor_weight_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${DateFormat.yMMMd().format(s.scanDate)} · '
                      '${s['percentBodyFat'] != null ? '${fmtNum(s['percentBodyFat']!)}% fat' : ''}'
                      '${s['skeletalMuscleMass'] != null ? ' · ${fmtNum(s['skeletalMuscleMass']!)} kg muscle' : ''}',
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
