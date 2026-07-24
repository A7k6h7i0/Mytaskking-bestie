import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import 'state.dart';
import 'telecaller_oem_recording.dart';
import 'telecaller_phone_recorder.dart';
import 'telecaller_recording_setup.dart';
import 'telecaller_recording_storage.dart';

enum RecordingProcessPhase {
  idle,
  requestingAccess,
  scanning,
  uploading,
  success,
  failed,
}

class RecordingProcessState {
  const RecordingProcessState({
    required this.phase,
    this.detail,
    this.fileName,
    this.error,
  });

  final RecordingProcessPhase phase;
  final String? detail;
  final String? fileName;
  final String? error;

  RecordingProcessState copyWith({
    RecordingProcessPhase? phase,
    String? detail,
    String? fileName,
    String? error,
  }) =>
      RecordingProcessState(
        phase: phase ?? this.phase,
        detail: detail ?? this.detail,
        fileName: fileName ?? this.fileName,
        error: error ?? this.error,
      );
}

typedef ProcessListener = void Function(RecordingProcessState state);

/// Auto-scan OEM folder / MediaStore and upload to backend.
class TelecallerRecordingUploader {
  TelecallerRecordingUploader(this._ref);

  final WidgetRef _ref;

  Future<bool> uploadFromHit(OemRecordingHit hit, String callId) async {
    List<int>? bytes;
    for (var attempt = 0; attempt < 6; attempt++) {
      bytes = await TelecallerOemRecording.readHitBytes(hit);
      if (bytes != null && bytes.isNotEmpty) break;
      if (attempt < 5) {
        await Future.delayed(Duration(milliseconds: 800 + attempt * 400));
      }
    }
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'Could not read "${hit.displayName}" from phone storage '
        '(file may still be saving). Use manual pick or wait a few seconds.',
      );
    }

    final api = _ref.read(apiProvider);
    late final Map<String, dynamic> asset;
    try {
      asset = await api.uploadFile(
        bytes: bytes,
        filename: hit.displayName,
        mimeType: hit.mimeType,
      );
    } catch (e) {
      throw StateError('File upload failed: ${formatApiError(e)}');
    }

    final fileId = asset['id']?.toString();
    final url = asset['url']?.toString();
    if ((fileId == null || fileId.isEmpty) && (url == null || url.isEmpty)) {
      throw StateError(
        'Server did not return a file URL after upload. Check R2/storage config.',
      );
    }

    try {
      await api.attachTelecallerCallRecording(
        callId,
        fileId: fileId,
        url: url,
      );
    } catch (e) {
      final msg = formatApiError(e);
      if (msg.toLowerCase().contains('call not found')) {
        throw StateError(
          'Call log not found on server ($callId). End the call from the app, not dialer only.',
        );
      }
      if (msg.toLowerCase().contains('route') &&
          msg.toLowerCase().contains('recording')) {
        throw StateError(
          'Telecaller recording API missing on server — redeploy backend from latest main.',
        );
      }
      throw StateError('Link recording to call failed: $msg');
    }

    await TelecallerRecordingSetup.markLastUploaded(hit.uri, hit.modifiedMs);
    return true;
  }

  Future<bool> runAutoUpload({
    required String callId,
    DateTime? callStartedAt,
    bool phoneRecordingActive = false,
    required ProcessListener onState,
  }) async {
    await TelecallerRecordingSetup.load();
    final hasFolder = TelecallerRecordingSetup.hasLinkedFolder;
    final hasLinked = TelecallerRecordingSetup.hasLinkedStorage;

    onState(const RecordingProcessState(
      phase: RecordingProcessPhase.requestingAccess,
      detail: 'Checking storage access…',
    ));

    if (TelecallerRecordingStorage.supported) {
      final ok = await TelecallerRecordingStorage.ensureAudioAccess();
      if (!ok && !hasLinked) {
        onState(const RecordingProcessState(
          phase: RecordingProcessPhase.failed,
          error: 'Storage permission denied',
          detail: 'Allow audio access or pick the file manually.',
        ));
        return false;
      }
    }

    if (hasLinked && !hasFolder) {
      onState(const RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        error: 'Only a test file was linked — link the recordings folder',
        detail: 'Setup → Choose folder (not a single file) for auto-upload.',
      ));
      return false;
    }

    if (hasFolder && TelecallerRecordingSetup.treeUri != null) {
      final accessible = await TelecallerRecordingStorage.verifyTreeAccess(
        TelecallerRecordingSetup.treeUri!,
      );
      if (!accessible) {
        onState(const RecordingProcessState(
          phase: RecordingProcessPhase.failed,
          error: 'Folder access lost — re-link in telecaller setup',
          detail: 'Open setup and choose your call recordings folder again.',
        ));
        return false;
      }
    }

    // Prefer OEM folder when linked — skip unreliable mic capture.
    if (!hasLinked &&
        phoneRecordingActive &&
        TelecallerPhoneRecorder.supported) {
      onState(const RecordingProcessState(
        phase: RecordingProcessPhase.scanning,
        detail: 'Saving in-app recording…',
      ));
      final micPath = await TelecallerPhoneRecorder.instance.stop();
      if (micPath != null) {
        try {
          final file = File(micPath);
          if (await file.exists()) {
            onState(RecordingProcessState(
              phase: RecordingProcessPhase.uploading,
              fileName: file.path.split(Platform.pathSeparator).last,
              detail: 'Uploading recording…',
            ));
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty) {
              final api = _ref.read(apiProvider);
              final asset = await api.uploadFile(
                bytes: bytes,
                filename: file.path.split(Platform.pathSeparator).last,
                mimeType: 'audio/mp4',
              );
              await api.attachTelecallerCallRecording(
                callId,
                fileId: asset['id']?.toString(),
                url: asset['url']?.toString(),
              );
              try {
                await file.delete();
              } catch (_) {}
              onState(const RecordingProcessState(
                phase: RecordingProcessPhase.success,
                detail: 'Recording uploaded',
              ));
              return true;
            }
          }
        } catch (e) {
          onState(RecordingProcessState(
            phase: RecordingProcessPhase.failed,
            error: formatApiError(e),
          ));
          return false;
        }
      }
    }

    final label = TelecallerRecordingSetup.folderLabel;
    onState(RecordingProcessState(
      phase: RecordingProcessPhase.scanning,
      detail: label != null
          ? 'Scanning $label… (It may take up to 30s)'
          : 'Scanning for call recording…',
    ));

    // Give OEM dialers time to flush the file after hang-up.
    await Future.delayed(const Duration(seconds: 2));

    final modifiedAfter = callStartedAt != null
        ? callStartedAt.subtract(const Duration(seconds: 90))
        : DateTime.now().subtract(const Duration(minutes: 5));

    OemRecordingHit? hit;
    try {
      hit = await TelecallerOemRecording.findNewestWithRetry(
        modifiedAfter: modifiedAfter,
        attempts: 12,
        delay: const Duration(seconds: 2),
      );
    } catch (e) {
      onState(RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        error: formatApiError(e),
        detail: 'Could not read recordings folder',
      ));
      return false;
    }

    if (hit == null) {
      onState(const RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        error: 'No new recording found',
        detail: 'Auto-scan did not find a call recording file.',
      ));
      return false;
    }

    onState(RecordingProcessState(
      phase: RecordingProcessPhase.uploading,
      fileName: hit.displayName,
      detail: 'Uploading ${hit.displayName}…',
    ));

    try {
      final ok = await uploadFromHit(hit, callId);
      if (ok) {
        onState(const RecordingProcessState(
          phase: RecordingProcessPhase.success,
          detail: 'Recording uploaded',
        ));
        return true;
      }
    } catch (e) {
      onState(RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        error: e is StateError ? e.message : formatApiError(e),
        detail: 'Upload failed',
        fileName: hit.displayName,
      ));
      return false;
    }

    onState(RecordingProcessState(
      phase: RecordingProcessPhase.failed,
      error: 'Could not read recording file',
      fileName: hit.displayName,
    ));
    return false;
  }

  Future<bool> uploadManualPick({
    required String callId,
    required ProcessListener onState,
  }) async {
    onState(const RecordingProcessState(
      phase: RecordingProcessPhase.scanning,
      detail: 'Choose a recording file…',
    ));

    if (TelecallerRecordingStorage.supported) {
      await TelecallerRecordingStorage.ensureAudioAccess();
      final picked = await TelecallerRecordingStorage.pickRecordingFile();
      if (picked == null) {
        onState(const RecordingProcessState(
          phase: RecordingProcessPhase.failed,
          error: 'No file selected',
        ));
        return false;
      }

      final uri = picked['fileUri'] as String?;
      final name = picked['displayName'] as String? ?? 'recording';
      if (uri == null || uri.isEmpty) return false;

      final hit = OemRecordingHit(
        uri: uri,
        displayName: name,
        modifiedMs: (picked['modifiedMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        size: (picked['size'] as num?)?.toInt() ?? 0,
        source: 'manual',
        mimeType: TelecallerOemRecording.mimeForPath(name),
      );

      onState(RecordingProcessState(
        phase: RecordingProcessPhase.uploading,
        fileName: name,
        detail: 'Uploading $name…',
      ));

      try {
        final ok = await uploadFromHit(hit, callId);
        if (ok) {
          await TelecallerRecordingSetup.setLinkedFile(
            fileUri: uri,
            displayName: name,
          );
          onState(const RecordingProcessState(
            phase: RecordingProcessPhase.success,
            detail: 'Recording uploaded',
          ));
          return true;
        }
      } catch (e) {
        onState(RecordingProcessState(
          phase: RecordingProcessPhase.failed,
          error: e is StateError ? e.message : formatApiError(e),
          fileName: name,
        ));
        return false;
      }
    }

    onState(const RecordingProcessState(
      phase: RecordingProcessPhase.failed,
      error: 'Manual pick not supported on this device',
    ));
    return false;
  }
}
