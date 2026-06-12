import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../communication_service.dart';
import '../../utils/logger.dart';

class WebSocketCommunicationService implements CommunicationService {
  final String _host;
  final int _port;
  WebSocketChannel? _channel;
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _commandController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isConnected = false;
  Timer? _reconnectTimer;
  StreamSubscription? _channelSubscription;

  WebSocketCommunicationService({String? host, int? port})
      : _host = host ?? dotenv.env['BACKEND_HOST'] ?? '192.168.1.100',
        _port = port ?? int.tryParse(dotenv.env['BACKEND_PORT'] ?? '8000') ?? 8000;

  @override
  Future<bool> connect() async {
    try {
      final url = Uri.parse('ws://$_host:$_port/ws');
      Logger.d('WebSocket', '正在连接: $url');
      
      _channel = WebSocketChannel.connect(url);
      _isConnected = true;
      Logger.d('WebSocket', '连接成功');
      
      _channelSubscription = _channel!.stream.listen(
        (data) => _handleMessage(data),
        onError: (error) => _handleError(error),
        onDone: () => _handleDisconnect(),
      );
      
      return true;
    } catch (e) {
      Logger.e('WebSocket', '连接失败: $e');
      _scheduleReconnect();
      return false;
    }
  }

  void _handleMessage(dynamic data) {
    try {
      if (data is String) {
        Logger.d('WebSocket', '收到消息: ${data.length} 字符');
        final jsonData = jsonDecode(data);
        
        if (jsonData['type'] == 'message') {
          Logger.d('WebSocket', '消息内容: ${jsonData['content']}');
          _messageController.add(jsonData['content']);
        } else if (jsonData['type'] == 'command') {
          Logger.d('WebSocket', '收到命令: ${jsonData['data']}');
          _commandController.add(jsonData['data']);
        } else if (jsonData['type'] == 'connected') {
          Logger.i('WebSocket', '服务端确认连接: session=${jsonData['session_id']}, mode=${jsonData['mode']}');
        } else if (jsonData['type'] == 'frame_analyzed') {
          Logger.d('WebSocket', '图像分析结果: ${jsonData['description']}');
          _messageController.add(jsonData['description']);
        }
      }
    } catch (e) {
      Logger.w('WebSocket', '消息解析失败: $e');
      _messageController.add(data.toString());
    }
  }

  void _handleError(dynamic error) {
    Logger.e('WebSocket', '连接错误: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _handleDisconnect() {
    Logger.w('WebSocket', '连接断开');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (!_isConnected) {
        Logger.i('WebSocket', '尝试重新连接...');
        await connect();
      }
    });
  }

  @override
  Future<void> disconnect() async {
    Logger.d('WebSocket', '主动断开连接');
    _reconnectTimer?.cancel();
    await _channelSubscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  @override
  Future<String> sendTextMessage(String message) async {
    if (!_isConnected || _channel == null) {
      Logger.e('WebSocket', '发送失败：未连接到服务器');
      throw Exception('Not connected to server');
    }
    
    final request = jsonEncode({
      'type': 'text',
      'content': message,
    });
    
    Logger.d('WebSocket', '发送文本消息: "${message.substring(0, message.length > 50 ? 50 : message.length)}${message.length > 50 ? '...' : ''}"');
    Logger.d('WebSocket', '数据包: ${request.substring(0, request.length > 100 ? 100 : request.length)}${request.length > 100 ? '...' : ''}');
    
    _channel!.sink.add(request);
    
    final completer = Completer<String>();
    StreamSubscription? subscription;
    subscription = _messageController.stream.listen((response) {
      Logger.d('WebSocket', '收到回复: "${response.substring(0, response.length > 50 ? 50 : response.length)}${response.length > 50 ? '...' : ''}"');
      completer.complete(response);
      subscription?.cancel();
    });
    
    return completer.future.timeout(const Duration(seconds: 30));
  }

  @override
  Future<String> sendImage(Uint8List imageData) async {
    if (!_isConnected || _channel == null) {
      Logger.e('WebSocket', '发送失败：未连接到服务器');
      throw Exception('Not connected to server');
    }
    
    final base64Image = base64Encode(imageData);
    final request = jsonEncode({
      'type': 'frame',
      'data': base64Image,
    });
    
    Logger.d('WebSocket', '发送图像: ${imageData.length} 字节 (Base64: ${base64Image.length} 字符)');
    
    _channel!.sink.add(request);
    
    final completer = Completer<String>();
    StreamSubscription? subscription;
    subscription = _messageController.stream.listen((response) {
      Logger.d('WebSocket', '图像分析结果: "${response.substring(0, response.length > 100 ? 100 : response.length)}${response.length > 100 ? '...' : ''}"');
      completer.complete(response);
      subscription?.cancel();
    });
    
    return completer.future.timeout(const Duration(seconds: 30));
  }

  @override
  Stream<String> get messageStream => _messageController.stream;

  @override
  Stream<Map<String, dynamic>> get commandStream => _commandController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  void dispose() {
    Logger.d('WebSocket', '释放资源');
    _reconnectTimer?.cancel();
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _messageController.close();
    _commandController.close();
  }
}