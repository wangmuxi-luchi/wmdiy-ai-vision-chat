import '../message_receiver_service.dart';

class MockMessageReceiverService implements MessageReceiverService {
  @override
  Future<String> receiveMessage(String input) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return '回复：$input';
  }
}