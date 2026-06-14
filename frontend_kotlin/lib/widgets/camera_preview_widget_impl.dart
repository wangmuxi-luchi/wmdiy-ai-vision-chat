import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/locator.dart';
import '../services/camera_service.dart';

class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({super.key});

  double _getCorrectAspectRatio(CameraController controller, BuildContext context) {
    final raw = controller.value.aspectRatio;
    final orientation = MediaQuery.of(context).orientation;
    if (Theme.of(context).platform == TargetPlatform.android && orientation == Orientation.portrait) {
      return 1 / raw;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final cameraService = locator<CameraService>();
    
    return ValueListenableBuilder<CameraController?>(
      valueListenable: cameraService.controllerNotifier,
      builder: (context, controller, child) {
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox();
        }
        
        final double aspectRatio = _getCorrectAspectRatio(controller, context);
        
        return ClipRect(
          child: Align(
            alignment: Alignment.center,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}