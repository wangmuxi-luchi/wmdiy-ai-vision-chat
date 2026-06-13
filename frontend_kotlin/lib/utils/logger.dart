import 'package:logger/logger.dart' as external_logger;

class Logger {
  static final external_logger.Logger _logger = external_logger.Logger(
    printer: external_logger.SimplePrinter(printTime: true),
  );

  static String _getFileInfo() {
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
            return '[${fileLineMatch.group(1)}:${fileLineMatch.group(2)}]';
          }
          
          var colonMatch = RegExp(r'([a-zA-Z0-9_]+\.dart):(\d+)').firstMatch(line);
          if (colonMatch != null) {
            return '[${colonMatch.group(1)}:${colonMatch.group(2)}]';
          }
          
          var pathMatch = RegExp(r'[/\\]([^/\\]+\.dart):(\d+)').firstMatch(line);
          if (pathMatch != null) {
            return '[${pathMatch.group(1)}:${pathMatch.group(2)}]';
          }
        }
      }
    } catch (e) {
      // 忽略解析错误
    }
    return '';
  }

  static void d(String tag, String message) {
    final fileInfo = _getFileInfo();
    _logger.d('$fileInfo [$tag] $message');
  }

  static void e(String tag, String message, [Object? error]) {
    
    final fileInfo = _getFileInfo();
    _logger.e('$fileInfo [$tag] $message', error);
  }

  static void i(String tag, String message) {
    final fileInfo = _getFileInfo();
    _logger.i('$fileInfo [$tag] $message');
  }

  static void w(String tag, String message) {
    final fileInfo = _getFileInfo();
    _logger.w('$fileInfo [$tag] $message');
  }

  static void v(String tag, String message) {
    final fileInfo = _getFileInfo();
    _logger.v('$fileInfo [$tag] $message');
  }

  static void wtf(String tag, String message) {
    final fileInfo = _getFileInfo();
    _logger.wtf('$fileInfo [$tag] $message');
  }
}