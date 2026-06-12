import 'dart:async';
import 'package:asr_plugin/asr_plugin.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../speech_recognition_service.dart';

class ASRSpeechRecognitionService implements SpeechRecognitionService {
  final ASRControllerConfig _config = ASRControllerConfig();
  ASRController? _controller;
  final StreamController<String> _resultController = StreamController<String>();

  ASRSpeechRecognitionService() {
    _config.appID = int.parse(dotenv.env['TENCENT_APP_ID'] ?? '0');
    _config.secretID = dotenv.env['TENCENT_SECRET_ID'] ?? '';
    _config.secretKey = dotenv.env['TENCENT_SECRET_KEY'] ?? '';
    _config.engine_model_type = "16k_zh";
    _config.setCustomParam("emotion_recognition", 0);
  }

  @override
  Stream<String> startListening() async* {
    try {
      if (_controller != null) {
        await _controller?.release();
      }
      _controller = await _config.build();
      Stream<ASRData> asrStream = _controller!.recognize();

      await for (final val in asrStream) {
        switch (val.type) {
          case ASRDataType.SLICE:
          case ASRDataType.SEGMENT:
            if (val.res != null) {
              yield val.res!;
            }
            break;
          case ASRDataType.SUCCESS:
            if (val.result != null) {
              yield val.result!;
            }
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