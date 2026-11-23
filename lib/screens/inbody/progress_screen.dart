import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../logic/progress_calculator.dart';
import '../../models/scan.dart';
import '../../providers/scan_history_provider.dart';
import '../../providers/session_provider.dart';
import '../../repositories/scan_repository.dart';
import '../../services/api_service.dart';
import 'share_scan.dart';

/// Progress-over-time analysis:
///  * numbers: ProgressCalculator (deterministic, unit-tested)
///  * charts:  fl_chart, one metric at a time
///  * words:   the LLM only receives the computed numbers + goal
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  String _metric = 'percentBodyFat';
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ScanHistoryProvider>().load());
  }

  Future<void> _generate(ProgressResult r) async {
    final user = context.read<SessionProvider>().user!;
    if (!user.isPremium && user.progressUsed >= AppConfig.freeProgressQuota) {
      showPremiumPrompt(context, 'Your free progress analysis has been used. Premium unlocks unlimited progress reports.',
          () => context.push('/premium'));
      return;
    }
    final api = context.read<ApiService>();
    final repo = context.read<ScanRepository>();
    setState(() => _generating = true);
    try {
      final numbers = r.toJson();
      final ai = await api.analyzeProgress(numbers);
      await repo.saveReport(user.uid,
          narrative: ai.narrative, focus: ai.focus, fromScanId: r.fromScanId, toScanId: r.toScanId, numbers: numbers);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.needsPremium) {
        showPremiumPrompt(context, e.message, () => context.push('/premium'));
      } else {
        showSnack(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<ScanHistoryProvider>();
    final user = context.watch<SessionProvider>().user!;

    if (!history.loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Progress')),
        body: history.error != null ? ErrorView(error: history.error, onRetry: () => history.load(force: true)) : const LoadingView(),
      );
    }
    if (!history.canAnalyzeProgress) {
      return Scaffold(
        appBar: AppBar(title: const Text('Progress')),
        body: EmptyView(
          icon: Icons.insights,
          title: 'Need two scans',
          message: 'Progress analysis compares at least two confirmed InBody scans.',
          action: FilledButton(onPressed: () => context.push('/inbody/new'), child: const Text('Add a scan')),
        ),
      );
    }

    final points = history.scans.map(ScanPoint.fromScan).toList()..sort((a, b) => a.date.compareTo(b.date));
    final result = ProgressCalculator.compute(points, user.goal);
    final available = result.trends.map((t) => t.key).toList();
    if (!available.contains(_metric)) _metric = available.first;
    final metric = metricByKey(_metric);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text(
          '${result.scanCount} scans · ${DateFormat.yMMMd().format(result.from)} → ${DateFormat.yMMMd().format(result.to)}'
          ' · ${result.weeks.toStringAsFixed(1)} weeks · Goal: ${AppConfig.goals[result.goal]}',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatTile(label: 'Improved', value: '${result.improved.length}')),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Needs work', value: '${result.worsened.length}')),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Stable', value: '${result.trends.length - result.improved.length - result.worsened.length}')),
        ]),
        const SectionHeader('History'),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final k in available) ...[
              ChoiceChip(
                label: Text(metricByKey(k).label),
                selected: k == _metric,
                onSelected: (_) => setState(() => _metric = k),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(8, 20, 20, 8),
          child: SizedBox(height: 220, child: _MetricChart(points: points, metric: metric)),
        ),
        const SectionHeader('Changes'),
        for (final t in result.trends) _TrendRow(t: t),
        const SectionHeader('AI progress analysis'),
        StreamBuilder<ProgressReport?>(
          stream: context.read<ScanRepository>().watchLatestReport(user.uid),
          builder: (context, snap) {
            final report = snap.data;
            final upToDate = report != null && report.toScanId == result.toScanId && report.fromScanId == result.fromScanId;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (report != null)
                DarkCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(upToDate ? 'Your progress' : 'Previous analysis',
                        style: const TextStyle(color: AppColors.lime, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(report.narrative, style: const TextStyle(color: Colors.white, height: 1.45)),
                    if (report.focus.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Focus next', style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w700)),
                      for (final f in report.focus)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('• $f', style: const TextStyle(color: Colors.white)),
                        ),
                    ],
                  ]),
                ),
              if (!upToDate) ...[
                const SizedBox(height: 12),
                BusyButton(
                  label: report == null ? 'Generate AI analysis' : 'Update analysis with latest scan',
                  icon: Icons.auto_awesome,
                  busy: _generating,
                  onPressed: () => _generate(result),
                ),
                if (!user.isPremium)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Free accounts include ${AppConfig.freeProgressQuota} progress analysis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
              ],
            ]);
          },
        ),
        const Disclaimer(),
      ]),
    );
  }
}

class _MetricChart extends StatelessWidget {
  const _MetricChart({required this.points, required this.metric});
  final List<ScanPoint> points;
  final InBodyMetric metric;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        if (points[i].values[metric.key] != null) FlSpot(i.toDouble(), points[i].values[metric.key]!),
    ];
    if (spots.isEmpty) return const Center(child: Text('No data for this metric'));
    final ys = spots.map((s) => s.y);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.25).clamp(0.5, double.infinity).toDouble();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, meta) => Text(fmtNum(v), style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 26,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= points.length || (v - i).abs() > 0.01) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat.MMMd().format(points[i].date), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 3,
            color: onSurface,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppColors.lime.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.t});
  final MetricTrend t;

  @override
  Widget build(BuildContext context) {
    final m = metricByKey(t.key);
    final color = switch (t.assessment) {
      Assessment.improved => AppColors.success,
      Assessment.worsened => AppColors.danger,
      Assessment.stable => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final icon = switch (t.trend) {
      Trend.up => Icons.arrow_upward,
      Trend.down => Icons.arrow_downward,
      Trend.flat => Icons.remove,
    };
    final sign = t.change > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${fmtNum(t.first)} → ${fmtNum(t.last)} ${m.unit}',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: color),
              Text('$sign${fmtNum(t.change, digits: 2)} ${m.unit}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ]),
            if (t.perWeek != 0)
              Text('${t.perWeek > 0 ? '+' : ''}${fmtNum(t.perWeek, digits: 2)}/week',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ]),
      ),
    );
  }
}
