import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:frontend_kotlin/main.dart';
import 'package:frontend_kotlin/services/speech_recognition_service.dart';
import 'package:frontend_kotlin/services/text_processor_service.dart';

class MockSpeechRecognitionService implements SpeechRecognitionService {
  StreamController<String>? _controller;

  @override
  Stream<String> startListening() {
    _controller = StreamController<String>.broadcast();
    Future.microtask(() => _controller?.add('测试语音识别结果'));
    return _controller!.stream;
  }

  @override
  Future<void> stopListening() async {
    await _controller?.close();
    _controller = null;
  }

  @override
  void dispose() {
    _controller?.close();
  }
}

class MockTextProcessorService implements TextProcessorService {
  @override
  Future<String> processText(String text) async {
    return '处理后的文本: $text';
  }
}

void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env');
    
    GetIt.instance.registerLazySingleton<SpeechRecognitionService>(
      () => MockSpeechRecognitionService(),
    );
    GetIt.instance.registerLazySingleton<TextProcessorService>(
      () => MockTextProcessorService(),
    );
  });

  tearDownAll(() {
    GetIt.instance.reset();
  });

  group('语音识别应用测试', () {
    testWidgets('初始界面显示正确', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.text('实时语音识别'), findsOneWidget);
      expect(find.text('点击下方按钮开始录音识别'), findsOneWidget);
      expect(find.text('开始识别'), findsOneWidget);
    });

    testWidgets('点击开始按钮后状态变化', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final startButton = find.text('开始识别');
      expect(startButton, findsOneWidget);

      await tester.tap(startButton);
      await tester.pumpAndSettle();

      expect(find.text('停止识别'), findsOneWidget);
    });

    testWidgets('界面元素布局测试', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('按钮点击后显示停止识别', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final button = find.text('开始识别');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('停止识别'), findsOneWidget);
    });

    testWidgets('多次点击状态切换', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('开始识别'));
      await tester.pumpAndSettle();
      expect(find.text('停止识别'), findsOneWidget);

      await tester.tap(find.text('停止识别'));
      await tester.pumpAndSettle();
      expect(find.text('开始识别'), findsOneWidget);
    });
  });
}