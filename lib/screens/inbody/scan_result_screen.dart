import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/widgets/common.dart';
import '../../models/scan.dart';
import '../../providers/session_provider.dart';
import '../../repositories/scan_repository.dart';
import 'inbody_screen.dart';
import 'share_scan.dart';

/// One scan. Readable by its owner, or by a PT it was explicitly shared with.
class ScanResultScreen extends StatelessWidget {
  const ScanResultScreen({super.key, required this.memberId, required this.scanId});
  final String memberId;
  final String scanId;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionProvider>().uid;
    final isOwner = me == memberId;
    return StreamProvider<LiveData<Scan?>>(
      initialData: const LiveData.loading(),
      create: (c) => c.read<ScanRepository>().watchScan(memberId, scanId).asLive(),
      child: Consumer<LiveData<Scan?>>(builder: (context, live, _) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => goBack(context)),
            title: const Text('InBody result'),
          ),
          body: Builder(builder: (_) {
            if (live.error != null) return ErrorView(error: live.error);
            if (live.loading) return const LoadingView();
            final s = live.data;
            if (s == null) return const EmptyView(icon: Icons.search_off, title: 'Scan not found');
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text(DateFormat.yMMMMd().format(s.scanDate),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              ScanSummaryView(scan: s),
              const SectionHeader('All values'),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(children: [
                  for (final m in kMetrics)
                    if (s[m.key] != null)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.label),
                        trailing: Text('${fmtNum(s[m.key]!)} ${m.unit}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                ]),
              ),
              if (s.imageUrl != null) ...[
                const SectionHeader('Original sheet'),
                GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(AppConfig.mediaUrl(s.imageUrl)!))),
                  ),
                  child: NetImage(url: s.imageUrl, height: 180, icon: Icons.description_outlined),
                ),
              ],
              const Disclaimer(),
              if (isOwner)
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push('/inbody/new'),
                      child: const Text('Scan again'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => shareScanWithTrainer(context, s),
                      child: Text(s.sharedWith.isEmpty ? 'Share with trainer' : 'Share again'),
                    ),
                  ),
                ]),
            ]);
          }),
        );
      }),
    );
  }
}
