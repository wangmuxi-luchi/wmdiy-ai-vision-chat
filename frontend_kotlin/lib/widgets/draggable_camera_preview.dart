import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../utils/logger.dart';

class CameraPreviewWidgetImpl extends StatelessWidget {
  static const String _tag = 'CameraPreviewWidgetImpl';
  final CameraController controller;
  final VoidCallback? onCapture;
  final VoidCallback? onSwitchCamera;
  final VoidCallback? onToggleFullscreen;
  final bool hasMultipleCameras;

  const CameraPreviewWidgetImpl({
    super.key,
    required this.controller,
    this.onCapture,
    this.onSwitchCamera,
    this.onToggleFullscreen,
    this.hasMultipleCameras = false,
  });

  double _getCorrectAspectRatio(BuildContext context) {
    final raw = controller.value.aspectRatio;
    final orientation = MediaQuery.of(context).orientation;
    if (Theme.of(context).platform == TargetPlatform.android && orientation == Orientation.portrait) {
      return 1 / raw;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    Logger.d(_tag, 'build() - controller: 存在');
    Logger.d(_tag, 'build() - isInitialized: ${controller.value.isInitialized}');
    
    if (!controller.value.isInitialized) {
      Logger.d(_tag, 'build() - 返回 CircularProgressIndicator');
      return const Center(child: CircularProgressIndicator());
    }

    final double aspectRatio = _getCorrectAspectRatio(context);
    Logger.d(_tag, 'build() - aspectRatio: $aspectRatio, isStreamingImages: ${controller.value.isStreamingImages}');

    return ClipRect(
      child: Align(
        alignment: Alignment.center,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            children: [
              CameraPreview(controller),
              if (onToggleFullscreen != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.black54,
                    onPressed: onToggleFullscreen,
                    child: const Icon(Icons.fullscreen),
                  ),
                ),
              if (hasMultipleCameras && onSwitchCamera != null)
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.black54,
                    onPressed: onSwitchCamera,
                    child: const Icon(Icons.cameraswitch),
                  ),
                ),
              if (onCapture != null)
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.black54,
                    onPressed: onCapture,
                    child: const Icon(Icons.send),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DraggableCameraPreview extends StatefulWidget {
  static const String _tag = 'DraggableCameraPreview';
  final CameraController controller;
  final double initialWidth;
  final double initialHeight;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onCapture;
  final VoidCallback? onSwitchCamera;
  final bool hasMultipleCameras;

  const DraggableCameraPreview({
    super.key,
    required this.controller,
    this.initialWidth = 300,
    this.initialHeight = 400,
    this.onToggleFullscreen,
    this.onCapture,
    this.onSwitchCamera,
    this.hasMultipleCameras = false,
  });

  @override
  State<DraggableCameraPreview> createState() => _DraggableCameraPreviewState();
}

class _DraggableCameraPreviewState extends State<DraggableCameraPreview> {
  double _width = 300;
  double _height = 400;
  Offset _position = Offset.zero;
  bool _isDragging = false;
  bool _isResizing = false;
  Offset _dragStart = Offset.zero;
  Offset _resizeStart = Offset.zero;
  double _startWidth = 0;
  double _startHeight = 0;

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
    _height = widget.initialHeight;
  }

  void _handlePanStart(DragStartDetails details) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
    
    const double resizeArea = 80;
    final bool nearRightEdge = (localPosition.dx - _width).abs() < resizeArea;
    final bool nearBottomEdge = (localPosition.dy - _height).abs() < resizeArea;
    
    if (nearRightEdge && nearBottomEdge) {
      _isResizing = true;
      _resizeStart = details.globalPosition;
      _startWidth = _width;
      _startHeight = _height;
    } else {
      _isDragging = true;
      _dragStart = details.globalPosition - _position;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_isDragging) {
      final RenderBox renderBox = context.findRenderObject() as RenderBox;
      final Size screenSize = renderBox.size;
      
      Offset newPosition = details.globalPosition - _dragStart;
      
      newPosition = Offset(
        newPosition.dx.clamp(0, screenSize.width - _width),
        newPosition.dy.clamp(0, screenSize.height - _height),
      );
      
      setState(() {
        _position = newPosition;
      });
    } else if (_isResizing) {
      final RenderBox renderBox = context.findRenderObject() as RenderBox;
      final Size screenSize = renderBox.size;
      
      final double deltaX = details.globalPosition.dx - _resizeStart.dx;
      final double deltaY = details.globalPosition.dy - _resizeStart.dy;
      
      double newWidth = (_startWidth + deltaX).clamp(150, 500);
      double newHeight = (_startHeight + deltaY).clamp(150, 600);
      
      setState(() {
        _width = newWidth;
        _height = newHeight;
        
        _position = Offset(
          _position.dx.clamp(0, screenSize.width - _width),
          _position.dy.clamp(0, screenSize.height - _height),
        );
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    _isDragging = false;
    _isResizing = false;
  }

  @override
  Widget build(BuildContext context) {
    Logger.d(DraggableCameraPreview._tag, 'build() - controller: 存在');
    Logger.d(DraggableCameraPreview._tag, 'build() - isInitialized: ${widget.controller.value.isInitialized}');
    Logger.d(DraggableCameraPreview._tag, 'build() - 位置: (${_position.dx.toStringAsFixed(2)}, ${_position.dy.toStringAsFixed(2)}), 尺寸: ${_width.toStringAsFixed(0)}x${_height.toStringAsFixed(0)}');
    
    return Stack(
      children: [
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            child: Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CameraPreviewWidgetImpl(
                  controller: widget.controller,
                  onCapture: widget.onCapture,
                  onSwitchCamera: widget.onSwitchCamera,
                  onToggleFullscreen: widget.onToggleFullscreen,
                  hasMultipleCameras: widget.hasMultipleCameras,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: _position.dx + _width - 15,
          top: _position.dy + _height - 15,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}