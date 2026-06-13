import 'package:flutter/material.dart';
import '../services/locator.dart';
import '../services/camera_service.dart';

class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final cameraService = locator<CameraService>();
    
    return ValueListenableBuilder<dynamic>(
      valueListenable: cameraService.controllerNotifier,
      builder: (context, controller, child) {
        if (!cameraService.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // 使用服务中注册的静态视图类型
        return HtmlElementView(viewType: 'web-camera-preview');
      },
    );
  }
}