import 'dart:async';
import '../message_receiver_service.dart';
import '../communication_service.dart';
import '../locator.dart';
import '../../utils/logger.dart';

class MessageReceiverServiceImpl implements MessageReceiverService {
  final CommunicationService _communicationService;
  final StreamController<String> _messageStreamController = StreamController<String>.broadcast();
  StreamSubscription? _subscription;

  MessageReceiverServiceImpl({CommunicationService? communicationService})
      : _communicationService = communicationService ?? locator<CommunicationService>();

  @override
  Future<String> receiveMessage(String input) async {
    Logger.d('MessageReceiver', '等待后端回复...');
    
    final completer = Completer<String>();
    StreamSubscription? subscription;
    
    subscription = _communicationService.messageStream.listen((message) {
      Logger.d('MessageReceiver', '收到后端消息: "$message"');
      completer.complete(message);
      subscription?.cancel();
    });

    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
      subscription?.cancel();
      Logger.e('MessageReceiver', '接收超时');
      return '超时未收到回复';
    });
  }

  Stream<String> get messageStream => _messageStreamController.stream;

  void startListening() {
    if (_subscription != null) return;
    
    Logger.d('MessageReceiver', '开始监听后端消息');
    _subscription = _communicationService.messageStream.listen((message) {
      Logger.d('MessageReceiver', '转发消息到UI: "$message"');
      _messageStreamController.add(message);
    }, onError: (error) {
      Logger.e('MessageReceiver', '消息监听错误: $error');
    }, onDone: () {
      Logger.w('MessageReceiver', '消息流已关闭');
    });
  }

  void stopListening() {
    Logger.d('MessageReceiver', '停止监听后端消息');
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    Logger.d('MessageReceiver', '释放资源');
    _subscription?.cancel();
    _messageStreamController.close();
  }
}