import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Captures video frames from the camera and sends them as Base64 JPEG.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isStreaming = false;
  Timer? _frameTimer;
  StreamController<String>? _frameController;

  // Callback when a frame is ready (Base64 JPEG)
  void Function(String base64Jpeg)? onFrame;

  Stream<String>? get frameStream => _frameController?.stream;
  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;

  /// Initialize the camera with the first available camera.
  Future<void> initialize({CameraLensDirection lens = CameraLensDirection.front}) async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    // Find desired lens direction
    CameraDescription? selected;
    for (final cam in _cameras) {
      if (cam.lensDirection == lens) {
        selected = cam;
        break;
      }
    }
    selected ??= _cameras.first;

    _controller = CameraController(selected, ResolutionPreset.medium);
    await _controller!.initialize();
    _isInitialized = true;
  }

  /// Start streaming frames at the given interval (in milliseconds).
  void startFrameStream({int intervalMs = 1000}) {
    if (!_isInitialized || _controller == null) return;

    _isStreaming = true;
    _frameController = StreamController<String>.broadcast();

    // Use a periodic timer to capture frames
    _frameTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _captureAndSend();
    });
  }

  Future<void> _captureAndSend() async {
    if (!_isInitialized || _controller == null || !_isStreaming) return;

    try {
      final XFile picture = await _controller!.takePicture();
      final Uint8List bytes = await picture.readAsBytes();

      // Resize and compress with the image package
      final img.Image? image = img.decodeImage(bytes);
      if (image == null) return;

      // Resize to max 640px wide for cost efficiency
      final img.Image resized = img.copyResize(image, width: 640);
      final Uint8List jpegBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));

      final String base64 = base64Encode(jpegBytes);
      _frameController!.add(base64);
      onFrame?.call(base64);
    } catch (e) {
      debugPrint('Frame capture error: $e');
    }
  }

  /// Stop streaming frames.
  void stopFrameStream() {
    _isStreaming = false;
    _frameTimer?.cancel();
    _frameTimer = null;
    _frameController?.close();
    _frameController = null;
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;

    final currentLens = _controller?.description.lensDirection;
    final newLens = currentLens == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final wasStreaming = _isStreaming;
    if (wasStreaming) stopFrameStream();

    await _controller?.dispose();
    await initialize(lens: newLens);

    if (wasStreaming) startFrameStream();
  }

  /// Dispose camera resources.
  Future<void> dispose() async {
    stopFrameStream();
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }
}
