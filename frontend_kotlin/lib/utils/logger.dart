import 'package:flutter/foundation.dart';

class Logger {
  static const bool _enableDebug = bool.fromEnvironment('DEBUG', defaultValue: true);

  static void d(String tag, String message) {
    if (_enableDebug) {
      debugPrint('APP::$tag: $message');
    }
  }

  static void e(String tag, String message, [Object? error]) {
    debugPrint('APP::ERROR::$tag: $message${error != null ? ' - $error' : ''}');
  }

  static void i(String tag, String message) {
    if (_enableDebug) {
      debugPrint('APP::INFO::$tag: $message');
    }
  }

  static void w(String tag, String message) {
    if (_enableDebug) {
      debugPrint('APP::WARN::$tag: $message');
    }
  }
}