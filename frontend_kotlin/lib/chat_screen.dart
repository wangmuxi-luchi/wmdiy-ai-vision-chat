import 'dart:async';
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'services/locator.dart';
import 'services/config_service.dart';
import 'services/speech_recognition_service.dart';
import 'services/message_receiver_service.dart';
import 'services/impl/message_receiver_service_impl.dart';
import 'services/command_receiver_service.dart';
import 'services/camera_image_service.dart';
import 'services/camera_service.dart';
import 'services/communication_service.dart';
import 'widgets/sidebar.dart';
import 'widgets/camera_preview_widget.dart';
import 'widgets/draggable_camera_preview.dart';
import 'utils/logger.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late SpeechRecognitionService _speechService;
  late MessageReceiverService _messageReceiverService;
  late CommandReceiverService _commandReceiverService;
  late CameraImageService _cameraImageService;
  late CameraService _cameraService;
  late CommunicationService _communicationService;
  late ConfigService _configService;
  StreamSubscription<Command>? _commandSubscription;
  StreamSubscription<String>? _messageSubscription;
  
  bool _isMicOn = false;
  bool _isCameraOn = true;
  bool _isFullscreen = false;
  bool _isCameraInitialized = false;
  bool _isSidebarOpen = false;
  bool _isAutoSendSpeech = false; // 语音转文字自动发送开关
  bool _isStoppingRecording = false; // 是否正在停止录音（用于防止关闭麦克风时接收缓存结果）
  int _cameraPreviewKey = 0;

  String _pendingSpeechText = '';
  String _confirmedSpeechText = ''; // 已确认的文本（一句话结束后累加）
  final List<ChatMessage> _messages = [];
  final List<CameraLog> _cameraLogs = [];
  int _imageCount = 0;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _speechInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initAsync();
  }
  
  Future<void> _initAsync() async {
    try {
      setupLocator();
      _speechService = locator<SpeechRecognitionService>();
      _messageReceiverService = locator<MessageReceiverService>();
      _commandReceiverService = locator<CommandReceiverService>();
      _cameraImageService = locator<CameraImageService>();
      _cameraService = locator<CameraService>();
      _communicationService = locator<CommunicationService>();
      _configService = locator<ConfigService>();
      await _configService.init();
      
      // 加载语音配置并设置到语音服务
      await _loadSpeechConfig();
      
      _subscribeToCommands();
      _subscribeToMessages();
      await _initializeCamera();
      await _connectToServer();
    } catch (e, stackTrace) {
      Logger.e('ChatScreen', '初始化异常: $e\n$stackTrace', e);
      _showErrorSnackBar('初始化失败: ${e.toString()}');
    }
  }
  
  Future<void> _loadSpeechConfig() async {
    try {
      final speechConfig = await _configService.getSpeechConfig();
      if (speechConfig.isValid) {
        _speechService.setCredentials(
          appId: int.parse(speechConfig.appId),
          secretId: speechConfig.secretId,
          secretKey: speechConfig.secretKey,
        );
        Logger.i('ChatScreen', '语音配置已加载: appId=${speechConfig.appId}');
      } else {
        Logger.w('ChatScreen', '语音配置无效，请在侧边栏设置');
      }
    } catch (e) {
      Logger.e('ChatScreen', '加载语音配置失败', e);
    }
  }
  
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  Future<void> _connectToServer() async {
    bool connected = await _communicationService.connect();
    if (connected) {
      Logger.i('ChatScreen', '已连接到后端服务器');
      _startMessageReceiver();
    } else {
      Logger.w('ChatScreen', '连接后端服务器失败');
    }
  }
  
  void _startMessageReceiver() {
    if (_messageReceiverService is MessageReceiverServiceImpl) {
      (_messageReceiverService as MessageReceiverServiceImpl).startListening();
    }
  }
  
  void _subscribeToMessages() {
    _messageSubscription = _communicationService.messageStream.listen((message) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(text: message, isUser: false));
        });
        _scrollToBottom();
      }
    });
  }
  
  Future<void> _initializeCamera() async {
    bool success = await _cameraService.initialize();
    setState(() {
      _isCameraInitialized = success;
    });
    if (success && _isCameraOn) {
      await _cameraService.startPreview();
    }
  }

  void _subscribeToCommands() {
    _commandSubscription = _commandReceiverService.commandStream.listen((command) {
      _handleCommand(command);
    });
  }

  void _handleCommand(Command command) {
    switch (command.type) {
      case 'send_camera_image':
        _handleSendCameraImage(command);
        break;
      default:
        Logger.w('ChatScreen', 'Unknown command type: ${command.type}');
    }
  }

  void _handleSendCameraImage(Command command) {
    _sendCameraImage(CameraTriggerType.command);
  }
  
  void _sendCameraImage(CameraTriggerType triggerType) {
    _imageCount++;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    setState(() {
      _cameraLogs.add(CameraLog(
        timestamp: timestamp,
        imageCount: _imageCount,
        status: '发送中...',
        triggerType: triggerType,
      ));
    });
    
    _cameraService.captureImage().then((imageData) async {
      if (imageData != null) {
        if (_communicationService.isConnected) {
          try {
            await _communicationService.sendImage(imageData);
            setState(() {
              _cameraLogs.last.status = '发送成功';
            });
          } catch (e) {
            setState(() {
              _cameraLogs.last.status = '发送失败: $e';
            });
          }
        } else {
          _cameraImageService.analyzeImage('camera_frame_data').then((analysisResult) {
            Logger.d('ChatScreen', '图像分析结果: $analysisResult');
            setState(() {
              _cameraLogs.last.status = '离线分析完成（未发送）';
            });
          });
        }
      } else {
        setState(() {
          _cameraLogs.last.status = '捕获失败';
        });
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _speechService.dispose();
    _commandReceiverService.dispose();
    if (_messageReceiverService is MessageReceiverServiceImpl) {
      (_messageReceiverService as MessageReceiverServiceImpl).dispose();
    }
    _cameraService.dispose();
    _communicationService.dispose();
    _commandSubscription?.cancel();
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _toggleMic() {
    Logger.d('ChatScreen', '切换麦克风状态: 当前=$_isMicOn');
    setState(() => _isMicOn = !_isMicOn);
    if (_isMicOn) {
      _startRecording();
    } else {
      _stopRecording();
    }
  }

  Future<void> _startRecording() async {
    Logger.d('ChatScreen', '========== 开始录音 ==========');
    try {
      Logger.d('ChatScreen', '调用 speechService.startListening()...');
      Stream<ASRResult> asrStream = _speechService.startListening();
      Logger.d('ChatScreen', 'startListening() 返回成功，开始监听Stream');
      
      asrStream.listen(
        (result) {
          // 如果正在停止录音，忽略收到的数据（可能是SDK缓存的旧数据）
          if (!mounted || _isStoppingRecording) {
            Logger.d('ChatScreen', '收到识别结果但已停止，忽略: text=${result.text}');
            return;
          }
          
          String text = result.text;
          bool isFinal = result.isFinal;
          Logger.d('ChatScreen', '收到识别结果: text="$text", isFinal=$isFinal');
          
          setState(() {
            if (isFinal) {
              // 一句话结束（最终结果）：累加到已确认文本
              _confirmedSpeechText += text;
              _pendingSpeechText = _confirmedSpeechText;
            } else {
              // 识别变化（中间结果）：显示已确认文本 + 当前识别内容
              _pendingSpeechText = _confirmedSpeechText + text;
            }
            _speechInputController.text = _pendingSpeechText;
          });
          Logger.d('ChatScreen', 'UI已更新识别结果: "$_pendingSpeechText"');
          
          // 如果开启自动发送且收到最终结果，立即发送
          if (_isAutoSendSpeech && isFinal && _pendingSpeechText.trim().isNotEmpty) {
            Logger.d('ChatScreen', '自动发送已开启，发送识别结果');
            _sendPendingSpeech();
          }
        },
        onError: (e) {
          Logger.e('ChatScreen', '语音识别错误: $e');
          if (mounted) {
            setState(() {
              _pendingSpeechText = "错误: $e";
              _isMicOn = false;
            });
          }
        },
        onDone: () {
          Logger.d('ChatScreen', '语音识别Stream结束');
          if (mounted && _isMicOn) {
            setState(() {
              _isMicOn = false;
            });
          }
        },
      );
      Logger.d('ChatScreen', 'Stream监听已设置完成');
    } catch (e) {
      Logger.e('ChatScreen', '启动录音异常: $e');
      if (mounted) {
        setState(() {
          _pendingSpeechText = "错误: $e";
          _isMicOn = false;
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    setState(() {
      _isStoppingRecording = true;
    });
    try {
      await _speechService.stopListening();
    } catch (e) {
      Logger.e('ChatScreen', 'Error stopping recording: $e');
    }
    setState(() {
      _isStoppingRecording = false;
    });
  }

  void _toggleCamera() {
    setState(() => _isCameraOn = !_isCameraOn);
    if (_isCameraInitialized) {
      if (_isCameraOn) {
        _cameraService.startPreview();
      } else {
        _cameraService.stopPreview();
      }
    }
  }
  
  Future<void> _switchCamera() async {
    if (_cameraService.isSwitching) {
      return;
    }
    
    setState(() {
      _isCameraInitialized = false;
    });
    
    bool success = await _cameraService.switchCamera();
    
    if (success && mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }
  
  void _toggleFullscreen() {
    Logger.d('ChatScreen', '_toggleFullscreen() - 之前: _isFullscreen=$_isFullscreen, _cameraPreviewKey=$_cameraPreviewKey');
    
    // 输出切换前的 video 状态
    _logVideoElementStatus('切换全屏前');
    
    setState(() {
      _isFullscreen = !_isFullscreen;
      _cameraPreviewKey++;
    });
    
    Logger.d('ChatScreen', '_toggleFullscreen() - 之后: _isFullscreen=$_isFullscreen, _cameraPreviewKey=$_cameraPreviewKey');
    
    // 延迟调用 restartPreview 确保 Widget 重建完成后再重启预览
    // 这是为了解决 Flutter Web 全屏切换时 CameraPreview 失效的问题
    Future.delayed(const Duration(milliseconds: 100), () {
      // 输出切换中的 video 状态
      _logVideoElementStatus('切换全屏中(100ms)');
    });
    
    Future.delayed(const Duration(milliseconds: 300), () {
      Logger.d('ChatScreen', '全屏切换后调用 restartPreview');
      // 输出切换后的 video 状态
      _logVideoElementStatus('切换全屏后(300ms)');
      _cameraService.restartPreview();
    });
    
    Future.delayed(const Duration(milliseconds: 500), () {
      // 输出 restartPreview 后的 video 状态
      _logVideoElementStatus('restartPreview 后(500ms)');
    });
  }
  
  void _logVideoElementStatus(String context) {
    try {
      js.context.callMethod('logVideoElementStatus', [context]);
    } catch (e) {
      Logger.d('ChatScreen', '_logVideoElementStatus 失败: $e');
    }
  }

  void _sendUserMessage(String text) {
    if (text.trim().isEmpty) return;
    
    final userMsg = ChatMessage(text: text.trim(), isUser: true);
    setState(() {
      _messages.add(userMsg);
    });
    _scrollToBottom();
    
    if (_communicationService.isConnected) {
      _communicationService.sendTextMessage(text).then((reply) {
        // 回复通过 messageStream 接收
      }).catchError((error) {
        Logger.e('ChatScreen', '发送消息失败: $error');
      });
    } else {
      _messageReceiverService.receiveMessage(text).then((replyText) {
        if (mounted) {
          final replyMsg = ChatMessage(
            text: replyText,
            isUser: false,
          );
          setState(() => _messages.add(replyMsg));
          _scrollToBottom();
        }
      });
    }
  }

  void _sendPendingSpeech() {
    if (_pendingSpeechText.trim().isEmpty) return;
    _sendUserMessage(_pendingSpeechText);
    setState(() {
      _pendingSpeechText = '';
      _confirmedSpeechText = ''; // 清空已确认文本
      _speechInputController.clear();
    });
  }

  void _scrollToBottom() {
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

  void _toggleSidebar() {
    setState(() => _isSidebarOpen = !_isSidebarOpen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullscreen ? null : AppBar(
        title: const Text('语音视频聊天助手'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _toggleSidebar,
        ),
        actions: [
          IconButton(
            icon: Icon(_isMicOn ? Icons.mic : Icons.mic_off),
            color: _isMicOn ? Colors.red : null,
            onPressed: _toggleMic,
          ),
          IconButton(
            icon: Icon(_isCameraOn ? Icons.videocam : Icons.videocam_off),
            onPressed: _toggleCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          _isFullscreen ? _buildCameraPreview(isFullscreen: true) : _buildNormalLayout(),
          if (_isSidebarOpen)
            Stack(
              children: [
                GestureDetector(
                  onTap: _toggleSidebar,
                  child: Container(
                    color: Colors.black38,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Sidebar(
                  isOpen: _isSidebarOpen,
                  onToggle: _toggleSidebar,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNormalLayout() {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: _buildMessageList()),
            _buildPendingSpeechArea(),
            _buildInputBar(),
          ],
        ),
        // 浮动的可拖动摄像头预览窗口
        if (_isCameraInitialized && _isCameraOn)
          DraggableCameraPreview(
            child: _buildCameraPreview(isFullscreen: false),
            onTap: _toggleFullscreen,
          ),
      ],
    );
  }

  Widget _buildCameraPreview({required bool isFullscreen}) {
    Logger.d('ChatScreen', '_buildCameraPreview() - isFullscreen=$isFullscreen, _isCameraInitialized=$_isCameraInitialized, _isCameraOn=$_isCameraOn, _cameraPreviewKey=$_cameraPreviewKey');
    
    return RepaintBoundary(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            if (_isCameraInitialized && _isCameraOn)
              Center(
                child: CameraPreviewWidget(key: ValueKey(_cameraPreviewKey)),
              )
            else
              Center(
                child: _isCameraOn
                    ? const Icon(Icons.videocam, size: 48, color: Colors.white70)
                    : const Icon(Icons.videocam_off, size: 48, color: Colors.white70),
              ),
            // 全屏模式下的控制按钮
            if (isFullscreen)
              Positioned(
                top: 40,
                left: 16,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(_isMicOn ? Icons.mic : Icons.mic_off, color: _isMicOn ? Colors.red : Colors.white, size: 32),
                      onPressed: _toggleMic,
                    ),
                    IconButton(
                      icon: Icon(_isCameraOn ? Icons.videocam : Icons.videocam_off, color: Colors.white, size: 32),
                      onPressed: _toggleCamera,
                    ),
                    if (_cameraService.hasMultipleCameras)
                      IconButton(
                        icon: const Icon(Icons.flip_camera_android, color: Colors.white, size: 32),
                        onPressed: _switchCamera,
                      ),
                  ],
                ),
              ),
            if (isFullscreen)
              Positioned(
                top: 40,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 32),
                  onPressed: _toggleFullscreen,
                ),
              ),
            if (isFullscreen)
              Positioned(
                bottom: 20,
                left: 20,
                child: _buildCameraLogList(),
              ),
            if (isFullscreen)
              Positioned(
                bottom: 20,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.camera, color: Colors.white, size: 48),
                  onPressed: () => _sendCameraImage(CameraTriggerType.manual),
                  tooltip: '手动发送图像',
                ),
              ),
            // 非全屏浮动窗口模式下的简单控制按钮
            if (!isFullscreen)
              Positioned(
                top: 4,
                right: 4,
                child: Row(
                  children: [
                    if (_cameraService.hasMultipleCameras)
                      IconButton(
                        icon: const Icon(Icons.flip_camera_android, color: Colors.white, size: 18),
                        onPressed: _switchCamera,
                        tooltip: '切换摄像头',
                      ),
                    IconButton(
                      icon: const Icon(Icons.maximize, color: Colors.white, size: 18),
                      onPressed: _toggleFullscreen,
                      tooltip: '全屏',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraLogList() {
    return Container(
      width: 200,
      height: 120,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        reverse: true,
        itemCount: _cameraLogs.length,
        itemBuilder: (context, index) {
          final log = _cameraLogs[_cameraLogs.length - 1 - index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: Text(
              log.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return Align(
          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: msg.isUser ? Colors.blue[100] : Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(msg.text),
          ),
        );
      },
    );
  }

  Widget _buildPendingSpeechArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isAutoSendSpeech ? Icons.check_circle : Icons.circle_outlined,
              color: _isAutoSendSpeech ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _isAutoSendSpeech = !_isAutoSendSpeech;
              });
            },
            tooltip: _isAutoSendSpeech ? '关闭自动发送' : '开启自动发送',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _speechInputController,
              decoration: const InputDecoration(
                hintText: '语音识别结果（未发送）...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 16),
              maxLines: null,
              onChanged: (text) {
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _pendingSpeechText = text;
                    });
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: _sendPendingSpeech,
            tooltip: '发送此文本',
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 4)],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              decoration: const InputDecoration(
                hintText: '手动输入文字...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) {
                  _sendUserMessage(text);
                  _inputController.clear();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              if (_inputController.text.trim().isNotEmpty) {
                _sendUserMessage(_inputController.text);
                _inputController.clear();
              }
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isImage;
  final bool isImageReply;
  
  ChatMessage({
    required this.text,
    required this.isUser,
    this.isImage = false,
    this.isImageReply = false,
  });
}

enum CameraTriggerType {
  manual,
  command,
}

class CameraLog {
  final int timestamp;
  final int imageCount;
  String status;
  final CameraTriggerType triggerType;
  
  CameraLog({
    required this.timestamp,
    required this.imageCount,
    required this.status,
    required this.triggerType,
  });
  
  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final hours = date.hour.toString().padLeft(2, '0');
    final minutes = date.minute.toString().padLeft(2, '0');
    final seconds = date.second.toString().padLeft(2, '0');
    final milliseconds = (timestamp % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds.$milliseconds';
  }
  
  String _getTriggerTypeText() {
    switch (triggerType) {
      case CameraTriggerType.manual:
        return '手动触发';
      case CameraTriggerType.command:
        return '命令触发';
    }
  }
  
  @override
  String toString() {
    return '[${_formatTimestamp(timestamp)}] 第$imageCount张图片 - ${_getTriggerTypeText()} - $status';
  }
}