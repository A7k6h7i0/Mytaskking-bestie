import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';

/// Admin field-force policy toggles (workspace settings scope `field`).
class FieldSettingsSection extends ConsumerStatefulWidget {
  const FieldSettingsSection({super.key});

  @override
  ConsumerState<FieldSettingsSection> createState() =>
      _FieldSettingsSectionState();
}

class _FieldSettingsSectionState extends ConsumerState<FieldSettingsSection> {
  bool _visitSelfieRequired = true;
  bool _blinkSelfieRequired = true;
  bool _outletApprovalRequired = true;
  int _gpsInterval = 120;
  int _autoVisitMinutes = 0;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(apiProvider).marketingFieldSettings();
      if (!mounted) return;
      setState(() {
        _visitSelfieRequired = s['visitSelfieRequired'] != false;
        _blinkSelfieRequired = s['blinkSelfieRequired'] != false;
        _outletApprovalRequired = s['outletCreationApprovalRequired'] == true;
        _gpsInterval = (s['gpsIntervalMovingSeconds'] as num?)?.toInt() ?? 120;
        _autoVisitMinutes =
            (s['autoVisitDurationMinutes'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String key, Object value) async {
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).setSetting(
            scope: 'field',
            key: key,
            value: value,
          );
      if (mounted) {
        bestieToast(context, 'Field setting saved', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: BestieSpinner(color: c.brand)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: Text('Visit selfie required', style: TextStyle(color: c.text)),
          subtitle: Text('Executives must capture a selfie to check in',
              style: TextStyle(color: c.textMuted, fontSize: 12)),
          value: _visitSelfieRequired,
          onChanged: _saving
              ? null
              : (v) {
                  setState(() => _visitSelfieRequired = v);
                  _save('visitSelfieRequired', v);
                },
        ),
        SwitchListTile(
          title: Text('Blink selfie (liveness)', style: TextStyle(color: c.text)),
          subtitle: Text('Require eye-blink before visit check-in photo',
              style: TextStyle(color: c.textMuted, fontSize: 12)),
          value: _blinkSelfieRequired,
          onChanged: _saving || !_visitSelfieRequired
              ? null
              : (v) {
                  setState(() => _blinkSelfieRequired = v);
                  _save('blinkSelfieRequired', v);
                },
        ),
        SwitchListTile(
          title: Text('Outlet creation approval', style: TextStyle(color: c.text)),
          subtitle: Text('New outlets from executives need manager approval',
              style: TextStyle(color: c.textMuted, fontSize: 12)),
          value: _outletApprovalRequired,
          onChanged: _saving
              ? null
              : (v) {
                  setState(() => _outletApprovalRequired = v);
                  _save('outletCreationApprovalRequired', v);
                },
        ),
        ListTile(
          title: Text('GPS ping interval', style: TextStyle(color: c.text)),
          subtitle: Text('Every $_gpsInterval seconds during active visit',
              style: TextStyle(color: c.textMuted, fontSize: 12)),
          trailing: DropdownButton<int>(
            value: _gpsInterval,
            items: const [
              DropdownMenuItem(value: 60, child: Text('1 min')),
              DropdownMenuItem(value: 120, child: Text('2 min')),
              DropdownMenuItem(value: 300, child: Text('5 min')),
            ],
            onChanged: _saving
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _gpsInterval = v);
                    _save('gpsIntervalMovingSeconds', v);
                  },
          ),
        ),
        ListTile(
          title: Text('Auto-complete visit', style: TextStyle(color: c.text)),
          subtitle: Text(
            _autoVisitMinutes > 0
                ? 'After $_autoVisitMinutes minutes at outlet'
                : 'Off — manual checkout only',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          trailing: DropdownButton<int>(
            value: _autoVisitMinutes,
            items: const [
              DropdownMenuItem(value: 0, child: Text('Off')),
              DropdownMenuItem(value: 5, child: Text('5 min')),
              DropdownMenuItem(value: 15, child: Text('15 min')),
              DropdownMenuItem(value: 30, child: Text('30 min')),
            ],
            onChanged: _saving
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _autoVisitMinutes = v);
                    _save('autoVisitDurationMinutes', v);
                  },
          ),
        ),
      ],
    );
  }
}
