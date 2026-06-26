import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../communication_service.dart';
import '../../utils/logger.dart';
import 'network_checker.dart';

enum ConnectionState { connecting, connected, disconnected, reconnecting }

class WebSocketCommunicationService implements CommunicationService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  final _messageController = StreamController<String>.broadcast();
  final _commandController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<ConnectionState>.broadcast();

  String _url;
  Duration _currentDelay;
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;
  bool _isClosed = false;
  bool _isChanging = false;
  bool _isChannelOpen = false;

  final Duration _initialReconnectDelay;
  final Duration _maxReconnectDelay;
  final Duration _heartbeatInterval;

  WebSocketCommunicationService({String? host, int? port})
      : _initialReconnectDelay = const Duration(seconds: 1),
        _maxReconnectDelay = const Duration(minutes: 1),
        _heartbeatInterval = const Duration(seconds: 30),
        _currentDelay = const Duration(seconds: 1),
        _url = _buildUrl(host ?? dotenv.env['BACKEND_HOST'] ?? 'localhost', port ?? int.tryParse(dotenv.env['BACKEND_PORT'] ?? '8000') ?? 8000);

  static String _buildUrl(String host, int port) {
    return 'ws://$host:$port/ws';
  }

  Stream<ConnectionState> get stateStream => _stateController.stream;

  String get currentUrl => _url;

  Future<void> changeUrl(String newUrl) async {
    if (_url == newUrl) return;
    if (_isChanging) return;

    _isChanging = true;
    Logger.i('WebSocket', '🔁 切换 WebSocket URL: $_url -> $newUrl');
    _url = newUrl;

    await _disconnect();
    await _cleanupResources();

    _reconnectAttempts = 0;
    _isReconnecting = false;
    _currentDelay = _initialReconnectDelay;
    _isClosed = false;

    await connect();
    _isChanging = false;
  }

  @override
  Future<void> updateConnection(String host, int port) async {
    final newUrl = _buildUrl(host, port);
    await changeUrl(newUrl);
  }

  @override
  Future<bool> connect() async {
    if (_isClosed) {
      Logger.w('WebSocket', 'Manager已关闭，无法连接');
      return false;
    }
    if (_channel != null) {
      Logger.w('WebSocket', '已经处于连接或连接中状态');
      return _isConnected();
    }

    await _cleanupResources();
    _updateState(ConnectionState.connecting);
    _reconnectAttempts = 0;
    _isReconnecting = false;
    _currentDelay = _initialReconnectDelay;

    Logger.d('WebSocket', '正在连接: $_url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
      await _channel!.ready.timeout(const Duration(seconds: 10));
      _isChannelOpen = true;
      _onConnected();
      return true;
    } catch (e) {
      Logger.e('WebSocket', '连接失败: $e');
      _onConnectionError(e);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    Logger.d('WebSocket', '主动断开连接');
    _isClosed = false;
    await _disconnect();
    await _cleanupResources();
    _updateState(ConnectionState.disconnected);
  }

  @override
  Future<String> sendTextMessage(String message) async {
    if (!_isConnected()) {
      Logger.e('WebSocket', '发送失败：未连接到服务器');
      return '发送失败：未连接到服务器';
    }

    final request = jsonEncode({
      'type': 'text',
      'data': message,
    });

    Logger.d('WebSocket', '[WS SEND 📤] 发送文本消息');
    Logger.d('WebSocket', '[WS SEND 📤] 原始数据: $request');

    try {
      _channel!.sink.add(request);
    } catch (e) {
      Logger.e('WebSocket', '发送失败: $e');
      return '发送失败: $e';
    }

    final completer = Completer<String>();
    StreamSubscription? subscription;
    subscription = _messageController.stream.listen((response) {
      Logger.d('WebSocket', '收到回复: "${response.substring(0, response.length > 50 ? 50 : response.length)}${response.length > 50 ? '...' : ''}"');
      completer.complete(response);
      subscription?.cancel();
    });

    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      Logger.e('WebSocket', '消息发送超时: $e');
      subscription.cancel();
      return '发送超时，请稍后重试';
    }
  }

  @override
  Future<String> sendSpeechMessage(String message) async {
    if (!_isConnected()) {
      Logger.e('WebSocket', '发送失败：未连接到服务器');
      return '发送失败：未连接到服务器';
    }

    final request = jsonEncode({
      'type': 'speech',
      'data': message,
    });

    Logger.d('WebSocket', '[WS SEND 📤] 发送语音识别结果');
    Logger.d('WebSocket', '[WS SEND 📤] 原始数据: $request');

    try {
      _channel!.sink.add(request);
    } catch (e) {
      Logger.e('WebSocket', '发送失败: $e');
      return '发送失败: $e';
    }

    final completer = Completer<String>();
    StreamSubscription? subscription;
    subscription = _messageController.stream.listen((response) {
      Logger.d('WebSocket', '收到回复: "${response.substring(0, response.length > 50 ? 50 : response.length)}${response.length > 50 ? '...' : ''}"');
      completer.complete(response);
      subscription?.cancel();
    });

    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      Logger.e('WebSocket', '消息发送超时: $e');
      subscription.cancel();
      return '发送超时，请稍后重试';
    }
  }

  @override
  Future<String> sendImage(Uint8List imageData) async {
    if (!_isConnected()) {
      Logger.e('WebSocket', '发送失败：未连接到服务器');
      return '发送失败：未连接到服务器';
    }

    Logger.d('WebSocket', '开始处理图像: ${imageData.length} 字节');

    final base64Image = base64Encode(imageData);
    Logger.d('WebSocket', 'Base64编码完成: ${base64Image.length} 字符');

    final request = jsonEncode({
      'type': 'frame',
      'data': base64Image,
    });

    Logger.d('WebSocket', '[WS SEND 📤] 发送图像消息');
    Logger.d('WebSocket', '[WS SEND 📤] 图像大小: ${imageData.length} 字节, Base64长度: ${base64Image.length} 字符');
    Logger.d('WebSocket', '[WS SEND 📤] 原始数据(JSON): {"type":"frame","data":"<BASE64 ${base64Image.length} chars>"}');

    try {
      _channel!.sink.add(request);
    } catch (e) {
      Logger.e('WebSocket', '发送失败: $e');
      return '发送失败: $e';
    }

    final completer = Completer<String>();
    StreamSubscription? subscription;
    subscription = _messageController.stream.listen((response) {
      Logger.d('WebSocket', '图像分析结果: "${response.substring(0, response.length > 100 ? 100 : response.length)}${response.length > 100 ? '...' : ''}"');
      completer.complete(response);
      subscription?.cancel();
    });

    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      Logger.e('WebSocket', '图像发送超时: $e');
      subscription.cancel();
      return '图像发送超时，请稍后重试';
    }
  }

  @override
  Stream<String> get messageStream => _messageController.stream;

  @override
  Stream<Map<String, dynamic>> get commandStream => _commandController.stream;

  @override
  bool get isConnected => _isConnected();

  @override
  void dispose() {
    Logger.d('WebSocket', '释放资源');
    _isClosed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isChannelOpen = false;
    _messageController.close();
    _commandController.close();
    _stateController.close();
  }

  bool _isConnected() => _channel != null && _isChannelOpen;

  void _onConnected() {
    _updateState(ConnectionState.connected);
    _reconnectAttempts = 0;
    _isReconnecting = false;
    _currentDelay = _initialReconnectDelay;
    _startHeartbeat();
    _startListening();
    Logger.i('WebSocket', '✅ 连接成功 ($_url)');
  }

  void _startListening() {
    if (_channel == null) return;

    _channel!.stream.listen(
      (data) => _handleMessage(data),
      onError: (error) => _handleError(error),
      onDone: () => _handleDone(),
    );
  }

  void _handleMessage(dynamic data) {
    try {
      if (data is String) {
        if (data == 'pong') {
          return;
        }
        Logger.d('WebSocket', '[WS RECV 📥] 原始数据(${data.length} 字符): ${data.length > 500 ? '${data.substring(0, 500)}...' : data}');
        final jsonData = jsonDecode(data);

        if (jsonData['type'] == 'message') {
          Logger.d('WebSocket', '[WS RECV 📥] 消息内容: ${jsonData['content']}');
          _messageController.add(jsonData['content']);
        } else if (jsonData['type'] == 'assistant_message') {
          Logger.d('WebSocket', '[WS RECV 📥] 助手回复: ${jsonData['text']}');
          _messageController.add(jsonData['text']);
        } else if (jsonData['type'] == 'command') {
          Logger.d('WebSocket', '[WS RECV 📥] 收到命令: ${jsonData['data']}');
          _commandController.add(jsonData['data']);
        } else if (jsonData['type'] == 'connected') {
          Logger.i('WebSocket', '[WS RECV 📥] 服务端确认连接: session=${jsonData['session_id']}, mode=${jsonData['mode']}');
        } else if (jsonData['type'] == 'frame_analyzed') {
          Logger.d('WebSocket', '[WS RECV 📥] 图像分析结果: ${jsonData['description']}');
        } else if (jsonData['type'] == 'user_message') {
          Logger.d('WebSocket', '[WS RECV 📥] 用户消息回显: ${jsonData['text']}');
        } else {
          Logger.w('WebSocket', '[WS RECV 📥] 未知消息类型: type=${jsonData['type']}');
        }
      }
    } catch (e) {
      Logger.w('WebSocket', '[WS RECV 📥] 消息解析失败: $e, 原始数据: ${data is String ? data.substring(0, data.length > 200 ? 200 : data.length) : data}');
      if (data is String) {
        _messageController.add(data);
      }
    }
  }

  void _handleError(dynamic error) {
    Logger.e('WebSocket', '连接错误: $error');
    _channel = null;
    _isChannelOpen = false;
    _isReconnecting = false;
    _onDisconnected();
  }

  void _handleDone() {
    Logger.w('WebSocket', '连接断开');
    _channel = null;
    _isChannelOpen = false;
    _onDisconnected();
  }

  void _onDisconnected() async {
    if (!_isClosed && !_isReconnecting) {
      if (!await hasNetworkConnectivity()) {
        Logger.w('WebSocket', '📡 无网络连接，等待网络恢复...');
        _waitForNetworkAndReconnect();
      } else if (_reconnectAttempts < 10) {
        _scheduleReconnect();
      } else {
        Logger.e('WebSocket', '❌ 已达最大重试次数 (10)，停止重连');
        _updateState(ConnectionState.disconnected);
      }
    }
  }

  void _scheduleReconnect() {
    if (_isClosed || _isReconnecting) return;
    _isReconnecting = true;
    _updateState(ConnectionState.reconnecting);
    _reconnectTimer?.cancel();

    Logger.i('WebSocket', '🔄 将在 ${_currentDelay.inSeconds}秒 后尝试第 ${_reconnectAttempts + 1} 次重连 ($_url)');

    _reconnectTimer = Timer(_currentDelay, () async {
      try {
        await _reconnect();
      } finally {
        _reconnectTimer = null;
      }
    });
  }

  Future<void> _reconnect() async {
    if (_isClosed) return;
    await _cleanupResources();
    _reconnectAttempts++;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
      await _channel!.ready.timeout(const Duration(seconds: 10));
      _isChannelOpen = true;
      _onConnected();
    } catch (e) {
      Logger.e('WebSocket', '❌ 重连失败 ($_reconnectAttempts/10): $e');
      _isReconnecting = false;
      _currentDelay = Duration(
        milliseconds: (_currentDelay.inMilliseconds * 2).clamp(0, _maxReconnectDelay.inMilliseconds),
      );
      _scheduleReconnect();
    }
  }

  void _onConnectionError(dynamic error) {
    Logger.e('WebSocket', '❌ 连接失败: $error');
    _isReconnecting = false;
    _isChannelOpen = false;
    if (error is WebSocketChannelException || error is TimeoutException) {
      _scheduleReconnect();
    } else {
      Logger.w('WebSocket', '⚠️ 未知错误: $error，放弃重连');
      _updateState(ConnectionState.disconnected);
    }
  }

  Future<void> _cleanupResources() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
  }

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (_) {}
      _channel = null;
      _isChannelOpen = false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) async {
      if (!_isConnected()) return;
      try {
        _channel!.sink.add('ping');
      } catch (e) {
        Logger.e('WebSocket', '💓 心跳失败，检测到连接断开: $e');
        timer.cancel();
        _disconnect();
        _onDisconnected();
      }
    });
  }

  void _waitForNetworkAndReconnect() {
    const checkInterval = Duration(seconds: 5);
    Timer.periodic(checkInterval, (timer) async {
      if (await hasNetworkConnectivity() && !_isClosed && _channel == null) {
        timer.cancel();
        Logger.i('WebSocket', '🌐 网络已恢复，尝试重连');
        _scheduleReconnect();
      }
    });
  }

  void _updateState(ConnectionState state) {
    if (_stateController.hasListener) {
      _stateController.add(state);
    }
  }

  void tryReconnect() {
    Logger.i('WebSocket', '🔄 手动触发重连，重置计数器');
    _reconnectAttempts = 0;
    _currentDelay = _initialReconnectDelay;
    _isReconnecting = false;
    _scheduleReconnect();
  }
}