import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'tts_service.dart';

class WebTtsService implements TtsService {
  final StreamController<dynamic> _completionController = StreamController.broadcast();
  bool _isSpeaking = false;

  WebTtsService() {
    _setupEndCallback();
  }

  void _setupEndCallback() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isSpeaking) {
        timer.cancel();
      }
      final synth = globalContext.getProperty('speechSynthesis'.toJS);
      if (synth != null) {
        final speaking = (synth as JSObject).getProperty('speaking'.toJS);
        if (speaking != null && speaking.isA<JSBoolean>()) {
          if (!(speaking as JSBoolean).toDart && _isSpeaking) {
            _isSpeaking = false;
            _completionController.add(null);
            timer.cancel();
          }
        }
      }
    });
  }

  @override
  Future<void> speak(String text, {String language = 'zh-CN', double rate = 1.0}) async {
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
        (utterance as JSObject).setProperty('lang'.toJS, language.toJS);
        utterance.setProperty('rate'.toJS, rate.toJS);
        final synth = globalContext.getProperty('speechSynthesis'.toJS);
        if (synth != null) {
          (synth as JSObject).callMethod('speak'.toJS, utterance);
        }
        _isSpeaking = true;
      }
    } catch (e) {
      debugPrint('Web TTS 错误: $e');
    }
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