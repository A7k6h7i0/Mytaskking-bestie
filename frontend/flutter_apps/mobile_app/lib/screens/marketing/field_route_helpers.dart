import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared map / route utilities for field executives.
class FieldRouteHelpers {
  FieldRouteHelpers._();

  static const _distance = Distance();
  static final Dio _osrm = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static bool isValidCoord(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.abs() < 0.01 && lng.abs() < 0.01) return false;
    if (lat < -85 || lat > 85 || lng < -180 || lng > 180) return false;
    return true;
  }

  static LatLng? outletLatLng(Map<String, dynamic> outlet) {
    final lat = _toDouble(outlet['latitude'] ?? outlet['lat']);
    final lng = _toDouble(outlet['longitude'] ?? outlet['lng']);
    if (!isValidCoord(lat, lng)) return null;
    return LatLng(lat!, lng!);
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static double distanceKm(LatLng from, LatLng to) {
    return _distance.as(LengthUnit.Kilometer, from, to);
  }

  static String formatKm(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }

  static String formatDuration(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final min = seconds ~/ 60;
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  /// Nearest-neighbour visit order from [start].
  static List<Map<String, dynamic>> greedyNearestRoute(
    LatLng start,
    List<Map<String, dynamic>> outlets,
  ) {
    final remaining = outlets
        .where((o) => outletLatLng(o) != null)
        .map((o) => Map<String, dynamic>.from(o))
        .toList();
    final result = <Map<String, dynamic>>[];
    var current = start;
    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        final dA = distanceKm(current, outletLatLng(a)!);
        final dB = distanceKm(current, outletLatLng(b)!);
        return dA.compareTo(dB);
      });
      final next = remaining.removeAt(0);
      final pt = outletLatLng(next)!;
      next['_distKm'] = distanceKm(current, pt);
      result.add(next);
      current = pt;
    }
    return result;
  }

  /// Attach straight-line distance from [origin] to each outlet.
  static List<Map<String, dynamic>> withDistancesFrom(
    LatLng origin,
    List<Map<String, dynamic>> outlets,
  ) {
    final enriched = <Map<String, dynamic>>[];
    for (final raw in outlets) {
      final o = Map<String, dynamic>.from(raw);
      final pt = outletLatLng(o);
      if (pt == null) continue;
      o['_distKm'] = distanceKm(origin, pt);
      enriched.add(o);
    }
    enriched.sort((a, b) =>
        ((a['_distKm'] as num).toDouble()).compareTo((b['_distKm'] as num).toDouble()));
    return enriched;
  }

  /// OSRM driving route between two points.
  static Future<OsrmLeg> fetchOsrmLeg(LatLng from, LatLng to) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson';
    try {
      final res = await _osrm.get<String>(url);
      final data = jsonDecode(res.data as String) as Map<String, dynamic>;
      if (data['code'] == 'Ok' && (data['routes'] as List).isNotEmpty) {
        final route = data['routes'][0] as Map<String, dynamic>;
        final distM = (route['distance'] as num).toDouble();
        final durSec = (route['duration'] as num).toInt();
        final coords = (route['geometry']['coordinates'] as List)
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        return OsrmLeg(
          points: coords,
          distanceLabel: distM < 1000
              ? '${distM.round()} m'
              : '${(distM / 1000).toStringAsFixed(1)} km',
          durationLabel: formatDuration(durSec),
          distanceKm: distM / 1000,
        );
      }
    } catch (_) {}
    final straight = distanceKm(from, to);
    return OsrmLeg(
      points: [from, to],
      distanceLabel: formatKm(straight),
      durationLabel: '—',
      distanceKm: straight,
    );
  }

  /// Build full optimized path polyline + per-leg info.
  static Future<OptimizedRouteResult> buildOptimizedPath(
    LatLng start,
    List<Map<String, dynamic>> sequence,
  ) async {
    if (sequence.isEmpty) {
      return const OptimizedRouteResult(points: [], legs: [], totalKm: 0);
    }
    final stops = <LatLng>[start];
    for (final o in sequence) {
      final pt = outletLatLng(o);
      if (pt != null) stops.add(pt);
    }

    final allPoints = <LatLng>[];
    final legs = <OsrmLeg>[];
    var totalKm = 0.0;

    for (var i = 0; i < stops.length - 1; i++) {
      final leg = await fetchOsrmLeg(stops[i], stops[i + 1]);
      legs.add(leg);
      totalKm += leg.distanceKm;
      if (allPoints.isEmpty) {
        allPoints.addAll(leg.points);
      } else if (leg.points.isNotEmpty) {
        allPoints.addAll(leg.points.skip(1));
      }
    }

    return OptimizedRouteResult(points: allPoints, legs: legs, totalKm: totalKm);
  }

  static Future<LatLng?> resolveCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return null;
      return LatLng(last.latitude, last.longitude);
    }
  }

  static Future<bool> openMapsNavigation(LatLng destination, {String? label}) async {
    final name = Uri.encodeComponent(label ?? 'Outlet');
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&destination_place_id=$name',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> openMapsDirections(LatLng from, LatLng to) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=${from.latitude},${from.longitude}&destination=${to.latitude},${to.longitude}&travelmode=driving',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class OsrmLeg {
  const OsrmLeg({
    required this.points,
    required this.distanceLabel,
    required this.durationLabel,
    required this.distanceKm,
  });

  final List<LatLng> points;
  final String distanceLabel;
  final String durationLabel;
  final double distanceKm;
}

class OptimizedRouteResult {
  const OptimizedRouteResult({
    required this.points,
    required this.legs,
    required this.totalKm,
  });

  final List<LatLng> points;
  final List<OsrmLeg> legs;
  final double totalKm;
}
