import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/coaching.dart';
import '../../models/pt_profile.dart';
import '../../providers/session_provider.dart';
import '../../repositories/pt_repository.dart';
import 'coaching_widgets.dart';

/// Trainer's home tab: incoming requests, negotiations and active clients.
class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user!;
    final live = context.watch<LiveData<List<Coaching>>>();

    return Scaffold(
      appBar: AppBar(title: const Text('Clients'), actions: const [ProfileAction()]),
      body: LiveView<List<Coaching>>(
        live: live,
        builder: (all) {
          final mine = all.where((c) => c.ptId == user.uid).toList();
          final reply = mine
              .where((c) => const {CoachingStatus.requested, CoachingStatus.accepted, CoachingStatus.countered}.contains(c.status))
              .toList();
          final waiting = mine.where((c) => c.status == CoachingStatus.proposed).toList();
          final active = mine.where((c) => c.status == CoachingStatus.active).toList();
          final past = mine.where((c) => !c.status.isOpen).toList();

          Widget section(String title, List<Coaching> list, {bool action = false}) => list.isEmpty
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SectionHeader('$title (${list.length})'),
                  for (final c in list) ...[
                    CoachingTile(coaching: c, myUid: user.uid, needsAction: action),
                    const SizedBox(height: 8),
                  ],
                ]);

          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            _ProfileStatusCard(uid: user.uid),
            if (mine.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EmptyView(
                  icon: Icons.groups_outlined,
                  title: 'No clients yet',
                  message: 'Complete your profile with a bio, price and transformations so members can find you.',
                ),
              ),
            section('Needs your reply', reply, action: true),
            section('Waiting for client', waiting),
            section('Active clients', active),
            section('Past', past),
          ]);
        },
      ),
    );
  }
}

class _ProfileStatusCard extends StatelessWidget {
  const _ProfileStatusCard({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PtProfile?>(
      stream: context.read<PtRepository>().watchPt(uid),
      builder: (context, snap) {
        final pt = snap.data;
        if (pt == null) return const SizedBox.shrink();
        final incomplete = pt.bio.isEmpty || pt.monthlyPrice == 0 || pt.specialties.isEmpty;
        return DarkCard(
          onTap: () => context.push('/pt/edit'),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  pt.verified ? 'PROFILE LIVE' : 'PENDING VERIFICATION',
                  style: const TextStyle(color: AppColors.lime, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  incomplete ? 'Complete your trainer profile' : 'Rating ${pt.rating.toStringAsFixed(1)} · ${pt.reviewCount} reviews',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                Text(
                  pt.verified ? 'Members can find and hire you.' : 'Our team will verify your profile soon.',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ]),
            ),
            const Icon(Icons.edit_outlined, color: AppColors.lime),
          ]),
        );
      },
    );
  }
}
