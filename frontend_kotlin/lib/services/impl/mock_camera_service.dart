import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../camera_service.dart';

class MockCameraService implements CameraService {
  bool _isInitialized = false;
  bool _isPreviewing = false;
  bool _isSwitching = false;
  CameraLensDirection _currentDirection = CameraLensDirection.back;
  final ValueNotifier<CameraController?> _controllerNotifier = ValueNotifier<CameraController?>(null);
  
  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isPreviewing => _isPreviewing;
  
  @override
  bool get hasMultipleCameras => true;
  
  @override
  bool get isSwitching => _isSwitching;
  
  @override
  double get aspectRatio => 4.0 / 3.0;
  
  @override
  CameraController? get controller => null;
  
  @override
  CameraLensDirection? get currentDirection => _currentDirection;
  
  @override
  ValueNotifier<CameraController?> get controllerNotifier => _controllerNotifier;
  
  @override
  Future<bool> initialize([CameraLensDirection direction = CameraLensDirection.back]) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _isInitialized = true;
    _currentDirection = direction;
    _controllerNotifier.value = null;
    return true;
  }
  
  @override
  Future<bool> switchCamera() async {
    if (!isInitialized || _isSwitching) {
      return false;
    }
    
    _isSwitching = true;
    
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      _currentDirection = 
          _currentDirection == CameraLensDirection.back 
              ? CameraLensDirection.front 
              : CameraLensDirection.back;
      return true;
    } finally {
      _isSwitching = false;
    }
  }
  
  @override
  Future<void> startPreview() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _isPreviewing = true;
  }
  
  @override
  Future<void> stopPreview() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _isPreviewing = false;
  }
  
  @override
  void restartPreview() {
    // Mock implementation
  }
  
  @override
  Future<Uint8List?> captureImage() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
  }
  
  @override
  void dispose() {
    _isInitialized = false;
    _isPreviewing = false;
  }
}