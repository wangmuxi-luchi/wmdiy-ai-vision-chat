import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_kotlin/widgets/sidebar.dart';
import 'package:frontend_kotlin/services/config_service.dart';

void main() {
  group('Sidebar 测试', () {
    late ConfigService configService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      configService = ConfigService();
      await configService.init();
      
      GetIt.instance.reset();
      GetIt.instance.registerLazySingleton<ConfigService>(() => configService);
    });

    tearDown(() {
      GetIt.instance.reset();
    });

    testWidgets('侧边栏默认折叠状态', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Sidebar(isOpen: false, onToggle: () {}),
        ),
      ));
      await tester.pumpAndSettle();

      final sidebar = find.byType(Sidebar);
      expect(sidebar, findsOneWidget);
    });

    testWidgets('侧边栏展开状态显示按钮列表', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Sidebar(isOpen: true, onToggle: () {}),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('语音转文字配置'), findsOneWidget);
      expect(find.text('后端服务配置'), findsOneWidget);
      expect(find.text('系统设置'), findsOneWidget);
      expect(find.text('帮助'), findsOneWidget);
    });

    testWidgets('侧边栏按钮图标存在', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Sidebar(isOpen: true, onToggle: () {}),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.cloud), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.help), findsOneWidget);
    });

    testWidgets('未配置时显示红点提示', (WidgetTester tester) async {
      await configService.clearSpeechConfig();
      await configService.clearBackendConfig();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Sidebar(isOpen: true, onToggle: () {}),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('语音转文字配置'), findsOneWidget);
      expect(find.text('后端服务配置'), findsOneWidget);
    });

    testWidgets('侧边栏折叠状态切换', (WidgetTester tester) async {
      bool isOpen = false;
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Sidebar(
            isOpen: isOpen, 
            onToggle: () => isOpen = !isOpen,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final toggleButton = find.byIcon(Icons.arrow_right);
      expect(toggleButton, findsOneWidget);
    });
  });
}