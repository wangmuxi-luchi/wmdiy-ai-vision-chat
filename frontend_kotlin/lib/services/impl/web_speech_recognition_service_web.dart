import 'dart:async';
import 'dart:js' as js;
import '../speech_recognition_service.dart';
import '../../utils/logger.dart';

class WebSpeechRecognitionService implements SpeechRecognitionService {
  StreamController<ASRResult>? _resultController;
  js.JsObject? _speechRecognizer;
  js.JsObject? _webRecorder;
  bool _isRecording = false;
  bool _isDisposed = false;

  @override
  Stream<ASRResult> startListening() async* {
    try {
      if (_isRecording) {
        Logger.w('WebASR', '正在录音中，忽略重复启动');
        return;
      }

      // 创建新的 StreamController
      _resultController = StreamController<ASRResult>();

      // 检查 SDK 是否已加载
      if (js.context['SpeechRecognizer'] == null) {
        throw Exception('SpeechRecognizer SDK 未加载，请检查 web/index.html 配置');
      }
      if (js.context['WebRecorder'] == null) {
        throw Exception('WebRecorder SDK 未加载，请检查 web/index.html 配置');
      }

      // 创建参数
      final params = js.JsObject.jsify({
        'secretid': '',
        'appid': '',
        'engine_model_type': '16k_zh',
        'voice_format': 1,
        'needvad': 1,
        'filter_dirty': 1,
        'filter_modal': 1,
        'filter_punc': 1,
        'convert_num_mode': 1,
        'word_info': 2,
      });

      // 创建识别器
      _speechRecognizer = js.JsObject(js.context['SpeechRecognizer'], [params]);

      // 设置回调
      _speechRecognizer!.callMethod('OnRecognitionStart', [
        js.allowInterop((js.JsObject res) {
          Logger.d('WebASR', '识别开始');
        })
      ]);

      _speechRecognizer!.callMethod('OnSentenceBegin', [
        js.allowInterop((js.JsObject res) {
          Logger.d('WebASR', '句子开始');
        })
      ]);

      _speechRecognizer!.callMethod('OnRecognitionResultChange', [
        js.allowInterop((js.JsObject res) {
          if (_isDisposed) return;
          final result = res['result'];
          if (result != null) {
            final text = result['voice_text_str'] ?? '';
            Logger.d('WebASR', '收到数据: type=SLICE, content="$text"');
            if (_resultController != null && !_resultController!.isClosed) {
              _resultController!.add(ASRResult(text.toString(), isFinal: false));
            }
          }
        })
      ]);

      _speechRecognizer!.callMethod('OnSentenceEnd', [
        js.allowInterop((js.JsObject res) {
          if (_isDisposed) return;
          final result = res['result'];
          if (result != null) {
            final text = result['voice_text_str'] ?? '';
            Logger.d('WebASR', '收到数据: type=SEGMENT, content="$text"');
            if (_resultController != null && !_resultController!.isClosed) {
              _resultController!.add(ASRResult(text.toString(), isFinal: true));
            }
          }
        })
      ]);

      _speechRecognizer!.callMethod('OnRecognitionComplete', [
        js.allowInterop((js.JsObject res) {
          Logger.d('WebASR', '识别完成');
          _isRecording = false;
          _closeController();
        })
      ]);

      _speechRecognizer!.callMethod('OnError', [
        js.allowInterop((dynamic err) {
          if (_isDisposed) return;
          final errorMsg = err is js.JsObject ? err.toString() : err;
          Logger.e('WebASR', '识别错误: $errorMsg');
          if (_resultController != null && !_resultController!.isClosed) {
            _resultController!.addError(Exception('识别错误: $errorMsg'));
          }
          _isRecording = false;
          _closeController();
        })
      ]);

      // 创建录音器
      _webRecorder = js.JsObject(js.context['WebRecorder']);

      // 设置录音数据回调
      _webRecorder!.callMethod('OnReceivedData', [
        js.allowInterop((js.JsObject data) {
          if (_isRecording && _speechRecognizer != null) {
            _speechRecognizer!.callMethod('write', [data]);
          }
        })
      ]);

      _webRecorder!.callMethod('OnError', [
        js.allowInterop((dynamic err) {
          if (_isDisposed) return;
          final errorMsg = err is js.JsObject ? err.toString() : err;
          Logger.e('WebASR', '录音错误: $errorMsg');
          if (_resultController != null && !_resultController!.isClosed) {
            _resultController!.addError(Exception('录音错误: $errorMsg'));
          }
        })
      ]);

      // 开始录音
      _webRecorder!.callMethod('start');

      // 建立识别连接（异步）
      _speechRecognizer!.callMethod('start');

      _isRecording = true;

      yield* _resultController!.stream;
    } catch (e) {
      Logger.e('WebASR', '启动失败: $e');
      _closeController();
      throw Exception('语音识别启动失败: $e');
    }
  }

  void _closeController() {
    try {
      if (_resultController != null && !_resultController!.isClosed) {
        _resultController!.close();
      }
      _resultController = null;
    } catch (e) {
      Logger.d('WebASR', '关闭控制器时出错: $e');
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      _isRecording = false;

      if (_webRecorder != null) {
        try {
          _webRecorder!.callMethod('stop');
        } catch (e) {
          Logger.d('WebASR', '停止录音时出错: $e');
        }
        _webRecorder = null;
      }

      if (_speechRecognizer != null) {
        try {
          _speechRecognizer!.callMethod('stop');
        } catch (e) {
          Logger.d('WebASR', '停止识别时出错: $e');
        }
        _speechRecognizer = null;
      }

      _closeController();
    } catch (e) {
      Logger.e('WebASR', '停止失败: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopListening();
    _closeController();
  }
}