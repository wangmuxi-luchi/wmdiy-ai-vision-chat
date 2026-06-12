import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static const String _speechConfigKey = 'speech_config';
  static const String _backendConfigKey = 'backend_config';
  
  static SharedPreferences? _instance;

  static Future<SharedPreferences> _getInstance() async {
    if (_instance == null) {
      _instance = await SharedPreferences.getInstance();
    }
    return _instance!;
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
        return SpeechConfig.fromJson(json);
      } catch (e) {
        return SpeechConfig();
      }
    }
    return SpeechConfig();
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
    return BackendConfig();
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