import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../services/audio_player_service.dart';
import '../services/audio_service.dart';
import '../services/camera_service.dart';
import '../services/permission_service.dart';
import '../services/websocket_service.dart';
import '../widgets/control_bar.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // Services
  final CameraService _cameraService = CameraService();
  final AudioService _audioService = AudioService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();
  final PermissionService _permissionService = PermissionService();
  WebSocketService? _wsService;

  // State
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final Uuid _uuid = const Uuid();
  bool _isInitialized = false;
  bool _isCameraOn = false;
  bool _isMicOn = false;
  bool _isConversationActive = false;
  String _statusText = '准备就绪';
  String? _sessionId;
  StreamSubscription<Map<String, dynamic>>? _wsTextSub;
  StreamSubscription<Uint8List>? _wsBinarySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsTextSub?.cancel();
    _wsBinarySub?.cancel();
    _wsService?.dispose();
    _cameraService.dispose();
    _audioService.dispose();
    _audioPlayerService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isInitialized) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    setState(() => _statusText = '正在请求权限...');

    final granted = await _permissionService.requestAll();
    if (!granted) {
      setState(() => _statusText = '需要摄像头和麦克风权限');
      return;
    }

    setState(() => _statusText = '正在初始化摄像头...');
    try {
      await _cameraService.initialize();
      setState(() => _isCameraOn = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
      setState(() => _statusText = '摄像头初始化失败');
      return;
    }

    setState(() {
      _isInitialized = true;
      _statusText = '已就绪，点击麦克风按钮开始对话';
    });
  }

  Future<void> _connectWebSocket() async {
    if (_wsService != null) return;

    final sessionId = _uuid.v4();
    _sessionId = sessionId;

    _wsService = WebSocketService(
      baseUrl: 'ws://localhost:8000', // macOS/Web -> localhost
      sessionId: sessionId,
    );

    try {
      await _wsService!.connect();
      setState(() => _statusText = '已连接');

      // Listen for text messages
      _wsTextSub = _wsService!.textStream.listen((msg) {
        _handleWsMessage(msg);
      });

      // Listen for binary (TTS audio)
      _wsBinarySub = _wsService!.binaryStream.listen((data) {
        _audioPlayerService.playBytes(data);
      });
    } catch (e) {
      debugPrint('WebSocket connect error: $e');
      setState(() => _statusText = '连接失败，请检查后端是否启动');
    }
  }

  void _handleWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == 'connected') {
      debugPrint('Session connected: ${msg['session_id']}');
    } else if (type == 'user_message') {
      _addMessage(msg['text'] as String, true);
    } else if (type == 'assistant_message') {
      _addMessage(msg['text'] as String, false);
    } else if (type == 'frame_analyzed') {
      debugPrint('Frame analyzed: ${msg['description']}');
    } else if (type == 'pong') {
      // keep-alive response
    }
  }

  void _addMessage(String text, bool isUser) {
    setState(() {
      _messages.add(ChatMessage(
        id: _uuid.v4(),
        text: text,
        isUser: isUser,
      ));
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleConversation() async {
    if (_isConversationActive) {
      // Stop conversation
      _wsService?.sendControl({'command': 'stop'});
      _cameraService.stopFrameStream();
      await _audioService.stopRecording();
      setState(() {
        _isConversationActive = false;
        _statusText = '对话已暂停';
      });
    } else {
      // Start conversation
      await _connectWebSocket();

      // Start camera streaming
      _cameraService.onFrame = (base64) {
        _wsService?.sendFrame(base64);
      };
      _cameraService.startFrameStream();

      // Start audio recording
      _audioService.onAudioChunk = (base64) {
        _wsService?.sendAudio(base64);
      };
      await _audioService.startRecording();

      setState(() {
        _isConversationActive = true;
        _statusText = '对话进行中...';
      });
    }
  }

  void _toggleCamera() {
    if (_isCameraOn) {
      _cameraService.stopFrameStream();
      setState(() => _isCameraOn = false);
    } else {
      _cameraService.startFrameStream();
      setState(() => _isCameraOn = true);
    }
  }

  void _toggleMic() {
    if (_isMicOn) {
      _audioService.stopRecording();
      setState(() => _isMicOn = false);
    } else {
      _audioService.startRecording();
      setState(() => _isMicOn = true);
    }
  }

  void _switchCamera() {
    _cameraService.switchCamera().then((_) {
      if (_isConversationActive) {
        _cameraService.onFrame = (base64) {
          _wsService?.sendFrame(base64);
        };
        _cameraService.startFrameStream();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Status bar
            _buildStatusBar(),

            // Camera preview — takes most of the screen
            Expanded(
              flex: 5,
              child: _buildCameraPreview(),
            ),

            // Messages area — compact, only expands when there are messages
            Flexible(
              flex: 3,
              child: _buildMessageList(),
            ),

            // Control bar
            if (_isInitialized)
              ControlBar(
                isCameraOn: _isCameraOn,
                isMicOn: _isMicOn,
                isConversationActive: _isConversationActive,
                onToggleCamera: _toggleCamera,
                onToggleMic: _toggleMic,
                onToggleConversation: _toggleConversation,
                onSwitchCamera: _switchCamera,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isInitialized || !_cameraService.isInitialized) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white54),
              SizedBox(height: 12),
              Text('正在初始化摄像头...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }

    // Use AspectRatio so the full camera frame is visible without cropping
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: _cameraService.controller!.value.aspectRatio,
        child: CameraPreview(_cameraService.controller!),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey[900],
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConversationActive
                  ? Colors.green
                  : _isInitialized
                      ? Colors.grey
                      : Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusText,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              _isInitialized ? '点击麦克风按钮开始对话' : '正在初始化...',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return MessageBubble(
          text: msg.text,
          isUser: msg.isUser,
        );
      },
    );
  }
}
