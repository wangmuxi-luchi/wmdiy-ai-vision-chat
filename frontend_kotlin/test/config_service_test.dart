import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_kotlin/services/config_service.dart';

void main() {
  group('ConfigService 测试', () {
    late ConfigService configService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      configService = ConfigService();
      await configService.init();
    });

    test('SpeechConfig 默认值测试', () async {
      final config = await configService.getSpeechConfig();
      
      expect(config.appId, '');
      expect(config.secretId, '');
      expect(config.secretKey, '');
      expect(config.region, 'ap-beijing');
      expect(config.isValid, false);
    });

    test('SpeechConfig 保存和读取测试', () async {
      final testConfig = SpeechConfig(
        appId: '1234567890',
        secretId: 'test_secret_id',
        secretKey: 'test_secret_key',
        region: 'ap-shanghai',
      );

      await configService.saveSpeechConfig(testConfig);
      final loadedConfig = await configService.getSpeechConfig();

      expect(loadedConfig.appId, '1234567890');
      expect(loadedConfig.secretId, 'test_secret_id');
      expect(loadedConfig.secretKey, 'test_secret_key');
      expect(loadedConfig.region, 'ap-shanghai');
      expect(loadedConfig.isValid, true);
    });

    test('SpeechConfig 验证测试', () {
      final emptyConfig = SpeechConfig();
      expect(emptyConfig.isValid, false);

      final partialConfig = SpeechConfig(appId: '123');
      expect(partialConfig.isValid, false);

      final validConfig = SpeechConfig(
        appId: '1234567890',
        secretId: 'secret_id',
        secretKey: 'secret_key',
      );
      expect(validConfig.isValid, true);
    });

    test('SpeechConfig 清空测试', () async {
      final testConfig = SpeechConfig(
        appId: '1234567890',
        secretId: 'test_secret_id',
        secretKey: 'test_secret_key',
      );

      await configService.saveSpeechConfig(testConfig);
      await configService.clearSpeechConfig();
      final config = await configService.getSpeechConfig();

      expect(config.appId, '');
      expect(config.secretId, '');
      expect(config.secretKey, '');
    });

    test('BackendConfig 默认值测试', () async {
      final config = await configService.getBackendConfig();
      
      expect(config.host, 'localhost');
      expect(config.port, 8000);
      expect(config.protocol, 'ws');
      expect(config.url, 'ws://localhost:8000/ws');
      expect(config.isValid, true);
    });

    test('BackendConfig 保存和读取测试', () async {
      final testConfig = BackendConfig(
        host: '192.168.1.100',
        port: 9000,
        protocol: 'wss',
      );

      await configService.saveBackendConfig(testConfig);
      final loadedConfig = await configService.getBackendConfig();

      expect(loadedConfig.host, '192.168.1.100');
      expect(loadedConfig.port, 9000);
      expect(loadedConfig.protocol, 'wss');
      expect(loadedConfig.url, 'wss://192.168.1.100:9000/ws');
    });

    test('BackendConfig URL生成测试', () {
      final config1 = BackendConfig(host: 'localhost', port: 8000, protocol: 'ws');
      expect(config1.url, 'ws://localhost:8000/ws');

      final config2 = BackendConfig(host: '192.168.1.1', port: 8080, protocol: 'wss');
      expect(config2.url, 'wss://192.168.1.1:8080/ws');
    });

    test('BackendConfig 验证测试', () {
      final defaultConfig = BackendConfig();
      expect(defaultConfig.isValid, true);

      final invalidPortConfig = BackendConfig(host: 'localhost', port: 70000);
      expect(invalidPortConfig.isValid, false);

      final emptyHostConfig = BackendConfig(host: '');
      expect(emptyHostConfig.isValid, false);
    });

    test('BackendConfig 清空测试', () async {
      final testConfig = BackendConfig(
        host: '192.168.1.100',
        port: 9000,
      );

      await configService.saveBackendConfig(testConfig);
      await configService.clearBackendConfig();
      final config = await configService.getBackendConfig();

      expect(config.host, 'localhost');
      expect(config.port, 8000);
    });
  });
}