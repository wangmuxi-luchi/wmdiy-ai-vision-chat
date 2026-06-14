import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../camera_service.dart';
import '../../utils/logger.dart';

const String _cameraViewType = 'web-camera-preview';

class CameraServiceImpl implements CameraService {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isPreviewing = false;
  bool _isSwitching = false;
  CameraLensDirection _currentDirection = CameraLensDirection.back;
  final ValueNotifier<CameraController?> _controllerNotifier = ValueNotifier<CameraController?>(null);
  bool _hasMultipleCameras = false;
  List<CameraDescription>? _cameras;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isPreviewing => _isPreviewing;

  @override
  bool get hasMultipleCameras => _hasMultipleCameras;

  @override
  bool get isSwitching => _isSwitching;

  @override
  CameraController? get controller => _controller;

  @override
  CameraLensDirection? get currentDirection => _currentDirection;

  @override
  ValueNotifier<CameraController?> get controllerNotifier => _controllerNotifier;
  
  @override
  double get aspectRatio {
    if (_controller == null || !_isInitialized) {
      return 4.0 / 3.0; // 默认 4:3
    }
    final size = _controller!.value.previewSize;
    return size != null ? size.width / size.height : 4.0 / 3.0;
  }
  
  String get viewType => _cameraViewType;

  @override
  Future<bool> initialize([CameraLensDirection direction = CameraLensDirection.back]) async {
    try {
      Logger.d('WebCamera', '正在初始化Web摄像头，方向: $direction');

      if (_cameras == null) {
        Logger.d('WebCamera', '开始获取可用摄像头列表...');
        _cameras = await availableCameras();
        Logger.d('WebCamera', '获取摄像头列表完成，共 ${_cameras!.length} 个设备');
        _hasMultipleCameras = _cameras!.length > 1;
        Logger.d('WebCamera', '检测到 ${_cameras!.length} 个摄像头设备');
      }

      if (_cameras!.isEmpty) {
        throw Exception('未检测到摄像头设备');
      }

      CameraDescription? selectedCamera;
      for (var camera in _cameras!) {
        Logger.d('WebCamera', '摄像头: ${camera.name}, 方向: ${camera.lensDirection}');
        if ((direction == CameraLensDirection.back && camera.lensDirection == CameraLensDirection.back) ||
            (direction == CameraLensDirection.front && camera.lensDirection == CameraLensDirection.front)) {
          selectedCamera = camera;
          break;
        }
      }

      if (selectedCamera == null) {
        selectedCamera = _cameras!.first;
        Logger.d('WebCamera', '未找到指定方向的摄像头，使用第一个摄像头');
      }

      Logger.d('WebCamera', '创建 CameraController，分辨率: ResolutionPreset.medium');
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
      );

      Logger.d('WebCamera', '开始初始化控制器...');
      await _controller!.initialize();
      Logger.d('WebCamera', '控制器初始化完成');

      _currentDirection = direction;
      _isInitialized = true;
      Logger.d('WebCamera', '设置 controllerNotifier.value = $_controller');
      _controllerNotifier.value = _controller;

      Logger.d('WebCamera', 'Web摄像头初始化成功');
      return true;
    } catch (e, stackTrace) {
      Logger.e('WebCamera', '初始化失败: $e\n$stackTrace');
      return false;
    }
  }

  @override
  Future<bool> switchCamera() async {
    if (!hasMultipleCameras || !isInitialized || _isSwitching) {
      if (_isSwitching) {
        Logger.w('WebCamera', '正在切换中，忽略请求');
      }
      return false;
    }

    _isSwitching = true;
    Logger.d('WebCamera', '开始切换摄像头');

    try {
      await stopPreview();

      _currentDirection = _currentDirection == CameraLensDirection.back
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      await initialize(_currentDirection);

      if (_isPreviewing) {
        await startPreview();
      }

      Logger.d('WebCamera', '切换成功，当前方向: $_currentDirection');
      return true;
    } catch (e) {
      Logger.e('WebCamera', '切换失败: $e');
      return false;
    } finally {
      _isSwitching = false;
    }
  }

  @override
  Future<void> startPreview() async {
    if (_controller != null && !_isPreviewing) {
      Logger.d('WebCamera', '启动预览');
      _isPreviewing = true;
    }
  }

  @override
  Future<void> stopPreview() async {
    if (_controller != null && _isPreviewing) {
      Logger.d('WebCamera', '停止预览');
      _isPreviewing = false;
    }
  }

  @override
  void restartPreview() {
    Logger.d('WebCamera', '重新启动预览');
    if (_controller != null && _isInitialized) {
      Logger.d('WebCamera', '触发 controllerNotifier 更新以重建预览');
      _controllerNotifier.value = null;
      Future.microtask(() {
        _controllerNotifier.value = _controller;
      });
    }
  }

  @override
  Future<Uint8List?> captureImage() async {
    if (!isInitialized || _controller == null) {
      Logger.e('WebCamera', '捕获失败：摄像头未初始化');
      return null;
    }

    try {
      Logger.d('WebCamera', '开始捕获图像');

      final XFile image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();

      Logger.d('WebCamera', '捕获成功，图像大小: ${bytes.length} 字节');
      return bytes;
    } catch (e) {
      Logger.e('WebCamera', '捕获失败: $e');
      return null;
    }
  }

  @override
  void dispose() {
    Logger.d('WebCamera', '释放Web摄像头资源');
    stopPreview();
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
    _isPreviewing = false;
    _controllerNotifier.value = null;
  }
}