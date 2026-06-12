import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../camera_service.dart';

class CameraServiceImpl implements CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isPreviewingInternal = false;
  bool _isSwitchingInternal = false;
  CameraLensDirection? _currentDirection;
  final ValueNotifier<CameraController?> _controllerNotifier = ValueNotifier<CameraController?>(null);
  
  @override
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  
  @override
  bool get isPreviewing => _isPreviewingInternal;
  
  @override
  bool get hasMultipleCameras => _cameras != null && _cameras!.length > 1;
  
  @override
  bool get isSwitching => _isSwitchingInternal;
  
  @override
  CameraController? get controller => _controller;
  
  @override
  CameraLensDirection? get currentDirection => _currentDirection;
  
  @override
  ValueNotifier<CameraController?> get controllerNotifier => _controllerNotifier;
  
  @override
  Future<bool> initialize([CameraLensDirection direction = CameraLensDirection.back]) async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        return false;
      }
      
      CameraDescription? camera = _findCamera(direction);
      if (camera == null) {
        camera = _cameras![0];
      }
      
      await _initCameraController(camera);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  CameraDescription? _findCamera(CameraLensDirection direction) {
    return _cameras?.firstWhere(
      (camera) => camera.lensDirection == direction,
      orElse: () => _cameras![0],
    );
  }
  
  Future<void> _initCameraController(CameraDescription camera) async {
    if (_controller != null) {
      await _controller?.dispose();
      _controller = null;
    }
    
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _controller = controller;
    
    await controller.initialize();
    _currentDirection = camera.lensDirection;
    _controllerNotifier.value = _controller;
  }
  
  @override
  Future<bool> switchCamera() async {
    if (!hasMultipleCameras || !isInitialized || _isSwitchingInternal) {
      return false;
    }
    
    _isSwitchingInternal = true;
    
    try {
      CameraLensDirection newDirection = 
          _currentDirection == CameraLensDirection.back 
              ? CameraLensDirection.front 
              : CameraLensDirection.back;
      
      CameraDescription? newCamera = _findCamera(newDirection);
      if (newCamera == null) {
        _isSwitchingInternal = false;
        return false;
      }
      
      await stopPreview();
      await _controller?.dispose();
      _controller = null;
      _controllerNotifier.value = null;
      
      await Future.delayed(Duration.zero);
      
      await _initCameraController(newCamera);
      
      if (_isPreviewingInternal) {
        await startPreview();
      }
      
      return true;
    } catch (e) {
      return false;
    } finally {
      _isSwitchingInternal = false;
    }
  }
  
  @override
  Future<void> startPreview() async {
    if (_controller != null && !_isPreviewingInternal) {
      await _controller!.startImageStream((image) {});
      _isPreviewingInternal = true;
    }
  }
  
  @override
  Future<void> stopPreview() async {
    if (_controller != null && _isPreviewingInternal) {
      await _controller!.stopImageStream();
      _isPreviewingInternal = false;
    }
  }
  
  @override
  Future<Uint8List?> captureImage() async {
    if (!isInitialized) {
      return null;
    }
    
    try {
      final image = await _controller!.takePicture();
      return await image.readAsBytes();
    } catch (e) {
      return null;
    }
  }
  
  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _controllerNotifier.value = null;
  }
}