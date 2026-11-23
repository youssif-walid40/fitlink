import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/coaching.dart';
import '../../providers/session_provider.dart';
import '../../repositories/coaching_repository.dart';
import '../../services/api_service.dart';
import 'coaching_widgets.dart';

/// Member's "My plans" tab: the active plan (workout + nutrition) and all
/// requests / offers with trainers.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _nutrition = false;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user!;
    final live = context.watch<LiveData<List<Coaching>>>();

    return LiveView<List<Coaching>>(
      live: live,
      builder: (all) {
        final active = all.where((c) => c.status == CoachingStatus.active).toList();
        final current = active.isEmpty ? null : active.first;
        final open = all.where((c) => c.status.isOpen && c.status != CoachingStatus.active).toList();
        final past = all.where((c) => !c.status.isOpen).toList();

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 70,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('My plans'),
              if (current != null)
                Text('Assigned by ${current.ptName}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
            actions: const [ProfileAction()],
          ),
          body: all.isEmpty
              ? EmptyView(
                  icon: Icons.event_note_outlined,
                  title: 'No plans yet',
                  message: 'Hire a trainer to get a personalised workout and nutrition plan.',
                  action: FilledButton(onPressed: () => context.go('/home?tab=trainers'), child: const Text('Find a trainer')),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                  if (current != null && current.proposal != null) ...[
                    _ActivePlanCard(c: current),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: _TabButton(label: 'Workout', selected: !_nutrition, onTap: () => setState(() => _nutrition = false)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TabButton(label: 'Nutrition', selected: _nutrition, onTap: () => setState(() => _nutrition = true)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (!_nutrition)
                      for (final d in current.proposal!.workoutDays) ...[
                        WorkoutDayTile(
                          day: d,
                          isToday: d.day == todayShort(),
                          onTap: () => _openDay(context, current, d),
                        ),
                        const SizedBox(height: 8),
                      ]
                    else
                      _NutritionView(n: current.proposal!.nutrition),
                    if (!_nutrition && current.proposal!.workoutDays.isEmpty)
                      const Text('Your coach has not added workout days yet.'),
                  ],
                  if (open.isNotEmpty) ...[
                    const SectionHeader('Requests & offers'),
                    for (final c in open) ...[
                      CoachingTile(coaching: c, myUid: user.uid, needsAction: c.status == CoachingStatus.proposed),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (active.length > 1) ...[
                    const SectionHeader('Other active plans'),
                    for (final c in active.skip(1)) ...[
                      CoachingTile(coaching: c, myUid: user.uid),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (past.isNotEmpty) ...[
                    const SectionHeader('History'),
                    for (final c in past) ...[
                      CoachingTile(
                        coaching: c,
                        myUid: user.uid,
                        needsAction: c.status == CoachingStatus.completed && !c.reviewed,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ]),
        );
      },
    );
  }

  void _openDay(BuildContext context, Coaching c, WorkoutDay d) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d.day} · ${d.title}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${d.minutes} minutes', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (var i = 0; i < d.exercises.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 13, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                title: Text(d.exercises[i]),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Log this session'),
                onPressed: () async {
                  Navigator.pop(sheet);
                  try {
                    await context.read<CoachingRepository>().logSession(c.id);
                    if (context.mounted) {
                      context.read<ApiService>().notify(type: 'session', refId: c.id);
                      showSnack(context, 'Session logged 💪');
                    }
                  } catch (e) {
                    if (context.mounted) showSnack(context, friendlyError(e), error: true);
                  }
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ActivePlanCard extends StatelessWidget {
  const _ActivePlanCard({required this.c});
  final Coaching c;

  @override
  Widget build(BuildContext context) {
    final p = c.proposal!;
    final total = p.totalSessions == 0 ? 1 : p.totalSessions;
    return DarkCard(
      onTap: () => context.push('/coaching/${c.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ACTIVE PLAN',
            style: TextStyle(color: AppColors.lime, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(p.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (c.sessionsDone / total).clamp(0, 1).toDouble(),
            minHeight: 8,
            color: AppColors.lime,
            backgroundColor: Colors.white24,
          ),
        ),
        const SizedBox(height: 8),
        Text('Week ${c.currentWeek} of ${p.durationWeeks} · ${c.sessionsDone} of ${p.totalSessions} sessions done',
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => selected
      ? FilledButton(onPressed: onTap, style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), child: Text(label))
      : OutlinedButton(onPressed: onTap, style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)), child: Text(label));
}

class _NutritionView extends StatelessWidget {
  const _NutritionView({required this.n});
  final NutritionTargets? n;

  @override
  Widget build(BuildContext context) {
    if (n == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('This plan does not include a nutrition guide.'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: StatTile(label: 'Calories', value: '${n!.calories}')),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: 'Protein', value: '${n!.proteinG} g')),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: 'Water', value: '${fmtNum(n!.waterL)} L')),
      ]),
      if (n!.notes.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppCard(child: Text(n!.notes, style: const TextStyle(height: 1.45))),
      ],
    ]);
  }
}
