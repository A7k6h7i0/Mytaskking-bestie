import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

import 'field_route_helpers.dart';

/// Full-screen shop / business detail from directory search.
class ShopDetailScreen extends StatelessWidget {
  const ShopDetailScreen({
    super.key,
    required this.shop,
    required this.onSaveOutlet,
    this.saving = false,
  });

  final Map<String, dynamic> shop;
  final VoidCallback onSaveOutlet;
  final bool saving;

  String get _name => shop['businessName']?.toString() ?? 'Shop';
  String get _category => shop['businessCategory']?.toString() ?? '';
  String get _address => shop['address']?.toString() ?? '';
  String get _phone => shop['contactPhone']?.toString() ?? '';
  String get _email => shop['contactEmail']?.toString() ?? '';
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
    if (meters <= 0) return '';
    if (meters < 1000) return '$meters m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
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

  Future<void> _callPhone() async {
    if (_phone.isEmpty) return;
    final digits = _phone.replaceAll(RegExp(r'[^\d+]'), '');
    await launchUrl(Uri.parse('tel:$digits'), mode: LaunchMode.externalApplication);
  }

  Future<void> _emailShop() async {
    if (_email.isEmpty) return;
    await launchUrl(Uri.parse('mailto:$_email'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final rating = _rating;
    final reviews = _reviewCount;
    final dist = _distanceLabel();
    final pos = _position;

    final rows = <({IconData icon, String label, String value, VoidCallback? action})>[
      if (_category.isNotEmpty)
        (icon: Icons.category_outlined, label: 'Category', value: _category, action: null),
      if (_address.isNotEmpty)
        (icon: Icons.location_on_outlined, label: 'Address', value: _address, action: _openDirections),
      if (_phone.isNotEmpty)
        (icon: Icons.phone_outlined, label: 'Phone', value: _phone, action: _callPhone),
      if (_email.isNotEmpty)
        (icon: Icons.email_outlined, label: 'Email', value: _email, action: _emailShop),
      if (_website.isNotEmpty)
        (icon: Icons.language_outlined, label: 'Website', value: _website, action: _openWebsite),
      if (rating != null && rating > 0)
        (
          icon: Icons.star_outline_rounded,
          label: 'Rating',
          value: reviews != null && reviews > 0
              ? '${rating.toStringAsFixed(1)} ($reviews reviews)'
              : rating.toStringAsFixed(1),
          action: null,
        ),
      if (dist.isNotEmpty)
        (icon: Icons.near_me_outlined, label: 'Distance', value: dist, action: null),
      if (pos != null)
        (
          icon: Icons.gps_fixed,
          label: 'GPS',
          value: '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
          action: null,
        ),
    ];

    return Scaffold(
      backgroundColor: c.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: c.surface,
            foregroundColor: c.text,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: const Color(0xFFE2E8F0),
                    child: _image.isNotEmpty
                        ? Image.network(
                            _image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imageFallback(c),
                          )
                        : _imageFallback(c),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                  if (_category.isNotEmpty)
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1CA1EF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _category,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                      height: 1.2,
                    ),
                  ),
                  if (rating != null && rating > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _stars(rating),
                        const SizedBox(width: 8),
                        Text(
                          rating.toStringAsFixed(1),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: c.text,
                          ),
                        ),
                        if (reviews != null && reviews > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '($reviews reviews)',
                            style: TextStyle(color: c.textMuted, fontSize: 14),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  _mapPreview(c, pos),
                  const SizedBox(height: 20),
                  Text(
                    'Details',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...rows.map((r) => _detailRow(c, r.icon, r.label, r.value, r.action)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (_website.isNotEmpty)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openWebsite,
                            icon: const Icon(Icons.language_rounded, size: 18),
                            label: const Text('Website'),
                          ),
                        ),
                      if (_website.isNotEmpty) const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_position != null || _address.isNotEmpty)
                              ? _openDirections
                              : null,
                          icon: const Icon(Icons.directions_rounded, size: 18),
                          label: const Text('Directions'),
                        ),
                      ),
                    ],
                  ),
                  if (_phone.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _callPhone,
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: Text('Call $_phone'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: saving ? null : onSaveOutlet,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.surface),
                          )
                        : const Icon(Icons.add_business_outlined),
                    label: Text(saving ? 'Saving outlet…' : 'Save as outlet'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapPreview(BestieColors c, LatLng? pos) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: c.brandSoft,
        child: InkWell(
          onTap: (pos != null || _address.isNotEmpty) ? _openDirections : null,
          child: SizedBox(
            height: 190,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (pos != null)
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: pos,
                      initialZoom: 15.5,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.mytaskking.mytaskking_mobile',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: pos,
                            width: 44,
                            height: 44,
                            child: Icon(Icons.location_on, color: c.brand, size: 42),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, color: c.brand, size: 38),
                        const SizedBox(height: 8),
                        Text(
                          'Map location unavailable',
                          style: TextStyle(color: c.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                if (_address.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: c.shadow1,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.place_outlined, size: 18, color: c.brand),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: c.text),
                            ),
                          ),
                          Icon(Icons.open_in_new, size: 16, color: c.textMuted),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    BestieColors c,
    IconData icon,
    String label,
    String value,
    VoidCallback? onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: c.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: c.textMuted)),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: TextStyle(fontSize: 14, color: c.text, height: 1.35),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) Icon(Icons.chevron_right, color: c.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
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
        return Icon(icon, size: 20, color: const Color(0xFFFBBC04));
      }),
    );
  }

  Widget _imageFallback(BestieColors c) {
    return Center(
      child: Icon(Icons.storefront_rounded, size: 64, color: c.textMuted.withValues(alpha: 0.45)),
    );
  }
}
