import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/widgets/common.dart';
import '../../models/pt_profile.dart';
import '../../providers/session_provider.dart';
import '../../providers/trainer_filter_provider.dart';
import '../../repositories/pt_repository.dart';

class TrainersScreen extends StatelessWidget {
  const TrainersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gymId = context.select<SessionProvider, String?>((s) => s.user?.gymId);
    // Approved trainers at the member's gym – re-subscribed when the gym changes.
    return StreamProvider<Set<String>>(
      key: ValueKey(gymId),
      initialData: const {},
      create: (c) => gymId == null ? Stream.value(const <String>{}) : c.read<PtRepository>().watchApprovedPtIds(gymId),
      catchError: (_, __) => const {},
      child: const _TrainersView(),
    );
  }
}

class _TrainersView extends StatefulWidget {
  const _TrainersView();

  @override
  State<_TrainersView> createState() => _TrainersViewState();
}

class _TrainersViewState extends State<_TrainersView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveData<List<PtProfile>>>();
    final myGymIds = context.watch<Set<String>>();
    final f = context.watch<TrainerFilterProvider>();
    final user = context.watch<SessionProvider>().user!;

    return Scaffold(
      appBar: AppBar(title: const Text('Trainers'), actions: const [ProfileAction()]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: f.setQuery,
            decoration: const InputDecoration(hintText: 'Search by name or specialty', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<TrainerScope>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: TrainerScope.all, label: Text('All')),
              ButtonSegment(value: TrainerScope.myGym, label: const Text('My gym'), enabled: user.gymId != null),
              const ButtonSegment(value: TrainerScope.online, label: Text('Online')),
            ],
            selected: {f.scope},
            onSelectionChanged: (s) => f.setScope(s.first),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            children: [
              FilterChip(
                label: const Text('4★ and up'),
                selected: f.minRating >= 4,
                onSelected: (v) => f.setMinRating(v ? 4 : 0),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Under EGP 1,000'),
                selected: f.maxPrice == 1000,
                onSelected: (v) => f.setMaxPrice(v ? 1000 : null),
              ),
              for (final s in AppConfig.specialties.take(5)) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(s),
                  selected: f.specialty == s,
                  onSelected: (v) => f.setSpecialty(v ? s : null),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LiveView<List<PtProfile>>(
            live: live,
            builder: (pts) {
              final list = f.apply(pts.where((p) => p.id != user.uid).toList(), myGymIds);
              if (list.isEmpty) {
                return EmptyView(
                  icon: Icons.person_search_outlined,
                  title: 'No trainers found',
                  message: f.scope == TrainerScope.myGym
                      ? 'No trainers are affiliated with your gym yet. Try "Online".'
                      : 'Try changing your filters.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => TrainerCard(pt: list[i], atMyGym: myGymIds.contains(list[i].id)),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class TrainerCard extends StatelessWidget {
  const TrainerCard({super.key, required this.pt, this.atMyGym = false});
  final PtProfile pt;
  final bool atMyGym;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      onTap: () => context.push('/trainers/${pt.id}'),
      child: Row(children: [
        UserAvatar(initials: pt.initials, url: pt.photoUrl, radius: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(pt.name,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              if (pt.verified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 16)),
            ]),
            Text([...pt.specialties.take(2), pt.modeLabel].join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 4),
            Row(children: [
              RatingStars(rating: pt.rating, size: 14),
              const SizedBox(width: 4),
              Text('${pt.rating.toStringAsFixed(1)} (${pt.reviewCount})', style: TextStyle(fontSize: 12, color: muted)),
              if (atMyGym) ...[const SizedBox(width: 8), const Tag('YOUR GYM')],
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(egp(pt.monthlyPrice), style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('/month', style: TextStyle(fontSize: 12, color: muted)),
        ]),
      ]),
    );
  }
}
