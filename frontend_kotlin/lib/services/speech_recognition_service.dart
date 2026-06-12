abstract class SpeechRecognitionService {
  Stream<String> startListening();
  Future<void> stopListening();
  void dispose();
}