import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import '../shell_screen.dart';
import 'field_route_helpers.dart';

/// Executive route tab — map, distance to outlets, optimized visit order.
class FieldRouteScreen extends ConsumerStatefulWidget {
  const FieldRouteScreen({super.key});

  @override
  ConsumerState<FieldRouteScreen> createState() => _FieldRouteScreenState();
}

class _FieldRouteScreenState extends ConsumerState<FieldRouteScreen> {
  final _mapController = MapController();

  LatLng? _position;
  List<Map<String, dynamic>> _nearbyOutlets = const [];
  List<Map<String, dynamic>> _optimizedOutlets = const [];
  List<LatLng> _routeLine = const [];
  List<OsrmLeg> _legs = const [];
  double _totalRouteKm = 0;
  Map<String, dynamic>? _stats;

  bool _loading = true;
  bool _optimizing = false;
  bool _permissionDenied = false;
  String? _error;
  bool _showOptimized = false;
  double _radiusKm = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _permissionDenied = false;
    });
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait([
        FieldRouteHelpers.resolveCurrentPosition(),
        api.listMarketingOutlets(pageSize: 200),
        api.marketingDashboard(),
      ]);
      if (!mounted) return;

      final pos = results[0] as LatLng?;
      if (pos == null) {
        final perm = await Geolocator.checkPermission();
        _permissionDenied = perm == LocationPermission.deniedForever ||
            perm == LocationPermission.denied;
      }

      final resp = results[1] as Map<String, dynamic>;
      final rawItems = ((resp['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      List<Map<String, dynamic>> withDist = const [];
      if (pos != null) {
        withDist = FieldRouteHelpers.withDistancesFrom(pos, rawItems)
            .where((o) => (o['_distKm'] as num).toDouble() <= _radiusKm)
            .toList();
      } else {
        withDist = rawItems
            .where((o) => FieldRouteHelpers.outletLatLng(o) != null)
            .toList();
      }

      setState(() {
        _position = pos;
        _nearbyOutlets = withDist;
        _stats = results[2] as Map<String, dynamic>;
        _loading = false;
        if (_showOptimized && _optimizedOutlets.isEmpty && withDist.isNotEmpty) {
          _showOptimized = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _optimizeRoute() async {
    if (_position == null) {
      bestieToast(context, 'Turn on GPS to optimize your route',
          kind: BestieToastKind.warning);
      return;
    }
    final pool = _nearbyOutlets.isNotEmpty
        ? _nearbyOutlets
        : await _fetchAllMappedOutlets();
    if (!mounted) return;
    if (pool.isEmpty) {
      bestieToast(context, 'No outlets with map coordinates found',
          kind: BestieToastKind.warning);
      return;
    }

    setState(() => _optimizing = true);
    try {
      final sequence =
          FieldRouteHelpers.greedyNearestRoute(_position!, pool);
      final path = await FieldRouteHelpers.buildOptimizedPath(
        _position!,
        sequence,
      );
      if (!mounted) return;
      setState(() {
        _optimizedOutlets = sequence;
        _routeLine = path.points;
        _legs = path.legs;
        _totalRouteKm = path.totalKm;
        _showOptimized = true;
        _optimizing = false;
      });
      _fitMapToContent();
      bestieToast(context, 'Route ready — ${sequence.length} stops',
          kind: BestieToastKind.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _optimizing = false);
      bestieToast(context, formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllMappedOutlets() async {
    final resp =
        await ref.read(apiProvider).listMarketingOutlets(pageSize: 200);
    return ((resp['items'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((o) => FieldRouteHelpers.outletLatLng(o) != null)
        .toList();
  }

  void _fitMapToContent() {
    final points = <LatLng>[];
    if (_position != null) points.add(_position!);
    for (final o in _displayOutlets) {
      final pt = FieldRouteHelpers.outletLatLng(o);
      if (pt != null) points.add(pt);
    }
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 14);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  List<Map<String, dynamic>> get _displayOutlets =>
      _showOptimized ? _optimizedOutlets : _nearbyOutlets;

  LatLng get _mapCenter {
    if (_position != null) return _position!;
    for (final o in _displayOutlets) {
      final pt = FieldRouteHelpers.outletLatLng(o);
      if (pt != null) return pt;
    }
    return const LatLng(17.385, 78.4867);
  }

  Future<void> _openSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Route & map'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: BestieSpinner())
          : _error != null
              ? _errorBody(c)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statsRow(c),
                    _modeToggle(c),
                    Expanded(flex: 5, child: _mapSection(c)),
                    Expanded(flex: 4, child: _outletList(c)),
                    _bottomActions(c),
                  ],
                ),
    );
  }

  Widget _errorBody(BestieColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: c.danger),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _statsRow(BestieColors c) {
    final visits = (_stats?['visitsToday'] as num?)?.toInt() ?? 0;
    final outlets = (_stats?['outlets'] as num?)?.toInt() ?? _nearbyOutlets.length;
    final nearest = _nearbyOutlets.isEmpty
        ? '—'
        : FieldRouteHelpers.formatKm(
            (_nearbyOutlets.first['_distKm'] as num).toDouble());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _statChip(c, 'Visits today', '$visits'),
          const SizedBox(width: 8),
          _statChip(c, 'Outlets', '$outlets'),
          const SizedBox(width: 8),
          _statChip(c, 'Nearest', nearest),
          if (_showOptimized) ...[
            const SizedBox(width: 8),
            _statChip(c, 'Route', FieldRouteHelpers.formatKm(_totalRouteKm)),
          ],
        ],
      ),
    );
  }

  Widget _statChip(BestieColors c, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          border: Border.all(color: c.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: c.textMuted)),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15, color: c.text)),
          ],
        ),
      ),
    );
  }

  Widget _modeToggle(BestieColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Nearby'), icon: Icon(Icons.near_me_outlined, size: 18)),
          ButtonSegment(value: true, label: Text('Optimized'), icon: Icon(Icons.route_outlined, size: 18)),
        ],
        selected: {_showOptimized},
        onSelectionChanged: (s) {
          if (s.first && _optimizedOutlets.isEmpty) {
            _optimizeRoute();
            return;
          }
          setState(() => _showOptimized = s.first);
        },
      ),
    );
  }

  Widget _mapSection(BestieColors c) {
    if (_permissionDenied && _position == null) {
      return _locationPrompt(c);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: 13,
                minZoom: 3,
                maxZoom: 18,
                backgroundColor: const Color(0xFFE8EEF4),
                onMapReady: _fitMapToContent,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.mytaskking.mytaskking_mobile',
                  maxZoom: 19,
                ),
                if (_routeLine.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routeLine,
                        strokeWidth: 4.5,
                        color: c.brand,
                      ),
                    ],
                  ),
                MarkerLayer(markers: _buildMarkers(c)),
              ],
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: FloatingActionButton.small(
                heroTag: 'field-route-locate',
                backgroundColor: c.surface,
                foregroundColor: c.brand,
                onPressed: _position == null
                    ? _load
                    : () => _mapController.move(_position!, 16),
                child: const Icon(Icons.my_location_rounded),
              ),
            ),
            if (_optimizing)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: c.brand,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('Planning route…',
                              style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _locationPrompt(BestieColors c) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off_outlined, size: 52, color: c.textMuted),
          const SizedBox(height: 12),
          Text('Location needed',
              style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 6),
          Text(
            'Allow GPS to see distance to outlets and plan your route.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.location_searching),
            label: const Text('Enable location'),
          ),
          TextButton(onPressed: _openSettings, child: const Text('Open settings')),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers(BestieColors c) {
    final markers = <Marker>[];
    if (_position != null) {
      markers.add(Marker(
        point: _position!,
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: c.brand,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 20),
        ),
      ));
    }

    for (var i = 0; i < _displayOutlets.length; i++) {
      final o = _displayOutlets[i];
      final pt = FieldRouteHelpers.outletLatLng(o);
      if (pt == null) continue;
      final showNumber = _showOptimized;
      markers.add(Marker(
        point: pt,
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => _showOutletSheet(o, i),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: c.brand, width: 2.5),
            ),
            child: Center(
              child: showNumber
                  ? Text('${i + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: c.brand))
                  : Icon(Icons.storefront, size: 16, color: c.brand),
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  void _showOutletSheet(Map<String, dynamic> outlet, int index) {
    final c = BestieColors.of(context);
    final pt = FieldRouteHelpers.outletLatLng(outlet)!;
    final dist = outlet['_distKm'] as num?;
    final leg = index < _legs.length ? _legs[index] : null;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(outlet['name']?.toString() ?? 'Outlet',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: c.text)),
              if (outlet['address'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(outlet['address'].toString(),
                      style: TextStyle(color: c.textMuted, fontSize: 13)),
                ),
              const SizedBox(height: 12),
              if (dist != null)
                Text('Straight distance: ${FieldRouteHelpers.formatKm(dist.toDouble())}',
                    style: TextStyle(color: c.text)),
              if (leg != null)
                Text('Drive: ${leg.distanceLabel} · ${leg.durationLabel}',
                    style: TextStyle(color: c.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (_position != null) {
                          await FieldRouteHelpers.openMapsDirections(_position!, pt);
                        } else {
                          await FieldRouteHelpers.openMapsNavigation(
                            pt,
                            label: outlet['name']?.toString(),
                          );
                        }
                      },
                      icon: const Icon(Icons.navigation_outlined),
                      label: const Text('Navigate'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        final id = outlet['id']?.toString();
                        if (id != null) context.push('/marketing/outlets/$id');
                      },
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Visit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _outletList(BestieColors c) {
    final items = _displayOutlets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(
            children: [
              Text(
                _showOptimized ? 'Visit order' : 'Nearby outlets',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
              ),
              const Spacer(),
              if (!_showOptimized)
                TextButton(
                  onPressed: () async {
                    final picked = await showDialog<double>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Search radius'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [10.0, 25.0, 50.0, 100.0]
                              .map((km) => ListTile(
                                    title: Text('$km km'),
                                    trailing: _radiusKm == km
                                        ? Icon(Icons.check, color: c.brand)
                                        : null,
                                    onTap: () => Navigator.pop(ctx, km),
                                  ))
                              .toList(),
                        ),
                      ),
                    );
                    if (picked != null && picked != _radiusKm) {
                      setState(() => _radiusKm = picked);
                      _load();
                    }
                  },
                  child: Text('${_radiusKm.round()} km'),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront_outlined, size: 44, color: c.textMuted),
                        const SizedBox(height: 10),
                        Text(
                          _position == null
                              ? 'No mapped outlets yet'
                              : 'No outlets within ${_radiusKm.round()} km',
                          style: TextStyle(color: c.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _outletTile(c, items[i], i),
                ),
        ),
      ],
    );
  }

  Widget _outletTile(BestieColors c, Map<String, dynamic> outlet, int index) {
    final dist = outlet['_distKm'] as num?;
    final leg = _showOptimized && index < _legs.length ? _legs[index] : null;
    final pt = FieldRouteHelpers.outletLatLng(outlet);
    return Material(
      color: c.surface2,
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        onTap: () => _showOutletSheet(outlet, index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: c.brandSoft,
                child: Text(
                  _showOptimized ? '${index + 1}' : '${index + 1}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: c.brand),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outlet['name']?.toString() ?? 'Outlet',
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        if (dist != null)
                          FieldRouteHelpers.formatKm(dist.toDouble()),
                        if (leg != null) '${leg.distanceLabel} · ${leg.durationLabel}',
                        if (outlet['city'] != null) outlet['city'].toString(),
                      ].join(' · '),
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (pt != null)
                IconButton(
                  tooltip: 'Navigate',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.navigation_outlined, color: c.brand, size: 20),
                  onPressed: () async {
                    if (_position != null) {
                      await FieldRouteHelpers.openMapsDirections(_position!, pt);
                    } else {
                      await FieldRouteHelpers.openMapsNavigation(
                        pt,
                        label: outlet['name']?.toString(),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomActions(BestieColors c) {
    final clearance = shellNavClearance(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, clearance - 24),
      child: FilledButton.icon(
          onPressed: _optimizing ? null : _optimizeRoute,
          icon: _optimizing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.auto_graph_rounded),
          label: Text(_showOptimized ? 'Re-optimize route' : 'Optimize visit route'),
        ),
    );
  }
}
