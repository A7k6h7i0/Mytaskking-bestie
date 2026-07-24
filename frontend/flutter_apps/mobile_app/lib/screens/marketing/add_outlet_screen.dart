import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_route_helpers.dart';
import 'outlet_location_picker.dart';

/// Simple add-outlet flow — name + location (GPS or map).
class AddOutletScreen extends ConsumerStatefulWidget {
  const AddOutletScreen({super.key});

  @override
  ConsumerState<AddOutletScreen> createState() => _AddOutletScreenState();
}

class _AddOutletScreenState extends ConsumerState<AddOutletScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  LatLng? _location;
  String? _locationLabel;
  bool _busy = false;
  bool _locating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final places = await placemarkFromCoordinates(point.latitude, point.longitude);
      if (places.isEmpty) {
        setState(() {
          _locationLabel =
              '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
        });
        return;
      }
      final p = places.first;
      final parts = [
        if (p.street != null && p.street!.trim().isNotEmpty) p.street,
        if (p.subLocality != null && p.subLocality!.trim().isNotEmpty) p.subLocality,
        if (p.locality != null && p.locality!.trim().isNotEmpty) p.locality,
        if (p.administrativeArea != null && p.administrativeArea!.trim().isNotEmpty)
          p.administrativeArea,
      ].whereType<String>().toList();
      setState(() {
        _locationLabel = parts.isEmpty
            ? '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}'
            : parts.join(', ');
      });
    } catch (_) {
      setState(() {
        _locationLabel =
            '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
      });
    }
  }

  Future<void> _setLocation(LatLng point) async {
    setState(() {
      _location = point;
      _locationLabel = 'Finding address…';
    });
    await _reverseGeocode(point);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    final pos = await FieldRouteHelpers.resolveCurrentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos == null) {
      bestieToast(context, 'Location is off',
          body: 'Allow GPS in phone settings, then try again.',
          kind: BestieToastKind.warning);
      return;
    }
    await _setLocation(pos);
    if (mounted) {
      bestieToast(context, 'Location set', kind: BestieToastKind.success);
    }
  }

  Future<void> _pickOnMap() async {
    final picked = await OutletLocationPicker.open(context, initial: _location);
    if (picked == null || !mounted) return;
    await _setLocation(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      bestieToast(context, 'Add shop location',
          body: 'Tap “Use my location” or “Pick on map”.',
          kind: BestieToastKind.warning);
      return;
    }

    setState(() => _busy = true);
    try {
      String? address;
      String? city;
      try {
        final places =
            await placemarkFromCoordinates(_location!.latitude, _location!.longitude);
        if (places.isNotEmpty) {
          final p = places.first;
          address = [
            if (p.street != null && p.street!.trim().isNotEmpty) p.street,
            if (p.subLocality != null && p.subLocality!.trim().isNotEmpty) p.subLocality,
          ].whereType<String>().join(', ');
          if (address.isEmpty) address = null;
          city = p.locality ?? p.administrativeArea;
        }
      } catch (_) {}

      await ref.read(apiProvider).createMarketingOutlet({
        'name': _nameCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
        'latitude': _location!.latitude,
        'longitude': _location!.longitude,
        if (address != null && address.isNotEmpty) 'address': address,
        if (city != null && city.isNotEmpty) 'city': city,
        'source': 'manual',
      });

      if (!mounted) return;
      bestieToast(context, 'Outlet saved', kind: BestieToastKind.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      bestieToast(context, 'Could not save',
          body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Add new outlet'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Fill in the shop details. Location is required so it shows on your route map.',
              style: TextStyle(color: c.textMuted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text('Shop name', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'e.g. Rama General Store',
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Icons.storefront_outlined, color: c.textMuted),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter shop name' : null,
            ),
            const SizedBox(height: 16),
            Text('Phone (optional)',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '10-digit mobile number',
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Icons.phone_outlined, color: c.textMuted),
              ),
            ),
            const SizedBox(height: 24),
            Text('Shop location',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 4),
            Text(
              'Choose one option below',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _locationTile(
              c,
              icon: Icons.my_location_rounded,
              title: 'Use my current location',
              subtitle: 'Best when you are standing at the shop',
              loading: _locating,
              onTap: _locating ? null : _useCurrentLocation,
            ),
            const SizedBox(height: 10),
            _locationTile(
              c,
              icon: Icons.map_outlined,
              title: 'Pick on map',
              subtitle: 'Search area or tap the map to place pin',
              onTap: _pickOnMap,
            ),
            if (_location != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.successSoft,
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                  border: Border.all(color: c.success.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, color: c.success, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Location ready',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, color: c.text)),
                          const SizedBox(height: 4),
                          Text(
                            _locationLabel ?? '',
                            style: TextStyle(color: c.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _pickOnMap,
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                ),
              ),
              child: _busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.surface),
                    )
                  : const Text(
                      'Save outlet',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationTile(
    BestieColors c, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return Material(
      color: c.surface2,
      borderRadius: BorderRadius.circular(BestieTokens.rLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.brand),
                      )
                    : Icon(icon, color: c.brand, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
