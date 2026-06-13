import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import '../services/camera_service.dart';
import '../services/impl/camera_service_web.dart';

/// Web平台的摄像头预览组件
class CameraPreviewWeb extends StatelessWidget {
  final CameraService cameraService;

  const CameraPreviewWeb({super.key, required this.cameraService});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraController?>(
      valueListenable: cameraService.controllerNotifier,
      builder: (context, controller, child) {
        if (!cameraService.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final webCameraService = cameraService as CameraServiceImpl;
        final videoElement = webCameraService.videoElement;
        
        if (videoElement == null) {
          return const Center(child: Text('视频元素未创建'));
        }
        
        // 使用 PlatformViewRegistry 注册视图
        final viewId = 'camera-preview-${DateTime.now().microsecondsSinceEpoch}';
        PlatformViewRegistry.instance.registerViewFactory(
          viewId,
          (int viewId) => videoElement,
        );
        
        return HtmlElementView(viewType: viewId);
      },
    );
  }
}