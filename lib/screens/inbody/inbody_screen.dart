import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/scan.dart';
import '../../providers/scan_history_provider.dart';
import '../../providers/session_provider.dart';
import 'share_scan.dart';

class InBodyScreen extends StatefulWidget {
  const InBodyScreen({super.key});

  @override
  State<InBodyScreen> createState() => _InBodyScreenState();
}

class _InBodyScreenState extends State<InBodyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ScanHistoryProvider>().load());
  }

  void _newScan() {
    final user = context.read<SessionProvider>().user!;
    if (!user.isPremium && user.scansUsed >= AppConfig.freeScanQuota) {
      showPremiumPrompt(
        context,
        'You have used your ${AppConfig.freeScanQuota} free InBody analyses. Premium unlocks unlimited scans and progress analysis.',
        () => context.push('/premium'),
      );
      return;
    }
    context.push('/inbody/new');
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<ScanHistoryProvider>();
    final user = context.watch<SessionProvider>().user!;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Widget body;
    if (history.loading && !history.loaded) {
      body = const LoadingView(message: 'Loading your scans…');
    } else if (history.error != null && history.scans.isEmpty) {
      body = ErrorView(error: history.error, onRetry: () => history.load(force: true));
    } else if (history.scans.isEmpty) {
      body = EmptyView(
        icon: Icons.document_scanner_outlined,
        title: 'Understand your InBody results',
        message: 'Photograph your InBody printout and get a plain-language explanation with practical next steps.',
        action: FilledButton.icon(onPressed: _newScan, icon: const Icon(Icons.camera_alt_outlined), label: const Text('Scan my sheet')),
      );
    } else {
      final s = history.latest!;
      body = RefreshIndicator(
        onRefresh: () => history.load(force: true),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (!user.isPremium) _QuotaBanner(used: user.scansUsed),
          _LatestScan(scan: s),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _newScan, child: const Text('Scan again'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => shareScanWithTrainer(context, s),
                child: Text(s.sharedWith.isEmpty ? 'Share with trainer' : 'Shared ✓'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          AppCard(
            onTap: history.canAnalyzeProgress ? () => context.push('/inbody/progress') : null,
            child: Row(children: [
              Icon(Icons.insights, color: history.canAnalyzeProgress ? null : muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Progress over time', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    history.canAnalyzeProgress
                        ? 'Charts and an AI summary of ${history.scans.length} scans'
                        : 'Add one more scan to unlock progress analysis',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ]),
              ),
              if (history.canAnalyzeProgress) const Icon(Icons.chevron_right),
            ]),
          ),
          const SectionHeader('History'),
          for (final h in history.scans)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(backgroundColor: AppColors.limeSoft, child: Icon(Icons.description_outlined, color: AppColors.ink)),
              title: Text(DateFormat.yMMMd().format(h.scanDate)),
              subtitle: Text(scanHeadline(h)),
              trailing: h.sharedWith.isNotEmpty ? const Icon(Icons.people_outline, size: 18) : const Icon(Icons.chevron_right),
              onTap: () => context.push('/scan/${user.uid}/${h.id}'),
            ),
          const Disclaimer(),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('InBody analysis'),
          Text('Scan read and explained by AI',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: muted)),
        ]),
        actions: const [ProfileAction()],
      ),
      body: body,
    );
  }
}

class _QuotaBanner extends StatelessWidget {
  const _QuotaBanner({required this.used});
  final int used;

  @override
  Widget build(BuildContext context) {
    final left = (AppConfig.freeScanQuota - used).clamp(0, AppConfig.freeScanQuota);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        color: AppColors.limeSoft,
        onTap: () => context.push('/premium'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.workspace_premium_outlined, color: AppColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text('$left of ${AppConfig.freeScanQuota} free analyses left. Go Premium for unlimited scans.',
                style: const TextStyle(color: AppColors.ink, fontSize: 13)),
          ),
          const Icon(Icons.chevron_right, color: AppColors.ink),
        ]),
      ),
    );
  }
}

class _LatestScan extends StatelessWidget {
  const _LatestScan({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) => ScanSummaryView(scan: scan);
}

/// Three headline tiles + dark summary + recommended next steps (wireframe layout).
class ScanSummaryView extends StatelessWidget {
  const ScanSummaryView({super.key, required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    String v(String key, String unit) => scan[key] == null ? '–' : '${fmtNum(scan[key]!)}$unit';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: StatTile(label: 'Body fat', value: v('percentBodyFat', '%'))),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: 'Muscle mass', value: v('skeletalMuscleMass', ' kg'))),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: 'Body water', value: v('totalBodyWater', ' L'))),
      ]),
      const SizedBox(height: 12),
      DarkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your summary', style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Text(scan.summary.isEmpty ? 'No summary available.' : scan.summary,
              style: const TextStyle(color: Colors.white, height: 1.45)),
        ]),
      ),
      if (scan.nextSteps.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Recommended next steps', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            for (final step in scan.nextSteps)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 7)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step, style: const TextStyle(height: 1.4))),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}
