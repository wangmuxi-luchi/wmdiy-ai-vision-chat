import 'dart:async';
import 'dart:js' as js;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../speech_recognition_service.dart';
import '../../utils/logger.dart';

class WebSpeechRecognitionService implements SpeechRecognitionService {
  StreamController<ASRResult>? _resultController;
  js.JsObject? _webAudioRecognizer;
  bool _isRecording = false;
  bool _isDisposed = false;
  bool _isCanStop = false;

  String? _secretId;
  String? _secretKey;
  int? _appId;
  String? _token;
  String? _hotwordId;
  int? _needVad;
  int? _filterDirty;
  int? _filterModal;
  int? _filterPunc;
  int? _convertNumMode;
  int? _wordInfo;
  String? _engineModelType;
  int? _voiceFormat;
  bool? _echoCancellation;

  Map<String, dynamic>? _contextPrompt;

  WebSpeechRecognitionService() {
    _loadCredentialsFromEnv();
    _loadDefaultParameters();
  }

  void _loadCredentialsFromEnv() {
    try {
      final envAppId = dotenv.env['TENCENT_APP_ID'];
      final envSecretId = dotenv.env['TENCENT_SECRET_ID'];
      final envSecretKey = dotenv.env['TENCENT_SECRET_KEY'];
      final envToken = dotenv.env['TENCENT_TOKEN'];

      if (envAppId != null && envAppId.isNotEmpty) {
        _appId = int.tryParse(envAppId);
      }
      if (envSecretId != null && envSecretId.isNotEmpty) {
        _secretId = envSecretId;
      }
      if (envSecretKey != null && envSecretKey.isNotEmpty) {
        _secretKey = envSecretKey;
      }
      if (envToken != null && envToken.isNotEmpty) {
        _token = envToken;
      }

      if (_appId != null && _secretId != null && _secretKey != null) {
        Logger.d('WebASR', '已从环境变量加载默认凭证: appId=$_appId');
      }
    } catch (e) {
      Logger.d('WebASR', '从环境变量加载凭证失败: $e');
    }
  }

  void _loadDefaultParameters() {
    _engineModelType = '16k_zh_test';
    _voiceFormat = 1;
    _hotwordId = '';
    _needVad = 1;
    _filterDirty = 1;
    _filterModal = 1;
    _filterPunc = 1;
    _convertNumMode = 1;
    _wordInfo = 2;
    _echoCancellation = true;
  }

  void _checkMicrophonePermission() {
    Logger.d('WebASR', '麦克风权限将在start()调用时由SDK自动请求');
  }

  List<int> _toUint8Array(js.JsObject wordArray) {
    final words = wordArray['words'] as List<dynamic>;
    final sigBytes = wordArray['sigBytes'] as int;
    final u8 = List<int>.filled(sigBytes, 0);
    for (int i = 0; i < sigBytes; i++) {
      u8[i] = (words[i >> 2] >> (24 - (i % 4) * 8)) & 0xff;
    }
    return u8;
  }

  String _uint8ArrayToString(List<int> fileData) {
    String dataString = '';
    for (int i = 0; i < fileData.length; i++) {
      dataString += String.fromCharCode(fileData[i]);
    }
    return dataString;
  }

  void setParameters({
    String? engineModelType,
    int? voiceFormat,
    String? hotwordId,
    int? needVad,
    int? filterDirty,
    int? filterModal,
    int? filterPunc,
    int? convertNumMode,
    int? wordInfo,
    bool? echoCancellation,
  }) {
    if (engineModelType != null) _engineModelType = engineModelType;
    if (voiceFormat != null) _voiceFormat = voiceFormat;
    if (hotwordId != null) _hotwordId = hotwordId;
    if (needVad != null) _needVad = needVad;
    if (filterDirty != null) _filterDirty = filterDirty;
    if (filterModal != null) _filterModal = filterModal;
    if (filterPunc != null) _filterPunc = filterPunc;
    if (convertNumMode != null) _convertNumMode = convertNumMode;
    if (wordInfo != null) _wordInfo = wordInfo;
    if (echoCancellation != null) _echoCancellation = echoCancellation;
    Logger.d('WebASR', '参数已更新: engine_model_type=$_engineModelType, needvad=$_needVad');
  }

  void setContextPrompt({
    String? hotwordList,
    List<String>? promptTexts,
  }) {
    final promptItems = <Map<String, dynamic>>[];
    
    if (promptTexts != null && promptTexts.isNotEmpty) {
      final validTexts = promptTexts.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (validTexts.isNotEmpty) {
        promptItems.add({
          'context_type': 'scene',
          'context_data': validTexts.map((text) => {'text': text}).toList(),
        });
      }
    }

    if ((hotwordList == null || hotwordList.trim().isEmpty) && promptItems.isEmpty) {
      _contextPrompt = null;
      return;
    }

    _contextPrompt = {
      'context_type': 'context',
      'hotword_list': hotwordList?.trim() ?? '',
      'prompt': promptItems,
    };
    Logger.d('WebASR', '上下文提示已设置: ${_contextPrompt.toString()}');
  }

  void setToken(String token) {
    _token = token;
    Logger.d('WebASR', 'Token已更新');
  }

  @override
  void setCredentials({
    required String secretId,
    required String secretKey,
    required int appId,
  }) {
    _secretId = secretId;
    _secretKey = secretKey;
    _appId = appId;
    Logger.d('WebASR', '凭证已更新: appId=$appId, secretId=${secretId.isNotEmpty ? '***' : '空'}');
  }

  bool writeContent(Map<String, dynamic> contextPrompt) {
    if (_webAudioRecognizer == null) {
      Logger.w('WebASR', 'writeContent failed: WebAudioSpeechRecognizer not initialized');
      return false;
    }
    try {
      final jsContextPrompt = js.JsObject.jsify(contextPrompt);
      final result = _webAudioRecognizer!.callMethod('writeContent', [jsContextPrompt]);
      return result is bool ? result : (result != null);
    } catch (e) {
      Logger.e('WebASR', 'writeContent error: $e');
      return false;
    }
  }

  void destroyStream() {
    if (_webAudioRecognizer != null) {
      try {
        _webAudioRecognizer!.callMethod('destroyStream');
        Logger.d('WebASR', '音频流已销毁');
      } catch (e) {
        Logger.d('WebASR', 'destroyStream error: $e');
      }
    }
  }

  @override
  Stream<ASRResult> startListening() async* {
    try {
      Logger.d('WebASR', '========== 开始启动语音识别 ==========');
      
      if (_isRecording) {
        Logger.w('WebASR', '正在录音中，忽略重复启动');
        return;
      }

      Logger.d('WebASR', '检查凭证状态: secretId=${_secretId != null ? '已设置' : '空'}, secretKey=${_secretKey != null ? '已设置' : '空'}, appId=$_appId');
      
      if (_secretId == null || _secretId!.isEmpty) {
        throw Exception('请先设置 SecretId');
      }
      if (_secretKey == null || _secretKey!.isEmpty) {
        throw Exception('请先设置 SecretKey');
      }
      if (_appId == null || _appId! <= 0) {
        throw Exception('请先设置 AppId');
      }

      Logger.d('WebASR', '凭证检查通过');
      
      _resultController = StreamController<ASRResult>();
      Logger.d('WebASR', 'StreamController已创建');

      Logger.d('WebASR', '检查麦克风权限...');
      _checkMicrophonePermission();

      Logger.d('WebASR', '检查 WebAudioSpeechRecognizer SDK...');
      if (js.context['WebAudioSpeechRecognizer'] == null) {
        throw Exception('WebAudioSpeechRecognizer SDK 未加载，请检查 web/index.html 配置');
      }
      Logger.d('WebASR', 'WebAudioSpeechRecognizer SDK 已加载');

      Logger.d('WebASR', '使用配置: appId=$_appId, engine_model_type=$_engineModelType, needVad=$_needVad');

      Logger.d('WebASR', '创建签名回调函数...');
      final signCallback = js.allowInterop((String signStr) {
        Logger.d('WebASR', '签名回调被调用: signStr长度=${signStr.length}');
        final cryptoJS = js.context['CryptoJS'];
        if (cryptoJS == null) {
          Logger.e('WebASR', 'CryptoJS 未加载，请检查 web/index.html 中 cryptojs.js 是否正确加载');
          return '';
        }
        try {
          final hash = cryptoJS.callMethod('HmacSHA1', [signStr, _secretKey]);
          final bytes = _uint8ArrayToString(_toUint8Array(hash));
          final result = js.context.callMethod('btoa', [bytes]);
          Logger.d('WebASR', '签名成功');
          return result;
        } catch (e) {
          Logger.e('WebASR', '签名失败: $e');
          return '';
        }
      });
      Logger.d('WebASR', '签名回调函数已创建');

      Logger.d('WebASR', '构建参数对象...');
      final params = js.JsObject.jsify({
        'signCallback': signCallback,
        'secretid': _secretId,
        'secretkey': _secretKey,
        'appid': _appId,
        'engine_model_type': _engineModelType,
        'voice_format': _voiceFormat,
        'needvad': _needVad,
        'filter_dirty': _filterDirty,
        'filter_modal': _filterModal,
        'filter_punc': _filterPunc,
        'convert_num_mode': _convertNumMode,
        'word_info': _wordInfo,
        'echoCancellation': _echoCancellation,
        'isLog': true,
      });

      if (_hotwordId != null && _hotwordId!.isNotEmpty) {
        params['hotword_id'] = _hotwordId;
        Logger.d('WebASR', '已设置 hotword_id');
      }
      if (_token != null && _token!.isNotEmpty) {
        params['token'] = _token;
        Logger.d('WebASR', '已设置 token');
      }
      Logger.d('WebASR', '参数对象构建完成');

      Logger.d('WebASR', '准备初始化 WebAudioSpeechRecognizer...');
      try {
        _webAudioRecognizer = js.JsObject(js.context['WebAudioSpeechRecognizer'], [params]);
        Logger.d('WebASR', 'WebAudioSpeechRecognizer 初始化成功');
      } catch (e) {
        Logger.e('WebASR', 'WebAudioSpeechRecognizer 初始化失败: $e');
        throw e;
      }

      Logger.d('WebASR', '注册回调函数...');

      _webAudioRecognizer!['OnRecognitionStart'] = js.allowInterop((js.JsObject res) {
        Logger.d('WebASR', '【回调】OnRecognitionStart: res=$res');
        _isCanStop = true;

        if (_contextPrompt != null) {
          final ok = writeContent(_contextPrompt!);
          if (ok) {
            Logger.d('WebASR', '自动发送 contextPrompt 成功');
          } else {
            Logger.w('WebASR', '自动发送 contextPrompt 失败');
          }
        }
      });
      Logger.d('WebASR', '已注册 OnRecognitionStart 回调');

      _webAudioRecognizer!['OnSentenceBegin'] = js.allowInterop((js.JsObject res) {
        Logger.d('WebASR', '【回调】OnSentenceBegin: res=$res');
      });
      Logger.d('WebASR', '已注册 OnSentenceBegin 回调');

      _webAudioRecognizer!['OnRecognitionResultChange'] = js.allowInterop((js.JsObject res) {
        if (_isDisposed) {
          Logger.d('WebASR', '【回调】OnRecognitionResultChange: 已销毁，忽略');
          return;
        }
        final result = res['result'];
        Logger.d('WebASR', '【回调】OnRecognitionResultChange: result=$result');
        if (result != null) {
          final text = result['voice_text_str'] ?? '';
          Logger.d('WebASR', '【回调】OnRecognitionResultChange: 识别文本="$text"');
          if (_resultController != null && !_resultController!.isClosed) {
            _resultController!.add(ASRResult(text.toString(), isFinal: false));
            Logger.d('WebASR', '已将识别结果添加到Stream');
          }
        }
      });
      Logger.d('WebASR', '已注册 OnRecognitionResultChange 回调');

      _webAudioRecognizer!['OnSentenceEnd'] = js.allowInterop((js.JsObject res) {
        if (_isDisposed) {
          Logger.d('WebASR', '【回调】OnSentenceEnd: 已销毁，忽略');
          return;
        }
        final result = res['result'];
        Logger.d('WebASR', '【回调】OnSentenceEnd: result=$result');
        if (result != null) {
          final text = result['voice_text_str'] ?? '';
          Logger.d('WebASR', '【回调】OnSentenceEnd: 最终文本="$text"');
          if (_resultController != null && !_resultController!.isClosed) {
            _resultController!.add(ASRResult(text.toString(), isFinal: true));
            Logger.d('WebASR', '已将最终识别结果添加到Stream');
          }
        }
      });
      Logger.d('WebASR', '已注册 OnSentenceEnd 回调');

      _webAudioRecognizer!['OnRecognitionComplete'] = js.allowInterop((js.JsObject res) {
        Logger.d('WebASR', '【回调】OnRecognitionComplete: res=$res');
        _isRecording = false;
        _isCanStop = false;
        _closeController();
      });
      Logger.d('WebASR', '已注册 OnRecognitionComplete 回调');

      _webAudioRecognizer!['OnError'] = js.allowInterop((dynamic err) {
        if (_isDisposed) {
          Logger.d('WebASR', '【回调】OnError: 已销毁，忽略');
          return;
        }
        String errorMsg = '未知错误';
        if (err is js.JsObject) {
          // 尝试获取详细错误信息
          if (err['code'] != null) {
            errorMsg = '错误码: ${err['code']}';
          }
          if (err['message'] != null) {
            errorMsg += ', 错误信息: ${err['message']}';
          }
          if (err['detail'] != null) {
            errorMsg += ', 详情: ${err['detail']}';
          }
          if (errorMsg == '未知错误') {
            errorMsg = err.toString();
          }
        } else {
          errorMsg = err.toString();
        }
        Logger.e('WebASR', '【回调】OnError: $errorMsg');
        if (_resultController != null && !_resultController!.isClosed) {
          _resultController!.addError(Exception('识别错误: $errorMsg'));
        }
        _isRecording = false;
        _isCanStop = false;
        _closeController();
      });
      Logger.d('WebASR', '已注册 OnError 回调');

      _webAudioRecognizer!['OnRecorderStop'] = js.allowInterop((dynamic res) {
        Logger.d('WebASR', '【回调】OnRecorderStop: 录音器已停止');
      });
      Logger.d('WebASR', '已注册 OnRecorderStop 回调');

      Logger.d('WebASR', '所有回调已注册，准备调用 start()...');
      Logger.d('WebASR', '检查 _webAudioRecognizer: ${_webAudioRecognizer != null ? '已初始化' : '为空'}');
      try {
        Logger.d('WebASR', '正在调用 start()...');
        _webAudioRecognizer!.callMethod('start');
        Logger.d('WebASR', 'start() 调用成功，等待麦克风权限授权...');
        Logger.d('WebASR', '如果麦克风权限未授权，SDK 会等待用户授权');
      } catch (e) {
        Logger.e('WebASR', 'start() 调用失败: $e');
        Logger.e('WebASR', '错误类型: ${e.runtimeType}');
        throw e;
      }

      _isRecording = true;
      Logger.d('WebASR', '录音状态已设置为 true');

      Logger.d('WebASR', '开始监听Stream，等待识别结果...');
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

      if (_webAudioRecognizer != null && _isCanStop) {
        try {
          _webAudioRecognizer!.callMethod('stop');
        } catch (e) {
          Logger.d('WebASR', '停止识别时出错: $e');
        }
      }

      _isCanStop = false;
      _closeController();
    } catch (e) {
      Logger.e('WebASR', '停止失败: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopListening();
    destroyStream();
    _closeController();
  }
}