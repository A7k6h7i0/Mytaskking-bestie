import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../state.dart';
import '../shell_screen.dart';
import 'business_directory_service.dart';
import 'field_helpers.dart';
import 'field_route_helpers.dart';
import 'shop_listing_card.dart';
import 'shop_detail_screen.dart';
import 'shop_search_fuzzy.dart';

/// Shop/business directory — voice + smart search + rich listing cards.
class MarketingShopSearchScreen extends ConsumerStatefulWidget {
  const MarketingShopSearchScreen({super.key});

  @override
  ConsumerState<MarketingShopSearchScreen> createState() =>
      _MarketingShopSearchScreenState();
}

class _MarketingShopSearchScreenState
    extends ConsumerState<MarketingShopSearchScreen> {
  final _query = TextEditingController();
  final _area = TextEditingController();
  final _speech = stt.SpeechToText();

  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;
  bool _isListening = false;
  String _voiceText = '';
  String? _error;
  String? _voiceHint;
  String? _correctionHint;
  String? _savingId;

  @override
  void dispose() {
    _speech.cancel();
    _query.dispose();
    _area.dispose();
    super.dispose();
  }

  List<String> _splitVoiceAreas(String raw) {
    return raw
        .split(RegExp(r'\s*(?:,|/|;|\||\band\b|\&)\s*', caseSensitive: false))
        .map((e) => e.trim())
        .where((e) => e.length > 1)
        .toList();
  }

  ({String query, String area}) _parseVoiceText(String spoken) {
    final text = spoken.trim();
    if (text.isEmpty) return (query: '', area: '');

    var query = text;
    var areas = <String>[];
    final areaMatch = RegExp(
      r'\b(?:in|near|around|at|within)\b\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);

    if (areaMatch != null) {
      query = text.substring(0, areaMatch.start).trim();
      areas = _splitVoiceAreas(areaMatch.group(1) ?? '');
    }

    query = query
        .replaceAll(
          RegExp(
            r'\b(?:find|search|show|shops?|stores?|outlets?|businesses?|suppliers?|nearby|please|for|me)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (areas.isEmpty && query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      for (final category in ShopSearchFuzzy.categories) {
        final lowerCategory = category.toLowerCase();
        if (lowerQuery.startsWith('$lowerCategory ')) {
          final possibleArea = query.substring(category.length).trim();
          if (possibleArea.isNotEmpty) {
            query = category;
            areas = _splitVoiceAreas(possibleArea);
          }
          break;
        }
      }
      if (areas.isEmpty) {
        final words = query.split(RegExp(r'\s+'));
        if (words.length >= 2) {
          final firstFix = ShopSearchFuzzy.correctQuery(words.first);
          if (firstFix.changed) {
            query = firstFix.text;
            areas = _splitVoiceAreas(words.sublist(1).join(' '));
          }
        } else {
          final fuzzyCat = ShopSearchFuzzy.correctQuery(query);
          if (fuzzyCat.changed) query = fuzzyCat.text;
        }
      }
    }

    if (query.isEmpty && areas.isEmpty) query = text;

    return (
      query: query,
      area: areas.isEmpty ? '' : areas.join(', '),
    );
  }

  void _applyVoiceText(String spoken) {
    final parsed = _parseVoiceText(spoken);
    setState(() {
      _voiceText = spoken.trim();
      if (parsed.query.isNotEmpty) _query.text = parsed.query;
      if (parsed.area.isNotEmpty) _area.text = parsed.area;
      _error = null;
    });
  }

  Future<void> _startVoiceSearch() async {
    if (_loading || _isListening) return;
    FocusScope.of(context).unfocus();

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          _error = 'Could not hear clearly. Tap the mic and try again.';
        });
      },
    );

    if (!mounted) return;
    if (!available) {
      setState(() => _error = 'Voice search is not available on this phone.');
      return;
    }

    setState(() {
      _isListening = true;
      _voiceText = '';
      _voiceHint = 'Listening… say shop type and area, e.g. “Plywood in Kukatpally”.';
      _error = null;
    });

    await _speech.listen(
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 25),
      localeId: 'en_IN',
      onResult: (SpeechRecognitionResult result) {
        if (!mounted) return;
        setState(() => _voiceText = result.recognizedWords);
      },
    );
  }

  Future<void> _finishVoiceSearch() async {
    final spoken = _voiceText.trim();
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _voiceHint = null;
    });
    if (spoken.isEmpty) {
      setState(() => _error = 'Nothing heard. Tap Voice search and try again.');
      return;
    }
    _applyVoiceText(spoken);
    await _search();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    final area = _area.text.trim();
    if (q.isEmpty && area.isEmpty) {
      setState(() => _error = 'Enter shop type and/or area, or use voice search.');
      return;
    }

    final normalized = BusinessDirectoryService.normalizeInputs(query: q, area: area);
    String? correctionHint;
    if (normalized.changed) {
      final parts = <String>[];
      if (normalized.query.isNotEmpty &&
          normalized.query.toLowerCase() != q.toLowerCase()) {
        parts.add('shop type “${normalized.query}”');
      }
      if (normalized.area.isNotEmpty &&
          normalized.area.toLowerCase() != area.toLowerCase()) {
        parts.add('area “${normalized.area}”');
      }
      if (parts.isNotEmpty) {
        correctionHint = 'Showing results for ${parts.join(' and ')}';
      }
    }

    setState(() {
      _loading = true;
      _error = null;
      _correctionHint = correctionHint;
    });

    try {
      final pos = await FieldRouteHelpers.resolveCurrentPosition();
      final service = BusinessDirectoryService(ref.read(apiProvider));
      final rawAreas = area.isEmpty
          ? ['']
          : _splitVoiceAreas(area).isEmpty
              ? [area]
              : _splitVoiceAreas(area);

      final merged = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final a in rawAreas) {
        final correctedArea = ShopSearchFuzzy.correctArea(a).text;
        final batch = await service.search(
          query: q,
          area: correctedArea.isEmpty ? null : correctedArea,
          latitude: pos?.latitude,
          longitude: pos?.longitude,
          radiusKm: correctedArea.isEmpty ? 10 : 8,
          limit: 30,
        );
        for (final item in batch) {
          final key = '${item['businessName']}|${item['address']}'.toLowerCase();
          if (seen.add(key)) {
            if (correctedArea.isNotEmpty) item['searchArea'] = correctedArea;
            merged.add(item);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _results = merged;
        _loading = false;
        if (merged.isEmpty) {
          final displayQ = normalized.query.isNotEmpty ? normalized.query : q;
          final displayArea = normalized.area.isNotEmpty ? normalized.area : area;
          _error = displayQ.isEmpty
              ? 'No shops found in $displayArea.'
              : 'No shops found for “$displayQ”${displayArea.isEmpty ? '' : ' in $displayArea'}.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
        _correctionHint = null;
      });
    }
  }

  Future<void> _saveAsOutlet(Map<String, dynamic> biz) async {
    final id = biz['id']?.toString() ?? biz['placeId']?.toString() ?? biz['businessName']?.toString();

    final exec = await ensureExecutiveForOutlet(context, ref);
    if (!mounted) return;
    if (mustAssignExecutiveOnOutletCreate(ref.read(authStoreProvider).user) &&
        exec == null) {
      bestieToast(context, 'Assign executive',
          body: 'Select a field executive before saving this shop as an outlet.',
          kind: BestieToastKind.warning);
      return;
    }

    setState(() => _savingId = id);
    try {
      await ref.read(apiProvider).createMarketingOutlet({
        'name': biz['businessName'] ?? 'Shop',
        'phone': biz['contactPhone'],
        'address': biz['address'],
        'latitude': biz['gpsLat'],
        'longitude': biz['gpsLng'],
        'category': biz['businessCategory'],
        if (exec != null) 'assignedToId': exec['id'],
        'source': 'directory',
      });
      if (mounted) {
        bestieToast(context, 'Saved as outlet', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save outlet',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  int _gridColumns(double width) {
    if (width >= 1000) return 3;
    if (width >= 680) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final bottomClearance = shellNavClearance(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Shop search'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      body: Column(
        children: [
          Material(
            color: c.surface,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    ref.watch(authStoreProvider).user?.isFieldManager == true &&
                            !canActAsFieldExecutive(ref.watch(authStoreProvider).user)
                        ? 'Find shops to add as outlets for your team. You will assign an executive when saving.'
                        : 'Find shops to add as outlets. Type or tap Voice search.',
                    style: TextStyle(color: c.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _query,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Shop type',
                      hintText: 'e.g. Plywood, Medical store',
                      filled: true,
                      fillColor: c.surface2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _area,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Area (optional)',
                      hintText: 'e.g. Kukatpally, Hyderabad',
                      filled: true,
                      fillColor: c.surface2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _loading ? null : _search,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: _loading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.surface),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(_loading ? 'Searching…' : 'Search shops'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : _isListening
                            ? _finishVoiceSearch
                            : _startVoiceSearch,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: _isListening ? c.success : c.brand,
                      side: BorderSide(
                        color: _isListening ? c.success : c.brand,
                        width: 1.5,
                      ),
                    ),
                    icon: Icon(_isListening ? Icons.check_rounded : Icons.mic_rounded),
                    label: Text(_isListening ? 'Done speaking' : 'Voice search'),
                  ),
                  if (_isListening || _voiceText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _isListening ? c.successSoft : c.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isListening
                              ? c.success.withValues(alpha: 0.4)
                              : c.borderSoft,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _isListening ? Icons.mic_rounded : Icons.record_voice_over_outlined,
                            size: 20,
                            color: _isListening ? c.success : c.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isListening
                                  ? (_voiceText.isEmpty
                                      ? (_voiceHint ?? 'Listening…')
                                      : _voiceText)
                                  : 'Heard: $_voiceText',
                              style: TextStyle(color: c.text, fontSize: 13, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
            ),
          if (_correctionHint != null && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.spellcheck_rounded, size: 18, color: c.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _correctionHint!,
                      style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: BestieSpinner())
                : _results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Search or use voice to find shops',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textMuted),
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final cols = _gridColumns(constraints.maxWidth);
                          if (cols == 1) {
                            return ListView.separated(
                              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomClearance),
                              itemCount: _results.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 16),
                              itemBuilder: (_, i) => _cardAt(i),
                            );
                          }
                          return GridView.builder(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomClearance),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              mainAxisExtent: 460,
                            ),
                            itemCount: _results.length,
                            itemBuilder: (_, i) => _cardAt(i),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _cardAt(int i) {
    final biz = _results[i];
    final id = biz['id']?.toString() ?? biz['placeId']?.toString() ?? '$i';
    return ShopListingCard(
      shop: biz,
      saving: _savingId == id,
      onTap: () => _openDetail(biz),
      onSaveOutlet: () => _saveAsOutlet(biz),
    );
  }

  void _openDetail(Map<String, dynamic> biz) {
    final id = biz['id']?.toString() ?? biz['placeId']?.toString() ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopDetailScreen(
          shop: biz,
          saving: _savingId == id,
          onSaveOutlet: () => _saveAsOutlet(biz),
        ),
      ),
    );
  }
}
