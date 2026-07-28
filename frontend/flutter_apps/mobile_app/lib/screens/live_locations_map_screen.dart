import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

/// Map with multiple employee markers (login activity live view).
class LiveLocationsMapScreen extends StatelessWidget {
  const LiveLocationsMapScreen({
    super.key,
    required this.items,
  });

  final List<Map<String, dynamic>> items;

  static Future<void> open(
    BuildContext context, {
    required List<Map<String, dynamic>> items,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LiveLocationsMapScreen(items: items),
      ),
    );
  }

  LatLng? _point(Map<String, dynamic> row) {
    final lat = row['latitude'];
    final lng = row['longitude'];
    if (lat == null || lng == null) return null;
    return LatLng((lat as num).toDouble(), (lng as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final markers = <Marker>[];
    for (final row in items) {
      final point = _point(row);
      if (point == null) continue;
      final user = (row['user'] as Map?)?.cast<String, dynamic>() ?? {};
      final name = user['name']?.toString() ?? 'Employee';
      markers.add(
        Marker(
          point: point,
          width: 120,
          height: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_pin_circle_rounded, color: c.brand, size: 36),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.white70)],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final center = markers.isNotEmpty
        ? markers.first.point
        : const LatLng(20.5937, 78.9629);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(title: const Text('Live locations')),
      body: markers.isEmpty
          ? Center(
              child: Text(
                'No GPS locations in the last 24 hours.',
                style: TextStyle(color: c.textMuted),
              ),
            )
          : FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 12,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.mytaskking.mytaskking_mobile',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
    );
  }
}
