import 'dart:convert';
import '../text_processor_service.dart';

class BackendTextProcessorService implements TextProcessorService {

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