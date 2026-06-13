import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/locator.dart';
import '../services/camera_service.dart';

class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final cameraService = locator<CameraService>();
    
    return ValueListenableBuilder<CameraController?>(
      valueListenable: cameraService.controllerNotifier,
      builder: (context, controller, child) {
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox();
        }
        return CameraPreview(controller);
      },
    );
  }
}