import 'package:flutter/material.dart';
import '../services/locator.dart';
import '../services/camera_service.dart';
import 'camera_preview_web.dart';

class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final cameraService = locator<CameraService>();
    
    return CameraPreviewWeb(cameraService: cameraService);
  }
}