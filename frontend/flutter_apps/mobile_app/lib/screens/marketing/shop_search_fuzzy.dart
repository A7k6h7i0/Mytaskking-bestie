/// Typo-tolerant helpers for shop directory search (categories + areas).
class ShopSearchFuzzy {
  ShopSearchFuzzy._();

  static const categories = [
    'Plywood', 'Hardware', 'Sanitary', 'Electrical', 'Electronics',
    'Diagnostics', 'Pharmacy', 'Medical Store', 'Grocery', 'Kirana',
    'Furniture', 'Paint', 'Tiles', 'Mobile Shop', 'Restaurant', 'Salon',
    'Cafe', 'Supermarket', 'Stationery', 'Automobile', 'Tyre', 'Cement',
    'Plumbing', 'Building Material', 'Optical', 'Bakery', 'Hotel',
  ];

  /// Common Indian locality names (extend as needed).
  static const areas = [
    'Golconda', 'Kukatpally', 'Secunderabad', 'Hitech City', 'Hi Tech City',
    'Banjara Hills', 'Jubilee Hills', 'Madhapur', 'Gachibowli', 'Miyapur',
    'Ameerpet', 'Dilsukhnagar', 'LB Nagar', 'Uppal', 'Charminar', 'Abids',
    'Begumpet', 'Kondapur', 'Manikonda', 'Nampally', 'Malakpet', 'Mehdipatnam',
    'Tolichowki', 'Shaikpet', 'Attapur', 'Rajendra Nagar', 'Nizampet',
    'Bachupally', 'Alwal', 'Malkajgiri', 'Warangal', 'Karimnagar', 'Vijayawada',
    'Visakhapatnam', 'Vizag', 'Chennai', 'Bangalore', 'Bengaluru', 'Mumbai',
    'Delhi', 'Pune', 'Kolkata',
  ];

  static const _areaAliases = {
    'cholconda': 'Golconda',
    'golkonda': 'Golconda',
    'gol konda': 'Golconda',
    'golconda fort': 'Golconda',
    'kukatpally': 'Kukatpally',
    'kukatpallyy': 'Kukatpally',
    'kphb': 'Kukatpally',
    'k p h b': 'Kukatpally',
    'hitech city': 'Hitech City',
    'hi tech city': 'Hitech City',
    'hitec city': 'Hitech City',
    'secunderbad': 'Secunderabad',
    'secundrabad': 'Secunderabad',
    'banjarahills': 'Banjara Hills',
    'jubileehills': 'Jubilee Hills',
    'gachibowli': 'Gachibowli',
    'gachi bowli': 'Gachibowli',
    'madhapur': 'Madhapur',
    'miyapur': 'Miyapur',
    'ameerpet': 'Ameerpet',
    'dilsukhnagar': 'Dilsukhnagar',
    'dilsuknagar': 'Dilsukhnagar',
    'lb nagar': 'LB Nagar',
    'l b nagar': 'LB Nagar',
    'vizag': 'Visakhapatnam',
    'bangalore': 'Bengaluru',
  };

  /// Correct a shop-type query; returns [corrected, didChange].
  static ({String text, bool changed}) correctQuery(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return (text: input, changed: false);

    final words = input.split(RegExp(r'\s+'));
    var changed = false;
    final out = <String>[];

    for (final word in words) {
      final match = _bestFuzzyMatch(word, categories, minSimilarity: 0.68);
      if (match != null && match.toLowerCase() != word.toLowerCase()) {
        out.add(match);
        changed = true;
      } else {
        out.add(word);
      }
    }

    // Whole-phrase category match (e.g. "medical stor" → "Medical Store").
    final whole = _bestFuzzyMatch(input, categories, minSimilarity: 0.72);
    if (whole != null && whole.toLowerCase() != input.toLowerCase()) {
      return (text: whole, changed: true);
    }

    return (text: out.join(' '), changed: changed);
  }

  /// Correct area/locality spelling.
  static ({String text, bool changed}) correctArea(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return (text: input, changed: false);

    final key = _normalizeKey(input);
    final alias = _areaAliases[key];
    if (alias != null) return (text: alias, changed: alias.toLowerCase() != input.toLowerCase());

    final match = _bestFuzzyMatch(input, areas, minSimilarity: 0.72);
    if (match != null && match.toLowerCase() != input.toLowerCase()) {
      return (text: match, changed: true);
    }

    // Multi-part areas: "golconda, hyderabad" — fix each segment.
    final parts = input.split(RegExp(r'\s*,\s*'));
    if (parts.length > 1) {
      var any = false;
      final fixed = parts.map((p) {
        final r = correctArea(p);
        if (r.changed) any = true;
        return r.text;
      }).toList();
      if (any) return (text: fixed.join(', '), changed: true);
    }

    return (text: input, changed: false);
  }

  /// Extra API query strings to try (corrected + original + token variants).
  static List<String> queryVariants(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    final corrected = correctQuery(trimmed);
    final variants = <String>{trimmed, corrected.text};

    for (final token in trimmed.split(RegExp(r'[\s,./|+-]+'))) {
      if (token.length < 3) continue;
      final m = _bestFuzzyMatch(token, categories, minSimilarity: 0.68);
      if (m != null) variants.add(m);
    }

    return variants.where((v) => v.trim().isNotEmpty).toList();
  }

  static List<String> areaVariants(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    final corrected = correctArea(trimmed);
    return {
      trimmed,
      corrected.text,
      ...trimmed.split(RegExp(r'\s*,\s*')).map((p) => correctArea(p).text),
    }.where((v) => v.trim().isNotEmpty).toList();
  }

  /// Live autocomplete suggestions while the user types (prefix + fuzzy).
  static List<String> suggestCategories(String raw, {int limit = 6}) =>
      _suggestFrom(raw, categories, limit: limit);

  static List<String> suggestAreas(String raw, {int limit = 6}) =>
      _suggestFrom(raw, areas, limit: limit);

  static List<String> _suggestFrom(
    String raw,
    List<String> candidates, {
    int limit = 6,
    int minChars = 2,
  }) {
    final q = raw.trim();
    if (q.length < minChars) return const [];

    final qLower = q.toLowerCase();
    if (candidates.any((c) => c.toLowerCase() == qLower)) return const [];

    final scored = <MapEntry<String, double>>[];

    for (final candidate in candidates) {
      final cLower = candidate.toLowerCase();
      var score = 0.0;

      if (cLower.startsWith(qLower)) {
        score = 1.0 + (qLower.length / cLower.length) * 0.1;
      } else if (cLower.contains(qLower)) {
        score = 0.88;
      } else {
        for (final word in cLower.split(RegExp(r'\s+'))) {
          if (word.length < 2) continue;
          if (word.startsWith(qLower)) {
            score = score > 0.92 ? score : 0.92;
          } else if (word.contains(qLower)) {
            score = score > 0.82 ? score : 0.82;
          } else {
            final wSim = similarity(qLower, word);
            if (wSim >= 0.62 && wSim > score) score = wSim;
          }
        }
        final sim = similarity(qLower, cLower);
        if (sim >= 0.62 && sim > score) score = sim;
      }

      if (score >= 0.62) scored.add(MapEntry(candidate, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    final seen = <String>{};
    final out = <String>[];
    for (final entry in scored) {
      if (seen.add(entry.key.toLowerCase())) out.add(entry.key);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Fuzzy substring / word match for ranking.
  static bool fuzzyContains(String haystack, String needle) {
    final h = haystack.toLowerCase();
    final n = needle.toLowerCase().trim();
    if (n.isEmpty) return false;
    if (h.contains(n)) return true;

    for (final part in h.split(RegExp(r'[\s,./|+-]+'))) {
      if (part.length < 3 || n.length < 3) continue;
      if (similarity(part, n) >= 0.72) return true;
      if (levenshtein(part, n) <= _maxDistance(n.length)) return true;
    }
    return false;
  }

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final m = a.length;
    final n = b.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      final swap = prev;
      prev = curr;
      curr = swap;
    }
    return prev[n];
  }

  static double similarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1;
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1;
    return 1 - (levenshtein(a.toLowerCase(), b.toLowerCase()) / maxLen);
  }

  static String? _bestFuzzyMatch(
    String input,
    List<String> candidates, {
    required double minSimilarity,
  }) {
    final q = input.trim();
    if (q.isEmpty) return null;

    final qLower = q.toLowerCase();
    String? best;
    var bestScore = 0.0;

    for (final candidate in candidates) {
      final cLower = candidate.toLowerCase();
      if (cLower == qLower) return candidate;
      if (cLower.contains(qLower) || qLower.contains(cLower)) {
        final score = qLower.length / cLower.length;
        if (score > bestScore) {
          bestScore = score.clamp(0.0, 1.0);
          best = candidate;
        }
        continue;
      }

      final sim = similarity(qLower, cLower);
      final dist = levenshtein(qLower, cLower);
      if (sim >= minSimilarity && dist <= _maxDistance(q.length)) {
        if (sim > bestScore) {
          bestScore = sim;
          best = candidate;
        }
      }

      // Multi-word candidates: match each word.
      for (final word in cLower.split(RegExp(r'\s+'))) {
        if (word.length < 3) continue;
        final wSim = similarity(qLower, word);
        if (wSim >= minSimilarity && wSim > bestScore) {
          bestScore = wSim;
          best = candidate;
        }
      }
    }

    return bestScore >= minSimilarity ? best : null;
  }

  static int _maxDistance(int length) {
    if (length <= 4) return 1;
    if (length <= 7) return 2;
    return 3;
  }

  static String _normalizeKey(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
