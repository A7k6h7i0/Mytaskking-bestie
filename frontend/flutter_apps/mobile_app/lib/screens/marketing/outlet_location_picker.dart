import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'field_route_helpers.dart';

/// Pick an outlet location — search, tap map, or use GPS.
class OutletLocationPicker extends StatefulWidget {
  const OutletLocationPicker({super.key, this.initial});

  final LatLng? initial;

  static Future<LatLng?> open(BuildContext context, {LatLng? initial}) {
    return Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OutletLocationPicker(initial: initial),
      ),
    );
  }

  @override
  State<OutletLocationPicker> createState() => _OutletLocationPickerState();
}

class _OutletLocationPickerState extends State<OutletLocationPicker> {
  final _mapController = MapController();
  final _searchCtrl = TextEditingController();

  LatLng? _pin;
  LatLng _center = const LatLng(17.385, 78.4867);
  bool _loadingGps = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.initial != null) {
      setState(() {
        _pin = widget.initial;
        _center = widget.initial!;
        _loadingGps = false;
      });
      return;
    }
    final pos = await FieldRouteHelpers.resolveCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _center = pos;
        _pin = pos;
        _loadingGps = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(pos, 16);
      });
      return;
    }
    setState(() => _loadingGps = false);
  }

  Future<void> _useMyLocation() async {
    setState(() => _loadingGps = true);
    final pos = await FieldRouteHelpers.resolveCurrentPosition();
    if (!mounted) return;
    setState(() => _loadingGps = false);
    if (pos == null) {
      bestieToast(context, 'Could not get GPS',
          body: 'Turn on location or search an area below.',
          kind: BestieToastKind.warning);
      return;
    }
    setState(() {
      _pin = pos;
      _center = pos;
    });
    _mapController.move(pos, 17);
  }

  Future<void> _searchPlace() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      bestieToast(context, 'Type an area or landmark',
          kind: BestieToastKind.warning);
      return;
    }
    setState(() => _searching = true);
    try {
      final locations = await locationFromAddress(query);
      if (!mounted) return;
      if (locations.isEmpty) {
        bestieToast(context, 'Place not found',
            body: 'Try a nearby city or tap the map.',
            kind: BestieToastKind.error);
        return;
      }
      final loc = locations.first;
      final point = LatLng(loc.latitude, loc.longitude);
      setState(() {
        _pin = point;
        _center = point;
      });
      _mapController.move(point, 16);
      bestieToast(context, 'Location found', kind: BestieToastKind.success);
    } catch (_) {
      if (!mounted) return;
      bestieToast(context, 'Search failed',
          body: 'Check spelling or tap the map to place the pin.',
          kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Pick shop location'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: c.brandSoft,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search a place, tap the map, or use your current location.',
                  style: TextStyle(fontSize: 13, color: c.text),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchPlace(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'e.g. Kukatpally, Hyderabad',
                          filled: true,
                          fillColor: c.surface,
                          prefixIcon: Icon(Icons.search, color: c.textMuted, size: 22),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(BestieTokens.rMd),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _searching ? null : _searchPlace,
                      style: FilledButton.styleFrom(backgroundColor: c.brand),
                      child: _searching
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.surface,
                              ),
                            )
                          : const Text('Find'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 15,
                    minZoom: 4,
                    maxZoom: 18,
                    onTap: (_, point) => setState(() => _pin = point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.mytaskking.mytaskking_mobile',
                      maxZoom: 19,
                    ),
                    if (_pin != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pin!,
                            width: 48,
                            height: 48,
                            child: Icon(Icons.location_on, color: c.danger, size: 44),
                          ),
                        ],
                      ),
                  ],
                ),
                if (_loadingGps)
                  Positioned.fill(
                    child: ColoredBox(
                      color: c.surface.withValues(alpha: 0.7),
                      child: Center(child: BestieSpinner(color: c.brand)),
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.extended(
                    heroTag: 'outlet-pick-gps',
                    backgroundColor: c.surface,
                    foregroundColor: c.brand,
                    onPressed: _loadingGps ? null : _useMyLocation,
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text('My location'),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _pin == null ? null : () => Navigator.pop(context, _pin),
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(
                  _pin == null ? 'Pick a location first' : 'Use this location',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
