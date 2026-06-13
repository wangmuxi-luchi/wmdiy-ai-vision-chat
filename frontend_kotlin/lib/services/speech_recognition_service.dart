class ASRResult {
  final String text;
  final bool isFinal;

  ASRResult(this.text, {this.isFinal = false});
}

abstract class SpeechRecognitionService {
  Stream<ASRResult> startListening();
  Future<void> stopListening();
  void dispose();
  
  void setCredentials({
    required String secretId,
    required String secretKey,
    required int appId,
  });
}