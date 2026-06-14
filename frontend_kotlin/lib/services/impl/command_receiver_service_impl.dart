import 'dart:async';
import '../command_receiver_service.dart';

class CommandReceiverServiceImpl implements CommandReceiverService {
  final StreamController<Command> _commandController = StreamController.broadcast();
  
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
    _commandController.close();
  }
}