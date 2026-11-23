import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/gym.dart';
import '../../models/pt_profile.dart';
import '../../providers/session_provider.dart';
import '../../repositories/gym_repository.dart';
import '../../repositories/pt_repository.dart';
import '../../services/api_service.dart';
import '../gyms/gyms_screen.dart' show GymCard;

class OwnerDashboardScreen extends StatelessWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.select<SessionProvider, String>((s) => s.uid!);
    return StreamProvider<LiveData<Gym?>>(
      initialData: const LiveData.loading(),
      create: (c) => c.read<GymRepository>().watchOwnerGym(uid).asLive(),
      child: Scaffold(
        appBar: AppBar(title: const Text('My gym'), actions: const [ProfileAction()]),
        body: Consumer<LiveData<Gym?>>(builder: (context, live, _) {
          if (live.error != null) return ErrorView(error: live.error);
          if (live.loading) return const LoadingView();
          final gym = live.data;
          if (gym == null) {
            return EmptyView(
              icon: Icons.storefront_outlined,
              title: 'List your gym on FitLink',
              message: 'Add your tiers, prices, photos and facilities so nearby members can find you.',
              action: FilledButton(onPressed: () => context.push('/owner/gym'), child: const Text('Create listing')),
            );
          }
          return _Dashboard(gym: gym);
        }),
      ),
    );
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard({required this.gym});
  final Gym gym;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late Stream<List<GymMember>> _members;
  late Stream<List<Affiliation>> _affiliations;
  bool _boosting = false;

  @override
  void initState() {
    super.initState();
    _members = context.read<GymRepository>().watchMembers(widget.gym.id);
    _affiliations = context.read<PtRepository>().watchGymAffiliations(widget.gym.id);
  }

  Future<void> _boost(int days, int price) async {
    final ok = await confirm(
      context,
      title: 'Sponsor for $days days',
      message: '${egp(price)} – your gym appears at the top of the nearby list with a "Sponsored" label.\n\n'
          'Payment is simulated in this prototype.',
      ok: 'Pay & boost',
    );
    if (!ok || !mounted) return;
    setState(() => _boosting = true);
    try {
      await context.read<ApiService>().sponsorGym(widget.gym.id, days);
      if (mounted) showSnack(context, 'Your listing is now sponsored 🚀');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _boosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      if (!gym.verified)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: AppCard(
            color: AppColors.limeSoft,
            child: Row(children: [
              Icon(Icons.hourglass_top, color: AppColors.ink),
              SizedBox(width: 10),
              Expanded(child: Text('Pending verification – members will see your gym once approved.', style: TextStyle(color: AppColors.ink))),
            ]),
          ),
        ),
      GymCard(gym: gym),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: () => context.push('/owner/gym'), icon: const Icon(Icons.edit_outlined), label: const Text('Edit listing')),
      const SectionHeader('Overview'),
      StreamBuilder<List<GymMember>>(
        stream: _members,
        builder: (context, snap) {
          final members = snap.data ?? const <GymMember>[];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: StatTile(label: 'Members', value: snap.hasData ? '${members.length}' : '–')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Tiers', value: '${gym.tiers.length}')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Photos', value: '${gym.photos.length}')),
            ]),
            if (members.isNotEmpty) ...[
              const SectionHeader('Recent members'),
              for (final m in members.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(initials: initialsOf(m.name), radius: 18),
                  title: Text(m.name),
                  subtitle: Text(m.tier),
                  trailing: m.joinedAt == null ? null : Text(DateFormat.MMMd().format(m.joinedAt!), style: TextStyle(color: muted)),
                ),
            ],
          ]);
        },
      ),
      const SectionHeader('Sponsored placement'),
      gym.isSponsoredNow
          ? DarkCard(
              child: Text(
                'Sponsored${gym.sponsoredUntil == null ? '' : ' until ${DateFormat.yMMMd().format(gym.sponsoredUntil!)}'}. '
                'Your gym is shown first in the nearby list.',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Appear at the top of the nearby list with a featured banner.', style: TextStyle(color: muted)),
              const SizedBox(height: 10),
              if (_boosting) const LinearProgressIndicator(),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: _boosting || !gym.verified ? null : () => _boost(7, 500), child: const Text('7 days · EGP 500'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: _boosting || !gym.verified ? null : () => _boost(30, 1500), child: const Text('30 days · EGP 1,500'))),
              ]),
            ]),
      const SectionHeader('Trainer affiliation requests'),
      StreamBuilder<List<Affiliation>>(
        stream: _affiliations,
        builder: (context, snap) {
          if (snap.hasError) return Text(friendlyError(snap.error));
          final list = snap.data ?? const <Affiliation>[];
          if (list.isEmpty) return Text('No requests yet.', style: TextStyle(color: muted));
          final repo = context.read<PtRepository>();
          return Column(children: [
            for (final a in list)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  UserAvatar(initials: initialsOf(a.ptName), radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => context.push('/trainers/${a.ptId}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.ptName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(a.status, style: TextStyle(fontSize: 12, color: muted)),
                      ]),
                    ),
                  ),
                  if (a.status == 'pending') ...[
                    IconButton(
                      tooltip: 'Reject',
                      icon: const Icon(Icons.close),
                      onPressed: () => repo.setAffiliationStatus(a.id, 'rejected'),
                    ),
                    IconButton.filled(
                      tooltip: 'Approve',
                      icon: const Icon(Icons.check),
                      onPressed: () => repo.setAffiliationStatus(a.id, 'approved'),
                    ),
                  ] else if (a.status == 'approved')
                    TextButton(onPressed: () => repo.setAffiliationStatus(a.id, 'rejected'), child: const Text('Remove')),
                ]),
              ),
          ]);
        },
      ),
    ]);
  }
}
