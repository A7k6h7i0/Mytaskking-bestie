import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_helpers.dart';
import 'field_sub_scaffold.dart';
import 'gps_map_view_screen.dart';

class FieldGpsScreen extends ConsumerStatefulWidget {
  const FieldGpsScreen({super.key});

  @override
  ConsumerState<FieldGpsScreen> createState() => _FieldGpsScreenState();
}

class _FieldGpsScreenState extends ConsumerState<FieldGpsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ref.read(apiProvider).listFieldGps(pageSize: 100);
      if (!mounted) return;
      setState(() {
        _items = ((resp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
      });
    }
  }

  LatLng? _pointFor(Map<String, dynamic> g) {
    final lat = parseFieldCoordinate(g['latitude']);
    final lng = parseFieldCoordinate(g['longitude']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  String _formatLoggedAt(dynamic raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return '';
    final dt = DateTime.tryParse(text);
    if (dt == null) return text;
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _openMap(Map<String, dynamic> g) {
    final point = _pointFor(g);
    if (point == null) {
      bestieToast(context, 'No coordinates',
          body: 'This GPS entry has no map location.',
          kind: BestieToastKind.warning);
      return;
    }
    final user = (g['user'] as Map?)?.cast<String, dynamic>();
    GpsMapViewScreen.open(
      context,
      point: point,
      title: user?['name']?.toString() ?? 'Executive',
      subtitle: _formatLoggedAt(g['loggedAt']),
    );
  }

  Widget _emptyBody(
    BestieColors c, {
    required String message,
    required IconData icon,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight > 0 ? constraints.maxHeight : 320,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 40, color: c.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final isManager = ref.watch(authStoreProvider).user?.isFieldManager ?? false;
    if (!isManager) {
      return FieldSubScaffold(
        title: 'GPS log',
        body: Center(child: Text('Managers only', style: TextStyle(color: c.textMuted))),
      );
    }
    return FieldSubScaffold(
      title: 'Team GPS log',
      body: _loading
          ? const Center(child: BestieSpinner())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? _emptyBody(
                      c,
                      icon: Icons.error_outline,
                      message: _error!,
                    )
                  : _items.isEmpty
                      ? _emptyBody(
                          c,
                          icon: Icons.my_location_outlined,
                          message:
                              'No GPS pings yet.\nExecutives log location during active outlet visits.',
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final g = _items[i];
                            final user = (g['user'] as Map?)?.cast<String, dynamic>();
                            final point = _pointFor(g);
                            final lat = parseFieldCoordinate(g['latitude']);
                            final lng = parseFieldCoordinate(g['longitude']);
                            final coords = (lat != null && lng != null)
                                ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                                : 'No coordinates';
                            return ListTile(
                              tileColor: c.surface2,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              title: Text(user?['name']?.toString() ?? 'Executive'),
                              subtitle: Text(
                                '$coords\n${_formatLoggedAt(g['loggedAt'])}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                tooltip: 'Map view',
                                icon: Icon(Icons.map_outlined, color: c.brand),
                                onPressed: point == null ? null : () => _openMap(g),
                              ),
                              onTap: point == null ? null : () => _openMap(g),
                            );
                          },
                        ),
            ),
    );
  }
}
