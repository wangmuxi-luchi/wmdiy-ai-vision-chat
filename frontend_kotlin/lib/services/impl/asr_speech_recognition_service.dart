import 'dart:async';
import 'package:asr_plugin/asr_plugin.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../speech_recognition_service.dart';
import '../config_service.dart';
import '../../utils/logger.dart';

class ASRSpeechRecognitionService implements SpeechRecognitionService {
  final ASRControllerConfig _config = ASRControllerConfig();
  ASRController? _controller;
  final StreamController<ASRResult> _resultController = StreamController<ASRResult>();
  bool _configLoaded = false;

  ASRSpeechRecognitionService() {
    _config.appID = int.parse(dotenv.env['TENCENT_APP_ID'] ?? '0');
    _config.secretID = dotenv.env['TENCENT_SECRET_ID'] ?? '';
    _config.secretKey = dotenv.env['TENCENT_SECRET_KEY'] ?? '';
    _config.engine_model_type = "16k_zh";
    _config.setCustomParam("emotion_recognition", 0);
    _loadConfigAsync();
  }

  Future<void> _loadConfigAsync() async {
    try {
      final configService = ConfigService();
      final speechConfig = await configService.getSpeechConfig();
      
      if (speechConfig.isValid) {
        _config.appID = int.parse(speechConfig.appId);
        _config.secretID = speechConfig.secretId;
        _config.secretKey = speechConfig.secretKey;
      }
      _configLoaded = true;
    } catch (e) {
      print('Error loading speech config: $e');
    }
  }

  Future<void> updateConfig() async {
    try {
      final configService = ConfigService();
      final speechConfig = await configService.getSpeechConfig();
      
      if (speechConfig.isValid) {
        _config.appID = int.parse(speechConfig.appId);
        _config.secretID = speechConfig.secretId;
        _config.secretKey = speechConfig.secretKey;
      } else {
        _config.appID = int.parse(dotenv.env['TENCENT_APP_ID'] ?? '0');
        _config.secretID = dotenv.env['TENCENT_SECRET_ID'] ?? '';
        _config.secretKey = dotenv.env['TENCENT_SECRET_KEY'] ?? '';
      }
      
      if (_controller != null) {
        _controller?.release();
        _controller = null;
      }
    } catch (e) {
      print('Error updating speech config: $e');
    }
  }

  @override
  Stream<ASRResult> startListening() async* {
    try {
      if (_controller != null) {
        await _controller?.release();
      }
      _controller = await _config.build();
      Stream<ASRData> asrStream = _controller!.recognize();

      await for (final val in asrStream) {
        String content = val.res ?? val.result ?? '(空)';
        Logger.d('ASR', '收到数据: type=${val.type}, content="$content"');
        
        switch (val.type) {
          case ASRDataType.SLICE:
            if (val.res != null) {
              yield ASRResult(val.res!, isFinal: false);
            }
            break;
          case ASRDataType.SEGMENT:
            // SEGMENT 表示单段话结束，标记为可发送的最终结果
            if (val.res != null) {
              yield ASRResult(val.res!, isFinal: true);
            }
            break;
          case ASRDataType.SUCCESS:
            // 屏蔽 SUCCESS 类型，关闭麦克风时不再发送完整会话
            // 用户希望只在 SEGMENT 阶段发送，避免重复发送
            break;
          case ASRDataType.NOTIFY:
            break;
        }
      }
    } on ASRError catch (e) {
      throw Exception("语音识别错误: ${e.message}");
    } catch (e) {
      throw Exception("语音识别异常: $e");
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      await _controller?.stop();
    } catch (e) {
      throw Exception("停止识别失败: $e");
    }
  }

  @override
  void dispose() {
    _controller?.stop();
    _controller?.release();
    _resultController.close();
  }
}