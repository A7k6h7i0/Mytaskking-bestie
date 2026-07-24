import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import 'shop_search_fuzzy.dart';

/// Smart business directory search — normalizes API results like Marketing Executives.
class BusinessDirectoryService {
  BusinessDirectoryService(this._api);

  final BestieApi _api;

  static const _stopWords = {
    'the', 'and', 'for', 'near', 'shop', 'store', 'stores', 'in', 'at', 'of', 'a', 'an',
  };

  /// Applies typo correction before search; use for UI hints.
  static ({String query, String area, bool changed}) normalizeInputs({
    required String query,
    required String area,
  }) {
    final qFix = ShopSearchFuzzy.correctQuery(query);
    final aFix = ShopSearchFuzzy.correctArea(area);
    return (
      query: qFix.text,
      area: aFix.text,
      changed: qFix.changed || aFix.changed,
    );
  }

  Future<List<Map<String, dynamic>>> search({
    required String query,
    String? area,
    double? latitude,
    double? longitude,
    double radiusKm = 10,
    int page = 1,
    int limit = 30,
  }) async {
    final q = query.trim();
    final areaText = area?.trim() ?? '';
    if (q.isEmpty && areaText.isEmpty && latitude == null) return [];

    final normalized = normalizeInputs(query: q, area: areaText);
    final correctedQ = normalized.query;
    final correctedArea = normalized.area;

    var lat = latitude;
    var lng = longitude;

    if ((lat == null || lng == null) && correctedArea.isNotEmpty) {
      final geo = await _geocodeArea(correctedArea);
      if (geo != null) {
        lat = geo.$1;
        lng = geo.$2;
      } else if (correctedArea != areaText) {
        // Retry geocode with original spelling if correction failed.
        final fallback = await _geocodeArea(areaText);
        if (fallback != null) {
          lat = fallback.$1;
          lng = fallback.$2;
        }
      }
    }

    final queryVariants = ShopSearchFuzzy.queryVariants(q);
    if (correctedQ.isNotEmpty && !queryVariants.contains(correctedQ)) {
      queryVariants.insert(0, correctedQ);
    }

    final term = correctedQ.isNotEmpty ? correctedQ : correctedArea;
    final tokens = correctedQ
        .split(RegExp(r'[\s,./|+-]+'))
        .map((t) => t.trim())
        .where((t) => t.length >= 3 && !_stopWords.contains(t.toLowerCase()))
        .toList();
    final shortTerm = tokens.isNotEmpty ? tokens.first : term;

    final attempts = <Map<String, dynamic>>[];
    void add(Map<String, dynamic> params) {
      final key = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      if (attempts.any((a) => a.entries.map((e) => '${e.key}=${e.value}').join('&') == key)) {
        return;
      }
      attempts.add(params);
    }

    for (final variant in queryVariants) {
      if (variant.isEmpty) continue;
      if (lat != null && lng != null) {
        add({'page': page, 'limit': limit, 'q': variant, 'lat': lat, 'lng': lng, 'radius': radiusKm});
      }
      add({'page': page, 'limit': limit, 'q': variant});
    }

    if (lat != null && lng != null && term.isNotEmpty) {
      add({'page': page, 'limit': limit, 'q': term, 'lat': lat, 'lng': lng, 'radius': radiusKm});
    }
    if (term.isNotEmpty) add({'page': page, 'limit': limit, 'q': term});
    if (shortTerm.isNotEmpty && shortTerm.toLowerCase() != term.toLowerCase()) {
      if (lat != null && lng != null) {
        add({'page': page, 'limit': limit, 'q': shortTerm, 'lat': lat, 'lng': lng, 'radius': radiusKm});
      } else {
        add({'page': page, 'limit': limit, 'q': shortTerm});
      }
    }
    if (q.isEmpty && correctedArea.isNotEmpty && lat != null && lng != null) {
      add({'page': page, 'limit': limit, 'lat': lat, 'lng': lng, 'radius': radiusKm});
    }

    final seen = <String>{};
    final pooled = <Map<String, dynamic>>[];

    for (final params in attempts) {
      try {
        final resp = await _api.searchBusinessDirectoryRaw(params);
        for (final raw in _parseList(resp)) {
          final item = normalize(raw, originLat: lat, originLng: lng, searchArea: correctedArea.isNotEmpty ? correctedArea : areaText);
          final id = item['id']?.toString() ?? item['placeId']?.toString() ?? '';
          final key = id.isNotEmpty ? id : '${item['businessName']}|${item['address']}';
          if (seen.add(key)) pooled.add(item);
        }
        if (pooled.length >= limit) break;
      } catch (_) {}
    }

    if (pooled.isEmpty) return [];

    if (q.isEmpty) {
      _sortByDistance(pooled);
      return pooled.take(limit).toList();
    }

    final ranked = pooled
        .map((item) => (item: item, score: _relevanceScore(item, correctedQ.isNotEmpty ? correctedQ : q, correctedArea.isNotEmpty ? correctedArea : areaText)))
        .where((e) => e.score > 0)
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final da = a.item['distanceMeters'];
        final db = b.item['distanceMeters'];
        if (da is int && db is int) return da.compareTo(db);
        return 0;
      });

    if (ranked.isEmpty) return pooled.take(limit).toList();
    return ranked.take(limit).map((e) => e.item).toList();
  }

  static Map<String, dynamic> normalize(
    dynamic raw, {
    double? originLat,
    double? originLng,
    String searchArea = '',
  }) {
    final item = Map<String, dynamic>.from(raw as Map);
    final lat = double.tryParse(item['latitude']?.toString() ?? '') ??
        double.tryParse(item['lat']?.toString() ?? '') ??
        double.tryParse(item['gpsLat']?.toString() ?? '') ??
        0.0;
    final lng = double.tryParse(item['longitude']?.toString() ?? '') ??
        double.tryParse(item['lng']?.toString() ?? '') ??
        double.tryParse(item['lon']?.toString() ?? '') ??
        double.tryParse(item['gpsLng']?.toString() ?? '') ??
        0.0;

    int? distanceMeters;
    final distanceKm = double.tryParse(item['distance']?.toString() ?? '');
    if (distanceKm != null) {
      distanceMeters = (distanceKm * 1000).round();
    } else if (originLat != null &&
        originLng != null &&
        !(lat.abs() < 0.01 && lng.abs() < 0.01)) {
      distanceMeters = _haversineMeters(originLat, originLng, lat, lng).round();
    }

    final categories = item['categories'];
    final categoryLabel = categories is List && categories.isNotEmpty
        ? categories.map((e) => e.toString()).join(', ')
        : (item['main_category'] ??
            item['businessCategory'] ??
            item['category'] ??
            'Business')
            .toString();

    final featured = item['featured_image'] ??
        item['featuredImage'] ??
        item['image'] ??
        item['photo'] ??
        item['thumbnail'] ??
        (item['images'] is List && (item['images'] as List).isNotEmpty
            ? (item['images'] as List).first
            : null);

    final reviewCount = item['reviews_count'] ??
        item['review_count'] ??
        item['user_ratings_total'] ??
        item['reviews'];

    return {
      'id': item['id']?.toString() ?? item['place_id']?.toString() ?? '',
      'placeId': item['place_id']?.toString() ?? '',
      'businessName':
          item['name'] ?? item['business_name'] ?? item['businessName'] ?? 'Unknown Business',
      'businessCategory': categoryLabel,
      'address': item['address']?.toString() ?? '',
      'contactPhone': item['phone'] ?? item['contactPhone'] ?? item['contact_phone'] ?? '',
      'contactEmail': item['email'] ?? item['contactEmail'] ?? '',
      'website': item['website']?.toString() ?? '',
      'rating': _toDouble(item['rating']),
      'reviewCount': reviewCount is num ? reviewCount.toInt() : int.tryParse('$reviewCount'),
      'gpsLat': lat,
      'gpsLng': lng,
      'distanceMeters': distanceMeters,
      'featuredImage': featured?.toString() ?? '',
      'searchArea': searchArea,
      'source': 'mytaskking',
      '_raw': item,
    };
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static List<dynamic> _parseList(Map<String, dynamic> resp) {
    final data = resp['data'];
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return const [];
  }

  static void _sortByDistance(List<Map<String, dynamic>> items) {
    items.sort((a, b) {
      final da = a['distanceMeters'];
      final db = b['distanceMeters'];
      if (da is int && db is int) return da.compareTo(db);
      if (da is int) return -1;
      if (db is int) return 1;
      return 0;
    });
  }

  static int _relevanceScore(Map<String, dynamic> item, String query, String area) {
    final name = (item['businessName']?.toString() ?? '').toLowerCase();
    final category = (item['businessCategory']?.toString() ?? '').toLowerCase();
    final address = (item['address']?.toString() ?? '').toLowerCase();
    final identity = '$name $category $address';
    final qLower = query.toLowerCase().trim();

    var score = 0;
    if (name == qLower) score += 100;
    if (name.contains(qLower) || ShopSearchFuzzy.fuzzyContains(name, qLower)) score += 50;
    if (identity.contains(qLower) || ShopSearchFuzzy.fuzzyContains(identity, qLower)) {
      score += 30;
    }

    final tokens = qLower
        .split(RegExp(r'[\s,./|+-]+'))
        .where((t) => t.length >= 3 && !_stopWords.contains(t))
        .toList();

    var tokenHits = 0;
    for (final t in tokens) {
      if (name.contains(t) || ShopSearchFuzzy.fuzzyContains(name, t)) {
        score += 20;
        tokenHits++;
      } else if (category.contains(t) || ShopSearchFuzzy.fuzzyContains(category, t)) {
        score += 14;
        tokenHits++;
      } else {
        // Typo category match: "restrurent" ≈ "restaurant".
        final catMatch = ShopSearchFuzzy.correctQuery(t);
        if (catMatch.changed &&
            (category.contains(catMatch.text.toLowerCase()) ||
                ShopSearchFuzzy.fuzzyContains(category, catMatch.text))) {
          score += 12;
          tokenHits++;
        }
      }
    }

    if (tokens.isEmpty) return score > 0 ? score : 1;
    if (tokenHits == 0) {
      // Allow fuzzy whole-query match against category/name.
      if (ShopSearchFuzzy.fuzzyContains(identity, qLower)) return 8;
      return 0;
    }
    if (tokens.length >= 2 && tokenHits < (tokens.length / 2).ceil()) return 0;

    if (area.isNotEmpty) {
      final areaLower = area.toLowerCase();
      if (address.contains(areaLower) || ShopSearchFuzzy.fuzzyContains(address, areaLower)) {
        score += 8;
      } else {
        for (final variant in ShopSearchFuzzy.areaVariants(area)) {
          if (variant.toLowerCase() != areaLower &&
              (address.contains(variant.toLowerCase()) ||
                  ShopSearchFuzzy.fuzzyContains(address, variant))) {
            score += 6;
            break;
          }
        }
      }
    }
    return score;
  }

  static Future<(double, double)?> _geocodeArea(String area) async {
    for (final variant in ShopSearchFuzzy.areaVariants(area)) {
      try {
        final locations = await locationFromAddress('$variant, India');
        if (locations.isNotEmpty) {
          return (locations.first.latitude, locations.first.longitude);
        }
      } catch (_) {}
    }
    return null;
  }

  static double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
