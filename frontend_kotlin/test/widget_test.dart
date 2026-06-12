import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:camera/camera.dart';
import 'package:frontend_kotlin/main.dart';
import 'package:frontend_kotlin/services/speech_recognition_service.dart';
import 'package:frontend_kotlin/services/text_processor_service.dart';
import 'package:frontend_kotlin/services/message_receiver_service.dart';
import 'package:frontend_kotlin/services/command_receiver_service.dart';
import 'package:frontend_kotlin/services/camera_image_service.dart';
import 'package:frontend_kotlin/services/camera_service.dart';

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

class MockMessageReceiverService implements MessageReceiverService {
  @override
  Future<String> receiveMessage(String input) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return '回复：$input';
  }
}

class MockCommandReceiverService implements CommandReceiverService {
  final StreamController<Command> _commandController = StreamController.broadcast();
  Timer? _autoSendTimer;
  bool _autoSendEnabled = false;
  
  MockCommandReceiverService({bool autoSend = false}) {
    _autoSendEnabled = autoSend;
    if (_autoSendEnabled) {
      _startAutoSendingCommands();
    }
  }
  
  void _startAutoSendingCommands() {
    _autoSendTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _commandController.add(Command(
        type: 'send_camera_image',
        data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
      ));
    });
  }
  
  @override
  Stream<Command> get commandStream => _commandController.stream;
  
  @override
  void sendCameraImage() {
    _commandController.add(Command(
      type: 'send_camera_image',
      data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
    ));
  }
  
  void sendCommand(Command command) {
    _commandController.add(command);
  }
  
  @override
  void dispose() {
    _autoSendTimer?.cancel();
    _commandController.close();
  }
}

class MockCameraImageService implements CameraImageService {
  @override
  Future<String> analyzeImage(String imageData) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return '图像分析结果：画面中有一个人正在说话，背景是室内环境';
  }
}

class TestCommandReceiverService implements CommandReceiverService {
  final StreamController<Command> _commandController = StreamController.broadcast();
  
  @override
  Stream<Command> get commandStream => _commandController.stream;
  
  @override
  void sendCameraImage() {}
  
  void sendCommand(Command command) {}
  
  @override
  void dispose() {
    _commandController.close();
  }
}

class MockCameraServiceImpl implements CameraService {
  bool _isInitialized = false;
  bool _isPreviewing = false;
  bool _isSwitching = false;
  CameraLensDirection _currentDirection = CameraLensDirection.back;
  final ValueNotifier<CameraController?> _controllerNotifier = ValueNotifier<CameraController?>(null);
  
  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isPreviewing => _isPreviewing;
  
  @override
  bool get hasMultipleCameras => true;
  
  @override
  bool get isSwitching => _isSwitching;
  
  @override
  CameraController? get controller => null;
  
  @override
  CameraLensDirection? get currentDirection => _currentDirection;
  
  @override
  ValueNotifier<CameraController?> get controllerNotifier => _controllerNotifier;
  
  @override
  Future<bool> initialize([CameraLensDirection direction = CameraLensDirection.back]) async {
    _isInitialized = true;
    _currentDirection = direction;
    _controllerNotifier.value = null;
    return true;
  }
  
  @override
  Future<bool> switchCamera() async {
    if (!isInitialized || _isSwitching) {
      return false;
    }
    _isSwitching = true;
    try {
      _currentDirection = 
          _currentDirection == CameraLensDirection.back 
              ? CameraLensDirection.front 
              : CameraLensDirection.back;
      return true;
    } finally {
      _isSwitching = false;
    }
  }
  
  @override
  Future<void> startPreview() async {
    _isPreviewing = true;
  }
  
  @override
  Future<void> stopPreview() async {
    _isPreviewing = false;
  }
  
  @override
  Future<Uint8List?> captureImage() async {
    return Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
  }
  
  @override
  void dispose() {
    _isInitialized = false;
    _isPreviewing = false;
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
    GetIt.instance.registerLazySingleton<MessageReceiverService>(
      () => MockMessageReceiverService(),
    );
    GetIt.instance.registerLazySingleton<CommandReceiverService>(
      () => MockCommandReceiverService(),
    );
    GetIt.instance.registerLazySingleton<CameraImageService>(
      () => MockCameraImageService(),
    );
    GetIt.instance.registerLazySingleton<CameraService>(
      () => MockCameraServiceImpl(),
    );
  });

  tearDownAll(() {
    GetIt.instance.reset();
  });

  group('视频聊天助手测试', () {
    testWidgets('初始界面显示正确', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.text('语音视频聊天助手'), findsOneWidget);
      expect(find.text('语音识别结果（未发送）...'), findsOneWidget);
      expect(find.text('手动输入文字...'), findsOneWidget);
    });

    testWidgets('AppBar中麦克风和摄像头开关按钮存在', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final appBarMicIcons = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.mic_off),
      );
      expect(appBarMicIcons, findsOneWidget);

      final camIcons = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.videocam),
      );
      expect(camIcons, findsOneWidget);
    });

    testWidgets('界面元素布局测试', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('发送'), findsOneWidget);
    });

    testWidgets('麦克风开关功能', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final micOffIcon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.mic_off),
      );
      expect(micOffIcon, findsOneWidget);

      await tester.tap(micOffIcon);
      await tester.pumpAndSettle();

      final micOnIcon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.mic),
      );
      expect(micOnIcon, findsOneWidget);
    });

    testWidgets('摄像头开关功能', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final camOnIcon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.videocam),
      );
      expect(camOnIcon, findsOneWidget);

      await tester.tap(camOnIcon);
      await tester.pump();

      final camOffIcon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.videocam_off),
      );
      expect(camOffIcon, findsOneWidget);
    });

    testWidgets('发送文本消息', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final textField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == '手动输入文字...',
      );
      expect(textField, findsOneWidget);

      await tester.enterText(textField, '测试消息');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.text('测试消息'), findsOneWidget);
      expect(find.textContaining('回复：'), findsOneWidget);
    });

    testWidgets('发送未发送区域的识别结果', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('你好，我想问一下天气怎么样？'), findsOneWidget);

      final sendIcons = find.byIcon(Icons.send);
      expect(sendIcons, findsNWidgets(1));
      await tester.tap(sendIcons.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.text('你好，我想问一下天气怎么样？'), findsOneWidget);
      expect(find.textContaining('回复：'), findsOneWidget);
    });

    testWidgets('输入框为空时不发送', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('回复：'), findsNothing);

      await tester.tap(find.text('发送'));
      await tester.pump();

      expect(find.textContaining('回复：'), findsNothing);
    });

    testWidgets('命令接收 - 测试阶段摄像头命令不显示消息', (WidgetTester tester) async {
      final mockCommandService = TestCommandReceiverService();
      GetIt.instance.unregister<CommandReceiverService>();
      GetIt.instance.registerSingleton<CommandReceiverService>(mockCommandService);
      
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('摄像头图像已发送'), findsNothing);

      mockCommandService.sendCommand(Command(
        type: 'send_camera_image',
        data: {'timestamp': 1234567890},
      ));
      
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.textContaining('摄像头图像已发送'), findsNothing);
      expect(find.textContaining('图像分析结果'), findsNothing);
    });
  });
}