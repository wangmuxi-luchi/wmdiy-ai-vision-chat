import 'package:logger/logger.dart' as external_logger;

class Logger {
  static final external_logger.Logger _logger = external_logger.Logger(
    printer: external_logger.SimplePrinter(printTime: true),
  );

  // 屏蔽的源文件列表（不输出这些文件中的任何 debug 日志）
  static final Set<String> _suppressFiles = {
    'camera_manager.dart',
    'camera_service_impl.dart',
    'camera_service_web.dart',
    'force_play_video_web.dart',
    'draggable_camera_preview.dart',
  };

  // 屏蔽的特定调用点："文件名:行号"
  static final Set<String> _suppressCalls = {
    'chat_screen.dart:353',  // _toggleFullscreen 摄像头全屏日志
    'chat_screen.dart:355',
    'chat_screen.dart:471',  // _buildNormalLayout 摄像头状态日志
    'chat_screen.dart:472',
    'chat_screen.dart:473',
    'chat_screen.dart:474',
    'chat_screen.dart:477',
    'chat_screen.dart:478',
    'chat_screen.dart:509',  // _buildCameraPreview 摄像头预览日志
    'chat_screen.dart:510',
    'chat_screen.dart:511',
    'chat_screen.dart:512',
    'chat_screen.dart:513',
    'chat_screen.dart:516',
    'chat_screen.dart:522',
  };

  static ({String file, String line}) _getFileInfo() {
    try {
      final stackTrace = StackTrace.current.toString();
      final lines = stackTrace.split('\n');

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        if (line.contains('.dart') &&
            !line.contains('logger.dart') &&
            !line.contains('package:logger')) {

          var fileLineMatch = RegExp(r'([a-zA-Z0-9_]+\.dart)\s+(\d+):(\d+)').firstMatch(line);
          if (fileLineMatch != null) {
            return (file: fileLineMatch.group(1)!, line: fileLineMatch.group(2)!);
          }

          var colonMatch = RegExp(r'([a-zA-Z0-9_]+\.dart):(\d+)').firstMatch(line);
          if (colonMatch != null) {
            return (file: colonMatch.group(1)!, line: colonMatch.group(2)!);
          }

          var pathMatch = RegExp(r'[/\\]([^/\\]+\.dart):(\d+)').firstMatch(line);
          if (pathMatch != null) {
            return (file: pathMatch.group(1)!, line: pathMatch.group(2)!);
          }
        }
      }
    } catch (e) {
      // 忽略解析错误
    }
    return (file: '', line: '');
  }

  static bool _isSuppressed(String file, String line) {
    // 按文件名屏蔽
    if (_suppressFiles.contains(file)) return true;
    // 按文件名:行号屏蔽
    if (_suppressCalls.contains('$file:$line')) return true;
    return false;
  }

  static void d(String tag, String message) {
    final info = _getFileInfo();
    if (_isSuppressed(info.file, info.line)) return;
    _logger.d('[${info.file}:${info.line}] [$tag] $message');
  }

  static void e(String tag, String message, [Object? error]) {
    final info = _getFileInfo();
    _logger.e('[${info.file}:${info.line}] [$tag] $message', error);
  }

  static void i(String tag, String message) {
    final info = _getFileInfo();
    if (_isSuppressed(info.file, info.line)) return;
    _logger.i('[${info.file}:${info.line}] [$tag] $message');
  }

  static void w(String tag, String message) {
    final info = _getFileInfo();
    _logger.w('[${info.file}:${info.line}] [$tag] $message');
  }

  static void v(String tag, String message) {
    final info = _getFileInfo();
    if (_isSuppressed(info.file, info.line)) return;
    _logger.v('[${info.file}:${info.line}] [$tag] $message');
  }

  static void wtf(String tag, String message) {
    final info = _getFileInfo();
    _logger.wtf('[${info.file}:${info.line}] [$tag] $message');
  }
}