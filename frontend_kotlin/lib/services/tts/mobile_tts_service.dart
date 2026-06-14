import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import '../../utils/logger.dart';
import 'tts_service.dart';

class MobileTtsService implements TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  final StreamController<dynamic> _completionController = StreamController.broadcast();
  bool _initialized = false;
  Future<void>? _bindingFuture;

  MobileTtsService() {
    Logger.i('MobileTts', 'MobileTtsService 构造函数开始');
    _flutterTts.setCompletionHandler(() {
      Logger.d('MobileTts', '朗读完成回调');
      _completionController.add(null);
    });

    _flutterTts.setErrorHandler((msg) {
      Logger.e('MobileTts', 'TTS 错误: $msg');
    });

    _flutterTts.setStartHandler(() {
      Logger.i('MobileTts', '引擎启动回调 — 播放已开始');
    });

    _bindingFuture = _initEngine();
  }

  Future<void> _initEngine() async {
    Logger.d('MobileTts', '初始化引擎...');
    try {
      await _flutterTts.setLanguage('zh-CN');
      await _flutterTts.setSpeechRate(0.5);
      Logger.d('MobileTts', 'setLanguage/setSpeechRate 完成，触发引擎绑定...');
    } catch (e) {
      Logger.e('MobileTts', '初始化 setLanguage 失败: $e');
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    Logger.d('MobileTts', '等待引擎初始化...');

    await _bindingFuture;

    for (var i = 0; i < 20; i++) {
      try {
        final languages = await _flutterTts.getLanguages;
        if (languages is List && languages.isNotEmpty) {
          _initialized = true;
          Logger.i('MobileTts', '引擎初始化完成 (尝试 ${i + 1} 次, 语言数: ${languages.length})');
          return;
        }
        Logger.d('MobileTts', 'getLanguages 返回空，引擎未就绪 (尝试 ${i + 1})');
      } catch (e) {
        Logger.d('MobileTts', 'getLanguages 异常: $e (尝试 ${i + 1})');
      }

      try {
        await _flutterTts.setLanguage('zh-CN');
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 500));
    }

    Logger.e('MobileTts', '引擎初始化超时（已重试20次）');
    throw Exception('TTS 引擎初始化超时，请检查系统 TTS 设置');
  }

  @override
  Future<void> speak(String text, {String language = 'zh-CN', double rate = 1.0}) async {
    Logger.i('MobileTts', '[TTS speak] 开始: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}"');
    await _ensureInitialized();
    await _flutterTts.setLanguage(language);
    await _flutterTts.setSpeechRate(rate);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    final completer = Completer<void>();
    late StreamSubscription<dynamic> subscription;
    subscription = _completionController.stream.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
        subscription.cancel();
      }
    });

    await _flutterTts.speak(text);
    Logger.d('MobileTts', '[TTS speak] 已调用 speak，等待播放完成...');

    await completer.future.timeout(const Duration(seconds: 60));
    Logger.d('MobileTts', '[TTS speak] 播放完成');
  }

  @override
  Future<void> stop() async {
    Logger.d('MobileTts', '[TTS] 停止');
    await _flutterTts.stop();
  }

  @override
  Future<void> pause() async {
    Logger.d('MobileTts', '[TTS] 暂停');
    await _flutterTts.pause();
  }

  @override
  Future<void> resume() async {
    Logger.d('MobileTts', '[TTS] 恢复');
    await _flutterTts.setLanguage('zh-CN');
    await _flutterTts.speak('');
  }

  @override
  Future<bool> isLanguageAvailable(String language) async {
    await _ensureInitialized();
    final result = await _flutterTts.isLanguageAvailable(language);
    return result == true || result == 1;
  }

  @override
  Stream get onComplete => _completionController.stream;

  @override
  void dispose() {
    Logger.d('MobileTts', '释放资源');
    _completionController.close();
    _flutterTts.stop();
  }
}