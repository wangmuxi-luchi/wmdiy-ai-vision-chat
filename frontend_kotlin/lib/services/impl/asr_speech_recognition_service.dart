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
  bool _isListening = false;

  ASRSpeechRecognitionService() {
    _config.appID = int.parse(dotenv.env['TENCENT_APP_ID'] ?? '0');
    _config.secretID = dotenv.env['TENCENT_SECRET_ID'] ?? '';
    _config.secretKey = dotenv.env['TENCENT_SECRET_KEY'] ?? '';
    _config.engine_model_type = "16k_zh";
    _config.setCustomParam("emotion_recognition", 0);
    Logger.d('ASR', '构造函数 - 从环境变量加载默认凭证: appId=${_config.appID}, secretId=${_config.secretID.isNotEmpty ? '***' : '空'}, secretKey=${_config.secretKey.isNotEmpty ? '***' : '空'}');
    _loadConfigAsync();
  }

  Future<void> _loadConfigAsync() async {
    try {
      Logger.d('ASR', '_loadConfigAsync - 开始加载语音配置');
      final configService = ConfigService();
      final speechConfig = await configService.getSpeechConfig();
      
      if (speechConfig.isValid) {
        _config.appID = int.parse(speechConfig.appId);
        _config.secretID = speechConfig.secretId;
        _config.secretKey = speechConfig.secretKey;
        Logger.d('ASR', '_loadConfigAsync - 配置文件有效，使用配置文件凭证: appId=${_config.appID}');
      } else {
        Logger.d('ASR', '_loadConfigAsync - 配置文件无效，继续使用环境变量凭证');
      }
    } catch (e) {
      Logger.e('ASR', '_loadConfigAsync - 加载语音配置失败: $e');
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
      Logger.e('ASR', 'Error updating speech config: $e');
    }
  }

  @override
  Stream<ASRResult> startListening() async* {
    try {
      Logger.d('ASR', 'startListening - 开始语音识别');
      Logger.d('ASR', 'startListening - 当前配置: appId=${_config.appID}, secretId=${_config.secretID.isNotEmpty ? '已设置' : '空'}, secretKey=${_config.secretKey.isNotEmpty ? '已设置' : '空'}, engine=${_config.engine_model_type}');
      
      if (_isListening) {
        Logger.w('ASR', 'startListening - 正在监听中，强制停止旧会话');
        try {
          await _controller?.stop().timeout(const Duration(seconds: 3));
        } catch (_) {}
        try {
          await _controller?.release();
        } catch (_) {}
        _controller = null;
        _isListening = false;
      }
      
      if (_controller != null) {
        Logger.d('ASR', 'startListening - 释放之前的控制器');
        await _controller?.release();
        _controller = null;
      }
      
      Logger.d('ASR', 'startListening - 构建ASR控制器...');
      _controller = await _config.build();
      Logger.d('ASR', 'startListening - ASR控制器构建成功');
      
      _isListening = true;
      Logger.d('ASR', 'startListening - 开始识别流...');
      Stream<ASRData> asrStream = _controller!.recognize();
      Logger.d('ASR', 'startListening - 识别流已启动，等待语音数据...');

      await for (final val in asrStream) {
        String content = val.res ?? val.result ?? '(空)';
        Logger.d('ASR', 'startListening - 收到数据: type=${val.type}, res=${val.res ?? 'null'}, result=${val.result ?? 'null'}');
        
        switch (val.type) {
          case ASRDataType.SLICE:
            Logger.d('ASR', 'startListening - 收到中间结果(SLICE): $content');
            if (val.res != null) {
              yield ASRResult(val.res!, isFinal: false);
              Logger.d('ASR', 'startListening - 输出中间结果: $content');
            }
            break;
          case ASRDataType.SEGMENT:
            Logger.d('ASR', 'startListening - 收到分段结果(SEGMENT): $content');
            if (val.res != null) {
              yield ASRResult(val.res!, isFinal: true);
              Logger.d('ASR', 'startListening - 输出最终结果: $content');
            }
            break;
          case ASRDataType.SUCCESS:
            Logger.d('ASR', 'startListening - 收到成功通知(SUCCESS): $content');
            break;
          case ASRDataType.NOTIFY:
            Logger.d('ASR', 'startListening - 收到通知(NOTIFY): $content');
            break;
        }
      }
      
      Logger.d('ASR', 'startListening - 识别流结束');
    } on ASRError catch (e) {
      _isListening = false;
      Logger.e('ASR', 'startListening - 语音识别错误: ${e.message}');
      throw Exception("语音识别错误: ${e.message}");
    } catch (e) {
      _isListening = false;
      Logger.e('ASR', 'startListening - 语音识别异常: $e, 类型: ${e.runtimeType}');
      throw Exception("语音识别异常: $e");
    } finally {
      _isListening = false;
      Logger.d('ASR', 'startListening - finally: 监听状态已重置');
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      Logger.d('ASR', 'stopListening - 停止语音识别');
      if (_controller != null) {
        Logger.d('ASR', 'stopListening - 调用控制器stop方法');
        await _controller?.stop();
        Logger.d('ASR', 'stopListening - 控制器stop完成');
      } else {
        Logger.w('ASR', 'stopListening - 控制器为空，无需停止');
      }
    } catch (e) {
      Logger.e('ASR', 'stopListening - 停止识别失败: $e');
      throw Exception("停止识别失败: $e");
    } finally {
      _isListening = false;
    }
  }

  @override
  void setCredentials({
    required String secretId,
    required String secretKey,
    required int appId,
  }) {
    _config.appID = appId;
    _config.secretID = secretId;
    _config.secretKey = secretKey;
    Logger.d('ASR', '凭证已更新: appId=$appId, secretId=${secretId.isNotEmpty ? '***' : '空'}');
    
    // 如果控制器已创建，释放它以便下次使用新配置
    if (_controller != null) {
      _controller?.release();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.stop();
    _controller?.release();
    _resultController.close();
  }
}