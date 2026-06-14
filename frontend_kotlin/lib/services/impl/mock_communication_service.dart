import 'dart:async';
import 'dart:typed_data';
import '../communication_service.dart';

class MockCommunicationService implements CommunicationService {
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _commandController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isConnected = false;

  @override
  Future<bool> connect() async {
    _isConnected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
  }

  @override
  Future<String> sendTextMessage(String message) async {
    final response = '回复：$message';
    _messageController.add(response);
    return response;
  }

  @override
  Future<String> sendSpeechMessage(String message) async {
    final response = '语音回复：$message';
    _messageController.add(response);
    return response;
  }

  @override
  Future<String> sendImage(Uint8List imageData) async {
    final response = '图像分析结果：画面中有一个人正在说话，背景是室内环境';
    _messageController.add(response);
    return response;
  }

  @override
  Future<void> updateConnection(String host, int port) async {
    // 模拟更新连接配置
    _isConnected = false;
    await Future.delayed(const Duration(milliseconds: 100));
    _isConnected = true;
  }

  void simulateCommand(Map<String, dynamic> command) {
    _commandController.add(command);
  }

  @override
  Stream<String> get messageStream => _messageController.stream;

  @override
  Stream<Map<String, dynamic>> get commandStream => _commandController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  void dispose() {
    _messageController.close();
    _commandController.close();
  }
}