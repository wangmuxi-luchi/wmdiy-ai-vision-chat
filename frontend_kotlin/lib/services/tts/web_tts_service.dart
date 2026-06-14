import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'tts_service.dart';

class WebTtsService implements TtsService {
  final StreamController<dynamic> _completionController = StreamController.broadcast();
  bool _isSpeaking = false;

  WebTtsService();

  @override
  Future<void> speak(String text, {String language = 'zh-CN', double rate = 1.0}) async {
    final completer = Completer<void>();
    try {
      final escapedText = text
          .replaceAll('\\', '\\\\')
          .replaceAll('\'', '\\\'')
          .replaceAll('\n', '\\n');
      final utterance = globalContext.callMethod(
        'eval'.toJS,
        'new SpeechSynthesisUtterance(\'$escapedText\')'.toJS,
      );
      if (utterance != null) {
        final utteranceObj = utterance as JSObject;
        utteranceObj.setProperty('lang'.toJS, language.toJS);
        utteranceObj.setProperty('rate'.toJS, rate.toJS);

        utteranceObj.setProperty('onend'.toJS, (() {
          _isSpeaking = false;
          _completionController.add(null);
          if (!completer.isCompleted) {
            completer.complete();
          }
        }).toJS);

        utteranceObj.setProperty('onerror'.toJS, ((JSObject event) {
          _isSpeaking = false;
          debugPrint('Web TTS 播放错误: $event');
          if (!completer.isCompleted) {
            completer.complete();
          }
        }).toJS);

        final synth = globalContext.getProperty('speechSynthesis'.toJS);
        if (synth != null) {
          (synth as JSObject).callMethod('speak'.toJS, utteranceObj);
          _isSpeaking = true;
        } else {
          if (!completer.isCompleted) completer.complete();
        }
      } else {
        if (!completer.isCompleted) completer.complete();
      }
    } catch (e) {
      _isSpeaking = false;
      debugPrint('Web TTS 错误: $e');
      if (!completer.isCompleted) completer.complete();
    }
    return completer.future;
  }

  @override
  Future<void> stop() async {
    try {
      final synth = globalContext.getProperty('speechSynthesis'.toJS);
      if (synth != null) {
        (synth as JSObject).callMethod('cancel'.toJS);
      }
      _isSpeaking = false;
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    try {
      final synth = globalContext.getProperty('speechSynthesis'.toJS);
      if (synth != null) {
        (synth as JSObject).callMethod('pause'.toJS);
      }
    } catch (_) {}
  }

  @override
  Future<void> resume() async {
    try {
      final synth = globalContext.getProperty('speechSynthesis'.toJS);
      if (synth != null) {
        (synth as JSObject).callMethod('resume'.toJS);
      }
    } catch (_) {}
  }

  @override
  Future<bool> isLanguageAvailable(String language) async {
    try {
      final synth = globalContext.getProperty('speechSynthesis'.toJS);
      if (synth != null) {
        (synth as JSObject).callMethod('getVoices'.toJS);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream get onComplete => _completionController.stream;

  @override
  void dispose() {
    _completionController.close();
    stop();
  }
}