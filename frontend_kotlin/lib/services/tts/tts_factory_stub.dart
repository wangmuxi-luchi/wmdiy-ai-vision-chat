import 'tts_service.dart';
import 'mobile_tts_service.dart';
import '../../utils/logger.dart';

TtsService createTtsService() {
  Logger.i('TTS', '创建 MobileTtsService (移动端)');
  return MobileTtsService();
}