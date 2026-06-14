import 'dart:typed_data';

abstract class CommunicationService {
  Future<bool> connect();
  
  Future<void> disconnect();
  
  Future<String> sendTextMessage(String message);
  
  Future<String> sendSpeechMessage(String message);
  
  Future<String> sendImage(Uint8List imageData);
  
  Future<void> updateConnection(String host, int port);
  
  Stream<String> get messageStream;
  
  Stream<Map<String, dynamic>> get commandStream;
  
  bool get isConnected;
  
  void dispose();
}