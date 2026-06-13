export 'impl/camera_service_impl.dart'
    if (dart.library.html) 'impl/camera_service_web.dart';

import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

abstract class CameraService {
  Future<bool> initialize([CameraLensDirection direction = CameraLensDirection.back]);
  
  Future<void> startPreview();
  
  Future<void> stopPreview();
  
  Future<Uint8List?> captureImage();
  
  Future<bool> switchCamera();
  
  bool get isInitialized;
  
  bool get isPreviewing;
  
  bool get hasMultipleCameras;
  
  bool get isSwitching;
  
  CameraController? get controller;
  
  CameraLensDirection? get currentDirection;
  
  ValueNotifier<CameraController?> get controllerNotifier;
  
  void dispose();
}