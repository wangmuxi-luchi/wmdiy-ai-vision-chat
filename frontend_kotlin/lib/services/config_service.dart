import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConfigService {
  static const String _speechConfigKey = 'speech_config';
  static const String _backendConfigKey = 'backend_config';
  static const String _imageTransmissionConfigKey = 'image_transmission_config';
  static const String _ttsConfigKey = 'tts_config';
  
  static SharedPreferences? _instance;

  static Future<SharedPreferences> _getInstance() async {
    return _instance ??= await SharedPreferences.getInstance();
  }

  Future<void> init() async {
    await _getInstance();
  }

  Future<SpeechConfig> getSpeechConfig() async {
    final prefs = await _getInstance();
    final String? jsonString = prefs.getString(_speechConfigKey);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> json = jsonDecode(jsonString);
        final config = SpeechConfig.fromJson(json);
        if (config.isValid) {
          return config;
        }
      } catch (e) {
        // 解析失败，使用默认配置
      }
    }
    return _getDefaultSpeechConfig();
  }

  SpeechConfig _getDefaultSpeechConfig() {
    final envAppId = dotenv.env['TENCENT_APP_ID'] ?? '';
    final envSecretId = dotenv.env['TENCENT_SECRET_ID'] ?? '';
    final envSecretKey = dotenv.env['TENCENT_SECRET_KEY'] ?? '';
    
    return SpeechConfig(
      appId: envAppId,
      secretId: envSecretId,
      secretKey: envSecretKey,
      region: dotenv.env['TENCENT_REGION'] ?? 'ap-beijing',
    );
  }

  Future<void> saveSpeechConfig(SpeechConfig config) async {
    final prefs = await _getInstance();
    final String jsonString = jsonEncode(config.toJson());
    await prefs.setString(_speechConfigKey, jsonString);
  }

  Future<void> clearSpeechConfig() async {
    final prefs = await _getInstance();
    await prefs.remove(_speechConfigKey);
  }

  Future<BackendConfig> getBackendConfig() async {
    final prefs = await _getInstance();
    final String? jsonString = prefs.getString(_backendConfigKey);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> json = jsonDecode(jsonString);
        return BackendConfig.fromJson(json);
      } catch (e) {
        return BackendConfig();
      }
    }
    return _getDefaultBackendConfig();
  }

  BackendConfig _getDefaultBackendConfig() {
    return BackendConfig(
      host: dotenv.env['BACKEND_HOST'] ?? 'localhost',
      port: int.tryParse(dotenv.env['BACKEND_PORT'] ?? '8000') ?? 8000,
      protocol: dotenv.env['BACKEND_PROTOCOL'] ?? 'ws',
    );
  }

  Future<void> saveBackendConfig(BackendConfig config) async {
    final prefs = await _getInstance();
    final String jsonString = jsonEncode(config.toJson());
    await prefs.setString(_backendConfigKey, jsonString);
  }

  Future<void> clearBackendConfig() async {
    final prefs = await _getInstance();
    await prefs.remove(_backendConfigKey);
  }

  Future<ImageTransmissionConfig> getImageTransmissionConfig() async {
    final prefs = await _getInstance();
    final String? jsonString = prefs.getString(_imageTransmissionConfigKey);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> json = jsonDecode(jsonString);
        return ImageTransmissionConfig.fromJson(json);
      } catch (e) {
        // 解析失败，使用默认配置
      }
    }
    return _getDefaultImageTransmissionConfig();
  }

  ImageTransmissionConfig _getDefaultImageTransmissionConfig() {
    return ImageTransmissionConfig(
      speechTriggerEnabled: true,
      fixedIntervalEnabled: false,
      sendInterval: 5,
    );
  }

  Future<void> saveImageTransmissionConfig(ImageTransmissionConfig config) async {
    final prefs = await _getInstance();
    final String jsonString = jsonEncode(config.toJson());
    await prefs.setString(_imageTransmissionConfigKey, jsonString);
  }

  Future<void> clearImageTransmissionConfig() async {
    final prefs = await _getInstance();
    await prefs.remove(_imageTransmissionConfigKey);
  }

  Future<TtsConfig> getTtsConfig() async {
    final prefs = await _getInstance();
    final String? jsonString = prefs.getString(_ttsConfigKey);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> json = jsonDecode(jsonString);
        return TtsConfig.fromJson(json);
      } catch (e) {
        // 解析失败，使用默认配置
      }
    }
    return _getDefaultTtsConfig();
  }

  TtsConfig _getDefaultTtsConfig() {
    return TtsConfig(speechRate: 1.0);
  }

  Future<void> saveTtsConfig(TtsConfig config) async {
    final prefs = await _getInstance();
    final String jsonString = jsonEncode(config.toJson());
    await prefs.setString(_ttsConfigKey, jsonString);
  }

  Future<void> clearTtsConfig() async {
    final prefs = await _getInstance();
    await prefs.remove(_ttsConfigKey);
  }
}

class SpeechConfig {
  String appId;
  String secretId;
  String secretKey;
  String region;

  SpeechConfig({
    this.appId = '',
    this.secretId = '',
    this.secretKey = '',
    this.region = 'ap-beijing',
  });

  factory SpeechConfig.fromJson(Map<String, dynamic> json) {
    return SpeechConfig(
      appId: json['appId'] ?? '',
      secretId: json['secretId'] ?? '',
      secretKey: json['secretKey'] ?? '',
      region: json['region'] ?? 'ap-beijing',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'appId': appId,
      'secretId': secretId,
      'secretKey': secretKey,
      'region': region,
    };
  }

  bool get isValid {
    return appId.isNotEmpty && secretId.isNotEmpty && secretKey.isNotEmpty;
  }
}

class BackendConfig {
  String host;
  int port;
  String protocol;

  BackendConfig({
    this.host = 'localhost',
    this.port = 8000,
    this.protocol = 'ws',
  });

  factory BackendConfig.fromJson(Map<String, dynamic> json) {
    return BackendConfig(
      host: json['host'] ?? 'localhost',
      port: json['port'] ?? 8000,
      protocol: json['protocol'] ?? 'ws',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'protocol': protocol,
    };
  }

  String get url {
    return '$protocol://$host:$port/ws';
  }

  bool get isValid {
    return host.isNotEmpty && port > 0 && port <= 65535;
  }
}

class ImageTransmissionConfig {
  bool speechTriggerEnabled;
  bool fixedIntervalEnabled;
  int sendInterval;

  ImageTransmissionConfig({
    this.speechTriggerEnabled = true,
    this.fixedIntervalEnabled = false,
    this.sendInterval = 5,
  });

  factory ImageTransmissionConfig.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('speechTriggerEnabled') || json.containsKey('fixedIntervalEnabled')) {
      return ImageTransmissionConfig(
        speechTriggerEnabled: json['speechTriggerEnabled'] as bool? ?? true,
        fixedIntervalEnabled: json['fixedIntervalEnabled'] as bool? ?? false,
        sendInterval: (json['sendInterval'] as num?)?.toInt() ?? 5,
      );
    }
    final oldMode = json['mode'] as String?;
    return ImageTransmissionConfig(
      speechTriggerEnabled: oldMode != 'fixedFrameRate',
      fixedIntervalEnabled: oldMode == 'fixedFrameRate',
      sendInterval: (json['sendInterval'] as num?)?.toInt() ?? 5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'speechTriggerEnabled': speechTriggerEnabled,
      'fixedIntervalEnabled': fixedIntervalEnabled,
      'sendInterval': sendInterval,
    };
  }

  String get modeLabel {
    if (speechTriggerEnabled && fixedIntervalEnabled) {
      return '语音触发 + 定时发送';
    }
    if (speechTriggerEnabled) {
      return '语音触发';
    }
    if (fixedIntervalEnabled) {
      return '定时发送';
    }
    return '未启用';
  }
}

class TtsConfig {
  double speechRate;

  TtsConfig({
    this.speechRate = 1.0,
  });

  factory TtsConfig.fromJson(Map<String, dynamic> json) {
    return TtsConfig(
      speechRate: (json['speechRate'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'speechRate': speechRate,
    };
  }
}