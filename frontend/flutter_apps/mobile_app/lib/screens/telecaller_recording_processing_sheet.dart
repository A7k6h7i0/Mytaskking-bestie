import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../telecaller_recording_uploader.dart';

/// Shown when the telecaller returns from a phone call — scans & uploads recording.
class TelecallerRecordingProcessingSheet extends ConsumerStatefulWidget {
  const TelecallerRecordingProcessingSheet({
    super.key,
    required this.callId,
    required this.callStartedAt,
    required this.phoneRecordingActive,
    required this.onFinished,
  });

  final String callId;
  final DateTime? callStartedAt;
  final bool phoneRecordingActive;
  final VoidCallback onFinished;

  @override
  ConsumerState<TelecallerRecordingProcessingSheet> createState() =>
      _TelecallerRecordingProcessingSheetState();
}

class _TelecallerRecordingProcessingSheetState
    extends ConsumerState<TelecallerRecordingProcessingSheet> {
  static const _primaryBlue = Color(0xFF3B99F6);

  RecordingProcessState _state = const RecordingProcessState(
    phase: RecordingProcessPhase.requestingAccess,
    detail: 'Preparing…',
  );
  bool _manualBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAuto());
  }

  Future<void> _runAuto() async {
    final uploader = TelecallerRecordingUploader(ref);
    await uploader.runAutoUpload(
      callId: widget.callId,
      callStartedAt: widget.callStartedAt,
      phoneRecordingActive: widget.phoneRecordingActive,
      onState: (s) {
        if (mounted) setState(() => _state = s);
      },
    );
  }

  Future<void> _pickManual() async {
    if (_manualBusy) return;
    setState(() => _manualBusy = true);
    final uploader = TelecallerRecordingUploader(ref);
    await uploader.uploadManualPick(
      callId: widget.callId,
      onState: (s) {
        if (mounted) setState(() => _state = s);
      },
    );
    if (mounted) setState(() => _manualBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final failed = _state.phase == RecordingProcessPhase.failed;
    final success = _state.phase == RecordingProcessPhase.success;
    final busy = !failed && !success;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Call recording',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 16),
          _StatusRow(state: _state, busy: busy),
          if (_state.fileName != null) ...[
            const SizedBox(height: 8),
            Text(
              _state.fileName!,
              style: TextStyle(fontSize: 13, color: c.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (_state.error != null) ...[
            const SizedBox(height: 10),
            Text(
              _state.error!,
              style: TextStyle(fontSize: 13, color: c.danger),
            ),
          ],
          const SizedBox(height: 24),
          if (failed) ...[
            FilledButton.icon(
              onPressed: _manualBusy ? null : _pickManual,
              icon: _manualBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.audio_file_outlined),
              label: const Text('Choose recording file manually'),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onFinished,
              child: const Text('Skip — log call outcome only'),
            ),
          ] else if (success) ...[
            FilledButton(
              onPressed: widget.onFinished,
              style: FilledButton.styleFrom(
                backgroundColor: _primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Continue'),
            ),
          ] else ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.state, required this.busy});

  final RecordingProcessState state;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    IconData icon;
    Color iconColor;

    switch (state.phase) {
      case RecordingProcessPhase.success:
        icon = Icons.check_circle_rounded;
        iconColor = c.success;
        break;
      case RecordingProcessPhase.failed:
        icon = Icons.error_outline_rounded;
        iconColor = c.danger;
        break;
      default:
        icon = Icons.folder_open_rounded;
        iconColor = const Color(0xFF3B99F6);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            state.detail ?? _phaseLabel(state.phase),
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: c.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _phaseLabel(RecordingProcessPhase phase) {
    switch (phase) {
      case RecordingProcessPhase.requestingAccess:
        return 'Checking storage access…';
      case RecordingProcessPhase.scanning:
        return 'Scanning for recording…';
      case RecordingProcessPhase.uploading:
        return 'Uploading…';
      case RecordingProcessPhase.success:
        return 'Recording uploaded';
      case RecordingProcessPhase.failed:
        return 'Upload failed';
      case RecordingProcessPhase.idle:
        return 'Waiting…';
    }
  }
}
