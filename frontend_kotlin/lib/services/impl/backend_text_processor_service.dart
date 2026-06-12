import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../text_processor_service.dart';

class BackendTextProcessorService implements TextProcessorService {
  final String _baseUrl;

  BackendTextProcessorService() 
    : _baseUrl = dotenv.env['WS_URL'] ?? 'ws://localhost:8000/ws';

  @override
  Future<String> processText(String text) async {
    try {
      return await _sendToBackend(text);
    } catch (e) {
      throw Exception("发送到后端失败: $e");
    }
  }

  Future<String> _sendToBackend(String text) async {
    final response = {
      'type': 'message',
      'content': text,
      'timestamp': DateTime.now().toIso8601String(),
    };
    return jsonEncode(response);
  }
}