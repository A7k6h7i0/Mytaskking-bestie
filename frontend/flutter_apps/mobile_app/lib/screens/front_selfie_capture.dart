import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class FrontSelfieCapture extends StatefulWidget {
  const FrontSelfieCapture({super.key});

  @override
  State<FrontSelfieCapture> createState() => _FrontSelfieCaptureState();
}

class _FrontSelfieCaptureState extends State<FrontSelfieCapture> {
  CameraController? _controller;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (front.isEmpty) throw 'This device has no front camera.';
      final controller = CameraController(
        front.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _takeSelfie() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      if (mounted) Navigator.pop<Uint8List>(context, bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Take login selfie'),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: controller == null || !controller.value.isInitialized
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white)),
                          ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: CameraPreview(controller),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Front camera only. Center your face and take a clear live selfie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: FloatingActionButton.large(
              onPressed: controller == null || _capturing ? null : _takeSelfie,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              child: _capturing
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.camera_alt_rounded, size: 34),
            ),
          ),
        ]),
      ),
    );
  }
}
