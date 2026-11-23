import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/app_user.dart';
import '../../models/gym.dart';
import '../../models/pt_profile.dart';
import '../../providers/gym_filter_provider.dart';
import '../../providers/session_provider.dart';
import '../../repositories/admin_repository.dart';
import '../../repositories/gym_repository.dart';
import '../../repositories/pt_repository.dart';
import '../../repositories/user_repository.dart';
import '../trainers/trainers_screen.dart';

class GymDetailScreen extends StatelessWidget {
  const GymDetailScreen({super.key, required this.gymId});
  final String gymId;

  @override
  Widget build(BuildContext context) {
    return StreamProvider<LiveData<Gym?>>(
      initialData: const LiveData.loading(),
      create: (c) => c.read<GymRepository>().watchGym(gymId).asLive(),
      child: Consumer<LiveData<Gym?>>(builder: (context, live, _) {
        if (live.error != null) {
          return Scaffold(appBar: AppBar(), body: ErrorView(error: live.error));
        }
        if (live.loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
        final gym = live.data;
        if (gym == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyView(icon: Icons.storefront_outlined, title: 'Gym not found'),
          );
        }
        return _GymDetail(gym: gym);
      }),
    );
  }
}

class _GymDetail extends StatelessWidget {
  const _GymDetail({required this.gym});
  final Gym gym;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user!;
    final km = context.read<GymFilterProvider>().distanceTo(gym);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final isMyGym = user.gymId == gym.id;
    final isOwner = user.uid == gym.ownerId;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => goBack(context)),
          actions: [
            if (isOwner)
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/owner/gym')),
            if (!isOwner)
              PopupMenuButton<String>(
                onSelected: (_) => _report(context, user),
                itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report listing'))],
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: gym.photos.isEmpty
                ? const NetImage(radius: 0, icon: Icons.storefront_outlined)
                : PageView(children: [for (final p in gym.photos) NetImage(url: p, radius: 0)]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          sliver: SliverList.list(children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (gym.isSponsoredNow) const Tag('SPONSORED'),
              if (gym.verified) const Tag('VERIFIED', icon: Icons.verified, color: AppColors.limeSoft, textColor: AppColors.ink),
              if (isMyGym) const Tag('YOUR GYM', color: AppColors.ink, textColor: AppColors.lime),
            ]),
            const SizedBox(height: 8),
            Text(gym.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              [gym.area, '${km.toStringAsFixed(1)} km away', if (gym.openHours.isNotEmpty) gym.openHours].join(' · '),
              style: TextStyle(color: muted),
            ),
            if (gym.description.isNotEmpty) ...[
              const SectionHeader('About'),
              Text(gym.description, style: const TextStyle(height: 1.45)),
            ],
            const SectionHeader('Membership tiers'),
            if (gym.tiers.isEmpty) Text('No tiers listed yet.', style: TextStyle(color: muted)),
            for (final t in gym.tiers) ...[
              _TierCard(
                tier: t,
                current: isMyGym && user.gymTier == t.name,
                onJoin: user.isMember ? () => _join(context, user, t) : null,
              ),
              const SizedBox(height: 10),
            ],
            if (gym.facilities.isNotEmpty) ...[
              const SectionHeader('Facilities'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in gym.facilities) Chip(label: Text(f), avatar: const Icon(Icons.check, size: 16)),
              ]),
            ],
            if (gym.policies.isNotEmpty) ...[
              const SectionHeader('Policies'),
              for (final p in gym.policies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 6)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p)),
                  ]),
                ),
            ],
            const SectionHeader('Location'),
            if (gym.address.isNotEmpty) Text(gym.address, style: TextStyle(color: muted)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 170,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(gym.lat, gym.lng),
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.fitlink.app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(gym.lat, gym.lng),
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, size: 36, color: AppColors.ink),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            _GymTrainers(gym: gym),
            if (user.isPt) _AffiliationAction(gym: gym, user: user),
            if (isMyGym && user.isMember) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () async {
                  if (await confirm(context, title: 'Leave gym?', message: 'You will be removed from ${gym.name}.', danger: true, ok: 'Leave')) {
                    if (context.mounted) await context.read<UserRepository>().leaveGym(user);
                  }
                },
                child: const Text('Leave this gym'),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Future<void> _join(BuildContext context, AppUser user, GymTier tier) async {
    final ok = await confirm(
      context,
      title: 'Join ${gym.name}',
      message: '${tier.name} – ${egp(tier.price)} per ${tier.period}.\n\nPayment is simulated in this prototype.',
      ok: 'Pay & join',
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<UserRepository>().joinGym(user, gym, tier);
      if (context.mounted) showSnack(context, 'Welcome to ${gym.name}! 🎉');
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _report(BuildContext context, AppUser user) async {
    final reason = await promptText(context, title: 'Report ${gym.name}', hint: 'What is wrong with this listing?');
    if (reason == null || !context.mounted) return;
    await context.read<AdminRepository>().submitReport(
          reporterId: user.uid,
          targetType: 'gym',
          targetId: gym.id,
          targetName: gym.name,
          reason: reason,
        );
    if (context.mounted) showSnack(context, 'Thanks – our team will review it.');
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.current, this.onJoin});
  final GymTier tier;
  final bool current;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) => AppCard(
        highlighted: current,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tier.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('${egp(tier.price)} / ${tier.period}', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (tier.perks.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tier.perks.join(' · '),
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ]),
          ),
          if (current)
            const Tag('CURRENT', color: AppColors.lime, textColor: AppColors.ink)
          else if (onJoin != null)
            FilledButton(
              onPressed: onJoin,
              style: FilledButton.styleFrom(minimumSize: const Size(70, 40)),
              child: const Text('Join'),
            ),
        ]),
      );
}

class _GymTrainers extends StatelessWidget {
  const _GymTrainers({required this.gym});
  final Gym gym;

  @override
  Widget build(BuildContext context) {
    final pts = context.watch<LiveData<List<PtProfile>>>().data ?? const <PtProfile>[];
    return StreamBuilder<Set<String>>(
      stream: context.read<PtRepository>().watchApprovedPtIds(gym.id),
      builder: (context, snap) {
        final ids = snap.data ?? const <String>{};
        final list = pts.where((p) => ids.contains(p.id)).toList();
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('Trainers at this gym'),
          for (final p in list) ...[TrainerCard(pt: p), const SizedBox(height: 10)],
        ]);
      },
    );
  }
}

class _AffiliationAction extends StatelessWidget {
  const _AffiliationAction({required this.gym, required this.user});
  final Gym gym;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PtRepository>();
    return StreamBuilder<List<Affiliation>>(
      stream: repo.watchPtAffiliations(user.uid),
      builder: (context, snap) {
        final mine = (snap.data ?? const <Affiliation>[]).where((a) => a.gymId == gym.id).firstOrNull;
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: mine == null
              ? FilledButton.icon(
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Request to coach at this gym'),
                  onPressed: () async {
                    try {
                      await repo.requestAffiliation(ptId: user.uid, ptName: user.name, gym: gym);
                      if (context.mounted) showSnack(context, 'Request sent to the gym owner');
                    } catch (e) {
                      if (context.mounted) showSnack(context, friendlyError(e), error: true);
                    }
                  },
                )
              : AppCard(
                  child: Row(children: [
                    Icon(mine.status == 'approved' ? Icons.verified : Icons.hourglass_top),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(switch (mine.status) {
                        'approved' => 'You are listed as a trainer at this gym.',
                        'rejected' => 'The gym declined your affiliation request.',
                        _ => 'Affiliation request pending owner approval.',
                      }),
                    ),
                  ]),
                ),
        );
      },
    );
  }
}

/// Small dialog that asks for one line of text.
Future<String?> promptText(BuildContext context, {required String title, String? hint, String ok = 'Send'}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        maxLength: 300,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (ctrl.text.trim().length >= 3) Navigator.pop(c, ctrl.text.trim());
          },
          child: Text(ok),
        ),
      ],
    ),
  );
}
