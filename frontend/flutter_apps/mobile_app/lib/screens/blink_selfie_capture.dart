import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

/// Front-camera selfie that only captures after a detected eye blink (liveness).
/// Returns the captured [File] via [Navigator.pop], or null if cancelled.
class BlinkSelfieCaptureScreen extends StatefulWidget {
  const BlinkSelfieCaptureScreen({
    super.key,
    this.title = 'Blink to capture selfie',
  });

  final String title;

  /// Opens the blink-gated selfie screen and returns the captured file, or null.
  static Future<File?> open(
    BuildContext context, {
    String title = 'Blink to capture selfie',
  }) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BlinkSelfieCaptureScreen(title: title),
      ),
    );
  }

  /// Returns JPEG bytes after blink-verified capture, or null if cancelled.
  static Future<Uint8List?> captureBytes(
    BuildContext context, {
    String title = 'Blink to capture selfie',
  }) async {
    final file = await open(context, title: title);
    if (file == null) return null;
    return file.readAsBytes();
  }

  @override
  State<BlinkSelfieCaptureScreen> createState() => _BlinkSelfieCaptureScreenState();
}

enum _BlinkPhase { lookingForFace, eyesOpen, eyesClosed, blinkDone, capturing }

class _BlinkSelfieCaptureScreenState extends State<BlinkSelfieCaptureScreen> {
  CameraController? _controller;
  FaceDetector? _detector;
  bool _initializing = true;
  bool _busy = false;
  bool _capturing = false;
  String? _error;
  String _hint = 'Position your face in the oval';
  _BlinkPhase _phase = _BlinkPhase.lookingForFace;

  /// Consecutive frames with eyes closed after eyes were open.
  int _closedFrames = 0;
  bool _hadEyesOpen = false;
  DateTime? _lastProcessAt;

  static const double _openThreshold = 0.55;
  static const double _closedThreshold = 0.25;
  static const int _minClosedFrames = 2;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.2,
        ),
      );

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'No camera found on this device.';
        });
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      setState(() => _initializing = false);

      await controller.startImageStream(_onCameraImage);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error =
            'Could not open the camera. Allow Camera permission in system settings, then try again.';
      });
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (_busy || _capturing || _phase == _BlinkPhase.blinkDone) return;
    final now = DateTime.now();
    if (_lastProcessAt != null &&
        now.difference(_lastProcessAt!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastProcessAt = now;
    _busy = true;

    try {
      final input = _inputImageFromCamera(image);
      if (input == null) return;

      final faces = await _detector!.processImage(input);
      if (!mounted) return;

      if (faces.isEmpty) {
        _updateUi(
          phase: _BlinkPhase.lookingForFace,
          hint: 'Position your face in the oval',
        );
        _resetBlinkState();
        return;
      }

      final face = faces.first;
      final left = face.leftEyeOpenProbability;
      final right = face.rightEyeOpenProbability;

      if (left == null || right == null) {
        _updateUi(
          phase: _BlinkPhase.lookingForFace,
          hint: 'Look straight at the camera',
        );
        return;
      }

      final avg = (left + right) / 2;
      final eyesOpen = avg >= _openThreshold;
      final eyesClosed = avg <= _closedThreshold;

      if (_phase == _BlinkPhase.capturing) return;

      if (!_hadEyesOpen) {
        if (eyesOpen) {
          _hadEyesOpen = true;
          _closedFrames = 0;
          _updateUi(
            phase: _BlinkPhase.eyesOpen,
            hint: 'Blink your eyes to capture',
          );
        } else {
          _updateUi(
            phase: _BlinkPhase.lookingForFace,
            hint: 'Keep your eyes open, then blink',
          );
        }
        return;
      }

      if (eyesClosed) {
        _closedFrames++;
        _updateUi(
          phase: _BlinkPhase.eyesClosed,
          hint: 'Blink detected… open your eyes',
        );
        return;
      }

      if (_closedFrames >= _minClosedFrames && eyesOpen) {
        _updateUi(
          phase: _BlinkPhase.blinkDone,
          hint: 'Blink verified — capturing…',
        );
        await _captureAfterBlink();
        return;
      }

      if (eyesOpen) {
        _closedFrames = 0;
        _updateUi(
          phase: _BlinkPhase.eyesOpen,
          hint: 'Blink your eyes to capture',
        );
      }
    } catch (_) {
      // Frame dropped — keep streaming.
    } finally {
      _busy = false;
    }
  }

  void _resetBlinkState() {
    _hadEyesOpen = false;
    _closedFrames = 0;
  }

  void _updateUi({required _BlinkPhase phase, required String hint}) {
    if (!mounted) return;
    if (_phase == phase && _hint == hint) return;
    setState(() {
      _phase = phase;
      _hint = hint;
    });
  }

  Future<void> _captureAfterBlink() async {
    if (_capturing) return;
    _capturing = true;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _capturing = false;
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      // Brief pause so the face is open-eyed in the still photo.
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;

      setState(() => _phase = _BlinkPhase.capturing);

      final shot = await controller.takePicture();
      final saved = await _persistJpeg(shot);

      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Capture failed. Please try again.';
        _phase = _BlinkPhase.lookingForFace;
        _hint = 'Blink your eyes to capture';
        _capturing = false;
      });
      _resetBlinkState();
      try {
        if (_controller != null &&
            _controller!.value.isInitialized &&
            !_controller!.value.isStreamingImages) {
          await _controller!.startImageStream(_onCameraImage);
        }
      } catch (_) {}
    }
  }

  Future<File> _persistJpeg(XFile shot) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/blink_selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(path);
    await file.writeAsBytes(await shot.readAsBytes());
    return file;
  }

  InputImage? _inputImageFromCamera(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;

    final sensorOrientation = controller.description.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    // Prefer NV21 (Android) / BGRA8888 (iOS) as required by ML Kit.
    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    Uint8List bytes;
    InputImageFormat imageFormat;
    int bytesPerRow;

    if (Platform.isAndroid) {
      if (format == InputImageFormat.nv21 && image.planes.length == 1) {
        bytes = image.planes.first.bytes;
        imageFormat = InputImageFormat.nv21;
        bytesPerRow = image.planes.first.bytesPerRow;
      } else if (image.planes.length >= 3) {
        // CameraX often delivers YUV_420_888 — convert to NV21.
        bytes = _yuv420ToNv21(image);
        imageFormat = InputImageFormat.nv21;
        bytesPerRow = image.width;
      } else {
        return null;
      }
    } else {
      if (format != InputImageFormat.bgra8888 || image.planes.isEmpty) {
        return null;
      }
      bytes = image.planes.first.bytes;
      imageFormat = InputImageFormat.bgra8888;
      bytesPerRow = image.planes.first.bytesPerRow;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: imageFormat,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  /// Packs YUV_420_888 camera planes into a single NV21 buffer for ML Kit.
  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final ySize = width * height;
    final out = Uint8List(ySize + (width * height ~/ 2));

    // Copy Y
    var outIndex = 0;
    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      out.setRange(outIndex, outIndex + width, yPlane.bytes, rowStart);
      outIndex += width;
    }

    // Interleave V/U (NV21 = YYYY + VUVU…)
    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < uvHeight; row++) {
      for (var col = 0; col < uvWidth; col++) {
        final uIndex = row * uPlane.bytesPerRow + col * uPixelStride;
        final vIndex = row * vPlane.bytesPerRow + col * vPixelStride;
        out[outIndex++] = vPlane.bytes[vIndex];
        out[outIndex++] = uPlane.bytes[uIndex];
      }
    }
    return out;
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(() async {
        try {
          if (controller.value.isStreamingImages) {
            await controller.stopImageStream();
          }
        } catch (_) {}
        try {
          await controller.dispose();
        } catch (_) {}
      }());
    }
    final detector = _detector;
    _detector = null;
    if (detector != null) {
      unawaited(detector.close());
    }
    super.dispose();
  }

  Color get _ringColor {
    switch (_phase) {
      case _BlinkPhase.lookingForFace:
        return Colors.white70;
      case _BlinkPhase.eyesOpen:
        return const Color(0xFFFFC107);
      case _BlinkPhase.eyesClosed:
        return const Color(0xFF4CAF50);
      case _BlinkPhase.blinkDone:
      case _BlinkPhase.capturing:
        return const Color(0xFF2196F3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null && _controller == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller!;
    final previewSize = controller.value.previewSize;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (previewSize != null)
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: previewSize.height,
                height: previewSize.width,
                child: CameraPreview(controller),
              ),
            ),
          )
        else
          SizedBox.expand(child: CameraPreview(controller)),
        CustomPaint(
          painter: _FaceOvalOverlayPainter(color: _ringColor),
          child: const SizedBox.expand(),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _phase == _BlinkPhase.blinkDone ||
                                  _phase == _BlinkPhase.capturing
                              ? Icons.check_circle
                              : Icons.remove_red_eye_outlined,
                          color: _ringColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _hint,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_phase == _BlinkPhase.capturing)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Selfie captures only after you blink',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FaceOvalOverlayPainter extends CustomPainter {
  _FaceOvalOverlayPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final hole = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.42),
          width: size.width * 0.62,
          height: size.height * 0.42,
        ),
      );
    final full = Path()..addRect(Offset.zero & size);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      overlay,
    );

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.42),
        width: size.width * 0.62,
        height: size.height * 0.42,
      ),
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceOvalOverlayPainter oldDelegate) =>
      oldDelegate.color != color;
}
