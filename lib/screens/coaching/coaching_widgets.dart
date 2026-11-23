import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/coaching.dart';

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return DateFormat.MMMd().format(t);
}

class CoachingTile extends StatelessWidget {
  const CoachingTile({super.key, required this.coaching, required this.myUid, this.needsAction = false});
  final Coaching coaching;
  final String myUid;
  final bool needsAction;

  @override
  Widget build(BuildContext context) {
    final c = coaching;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      highlighted: needsAction,
      onTap: () => context.push('/coaching/${c.id}'),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        UserAvatar(initials: initialsOf(c.otherName(myUid)), url: c.otherPhoto(myUid), radius: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.otherName(myUid), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              c.proposal?.title ?? '${c.level} · ${c.mode == 'online' ? 'Online' : 'In gym'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          StatusChip(c.status),
          const SizedBox(height: 4),
          Text(timeAgo(c.updatedAt), style: TextStyle(fontSize: 11, color: muted)),
        ]),
      ]),
    );
  }
}

/// Compact proposal card – used in the coaching screen and as a chat bubble.
class ProposalCard extends StatelessWidget {
  const ProposalCard({super.key, required this.proposal, this.actions, this.label = 'WORKOUT PLAN PROPOSAL'});
  final PlanProposal proposal;
  final Widget? actions;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: muted)),
        const SizedBox(height: 6),
        Text(p.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          '${p.durationWeeks} weeks · ${p.sessionsPerWeek} sessions per week'
          '${p.nutrition != null ? ' · Nutrition guide included' : ''}',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 10),
        Text(egp(p.price), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (p.version > 1)
          Text('Revision ${p.version}', style: TextStyle(fontSize: 12, color: muted)),
        if (actions != null) ...[const SizedBox(height: 12), actions!],
      ]),
    );
  }
}

class WorkoutDayTile extends StatelessWidget {
  const WorkoutDayTile({super.key, required this.day, this.isToday = false, this.onTap});
  final WorkoutDay day;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      highlighted: isToday,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isToday ? AppColors.lime : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(day.day, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(day.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${day.exercises.length} exercises · ${day.minutes} min', style: TextStyle(color: muted, fontSize: 13)),
          ]),
        ),
        if (isToday) const Text('Today', style: TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

String todayShort() => DateFormat('E').format(DateTime.now());
