import 'tts_service.dart';
import 'web_tts_service.dart';
import '../../utils/logger.dart';

TtsService createTtsService() {
  Logger.i('TTS', '创建 WebTtsService (Web端)');
  return WebTtsService();
}