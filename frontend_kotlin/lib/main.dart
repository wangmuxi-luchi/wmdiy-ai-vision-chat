import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'chat_screen.dart';
import 'utils/logger.dart';

void main() async {
  // 先确保绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 然后加载环境变量
  await dotenv.load();
  
  // 在同一个 zone 中运行应用
  runZonedGuarded<Future<void>>(
    () async {
      runApp(const MyApp());
    },
    (error, stackTrace) {
      Logger.e('Main', '全局未处理异常: $error', error);
      Logger.e('Main', '堆栈跟踪: $stackTrace', error);
    },
  );
}

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Chat Assistant',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ChatScreen(),
      navigatorKey: _navigatorKey,
      builder: (context, child) {
        return ErrorHandler(navigatorKey: _navigatorKey, child: child!);
      },
    );
  }
}

class ErrorHandler extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const ErrorHandler({super.key, required this.child, required this.navigatorKey});

  @override
  State<ErrorHandler> createState() => _ErrorHandlerState();
}

class _ErrorHandlerState extends State<ErrorHandler> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    FlutterError.onError = _handleFlutterError;
    PlatformDispatcher.instance.onError = _handlePlatformError;
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    setState(() {
      _error = details.exception;
    });
    Logger.e('ErrorHandler', 'Flutter错误: ${details.exception}', details.exception);
    _showErrorDialog(details.exception.toString());
  }

  bool _handlePlatformError(Object error, StackTrace stackTrace) {
    setState(() {
      _error = error;
    });
    Logger.e('ErrorHandler', '平台错误: $error', error);
    _showErrorDialog(error.toString());
    return true;
  }

  void _showErrorDialog(String message) {
    final context = widget.navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发生错误'),
          content: SingleChildScrollView(
            child: Text(message),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _error = null;
                });
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                '应用遇到问题',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }
}