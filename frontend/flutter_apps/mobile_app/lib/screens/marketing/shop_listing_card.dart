import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

import 'field_route_helpers.dart';

/// Google-style business listing card (responsive grid item).
class ShopListingCard extends StatelessWidget {
  const ShopListingCard({
    super.key,
    required this.shop,
    required this.onSaveOutlet,
    this.onTap,
    this.saving = false,
  });

  final Map<String, dynamic> shop;
  final VoidCallback onSaveOutlet;
  final VoidCallback? onTap;
  final bool saving;

  String get _name => shop['businessName']?.toString() ?? 'Shop';
  String get _category => shop['businessCategory']?.toString() ?? '';
  String get _address => shop['address']?.toString() ?? '';
  String get _phone => shop['contactPhone']?.toString() ?? '';
  String get _website => shop['website']?.toString() ?? '';
  String get _image => shop['featuredImage']?.toString() ?? '';
  double? get _rating {
    final r = shop['rating'];
    if (r is num) return r.toDouble();
    return double.tryParse(r?.toString() ?? '');
  }

  int? get _reviewCount {
    final c = shop['reviewCount'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return int.tryParse(c?.toString() ?? '');
  }

  LatLng? get _position {
    final lat = double.tryParse(shop['gpsLat']?.toString() ?? '');
    final lng = double.tryParse(shop['gpsLng']?.toString() ?? '');
    if (lat == null || lng == null) return null;
    if (!FieldRouteHelpers.isValidCoord(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  String _distanceLabel() {
    final m = shop['distanceMeters'];
    if (m is! num) return '';
    final meters = m.round();
    if (meters < 0) return '';
    if (meters < 1000) return '$meters m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  Widget _stars(double rating) {
    final stars = rating.clamp(0, 5);
    final full = stars.floor();
    final hasHalf = (stars - full) >= 0.25 && full < 5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        IconData icon;
        if (i < full) {
          icon = Icons.star_rounded;
        } else if (i == full && hasHalf) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(icon, size: 18, color: const Color(0xFFFBBC04));
      }),
    );
  }

  Future<void> _openWebsite() async {
    var url = _website.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _openDirections() async {
    final pos = _position;
    if (pos != null) {
      await FieldRouteHelpers.openMapsNavigation(pos, label: _name);
      return;
    }
    if (_address.isEmpty) return;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': _address,
      'travelmode': 'driving',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final rating = _rating;
    final reviews = _reviewCount;
    final dist = _distanceLabel();
    final searchArea = shop['searchArea']?.toString() ?? '';

    return Material(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 180,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: c.surface2,
                        child: _image.isNotEmpty
                            ? Image.network(
                                _image,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _imageFallback(c),
                              )
                            : _imageFallback(c),
                      ),
                      if (_category.isNotEmpty)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1CA1EF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _category,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      if (dist.isNotEmpty)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              dist,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      if (onTap != null)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_full, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text('Details',
                                    style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                          height: 1.3,
                        ),
                      ),
                      if (rating != null && rating > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stars(rating),
                            const SizedBox(width: 6),
                            Text(
                              rating.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: c.text,
                              ),
                            ),
                            if (reviews != null && reviews > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '($reviews reviews)',
                                style: TextStyle(fontSize: 14, color: c.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (searchArea.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          searchArea,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.brand),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_address.isNotEmpty)
                        _infoRow(c, Icons.location_on_outlined, _address),
                      if (_phone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _infoRow(c, Icons.phone_outlined, _phone),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _footerBtn(
                        c,
                        label: 'Website',
                        icon: Icons.language_rounded,
                        enabled: _website.isNotEmpty,
                        onTap: _openWebsite,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _footerBtn(
                        c,
                        label: 'Directions',
                        icon: Icons.directions_rounded,
                        enabled: _position != null || _address.isNotEmpty,
                        onTap: _openDirections,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saving ? null : onSaveOutlet,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.surface),
                          )
                        : const Icon(Icons.add_business_outlined, size: 18),
                    label: Text(saving ? 'Saving…' : 'Save as outlet'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageFallback(BestieColors c) {
    return Center(
      child: Icon(Icons.storefront_rounded, size: 48, color: c.textMuted.withValues(alpha: 0.5)),
    );
  }

  Widget _infoRow(BestieColors c, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: c.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: c.textSoft, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _footerBtn(
    BestieColors c, {
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled ? c.surface2 : c.surface3,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.borderSoft),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: enabled ? c.text : c.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: enabled ? c.text : c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
