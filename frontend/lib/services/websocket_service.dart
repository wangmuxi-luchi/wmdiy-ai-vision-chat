import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Manages the WebSocket connection to the backend.
class WebSocketService {
  final String baseUrl;
  final String sessionId;
  WebSocketChannel? _channel;
  bool _isConnected = false;

  // Stream controllers for incoming messages
  final StreamController<Map<String, dynamic>> _textController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Uint8List> _binaryController =
      StreamController<Uint8List>.broadcast();

  Stream<Map<String, dynamic>> get textStream => _textController.stream;
  Stream<Uint8List> get binaryStream => _binaryController.stream;
  bool get isConnected => _isConnected;

  WebSocketService({
    required this.baseUrl,
    required this.sessionId,
  });

  /// Connect to the WebSocket server.
  Future<void> connect() async {
    final uri = Uri.parse('$baseUrl/ws?session_id=$sessionId');
    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _isConnected = true;

      // Listen for messages
      _channel!.stream.listen(
        (data) {
          if (data is String) {
            try {
              final msg = jsonDecode(data) as Map<String, dynamic>;
              _textController.add(msg);
            } catch (_) {}
          } else if (data is List<int>) {
            _binaryController.add(Uint8List.fromList(data));
          }
        },
        onDone: () {
          _isConnected = false;
        },
        onError: (error) {
          _isConnected = false;
        },
      );
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  /// Send a video frame (Base64 JPEG) to the backend.
  void sendFrame(String base64Jpeg) {
    _sendJson({'type': 'frame', 'data': base64Jpeg});
  }

  /// Send an audio chunk (Base64 encoded) to the backend.
  void sendAudio(String base64Audio) {
    _sendJson({'type': 'audio', 'data': base64Audio});
  }

  /// Send a control command.
  void sendControl(Map<String, dynamic> command) {
    _sendJson({'type': 'control', 'data': command});
  }

  /// Send a ping to keep the connection alive.
  void sendPing() {
    _sendJson({'type': 'ping'});
  }

  void _sendJson(Map<String, dynamic> msg) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(msg));
    }
  }

  /// Close the connection gracefully.
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _isConnected = false;
  }

  /// Dispose stream controllers.
  void dispose() {
    _textController.close();
    _binaryController.close();
    disconnect();
  }
}
