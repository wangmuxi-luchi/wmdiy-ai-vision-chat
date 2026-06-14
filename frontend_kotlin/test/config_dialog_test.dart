import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_kotlin/widgets/speech_config_dialog.dart';
import 'package:frontend_kotlin/widgets/backend_config_dialog.dart';
import 'package:frontend_kotlin/services/config_service.dart';
import 'package:frontend_kotlin/services/speech_recognition_service.dart';
import 'package:frontend_kotlin/services/communication_service.dart';

class MockSpeechRecognitionService implements SpeechRecognitionService {
  @override
  Stream<ASRResult> startListening() => Stream.empty();

  @override
  Future<void> stopListening() async {}

  @override
  void dispose() {}

  @override
  void setCredentials({
    required String secretId,
    required String secretKey,
    required int appId,
  }) {}
}

class MockCommunicationService implements CommunicationService {
  @override
  Future<bool> connect() async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<String> sendTextMessage(String message) async => '';

  @override
  Future<String> sendImage(List<int> imageData) async => '';

  @override
  Future<void> updateConnection(String host, int port) async {}

  @override
  Stream<String> get messageStream => Stream.empty();

  @override
  Stream<Map<String, dynamic>> get commandStream => Stream.empty();

  @override
  bool get isConnected => false;

  @override
  void dispose() {}
}

void main() {
  group('配置对话框测试', () {
    late ConfigService configService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      configService = ConfigService();
      await configService.init();
      
      GetIt.instance.reset();
      GetIt.instance.registerLazySingleton<ConfigService>(() => configService);
      GetIt.instance.registerLazySingleton<SpeechRecognitionService>(
        () => MockSpeechRecognitionService(),
      );
      GetIt.instance.registerLazySingleton<CommunicationService>(
        () => MockCommunicationService(),
      );
    });

    tearDown(() {
      GetIt.instance.reset();
    });

    testWidgets('语音配置对话框显示加载状态', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => showDialog(
              context: tester.element(find.byType(ElevatedButton)),
              builder: (_) => const SpeechConfigDialog(),
            ),
            child: const Text('Open Dialog'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('语音配置对话框加载完成', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => showDialog(
              context: tester.element(find.byType(ElevatedButton)),
              builder: (_) => const SpeechConfigDialog(),
            ),
            child: const Text('Open Dialog'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('语音转文字配置'), findsOneWidget);
    });

    testWidgets('后端配置对话框显示加载状态', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => showDialog(
              context: tester.element(find.byType(ElevatedButton)),
              builder: (_) => const BackendConfigDialog(),
            ),
            child: const Text('Open Dialog'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('后端配置对话框加载完成', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => showDialog(
              context: tester.element(find.byType(ElevatedButton)),
              builder: (_) => const BackendConfigDialog(),
            ),
            child: const Text('Open Dialog'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('后端服务配置'), findsOneWidget);
    });
  });
}