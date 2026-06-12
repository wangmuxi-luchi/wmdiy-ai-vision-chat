import 'dart:async';
import '../command_receiver_service.dart';

class MockCommandReceiverService implements CommandReceiverService {
  final StreamController<Command> _commandController = StreamController.broadcast();
  Timer? _autoSendTimer;
  
  MockCommandReceiverService() {
    _startAutoSendingCommands();
  }
  
  void _startAutoSendingCommands() {
    _autoSendTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _commandController.add(Command(
        type: 'send_camera_image',
        data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
      ));
    });
  }
  
  @override
  Stream<Command> get commandStream => _commandController.stream;
  
  @override
  void sendCameraImage() {
    _commandController.add(Command(
      type: 'send_camera_image',
      data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
    ));
  }
  
  @override
  void dispose() {
    _autoSendTimer?.cancel();
    _commandController.close();
  }
}