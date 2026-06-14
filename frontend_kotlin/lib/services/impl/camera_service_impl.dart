import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../camera_service.dart';
import '../../utils/logger.dart';

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
  double get aspectRatio {
    if (_controller == null || !_controller!.value.isInitialized) {
      Logger.d('Camera', 'aspectRatio: 使用默认值 4:3');
      return 4.0 / 3.0;
    }
    final size = _controller!.value.previewSize;
    if (size != null) {
      final ratio = size.width / size.height;
      Logger.d('Camera', 'aspectRatio: ${size.width}x${size.height} = $ratio');
      return ratio;
    }
    Logger.d('Camera', 'aspectRatio: previewSize 为 null，使用默认值 4:3');
    return 4.0 / 3.0;
  }
  
  @override
  Future<bool> initialize([CameraLensDirection direction = CameraLensDirection.back]) async {
    try {
      Logger.d('Camera', '正在初始化摄像头，方向: $direction');
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        Logger.e('Camera', '未找到可用摄像头');
        return false;
      }
      
      Logger.d('Camera', '找到 ${_cameras!.length} 个摄像头');
      
      CameraDescription camera = _findCamera(direction) ?? _cameras![0];
      await _initCameraController(camera);
      Logger.d('Camera', '摄像头初始化成功，当前方向: ${camera.lensDirection}');
      return true;
    } catch (e) {
      Logger.e('Camera', '初始化失败: $e');
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
    
    Logger.d('Camera', '创建控制器: ${camera.name}, 分辨率: medium');
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
      if (_isSwitchingInternal) {
        Logger.w('Camera', '正在切换中，忽略请求');
      }
      return false;
    }
    
    _isSwitchingInternal = true;
    Logger.d('Camera', '开始切换摄像头');
    
    try {
      CameraLensDirection newDirection = 
          _currentDirection == CameraLensDirection.back 
              ? CameraLensDirection.front 
              : CameraLensDirection.back;
      
      CameraDescription? newCamera = _findCamera(newDirection);
      if (newCamera == null) {
        Logger.e('Camera', '未找到目标摄像头');
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
      
      Logger.d('Camera', '切换成功，当前方向: $newDirection');
      return true;
    } catch (e) {
      Logger.e('Camera', '切换失败: $e');
      return false;
    } finally {
      _isSwitchingInternal = false;
    }
  }
  
  @override
  Future<void> startPreview() async {
    if (_controller != null && !_isPreviewingInternal) {
      Logger.d('Camera', '启动预览');
      await _controller!.startImageStream((image) {});
      _isPreviewingInternal = true;
    }
  }
  
  @override
  Future<void> stopPreview() async {
    if (_controller != null && _isPreviewingInternal) {
      Logger.d('Camera', '停止预览');
      await _controller!.stopImageStream();
      _isPreviewingInternal = false;
    }
  }
  
  @override
  Future<Uint8List?> captureImage() async {
    if (!isInitialized) {
      Logger.e('Camera', '捕获失败：摄像头未初始化');
      return null;
    }
    
    try {
      Logger.d('Camera', '开始捕获图像');
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      Logger.d('Camera', '捕获成功，图像大小: ${bytes.length} 字节');
      return bytes;
    } catch (e) {
      Logger.e('Camera', '捕获失败: $e');
      return null;
    }
  }
  
  @override
  void restartPreview() {
    Logger.d('Camera', '重启预览');
    if (_controller != null && _isPreviewingInternal) {
      stopPreview();
      startPreview();
    }
  }
  
  @override
  void dispose() {
    Logger.d('Camera', '释放摄像头资源');
    _controller?.dispose();
    _controller = null;
    _controllerNotifier.value = null;
  }
}