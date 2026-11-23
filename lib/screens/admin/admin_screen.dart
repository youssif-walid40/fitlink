import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/common.dart';
import '../../models/gym.dart';
import '../../models/pt_profile.dart';
import '../../repositories/admin_repository.dart';

/// Admin: verify trainers and gyms, handle reports. Admins cannot read
/// private health data (scans) – security rules don't allow it.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AdminRepository>();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          title: const Text('Review queue'),
          actions: const [ProfileAction()],
          bottom: const TabBar(tabs: [Tab(text: 'Trainers'), Tab(text: 'Gyms'), Tab(text: 'Reports')]),
        ),
        body: TabBarView(children: [
          _Queue<PtProfile>(
            stream: repo.watchUnverifiedPts(),
            emptyText: 'No trainers waiting for verification',
            tile: (pt) => ListTile(
              leading: UserAvatar(initials: pt.initials, url: pt.photoUrl),
              title: Text(pt.name),
              subtitle: Text(pt.bio.isEmpty ? 'Profile incomplete' : pt.bio, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => context.push('/trainers/${pt.id}'),
              trailing: FilledButton(onPressed: () => repo.setPtVerified(pt.id, true), child: const Text('Verify')),
            ),
          ),
          _Queue<Gym>(
            stream: repo.watchUnverifiedGyms(),
            emptyText: 'No gyms waiting for verification',
            tile: (g) => ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(g.name),
              subtitle: Text('${g.area} · ${g.tiers.length} tiers · ${g.photos.length} photos'),
              onTap: () => context.push('/gyms/${g.id}'),
              trailing: FilledButton(onPressed: () => repo.setGymVerified(g.id, true), child: const Text('Verify')),
            ),
          ),
          _Queue<Report>(
            stream: repo.watchReports(),
            emptyText: 'No open reports',
            tile: (r) => ListTile(
              leading: Icon(r.targetType == 'gym' ? Icons.storefront_outlined : Icons.person_outline),
              title: Text(r.targetName),
              subtitle: Text(r.reason),
              onTap: () => context.push(r.targetType == 'gym' ? '/gyms/${r.targetId}' : '/trainers/${r.targetId}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'unverify') {
                    if (r.targetType == 'gym') {
                      await repo.setGymVerified(r.targetId, false);
                    } else {
                      await repo.setPtVerified(r.targetId, false);
                    }
                  }
                  await repo.dismissReport(r.id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'unverify', child: Text('Hide listing & close')),
                  PopupMenuItem(value: 'dismiss', child: Text('Dismiss report')),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Queue<T> extends StatefulWidget {
  const _Queue({required this.stream, required this.tile, required this.emptyText});
  final Stream<List<T>> stream;
  final Widget Function(T item) tile;
  final String emptyText;

  @override
  State<_Queue<T>> createState() => _QueueState<T>();
}

class _QueueState<T> extends State<_Queue<T>> with AutomaticKeepAliveClientMixin {
  late final Stream<List<T>> _stream = widget.stream;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<List<T>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error);
        if (!snap.hasData) return const LoadingView();
        final items = snap.data!;
        if (items.isEmpty) return EmptyView(icon: Icons.task_alt, title: 'All clear', message: widget.emptyText);
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (_, i) => widget.tile(items[i]),
        );
      },
    );
  }
}
