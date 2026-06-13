import 'dart:async';
import '../speech_recognition_service.dart';
import '../../utils/logger.dart';

class WebSpeechRecognitionService implements SpeechRecognitionService {
  final StreamController<ASRResult> _resultController = StreamController<ASRResult>();

  @override
  Stream<ASRResult> startListening() async* {
    throw Exception('WebSpeechRecognitionService only works on Web platform');
  }

  @override
  Future<void> stopListening() async {
    Logger.d('WebASR', 'stopListening called but not on Web platform');
  }

  @override
  void dispose() {
    if (!_resultController.isClosed) {
      _resultController.close();
    }
  }

  @override
  void setCredentials({
    required String secretId,
    required String secretKey,
    required int appId,
  }) {
    Logger.d('WebASR', 'setCredentials called but not on Web platform');
  }
}