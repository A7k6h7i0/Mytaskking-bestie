import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'field_route_helpers.dart';

/// Full-screen map for a single GPS ping (manager team log).
class GpsMapViewScreen extends StatelessWidget {
  const GpsMapViewScreen({
    super.key,
    required this.point,
    required this.title,
    this.subtitle,
  });

  final LatLng point;
  final String title;
  final String? subtitle;

  static Future<void> open(
    BuildContext context, {
    required LatLng point,
    required String title,
    String? subtitle,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GpsMapViewScreen(
          point: point,
          title: title,
          subtitle: subtitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                subtitle!,
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Text(
              '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
              style: TextStyle(
                color: c.textSoft,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BestieTokens.rLg),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.mytaskking.mytaskking_mobile',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 44,
                          height: 44,
                          child: Icon(Icons.person_pin_circle_rounded,
                              color: c.brand, size: 44),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: () => FieldRouteHelpers.openMapsNavigation(
                  point,
                  label: title,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open in Google Maps'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
