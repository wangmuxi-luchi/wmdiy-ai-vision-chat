import 'package:flutter/material.dart';

class DraggableCameraPreview extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double initialLeft;
  final double initialTop;

  const DraggableCameraPreview({
    super.key,
    required this.child,
    required this.onTap,
    this.initialLeft = 20,
    this.initialTop = 20,
  });

  @override
  State<DraggableCameraPreview> createState() => _DraggableCameraPreviewState();
}

class _DraggableCameraPreviewState extends State<DraggableCameraPreview> {
  Offset _offset = Offset.zero;
  Offset _initialOffset = Offset.zero;
  bool _isDragging = false;
  double _screenWidth = 0;
  double _screenHeight = 0;
  final double _previewWidth = 320;
  final double _previewHeight = 240;

  @override
  void initState() {
    super.initState();
    _offset = Offset(widget.initialLeft, widget.initialTop);
  }

  void _handlePanStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _initialOffset = details.globalPosition - _offset;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      _offset = details.globalPosition - _initialOffset;
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
  }

  double _clampX(double x) {
    return x.clamp(0, _screenWidth - _previewWidth);
  }

  double _clampY(double y) {
    return y.clamp(0, _screenHeight - _previewHeight);
  }

  @override
  Widget build(BuildContext context) {
    _screenWidth = MediaQuery.of(context).size.width;
    _screenHeight = MediaQuery.of(context).size.height;

    return Positioned(
      left: _clampX(_offset.dx),
      top: _clampY(_offset.dy),
      child: GestureDetector(
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        onTap: _isDragging ? null : widget.onTap,
        child: Container(
          width: _previewWidth,
          height: _previewHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 12,
                offset: const Offset(2, 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}