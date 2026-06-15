import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'utils/logger.dart';
import 'force_play_video.dart';

class CameraManager extends ChangeNotifier {
  static const String _tag = 'CameraManager';
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  CameraController? _controller;
  bool _isFullscreen = false;
  bool _isCameraOn = true;
  bool _imageSentForCurrentSentence = false;

  CameraController? get controller => _controller;
  bool get isFullscreen => _isFullscreen;
  bool get isCameraOn => _isCameraOn;
  bool get imageSentForCurrentSentence => _imageSentForCurrentSentence;
  List<CameraDescription> get cameras => _cameras;
  int get currentCameraIndex => _currentCameraIndex;
  CameraDescription get currentCamera => _cameras[_currentCameraIndex];

  /// 初始化时必须传入可用摄像头列表
  Future<void> initialize(List<CameraDescription> cameras) async {
    Logger.d(_tag, 'initialize() - 摄像头数量: ${cameras.length}');
    _cameras = cameras;
    if (_cameras.isNotEmpty) {
      _currentCameraIndex = 0;
      await _resetController();
    }
    Logger.d(_tag, 'initialize() - 完成, controller: ${_controller != null ? '存在' : 'null'}');
  }

  /// 切换到指定索引的摄像头
  Future<void> switchCamera(int index) async {
    Logger.d(_tag, 'switchCamera() - 目标索引: $index, 当前索引: $_currentCameraIndex, 摄像头总数: ${_cameras.length}');
    if (index == _currentCameraIndex && _controller != null) {
      Logger.d(_tag, 'switchCamera() - 无需切换，索引相同');
      return;
    }
    if (index < 0 || index >= _cameras.length) {
      Logger.d(_tag, 'switchCamera() - 无效索引: $index');
      return;
    }

    _currentCameraIndex = index;
    await _resetController();
    notifyListeners();
    Logger.d(_tag, 'switchCamera() - 完成, 当前索引: $_currentCameraIndex');
  }

  /// 便捷方法：切换前后摄像头（如果存在）
  Future<void> toggleCamera() async {
    Logger.d(_tag, 'toggleCamera() - 摄像头总数: ${_cameras.length}');
    if (_cameras.length < 2) {
      Logger.d(_tag, 'toggleCamera() - 摄像头不足2个，无法切换');
      return;
    }
    final newIndex = (_currentCameraIndex + 1) % _cameras.length;
    Logger.d(_tag, 'toggleCamera() - 从索引 $_currentCameraIndex 切换到 $newIndex');
    await switchCamera(newIndex);
  }

  Future<void> _resetController() async {
    Logger.d(_tag, '_resetController() - 开始, 当前controller: ${_controller != null ? '存在' : 'null'}');
    
    // 1. 停止旧预览（如果正在运行）
    await _controller?.dispose();
    _controller = null;
    Logger.d(_tag, '_resetController() - 旧controller已释放');

    // 2. 创建新 controller
    final newController = CameraController(
      _cameras[_currentCameraIndex],
      ResolutionPreset.medium,
    );
    Logger.d(_tag, '_resetController() - 新controller已创建');

    // 3. 初始化新 controller
    try {
      Logger.d(_tag, '_resetController() - 开始初始化...');
      await newController.initialize();
      Logger.d(_tag, '_resetController() - 初始化完成');
    } catch (e) {
      Logger.e(_tag, '摄像头初始化失败: $e');
      notifyListeners();
      return;
    }

    // 3.1 关闭闪光灯（Web 平台不支持，失败时静默跳过）
    try {
      await newController.setFlashMode(FlashMode.off);
      Logger.d(_tag, '_resetController() - 闪光灯已关闭');
    } catch (e) {
      Logger.d(_tag, '_resetController() - 闪光灯设置跳过（当前平台不支持）: $e');
    }

    // 4. 如果当前是关闭状态，新摄像头初始化后也保持暂停
    if (!_isCameraOn) {
      Logger.d(_tag, '_resetController() - 当前isCameraOn=false，暂停预览');
      await newController.pausePreview();
    }

    // 5. 赋值并通知
    _controller = newController;
    Logger.d(_tag, '_resetController() - 完成, controller: 存在, isCameraOn: $_isCameraOn');
    notifyListeners();
  }

  void toggleCameraOn() {
    Logger.d(_tag, 'toggleCameraOn() - 之前: _isCameraOn=$_isCameraOn, controller=${_controller != null ? '存在' : 'null'}');
    if (_controller == null) {
      Logger.d(_tag, 'toggleCameraOn() - controller为null，返回');
      return;
    }
    if (_isCameraOn) {
      _controller!.pausePreview();
      Logger.d(_tag, 'toggleCameraOn() - 已暂停预览');
    } else {
      _controller!.resumePreview();
      Logger.d(_tag, 'toggleCameraOn() - 已恢复预览');
    }
    _isCameraOn = !_isCameraOn;
    Logger.d(_tag, 'toggleCameraOn() - 之后: _isCameraOn=$_isCameraOn');
    notifyListeners();
  }

  void toggleFullscreen() {
    Logger.d(_tag, 'toggleFullscreen() - 之前: _isFullscreen=$_isFullscreen, controller=${_controller != null ? '存在' : 'null'}, isCameraOn=$_isCameraOn');
    _isFullscreen = !_isFullscreen;
    Logger.d(_tag, 'toggleFullscreen() - 之后: _isFullscreen=$_isFullscreen, controller=${_controller != null ? '存在' : 'null'}');
    notifyListeners();
    Logger.d(_tag, 'toggleFullscreen() - notifyListeners() 已调用');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller?.resumePreview();
      if (kIsWeb) {
        forcePlayVideoElement();
      }
    });
  }

  void markImageSent() {
    _imageSentForCurrentSentence = true;
  }

  void resetImageSentFlag() {
    _imageSentForCurrentSentence = false;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}