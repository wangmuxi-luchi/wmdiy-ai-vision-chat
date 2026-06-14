import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';
import '../utils/logger.dart';

class CameraPreviewWeb extends StatefulWidget {
  final CameraService cameraService;

  const CameraPreviewWeb({super.key, required this.cameraService});

  @override
  State<CameraPreviewWeb> createState() => _CameraPreviewWebState();
}

class _CameraPreviewWebState extends State<CameraPreviewWeb> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureVideoPlaying();
    });
  }

  @override
  void didUpdateWidget(covariant CameraPreviewWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureVideoPlaying();
    });
  }

  void _ensureVideoPlaying() {
    try {
      js.context.callMethod('ensureVideoPlaying');
    } catch (e) {
      Logger.d('CameraPreviewWeb', '_ensureVideoPlaying 失败: $e');
    }
  }

  void _logVideoElementStatus(String context) {
    try {
      js.context.callMethod('logVideoElementStatus', [context]);
    } catch (e) {
      Logger.d('CameraPreviewWeb', '_logVideoElementStatus 失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Logger.d('CameraPreviewWeb', 'build() - isInitialized: ${widget.cameraService.isInitialized}, controller: ${widget.cameraService.controller}');
    
    return ValueListenableBuilder<CameraController?>(
      valueListenable: widget.cameraService.controllerNotifier,
      builder: (context, controller, child) {
        if (controller == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureVideoPlaying();
        });

        // 获取视频尺寸并计算宽高比
        final previewSize = controller.value.previewSize;
        double aspectRatio = 4 / 3; // 默认比例
        
        if (previewSize != null) {
          aspectRatio = previewSize.width / previewSize.height;
          Logger.d('CameraPreviewWeb', '视频尺寸: ${previewSize.width}x${previewSize.height}, 比例: $aspectRatio');
        }

        // 使用 AspectRatio 保持视频正确比例，避免黑边
        return AspectRatio(
          aspectRatio: aspectRatio,
          child: CameraPreview(controller),
        );
      },
    );
  }
}