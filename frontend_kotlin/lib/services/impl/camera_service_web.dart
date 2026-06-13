import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../camera_service.dart';
import '../../utils/logger.dart';

const String _cameraViewType = 'web-camera-preview';

class CameraServiceImpl implements CameraService {
  html.VideoElement? _videoElement;
  html.MediaStream? _stream;
  html.CanvasElement? _canvasElement;
  bool _isInitialized = false;
  bool _isPreviewing = false;
  bool _isSwitching = false;
  CameraLensDirection _currentDirection = CameraLensDirection.back;
  final ValueNotifier<CameraController?> _controllerNotifier = ValueNotifier<CameraController?>(null);
  bool _hasMultipleCameras = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isPreviewing => _isPreviewing;

  @override
  bool get hasMultipleCameras => _hasMultipleCameras;

  @override
  bool get isSwitching => _isSwitching;

  @override
  CameraController? get controller => null;

  @override
  CameraLensDirection? get currentDirection => _currentDirection;

  @override
  ValueNotifier<CameraController?> get controllerNotifier => _controllerNotifier;
  
  html.VideoElement? get videoElement => _videoElement;
  
  String get viewType => _cameraViewType;

  @override
  Future<bool> initialize([CameraLensDirection direction = CameraLensDirection.back]) async {
    try {
      Logger.d('WebCamera', '正在初始化Web摄像头，方向: $direction');

      final facingMode = direction == CameraLensDirection.back ? 'environment' : 'user';
      
      final constraints = {
        'video': {
          'facingMode': facingMode,
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
        'audio': false,
      };

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception('浏览器不支持媒体设备访问');
      }
      _stream = await mediaDevices.getUserMedia(constraints);

      _videoElement = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..srcObject = _stream
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';
      // 设置 playsinline 属性（iOS Safari 兼容）
      _videoElement!.setAttribute('playsinline', 'true');

      _canvasElement = html.CanvasElement();

      await _detectCameraCount();

      _currentDirection = direction;
      _isInitialized = true;
      _controllerNotifier.value = null;

      // 注册视图工厂
      _registerViewFactory();

      Logger.d('WebCamera', 'Web摄像头初始化成功');
      return true;
    } catch (e) {
      Logger.e('WebCamera', '初始化失败: $e');
      return false;
    }
  }

  void _registerViewFactory() {
    try {
      // 使用 JavaScript 互操作动态注册视图工厂
      // 将视频元素存储到全局对象供 JS 访问
      js.context['_cameraVideoElement'] = _videoElement;
      
      // 执行 JavaScript 代码注册视图工厂
      final jsCode = '''
        (function() {
          var viewType = "$_cameraViewType";
          var videoElement = window._cameraVideoElement;
          
          // 尝试多种方式注册视图工厂
          if (window.flutterWebRenderer && window.flutterWebRenderer.platformViewRegistry) {
            window.flutterWebRenderer.platformViewRegistry.registerViewFactory(viewType, function(controller) {
              return videoElement;
            });
          } else if (window.ui && window.ui.platformViewRegistry) {
            window.ui.platformViewRegistry.registerViewFactory(viewType, function(controller) {
              return videoElement;
            });
          } else if (window.platformViewRegistry) {
            window.platformViewRegistry.registerViewFactory(viewType, function(controller) {
              return videoElement;
            });
          } else {
            console.error("无法找到 platformViewRegistry");
          }
        })();
      ''';
      
      js.context['eval'](jsCode);
      Logger.d('WebCamera', '视图工厂注册成功: $_cameraViewType');
    } catch (e) {
      Logger.e('WebCamera', '注册视图工厂失败: $e');
    }
  }

  Future<void> _detectCameraCount() async {
    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        _hasMultipleCameras = true;
        return;
      }
      final devices = await mediaDevices.enumerateDevices();
      final videoDevices = devices.where((d) => d.kind == 'videoinput').toList();
      _hasMultipleCameras = videoDevices.length > 1;
      Logger.d('WebCamera', '检测到 ${videoDevices.length} 个摄像头设备');
    } catch (e) {
      Logger.d('WebCamera', '无法检测摄像头数量: $e');
      _hasMultipleCameras = true;
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
      await _disposeStream();

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
    if (_videoElement != null && !_isPreviewing) {
      Logger.d('WebCamera', '启动预览');
      _isPreviewing = true;
    }
  }

  @override
  Future<void> stopPreview() async {
    if (_videoElement != null && _isPreviewing) {
      Logger.d('WebCamera', '停止预览');
      _isPreviewing = false;
    }
  }

  @override
  Future<Uint8List?> captureImage() async {
    if (!isInitialized || _videoElement == null || _canvasElement == null) {
      Logger.e('WebCamera', '捕获失败：摄像头未初始化');
      return null;
    }

    try {
      Logger.d('WebCamera', '开始捕获图像');

      _canvasElement!.width = _videoElement!.videoWidth ?? 640;
      _canvasElement!.height = _videoElement!.videoHeight ?? 480;

      final ctx = _canvasElement!.context2D;
      ctx.drawImage(_videoElement!, 0, 0);

      final blob = await _canvasElement!.toBlob('image/jpeg', 0.9);
      if (blob == null) {
        Logger.e('WebCamera', '捕获失败：无法生成Blob');
        return null;
      }

      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      await reader.onLoad.first;

      Uint8List uint8List;
      if (reader.result is ByteBuffer) {
        final bytes = reader.result as ByteBuffer;
        uint8List = bytes.asUint8List();
      } else if (reader.result is Uint8List) {
        uint8List = reader.result as Uint8List;
      } else if (reader.result != null) {
        Logger.d('WebCamera', '未知的result类型: ${reader.result.runtimeType}');
        uint8List = Uint8List.fromList((reader.result as List).cast<int>());
      } else {
        Logger.e('WebCamera', '捕获失败：reader.result为空');
        return null;
      }

      Logger.d('WebCamera', '捕获成功，图像大小: ${uint8List.length} 字节');
      return uint8List;
    } catch (e) {
      Logger.e('WebCamera', '捕获失败: $e');
      return null;
    }
  }

  Future<void> _disposeStream() async {
    if (_stream != null) {
      _stream!.getTracks().forEach((track) => track.stop());
      _stream = null;
    }
  }

  @override
  void dispose() {
    Logger.d('WebCamera', '释放Web摄像头资源');
    stopPreview();
    _disposeStream();
    _videoElement?.remove();
    _videoElement = null;
    _canvasElement = null;
    _isInitialized = false;
    _isPreviewing = false;
    _controllerNotifier.value = null;
  }
}