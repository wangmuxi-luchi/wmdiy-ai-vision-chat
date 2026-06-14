import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'services/locator.dart';
import 'services/config_service.dart';
import 'services/speech_recognition_service.dart';
import 'services/message_receiver_service.dart';
import 'services/impl/message_receiver_service_impl.dart';
import 'services/command_receiver_service.dart';
import 'services/camera_image_service.dart';
import 'services/communication_service.dart';
import 'widgets/sidebar.dart';
import 'widgets/draggable_camera_preview.dart';
import 'utils/logger.dart';
import 'package:provider/provider.dart';
import 'camera_manager.dart';
import 'services/tts/tts_service.dart';

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
  late CommunicationService _communicationService;
  late ConfigService _configService;
  StreamSubscription<Command>? _commandSubscription;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<ASRResult>? _asrSubscription;
  
  bool _isMicOn = false;
  bool _isSidebarOpen = false;
  bool _isAutoSendSpeech = false;
  bool _isAutoSendImage = false;
  bool _isTtsEnabled = false;
  bool _isStoppingRecording = false;
  bool _isTtsSpeaking = false;
  int _recordingId = 0;

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
      _communicationService = locator<CommunicationService>();
      _configService = locator<ConfigService>();
      await _configService.init();
      
      // 加载语音配置并设置到语音服务
      await _loadSpeechConfig();
      
      _subscribeToCommands();
      _subscribeToMessages();
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
    _messageSubscription = _communicationService.messageStream.listen((message) async {
      Logger.d('ChatScreen', '[TTS 检查] 收到消息: "${message.length > 50 ? '${message.substring(0, 50)}...' : message}"');
      Logger.d('ChatScreen', '[TTS 检查] _isTtsEnabled = $_isTtsEnabled');
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(text: message, isUser: false));
        });
        _scrollToBottom();

        if (_isTtsEnabled) {
          try {
            final tts = context.read<TtsService>();

            final bool wasMicOn = _isMicOn;
            if (wasMicOn) {
              Logger.d('ChatScreen', '[TTS] TTS朗读前自动关闭麦克风');
              _toggleMic(turnOn: false);
            }

            _isTtsSpeaking = true;
            Logger.d('ChatScreen', '[TTS] 开始朗读...');
            await tts.speak(message);
            _isTtsSpeaking = false;

            if (wasMicOn && _isTtsEnabled && mounted) {
              Logger.d('ChatScreen', '[TTS] 朗读完成，自动恢复麦克风');
              _toggleMic(turnOn: true);
            }
          } catch (e) {
            _isTtsSpeaking = false;
            Logger.e('ChatScreen', 'TTS 播放失败: $e', e);
          }
        } else {
          Logger.d('ChatScreen', '[TTS] 未开启朗读，跳过');
        }
      }
    });
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
    
    final manager = context.read<CameraManager>();
    if (manager.controller == null) {
      setState(() {
        _cameraLogs.last.status = '捕获失败: 摄像头未初始化';
      });
      return;
    }
    
    manager.controller!.takePicture().then((XFile file) async {
      final imageData = await file.readAsBytes();
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
    }).catchError((e) {
      setState(() {
        _cameraLogs.last.status = '捕获失败: $e';
      });
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _speechInputController.dispose();
    _scrollController.dispose();
    _speechService.dispose();
    _commandReceiverService.dispose();
    if (_messageReceiverService is MessageReceiverServiceImpl) {
      (_messageReceiverService as MessageReceiverServiceImpl).dispose();
    }
    _communicationService.dispose();
    _commandSubscription?.cancel();
    _messageSubscription?.cancel();
    _asrSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleMic({bool? turnOn, bool skipRecording = false}) async {
    final targetState = turnOn ?? !_isMicOn;
    if (targetState && _isTtsSpeaking) {
      Logger.d('ChatScreen', '[TTS] 朗读中，禁止打开麦克风');
      return;
    }
    if (_isMicOn == targetState) {
      Logger.d('ChatScreen', '麦克风状态已是 ${targetState ? "开启" : "关闭"}，无需切换');
      return;
    }
    Logger.d('ChatScreen', '切换麦克风状态: $_isMicOn → $targetState${skipRecording ? ' (仅更新状态)' : ''}');
    setState(() => _isMicOn = targetState);
    if (skipRecording) return;
    if (_isMicOn) {
      _startRecording();
    } else {
      await _stopRecording();
    }
  }

  Future<void> _startRecording() async {
    Logger.d('ChatScreen', '========== 开始录音 ==========');
    try {
      final recordingId = ++_recordingId;
      Logger.d('ChatScreen', '调用 speechService.startListening()... (recordingId=$recordingId)');
      Stream<ASRResult> asrStream = _speechService.startListening();
      Logger.d('ChatScreen', 'startListening() 返回成功，开始监听Stream');
      
      await _asrSubscription?.cancel();
      _asrSubscription = asrStream.listen(
        (result) {
          if (!mounted || _isStoppingRecording) {
            Logger.d('ChatScreen', '收到识别结果但已停止，忽略: text=${result.text}');
            return;
          }
          
          String text = result.text;
          bool isFinal = result.isFinal;
          Logger.d('ChatScreen', '收到识别结果: text="$text", isFinal=$isFinal');
          
          setState(() {
            if (isFinal) {
              _confirmedSpeechText += text;
              _pendingSpeechText = _confirmedSpeechText;
            } else {
              _pendingSpeechText = _confirmedSpeechText + text;
            }
            _speechInputController.text = _pendingSpeechText;
          });
          Logger.d('ChatScreen', 'UI已更新识别结果: "$_pendingSpeechText"');
          
          // 自动发送图像：句子开始时（第一个SLICE）发一帧，句子结束时（SEGMENT）重置标记
          final cameraManager = context.read<CameraManager>();
          if (_isAutoSendImage && !isFinal && !cameraManager.imageSentForCurrentSentence) {
            Logger.d('ChatScreen', '[自动发送图像] 新句子第一帧SLICE，捕获图像');
            cameraManager.markImageSent();
            _captureAndSendFrame();
          } else if (isFinal) {
            cameraManager.resetImageSentFlag();
          }
          
          if (_isAutoSendSpeech && isFinal && _pendingSpeechText.trim().isNotEmpty) {
            Logger.d('ChatScreen', '自动发送已开启，发送识别结果');
            _sendPendingSpeech();
          }
        },
        onError: (e) {
          Logger.e('ChatScreen', '语音识别错误: $e');
          if (mounted && _recordingId == recordingId) {
            _speechService.stopListening();
            _toggleMic(turnOn: false, skipRecording: true);
            setState(() {
              _pendingSpeechText = "错误: $e";
            });
          }
        },
        onDone: () {
          Logger.d('ChatScreen', '语音识别Stream结束 (recordingId=$recordingId, current=$_recordingId)');
          if (mounted && _recordingId == recordingId) {
            _speechService.stopListening();
            _toggleMic(turnOn: false, skipRecording: true);
          }
        },
      );
      Logger.d('ChatScreen', 'Stream监听已设置完成');
    } catch (e) {
      Logger.e('ChatScreen', '启动录音异常: $e');
      if (mounted) {
        _toggleMic(turnOn: false, skipRecording: true);
        setState(() {
          _pendingSpeechText = "错误: $e";
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
      await _asrSubscription?.cancel();
      _asrSubscription = null;
    } catch (e) {
      Logger.e('ChatScreen', 'Error stopping recording: $e');
    }
    setState(() {
      _isStoppingRecording = false;
    });
  }

  void _toggleCamera() {
    final manager = context.read<CameraManager>();
    manager.toggleCameraOn();
  }

  void _toggleTts() {
    setState(() {
      _isTtsEnabled = !_isTtsEnabled;
    });
    Logger.i('ChatScreen', '[TTS] 朗读开关: $_isTtsEnabled');
    if (!_isTtsEnabled) {
      _isTtsSpeaking = false;
      try {
        final tts = context.read<TtsService>();
        tts.stop();
      } catch (_) {}
    }
  }

  void _toggleAutoSendImage() {
    setState(() {
      _isAutoSendImage = !_isAutoSendImage;
    });
    Logger.i('ChatScreen', '[自动发送图像] 开关: $_isAutoSendImage');
  }

  Future<void> _captureAndSendFrame() async {
    final manager = context.read<CameraManager>();
    if (manager.controller == null || !manager.isCameraOn) return;
    if (!_communicationService.isConnected) return;

    try {
      final XFile file = await manager.controller!.takePicture();
      final imageData = await file.readAsBytes();
      await _communicationService.sendImage(imageData);
    } catch (e) {
      Logger.e('ChatScreen', '[自动发送图像] 捕获失败: $e');
    }
  }
  
  Future<void> _switchCamera() async {
    final manager = context.read<CameraManager>();
    await manager.toggleCamera();
  }
  
  void _toggleFullscreen() {
    final manager = context.read<CameraManager>();
    Logger.d('ChatScreen', '_toggleFullscreen() - 调用前: isFullscreen=${manager.isFullscreen}, controller=${manager.controller != null ? '存在' : 'null'}');
    manager.toggleFullscreen();
    Logger.d('ChatScreen', '_toggleFullscreen() - 调用后: isFullscreen=${manager.isFullscreen}');
  }

  Future<void> _sendUserMessage(String text) async {
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

    if (_isAutoSendImage) {
      await _captureAndSendFrame();
    }
  }

  Future<void> _sendPendingSpeech() async {
    if (_pendingSpeechText.trim().isEmpty) return;
    final text = _pendingSpeechText.trim();
    final userMsg = ChatMessage(text: text, isUser: true);
    setState(() {
      _messages.add(userMsg);
      _pendingSpeechText = '';
      _confirmedSpeechText = '';
      _speechInputController.clear();
    });
    _scrollToBottom();
    
    if (_communicationService.isConnected) {
      _communicationService.sendSpeechMessage(text).catchError((error) {
        Logger.e('ChatScreen', '发送语音消息失败: $error');
        return '发送失败';
      });
    }

    if (_isAutoSendImage) {
      await _captureAndSendFrame();
    }
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
    final manager = context.watch<CameraManager>();
    
    return Scaffold(
      appBar: manager.isFullscreen ? null : AppBar(
        title: const Text('语音视频聊天助手'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _toggleSidebar,
        ),
        actions: [
          IconButton(
            icon: Icon(_isAutoSendImage ? Icons.photo_camera : Icons.photo_camera_outlined),
            color: _isAutoSendImage ? Colors.orange : null,
            onPressed: _toggleAutoSendImage,
            tooltip: _isAutoSendImage ? '关闭自动发送图像' : '开启自动发送图像(每秒1帧)',
          ),
          IconButton(
            icon: Icon(_isMicOn ? Icons.mic : Icons.mic_off),
            color: _isMicOn ? Colors.red : null,
            onPressed: _toggleMic,
          ),
          IconButton(
            icon: Icon(manager.isCameraOn ? Icons.videocam : Icons.videocam_off),
            onPressed: _toggleCamera,
          ),
          IconButton(
            icon: Icon(_isTtsEnabled ? Icons.volume_up : Icons.volume_off),
            color: _isTtsEnabled ? Colors.blue : null,
            onPressed: _toggleTts,
            tooltip: _isTtsEnabled ? '关闭朗读' : '开启朗读',
          ),
        ],
      ),
      body: Stack(
        children: [
          manager.isFullscreen ? _buildCameraPreview(isFullscreen: true) : _buildNormalLayout(context),
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

  Widget _buildNormalLayout(BuildContext context) {
    final manager = context.watch<CameraManager>();
    final controllerExists = manager.controller != null;
    
    Logger.d('ChatScreen', '_buildNormalLayout() - 开始构建');
    Logger.d('ChatScreen', '_buildNormalLayout() - controller=${controllerExists ? '存在' : 'null'}');
    Logger.d('ChatScreen', '_buildNormalLayout() - isFullscreen=${manager.isFullscreen}');
    Logger.d('ChatScreen', '_buildNormalLayout() - isCameraOn=${manager.isCameraOn}');
    
    if (controllerExists) {
      Logger.d('ChatScreen', '_buildNormalLayout() - controller状态: isInitialized=${manager.controller!.value.isInitialized}, isStreamingImages=${manager.controller!.value.isStreamingImages}');
      Logger.d('ChatScreen', '_buildNormalLayout() - 将${manager.isCameraOn ? '显示' : '隐藏'}浮动摄像头预览窗口');
    }
    
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
        if (controllerExists && manager.isCameraOn)
          DraggableCameraPreview(
            controller: manager.controller!,
            initialWidth: 150,
            initialHeight: 200,
            onToggleFullscreen: _toggleFullscreen,
            onCapture: () => _sendCameraImage(CameraTriggerType.manual),
            onSwitchCamera: _switchCamera,
            hasMultipleCameras: manager.cameras.length > 1,
          ),
      ],
    );
  }

  Widget _buildCameraPreview({required bool isFullscreen}) {
    final manager = context.watch<CameraManager>();
    final controllerExists = manager.controller != null;
    final isPreviewEnabled = manager.isCameraOn;
    final willShowCameraPreview = controllerExists && isPreviewEnabled;
    
    Logger.d('ChatScreen', '_buildCameraPreview() - 开始构建');
    Logger.d('ChatScreen', '_buildCameraPreview() - isFullscreen=$isFullscreen');
    Logger.d('ChatScreen', '_buildCameraPreview() - controller=${controllerExists ? '存在' : 'null'}');
    Logger.d('ChatScreen', '_buildCameraPreview() - isCameraOn=$isPreviewEnabled');
    Logger.d('ChatScreen', '_buildCameraPreview() - 将${willShowCameraPreview ? '显示 CameraPreview' : '显示占位图标'}');
    
    if (controllerExists) {
      Logger.d('ChatScreen', '_buildCameraPreview() - controller状态: isInitialized=${manager.controller!.value.isInitialized}, isStreamingImages=${manager.controller!.value.isStreamingImages}');
    }
    
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          Logger.d('ChatScreen', '_buildCameraPreview() - LayoutBuilder constraints: ${constraints.maxWidth}x${constraints.maxHeight}');
          
          return Container(
            color: Colors.black,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              children: [
                if (willShowCameraPreview)
                  Center(
                    child: CameraPreview(manager.controller!),
                  )
                else
                  Center(
                    child: isPreviewEnabled
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
                          icon: Icon(_isAutoSendImage ? Icons.photo_camera : Icons.photo_camera_outlined, color: _isAutoSendImage ? Colors.orange : Colors.white, size: 32),
                          onPressed: _toggleAutoSendImage,
                          tooltip: _isAutoSendImage ? '关闭自动发送图像' : '开启自动发送图像(每秒1帧)',
                        ),
                        IconButton(
                          icon: Icon(_isMicOn ? Icons.mic : Icons.mic_off, color: _isMicOn ? Colors.red : Colors.white, size: 32),
                          onPressed: _toggleMic,
                        ),
                        IconButton(
                          icon: Icon(manager.isCameraOn ? Icons.videocam : Icons.videocam_off, color: Colors.white, size: 32),
                          onPressed: _toggleCamera,
                        ),
                        if (manager.cameras.length > 1)
                          IconButton(
                            icon: const Icon(Icons.flip_camera_android, color: Colors.white, size: 32),
                            onPressed: _switchCamera,
                          ),
                        IconButton(
                          icon: Icon(_isTtsEnabled ? Icons.volume_up : Icons.volume_off, color: Colors.white, size: 32),
                          onPressed: _toggleTts,
                          tooltip: _isTtsEnabled ? '关闭朗读' : '开启朗读',
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
                      icon: const Icon(Icons.send, color: Colors.white, size: 48),
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
                        if (manager.cameras.length > 1)
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
          );
        },
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