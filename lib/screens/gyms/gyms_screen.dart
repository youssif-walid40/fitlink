import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/gym.dart';
import '../../providers/gym_filter_provider.dart';

class GymsScreen extends StatefulWidget {
  const GymsScreen({super.key});

  @override
  State<GymsScreen> createState() => _GymsScreenState();
}

class _GymsScreenState extends State<GymsScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final f = context.read<GymFilterProvider>();
      _search.text = f.query;
      if (!f.position.live) f.locate();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveData<List<Gym>>>();
    final filter = context.watch<GymFilterProvider>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nearby gyms'),
          Text(
            filter.locating
                ? 'Finding your location…'
                : filter.sort == GymSort.price
                    ? 'Sorted by price'
                    : 'Sorted by distance',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Use my location',
            onPressed: filter.locating ? null : filter.locate,
            icon: filter.locating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(filter.position.live ? Icons.my_location : Icons.location_searching),
          ),
          const ProfileAction(),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: filter.setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search gyms or areas',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: filter.query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            filter.setQuery('');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ToggleButton(label: 'Map', selected: filter.showMap, onTap: () => filter.toggleMap(true)),
            const SizedBox(width: 6),
            _ToggleButton(label: 'List', selected: !filter.showMap, onTap: () => filter.toggleMap(false)),
          ]),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              ActionChip(
                avatar: Icon(Icons.tune, size: 18, color: filter.hasFilters ? AppColors.ink : null),
                label: Text(filter.hasFilters ? 'Filters on' : 'Filters'),
                backgroundColor: filter.hasFilters ? AppColors.lime : null,
                labelStyle: filter.hasFilters ? const TextStyle(color: AppColors.ink) : null,
                onPressed: () => _openFilters(context),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Nearest'),
                selected: filter.sort == GymSort.distance,
                onSelected: (_) => filter.setSort(GymSort.distance),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Cheapest'),
                selected: filter.sort == GymSort.price,
                onSelected: (_) => filter.setSort(GymSort.price),
              ),
              for (final f in ['Women-only hours', 'Pool', 'Open 24/7']) ...[
                const SizedBox(width: 8),
                FilterChip(label: Text(f), selected: filter.facilities.contains(f), onSelected: (_) => filter.toggleFacility(f)),
              ],
            ],
          ),
        ),
        if (filter.locationNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(filter.locationNote!, style: const TextStyle(fontSize: 12))),
            ]),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: LiveView<List<Gym>>(
            live: live,
            onRetry: () => setState(() {}),
            builder: (gyms) {
              final results = filter.apply(gyms);
              if (results.isEmpty) {
                return EmptyView(
                  icon: Icons.search_off,
                  title: gyms.isEmpty ? 'No gyms listed yet' : 'No gyms match',
                  message: gyms.isEmpty ? 'Check back soon.' : 'Try a different search or clear filters.',
                  action: filter.hasFilters
                      ? OutlinedButton(onPressed: filter.clear, child: const Text('Clear filters'))
                      : null,
                );
              }
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: filter.showMap
                    ? _GymMap(key: const ValueKey('map'), results: results, filter: filter)
                    : _GymList(key: const ValueKey('list'), results: results, onRefresh: filter.locate),
              );
            },
          ),
        ),
      ]),
    );
  }

  void _openFilters(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<GymFilterProvider>(),
          child: const _FilterSheet(),
        ),
      );
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 50,
        child: selected
            ? FilledButton(onPressed: onTap, style: FilledButton.styleFrom(minimumSize: const Size(60, 50)), child: Text(label))
            : OutlinedButton(onPressed: onTap, style: OutlinedButton.styleFrom(minimumSize: const Size(60, 50)), child: Text(label)),
      );
}

class _GymList extends StatelessWidget {
  const _GymList({super.key, required this.results, required this.onRefresh});
  final List<GymWithDistance> results;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => GymCard(gym: results[i].gym, km: results[i].km),
        ),
      );
}

class GymCard extends StatelessWidget {
  const GymCard({super.key, required this.gym, this.km});
  final Gym gym;
  final double? km;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final details = [
      if (km != null) '${km!.toStringAsFixed(1)} km',
      if (gym.minPrice != null) 'from ${egp(gym.minPrice!)}/mo',
    ].join(' · ');
    return AppCard(
      highlighted: gym.isSponsoredNow,
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/gyms/${gym.id}'),
      child: Row(children: [
        NetImage(url: gym.photos.isEmpty ? null : gym.photos.first, width: 64, height: 64, radius: 10),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (gym.isSponsoredNow)
              Text('SPONSORED',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: muted)),
            Text(gym.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            Text(details, style: TextStyle(color: muted, fontSize: 13)),
            if (gym.facilities.isNotEmpty)
              Text(gym.facilities.take(3).join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 13)),
          ]),
        ),
        const Icon(Icons.chevron_right),
      ]),
    );
  }
}

class _GymMap extends StatelessWidget {
  const _GymMap({super.key, required this.results, required this.filter});
  final List<GymWithDistance> results;
  final GymFilterProvider filter;

  @override
  Widget build(BuildContext context) {
    final me = LatLng(filter.position.lat, filter.position.lng);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(initialCenter: me, initialZoom: 12.5),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.fitlink.app',
            ),
            MarkerLayer(markers: [
              Marker(
                point: me,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
              for (final r in results)
                Marker(
                  point: LatLng(r.gym.lat, r.gym.lng),
                  width: 150,
                  height: 56,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => context.push('/gyms/${r.gym.id}'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: r.gym.isSponsoredNow ? AppColors.lime : AppColors.ink,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          r.gym.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: r.gym.isSponsoredNow ? AppColors.ink : Colors.white,
                          ),
                        ),
                      ),
                      const Icon(Icons.location_on, color: AppColors.ink, size: 26),
                    ]),
                  ),
                ),
            ]),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context) {
    final f = context.watch<GymFilterProvider>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              TextButton(onPressed: f.clear, child: const Text('Reset')),
            ]),
            const SizedBox(height: 8),
            Text('Max distance: ${f.maxDistanceKm == null ? 'Any' : '${f.maxDistanceKm!.round()} km'}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(
              value: f.maxDistanceKm ?? 30,
              min: 1,
              max: 30,
              divisions: 29,
              label: f.maxDistanceKm == null ? 'Any' : '${f.maxDistanceKm!.round()} km',
              onChanged: (v) => f.setMaxDistance(v >= 30 ? null : v),
            ),
            Text('Max monthly price: ${f.maxPrice == null ? 'Any' : egp(f.maxPrice!)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(
              value: (f.maxPrice ?? 3000).toDouble(),
              min: 300,
              max: 3000,
              divisions: 27,
              label: f.maxPrice == null ? 'Any' : egp(f.maxPrice!),
              onChanged: (v) => f.setMaxPrice(v >= 3000 ? null : v.round()),
            ),
            const SizedBox(height: 8),
            const Text('Facilities', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final fac in AppConfig.facilities)
                FilterChip(label: Text(fac), selected: f.facilities.contains(fac), onSelected: (_) => f.toggleFacility(fac)),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Show results')),
            ),
          ]),
        ),
      ),
    );
  }
}
